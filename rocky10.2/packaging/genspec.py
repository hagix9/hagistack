#!/usr/bin/python3
"""Write an RPM spec file from a Hagistack package definition (defs/<name>.toml).

This is Hagistack's own packaging for OpenStack on Rocky Linux 10.2. It does not
read, translate or rephrase any distribution's spec files. A definition states
facts — the upstream source and its pins, the binary packages and their names,
the files each one installs with owner and mode, the systemd units, the users —
and this program writes the spec around them using building blocks every
package shares:

  * the source: an OpenStack release tarball checked against its detached
    signature in prep (gpgverify, release key pinned in the manifest), or a PyPI
    sdist pinned by SHA-256 only (PyPI sdists are not signed);
  * upstream patches from third-party/, pinned by SHA-256;
  * a notice of Hagistack's changes to the upstream sources (changes =
    [...]): listed in %changelog and installed as HAGISTACK-CHANGES in every
    binary package of the source package; upstream files replaced by
    Hagistack's own (replace_files, e.g. the dashboard's logo);
  * a pyproject build (pyproject-rpm-macros): build and runtime requirements
    come from upstream metadata through the Python dependency generator;
  * an import check of the top-level modules, Sphinx HTML documentation,
    gettext catalogues (in the Python package or a separate -lang package),
    extras subpackages;
  * for services: config files from upstream etc/, Hagistack's own unit,
    logrotate, sudoers and sysusers files, systemd scriptlets by the standard
    systemd-rpm-macros, and short build or install steps that the definition
    spells out.

Run:  genspec.py defs/<name>.toml [-o <out.spec>]
Needs Python 3.11+ (tomllib). Exit status 2 on a definition error.
"""
import argparse
import os
import re
import sys
import tomllib

HERE = os.path.dirname(os.path.abspath(__file__))
FILES_DIR = os.path.join(HERE, 'files')
TOP = os.path.dirname(HERE)          # rocky10.2/

KINDS = {'python', 'python-tests', 'files', 'sphinx-html', 'extras', 'lang'}
ORIGINS = {'openstack', 'pypi'}
SOURCE_KEYS = {'name', 'origin', 'project', 'version', 'release', 'epoch', 'tarball', 'topdir',
               'sha256', 'signing_key', 'license', 'url', 'summary', 'description',
               'buildrequires', 'check', 'doc', 'doc_env', 'locale_domain', 'locale_path',
               'drop_after_install', 'patches', 'extra_licenses', 'prep_extra', 'build_extra',
               'install_extra', 'license_metadata', 'changes', 'changelog_date', 'replace_files'}
PACKAGE_KEYS = {'name', 'kind', 'summary', 'description', 'requires', 'recommends',
                'provides', 'obsoletes', 'conflicts', 'modules', 'tests_path', 'bin',
                'bin_symlinks', 'install', 'dirs', 'symlinks', 'systemd_units', 'sysusers',
                'docs', 'licenses', 'doc_dir', 'extras', 'files', 'scriptlets'}
INSTALL_KEYS = {'src', 'dest', 'mode', 'user', 'group', 'config'}
REPLACE_KEYS = {'src', 'dest'}
CHANGELOG_DATE_RE = r'(Mon|Tue|Wed|Thu|Fri|Sat|Sun) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) [0-3][0-9] 20[0-9]{2}'
DIR_KEYS = {'path', 'mode', 'user', 'group'}
PINNED_KEYS = {'path', 'sha256'}
SCRIPTLETS = ('pre', 'post', 'preun', 'postun', 'posttrans')
# A fixed date keeps the generated spec, and so the SRPM, reproducible.
CHANGELOG_DATE = 'Wed Nov 11 2026'


class DefError(Exception):
    pass


def need(cond, msg):
    if not cond:
        raise DefError(msg)


def _pinned(path, src, key):
    for it in src.get(key, []):
        need(isinstance(it, dict) and set(it) == PINNED_KEYS,
             f'{path}: {key} entries are {{ path = "...", sha256 = "..." }}')
        need(re.fullmatch(r'[0-9a-f]{64}', it['sha256']), f'{path}: {key}: bad sha256 for {it["path"]}')
        need(it['path'].startswith('third-party/') and '..' not in it['path'],
             f'{path}: {key}: {it["path"]} must live under third-party/')


def load(path):
    with open(path, 'rb') as f:
        d = tomllib.load(f)
    need(set(d) <= {'source', 'package'}, f'{path}: unknown top-level keys {sorted(set(d) - {"source", "package"})}')
    src, pkgs = d.get('source'), d.get('package')
    need(isinstance(src, dict), f'{path}: [source] is required')
    need(isinstance(pkgs, list) and pkgs, f'{path}: at least one [[package]] is required')
    unknown = set(src) - SOURCE_KEYS
    need(not unknown, f'{path}: unknown [source] keys {sorted(unknown)}')
    origin = src.setdefault('origin', 'openstack')
    need(origin in ORIGINS, f'{path}: origin must be one of {sorted(ORIGINS)}')
    for k in ('name', 'project', 'version', 'release', 'tarball', 'sha256', 'license',
              'summary', 'description'):
        need(k in src, f'{path}: [source] needs {k}')
    if origin == 'openstack':
        need('signing_key' in src, f'{path}: an openstack source needs signing_key')
        need(re.fullmatch(r'0x[0-9a-f]{40}', src['signing_key']), f'{path}: signing_key must be 0x + 40 hex digits')
    else:
        need('signing_key' not in src, f'{path}: a pypi source has no signature, so no signing_key')
    need(re.fullmatch(r'[0-9a-f]{64}', src['sha256']), f'{path}: sha256 must be 64 lowercase hex digits')
    need(re.fullmatch(r'[A-Za-z0-9.+-]+( (AND|OR) [A-Za-z0-9.+-]+)*', src['license']),
         f'{path}: license must be an SPDX expression')
    need(src.get('check', 'none') in ('none', 'import'), f'{path}: check is "none" or "import"')
    _pinned(path, src, 'patches')
    _pinned(path, src, 'extra_licenses')
    changes = src.get('changes', [])
    need(isinstance(changes, list) and all(isinstance(c, str) and c.strip() and '\n' not in c
                                           and c.isprintable() for c in changes),
         f'{path}: changes must be a list of one-line strings')
    need(not any('HAGISTACK_CHANGES_EOF' in c for c in changes), f'{path}: changes must not contain the notice terminator')
    # Every edit of the upstream tree must be declared, so the notice is complete.
    if src.get('patches') or src.get('prep_extra') or src.get('replace_files'):
        need(changes, f'{path}: patches, prep_extra or replace_files change upstream files: list them in changes')
    if 'changelog_date' in src:
        need(isinstance(src['changelog_date'], str) and re.fullmatch(CHANGELOG_DATE_RE, src['changelog_date']),
             f'{path}: changelog_date must look like "Fri Nov 13 2026"')
    for it in src.get('replace_files', []):
        need(isinstance(it, dict) and set(it) == REPLACE_KEYS, f'{path}: replace_files entries need exactly src and dest')
        need(it['src'].startswith('file:'), f'{path}: replace_files src must be file:<name>')
        f = os.path.join(FILES_DIR, src['name'], it['src'][5:])
        need(os.path.isfile(f) and not os.path.islink(f), f'{path}: Hagistack file {it["src"][5:]} not found in files/{src["name"]}/')
        d = it['dest']
        need(isinstance(d, str) and re.fullmatch(r'[A-Za-z0-9_./-]+', d) and not d.startswith('/')
             and '..' not in d.split('/'), f'{path}: replace_files dest must be a relative path in the source tree')
    names = set()
    for p in pkgs:
        unknown = set(p) - PACKAGE_KEYS
        need(not unknown, f'{path}: package {p.get("name")}: unknown keys {sorted(unknown)}')
        need('name' in p and 'kind' in p, f'{path}: every [[package]] needs name and kind')
        need(p['kind'] in KINDS, f'{path}: package {p["name"]}: kind must be one of {sorted(KINDS)}')
        need(p['name'] not in names, f'{path}: package {p["name"]} defined twice')
        names.add(p['name'])
        for it in p.get('install', []):
            need(set(it) <= INSTALL_KEYS, f'{path}: {p["name"]}: unknown install keys {sorted(set(it) - INSTALL_KEYS)}')
            need('src' in it and 'dest' in it, f'{path}: {p["name"]}: install needs src and dest')
            need(it['src'].split(':', 1)[0] in ('upstream', 'file'),
                 f'{path}: {p["name"]}: install src must start with upstream: or file:')
            if it['src'].startswith('file:'):
                f = os.path.join(FILES_DIR, src['name'], it['src'][5:])
                need(os.path.isfile(f) and not os.path.islink(f),
                     f'{path}: {p["name"]}: Hagistack file {it["src"][5:]} not found in files/{src["name"]}/')
            need(re.fullmatch(r'0[0-7]{3}', it.get('mode', '0644')), f'{path}: {p["name"]}: bad mode {it.get("mode")}')
        for dd in p.get('dirs', []):
            need(set(dd) <= DIR_KEYS and 'path' in dd, f'{path}: {p["name"]}: bad dirs entry {dd}')
            need(re.fullmatch(r'0[0-7]{3}', dd.get('mode', '0755')), f'{path}: {p["name"]}: bad dir mode {dd.get("mode")}')
        if p.get('sysusers'):
            f = os.path.join(FILES_DIR, src['name'], p['sysusers'])
            need(os.path.isfile(f), f'{path}: {p["name"]}: sysusers file {p["sysusers"]} not found')
        if p['kind'] == 'extras':
            need(p.get('extras') and isinstance(p['extras'], list), f'{path}: {p["name"]}: extras = ["..."] required')
        for k in p.get('scriptlets', {}):
            need(k in SCRIPTLETS, f'{path}: {p["name"]}: scriptlet {k} not one of {SCRIPTLETS}')
    return src, pkgs


def hagistack_files(src, pkgs):
    """Every Hagistack-authored file a definition uses, in a stable order."""
    seen = []
    for p in pkgs:
        for it in p.get('install', []):
            if it['src'].startswith('file:') and it['src'][5:] not in seen:
                seen.append(it['src'][5:])
        if p.get('sysusers') and p['sysusers'] not in seen:
            seen.append(p['sysusers'])
    for it in src.get('replace_files', []):
        if it['src'][5:] not in seen:
            seen.append(it['src'][5:])
    return seen


def topdir(src):
    if src.get('topdir'):
        return src['topdir']
    t = src['tarball']
    for ext in ('.tar.gz', '.tgz', '.tar.xz', '.zip'):
        if t.endswith(ext):
            return t[:-len(ext)]
    raise DefError(f'{src["name"]}: cannot derive the top directory from {t}')


def tests_paths(p):
    tp = p.get('tests_path')
    need(tp, f'package {p["name"]}: tests_path is required')
    return tp if isinstance(tp, list) else [tp]


def tags(p):
    out = []
    for key, tag in (('requires', 'Requires'), ('recommends', 'Recommends'), ('provides', 'Provides'),
                     ('obsoletes', 'Obsoletes'), ('conflicts', 'Conflicts')):
        for r in p.get(key, []):
            out.append(f'{tag + ":":<16}{r}')
    if p.get('sysusers'):
        out.append('Requires(pre):  shadow-utils')
    if p.get('systemd_units'):
        out.append('%{?systemd_requires}')
    return out


def has_hagistack_files(p):
    return bool(p.get('sysusers')) or any(it['src'].startswith('file:') for it in p.get('install', []))


def carries_changes(src, p):
    """The package installs HAGISTACK-CHANGES (every package with files, when the
    source package declares changes to upstream)."""
    return bool(src.get('changes')) and p['kind'] != 'extras'


def ships_hagistack_text(src, p):
    """The package installs something Hagistack wrote: its own files, or the
    HAGISTACK-CHANGES notice. Such a package says MIT and carries the text."""
    return has_hagistack_files(p) or carries_changes(src, p)


def relative_docs(p):
    """rpm copies relative %doc files into the package's doc directory itself;
    when a package has any, HAGISTACK-CHANGES joins them the same way."""
    return p['kind'] == 'sphinx-html' or bool(p.get('docs'))


def rpm_text(s):
    """A literal for the spec: % would start a macro."""
    return s.replace('%', '%%')


def changes_notice(src):
    evr = (f'{int(src["epoch"])}:' if src.get('epoch') else '') + f'{src["version"]}-{src["release"]}'
    lines = [
        f'Changes Hagistack made to the upstream sources of {src["project"]} {src["version"]}',
        '',
        f'This package is built from the upstream release {src["tarball"]}, with the',
        'changes listed below. They were made by Hagistack, not by the upstream',
        'project. The upstream copyright and licence notices are kept unchanged.',
        f'The spec file in the source RPM {src["name"]}-{evr} carries every change',
        '(its Patch lines and its %prep, %build and %install sections); the release',
        'documents them in THIRD_PARTY_NOTICES.md.',
        '',
        'Changes:',
    ]
    lines += [f'- {c}' for c in src['changes']]
    if src.get('patches'):
        lines += ['', 'Patches applied (from third-party/ of the Hagistack repository):']
        lines += [f'- Patch{i + 1:04d}: {os.path.basename(it["path"])} (sha256 {it["sha256"]})'
                  for i, it in enumerate(src['patches'])]
    lines += ['', "This notice is Hagistack's own text, under the MIT License (HAGISTACK-LICENSE)."]
    return lines


def with_mit(expr):
    """expr AND MIT, unless MIT is already one of its licences (no 'MIT AND MIT')."""
    ids = set(re.findall(r'[A-Za-z0-9.+-]+', expr)) - {'AND', 'OR', 'WITH'}
    return expr if 'MIT' in ids else expr + ' AND MIT'


def pkg_license(src, p):
    return with_mit(src['license']) if ships_hagistack_text(src, p) else src['license']


def srpm_license(src, pkgs):
    """The main package's tag is also the source package's: it names everything
    the SRPM carries, so MIT whenever the SRPM holds Hagistack files, even when
    the main package itself (a meta package, say) holds none."""
    return with_mit(src['license']) if any(ships_hagistack_text(src, p) for p in pkgs) else src['license']


def pkg_header(src, p, main):
    """%package block (or the main package's tags and %description)."""
    out = []
    if not main:
        out.append(f'%package -n {p["name"]}')
        out.append(f'Summary:        {p.get("summary", src["summary"])}')
        out.append(f'License:        {pkg_license(src, p)}')
    out.extend(tags(p))
    out.append('')
    out.append(f'%description{"" if main else " -n " + p["name"]}')
    out.append(p.get('description', src['description']).strip())
    out.append('')
    return out


def generate(src, pkgs):
    hfiles = hagistack_files(src, pkgs)
    by_kind = lambda k: [p for p in pkgs if p['kind'] == k]
    python_pkgs, tests_pkgs, doc_pkgs = by_kind('python'), by_kind('python-tests'), by_kind('sphinx-html')
    extras_pkgs, lang_pkgs = by_kind('extras'), by_kind('lang')
    need(len(python_pkgs) <= 1, f'{src["name"]}: at most one python package per source')
    need(not tests_pkgs or python_pkgs, f'{src["name"]}: a python-tests package needs a python package')
    need(not extras_pkgs or python_pkgs, f'{src["name"]}: an extras package needs a python package')
    need(not doc_pkgs or src.get('doc'), f'{src["name"]}: a sphinx-html package needs [source] doc = "<sphinx source dir>"')
    need(len(lang_pkgs) <= 1, f'{src["name"]}: at most one lang package')
    need(not lang_pkgs or src.get('locale_domain'), f'{src["name"]}: a lang package needs locale_domain')
    main = next((p for p in pkgs if p['name'] == src['name']), None)
    openstack = src['origin'] == 'openstack'
    s = []
    w = s.append
    w('# Generated by rocky10.2/packaging/genspec.py from defs/%s.toml. Edit the definition,' % src['name'])
    w('# not this file. Hagistack packaging; the packaged software keeps its own licence.')
    w('')
    w(f'Name:           {src["name"]}')
    if src.get('epoch'):
        w(f'Epoch:          {int(src["epoch"])}')
    w(f'Version:        {src["version"]}')
    w(f'Release:        {src["release"]}%{{?dist}}')
    w(f'Summary:        {(main or {}).get("summary", src["summary"])}')
    w(f'License:        {srpm_license(src, pkgs)}')
    if openstack:
        w(f'URL:            {src.get("url", "https://opendev.org/openstack/" + src["project"])}')
        w(f'Source0:        https://tarballs.openstack.org/{src["project"]}/{src["tarball"]}')
        w(f'Source1:        https://tarballs.openstack.org/{src["project"]}/{src["tarball"]}.asc')
        w(f'Source2:        https://releases.openstack.org/_static/{src["signing_key"]}.txt')
    else:
        p = src['project']
        w(f'URL:            {src.get("url", "https://pypi.org/project/" + p + "/")}')
        w(f'Source0:        https://files.pythonhosted.org/packages/source/{p[0]}/{p}/{src["tarball"]}')
    # Hagistack's own work in this source package (the spec, and any files under
    # files/<name>/) is under the MIT License; its text travels in every SRPM.
    w('Source99:       HAGISTACK-LICENSE')
    for i, f in enumerate(hfiles):
        w(f'Source{100 + i}:      {f}')
    for i, it in enumerate(src.get('extra_licenses', [])):
        w(f'Source{900 + i}:      {os.path.basename(it["path"])}')
    for i, it in enumerate(src.get('patches', [])):
        w(f'Patch{i + 1:04d}:      {os.path.basename(it["path"])}')
    w('BuildArch:      noarch')
    w('')
    w('BuildRequires:  python3-devel')
    w('BuildRequires:  pyproject-rpm-macros')
    if openstack:
        w('BuildRequires:  gnupg2')
    if any(p.get('systemd_units') for p in pkgs):
        w('BuildRequires:  systemd-rpm-macros')
    if src.get('locale_domain'):
        w('BuildRequires:  gettext')
    for b in src.get('buildrequires', []):
        w(f'BuildRequires:  {b}')
    w('')
    if main:
        s.extend(pkg_header(src, main, True))
    else:
        w('%description')
        w(src['description'].strip())
        w('')
    for p in pkgs:
        if p is main:
            continue
        if p['kind'] == 'extras':
            base = python_pkgs[0]['name']
            w(f'%pyproject_extras_subpkg -n {base} {" ".join(p["extras"])}')
            w('')
            continue
        if p['kind'] == 'python-tests' and python_pkgs:
            # A tests package is useless without the code it tests.
            req = f'{python_pkgs[0]["name"]} = %{{?epoch:%{{epoch}}:}}%{{version}}-%{{release}}'
            if req not in p.get('requires', []):
                p = dict(p, requires=[req] + p.get('requires', []))
        s.extend(pkg_header(src, p, False))

    srcidx = {f: 100 + i for i, f in enumerate(hfiles)}
    need_runtime = src.get('check') == 'import' or bool(src.get('doc'))

    w('%prep')
    if openstack:
        w("%{gpgverify} --keyring='%{SOURCE2}' --signature='%{SOURCE1}' --data='%{SOURCE0}'")
    w(f'%autosetup -n {topdir(src)} -p1')
    for line in src.get('prep_extra', []):
        w(line)
    for it in src.get('replace_files', []):
        # Upstream's file must be there: a moved file must not leave upstream's copy.
        w(f"test -f '{it['dest']}' || exit 1")
        w(f"cp -p '%{{SOURCE{srcidx[it['src'][5:]]}}}' '{it['dest']}'")
    if src.get('changes'):
        w("cat > HAGISTACK-CHANGES <<'HAGISTACK_CHANGES_EOF'")
        s.extend(rpm_text(x) for x in changes_notice(src))
        w('HAGISTACK_CHANGES_EOF')
    if src.get('extra_licenses'):
        w('cp -p ' + ' '.join(f'%{{SOURCE{900 + i}}}' for i in range(len(src['extra_licenses']))) + ' .')
    if any(ships_hagistack_text(src, p) for p in pkgs):
        w("cp -p '%{SOURCE99}' HAGISTACK-LICENSE")
    w('')
    w('%generate_buildrequires')
    # -r adds the runtime requirements too: the import check and Sphinx autodoc
    # both import the package, so they must be installed while it builds.
    w('%pyproject_buildrequires' + (' -r' if need_runtime else ''))
    w('')
    w('%build')
    w('%pyproject_wheel')
    for line in src.get('build_extra', []):
        w(line)
    # Sphinx HTML: for a -doc package, or for a package that lists html in docs.
    html_dirs = [p.get('doc_dir', 'html') for p in doc_pkgs]
    if src.get('doc') and not html_dirs and any('html' in p.get('docs', []) for p in pkgs):
        html_dirs = ['html']
    for d in dict.fromkeys(html_dirs):
        env = f'{src["doc_env"]} ' if src.get('doc_env') else ''
        w(f'{env}PYTHONPATH="$PWD" sphinx-build -b html -d doc-trees {src["doc"]} {d}')
        w(f'rm -rf {d}/.buildinfo')
    w('')
    w('%install')
    w('%pyproject_install')
    if python_pkgs:
        mods = ' '.join(python_pkgs[0].get('modules', []))
        need(mods, f'{src["name"]}: the python package needs modules = [...]')
        # -l asserts that upstream metadata names its licence files (PEP 639); a few
        # sdists do not, and then -L is used and the definition lists the files.
        w(f'%pyproject_save_files {"-l" if src.get("license_metadata", True) else "-L"} {mods}')
    # Catalogues are compiled into /usr/share/locale (packaged through find_lang);
    # the .po copies in site-packages are removed and dropped from the saved file
    # list, which pyproject_save_files builds from the wheel RECORD, not the disk.
    if src.get('locale_domain'):
        dom = src['locale_domain']
        lpath = src.get('locale_path', f'{dom}/locale')
        w(f'for po in {lpath}/*/LC_MESSAGES/{dom}.po; do')
        w('    lang="$(basename "$(dirname "$(dirname "$po")")")"')
        w('    install -d %{buildroot}%{_datadir}/locale/"$lang"/LC_MESSAGES')
        w(f'    msgfmt -o %{{buildroot}}%{{_datadir}}/locale/"$lang"/LC_MESSAGES/{dom}.mo "$po"')
        w('done')
        w(f'rm -rf %{{buildroot}}%{{python3_sitelib}}/{lpath}')
        w(f"sed -i '\\#/{lpath}#d' %{{pyproject_files}}")
        w(f'%find_lang {dom}')
    for d in src.get('drop_after_install', []):
        w(f'rm -rf %{{buildroot}}{d}')
    for p in pkgs:
        for dd in p.get('dirs', []):
            w(f'install -d -m {dd.get("mode", "0755")} %{{buildroot}}{dd["path"]}')
        for it in p.get('install', []):
            mode = it.get('mode', '0644')
            dest = it['dest']
            if it['src'].startswith('upstream:'):
                path = it['src'][9:]
                if '*' in os.path.basename(path):     # a glob: dest is the directory
                    w(f'install -d -m 0755 %{{buildroot}}{dest}')
                    w(f'install -p -m {mode} {path} %{{buildroot}}{dest}/')
                else:
                    w(f'install -p -D -m {mode} {path} %{{buildroot}}{dest}')
            else:
                w(f'install -p -D -m {mode} %{{SOURCE{srcidx[it["src"][5:]]}}} %{{buildroot}}{dest}')
        for ln in p.get('symlinks', []):
            w(f'install -d -m 0755 %{{buildroot}}{os.path.dirname(ln["path"])}')
            w(f'ln -s {ln["target"]} %{{buildroot}}{ln["path"]}')
        for link, target in p.get('bin_symlinks', {}).items():
            w(f'ln -s {target} %{{buildroot}}%{{_bindir}}/{link}')
        if p.get('sysusers'):
            w(f'install -p -D -m 0644 %{{SOURCE{srcidx[p["sysusers"]]}}} %{{buildroot}}%{{_sysusersdir}}/{p["name"]}.conf')
    for line in src.get('install_extra', []):
        w(line)
    for p in pkgs:
        if carries_changes(src, p) and not relative_docs(p):
            w(f'install -p -D -m 0644 HAGISTACK-CHANGES %{{buildroot}}%{{_docdir}}/{p["name"]}/HAGISTACK-CHANGES')
    w('')
    if src.get('check') == 'import':
        w('%check')
        # -t: top-level modules only. Importing every submodule pulls in test
        # helpers and example plugins whose dependencies are test-only (stevedore
        # ships example setup.py files inside the package; oslo_config.fixture
        # needs fixtures).
        w('%pyproject_check_import -t')
        w('')

    for p in pkgs:
        flag = '' if p is main else f' -n {p["name"]}'
        units = ' '.join(p.get('systemd_units', []))
        body = {k: [] for k in SCRIPTLETS}
        if p.get('sysusers'):
            body['pre'].append(f'%sysusers_create_compat %{{SOURCE{srcidx[p["sysusers"]]}}}')
        if units:
            body['post'].append(f'%systemd_post {units}')
            body['preun'].append(f'%systemd_preun {units}')
            body['postun'].append(f'%systemd_postun_with_restart {units}')
        for k, lines in p.get('scriptlets', {}).items():
            body[k].extend(lines)
        for k in SCRIPTLETS:
            if body[k]:
                w(f'%{k}{flag}')
                s.extend(body[k])
                w('')

    for p in pkgs:
        k = p['kind']
        if k == 'extras':
            continue
        head = '%files' + ('' if p is main else f' -n {p["name"]}')
        if k == 'python':
            head += ' -f %{pyproject_files}'
            if src.get('locale_domain') and not lang_pkgs:
                head += f' -f {src["locale_domain"]}.lang'
        if k == 'lang':
            head += f' -f {src["locale_domain"]}.lang'
        w(head)
        if k == 'python' and tests_pkgs:
            for t in tests_pkgs:
                for tp in tests_paths(t):
                    w(f'%exclude %{{python3_sitelib}}/{tp}')
        if k == 'python-tests':
            for tp in tests_paths(p):
                w(f'%{{python3_sitelib}}/{tp}')
        if k == 'sphinx-html':
            w(f'%doc {p.get("doc_dir", "html")}')
        for lic in p.get('licenses', []):
            w(f'%license {lic}')
        if ships_hagistack_text(src, p):
            w('%license HAGISTACK-LICENSE')
        for doc in p.get('docs', []):
            w(f'%doc {doc}')
        if carries_changes(src, p):
            if relative_docs(p):
                w('%doc HAGISTACK-CHANGES')
            else:
                ddir = f'%{{_docdir}}/{p["name"]}'
                if f'%dir {ddir}' not in p.get('files', []):
                    w(f'%dir {ddir}')
                w(f'%doc {ddir}/HAGISTACK-CHANGES')
        for b in p.get('bin', []):
            w(f'%{{_bindir}}/{b}')
        for link in p.get('bin_symlinks', {}):
            w(f'%{{_bindir}}/{link}')
        for dd in p.get('dirs', []):
            w(f'%dir %attr({dd.get("mode", "0755")}, {dd.get("user", "root")}, {dd.get("group", "root")}) {dd["path"]}')
        for it in p.get('install', []):
            attr = f'%attr({it.get("mode", "0644")}, {it.get("user", "root")}, {it.get("group", "root")})'
            cfg = '%config(noreplace) ' if it.get('config') else ''
            pat = os.path.basename(it['src'][9:]) if it['src'].startswith('upstream:') else ''
            dest = it['dest'] + (f'/{pat}' if '*' in pat else '')
            w(f'{cfg}{attr} {dest}')
        for ln in p.get('symlinks', []):
            w(ln['path'])
        if p.get('sysusers'):
            w(f'%{{_sysusersdir}}/{p["name"]}.conf')
        for line in p.get('files', []):
            w(line)
        w('')
    w('%changelog')
    evr = (f'{int(src["epoch"])}:' if src.get('epoch') else '') + f'{src["version"]}-{src["release"]}'
    w(f'* {src.get("changelog_date", CHANGELOG_DATE)} Hagistack - {evr}')
    w('- Hagistack packaging of the upstream release')
    if src.get('changes'):
        w('- Changes to the upstream sources, also in HAGISTACK-CHANGES:')
        for c in src['changes']:
            w(rpm_text(f'- {c}'))
        for i, it in enumerate(src.get('patches', [])):
            w(f'- Patch{i + 1:04d}: {os.path.basename(it["path"])}')
    return '\n'.join(s) + '\n'


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('definition')
    ap.add_argument('-o', '--output')
    ap.add_argument('--names', action='store_true',
                    help='print the binary package names the definition produces, one per line')
    a = ap.parse_args(argv)
    try:
        src, pkgs = load(a.definition)
        if a.names:
            sys.stdout.write(''.join(p['name'] + '\n' for p in pkgs))
            return 0
        text = generate(src, pkgs)
    except (DefError, tomllib.TOMLDecodeError, OSError) as e:
        print(f'genspec: {e}', file=sys.stderr)
        return 2
    if a.output:
        with open(a.output, 'w') as f:
            f.write(text)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == '__main__':
    sys.exit(main())
