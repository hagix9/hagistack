#!/usr/bin/python3
"""Write an RPM spec file from a Hagistack package definition (defs/<name>.toml).

This is Hagistack's own packaging for OpenStack on Rocky Linux 10.2. It does not
read, translate or rephrase any distribution's spec files. A definition states
facts — the upstream tarball and its pins, the binary packages and their names,
the files each one installs with owner and mode, the systemd units, the users —
and this program writes the spec around them using a small set of building
blocks that every package shares:

  * the OpenStack release tarball, checked against its detached signature in
    prep with the release key the manifest pins (gpgverify);
  * a pyproject build (pyproject-rpm-macros), so build and runtime requirements
    come from upstream's own metadata through the Python dependency generator;
  * optional Sphinx HTML documentation, gettext catalogues, an import check;
  * for services: config files copied from upstream etc/, Hagistack's own unit,
    logrotate, sudoers and sysusers files, systemd scriptlets by the standard
    systemd-rpm-macros.

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

KINDS = {'python', 'python-tests', 'files', 'sphinx-html'}
SOURCE_KEYS = {'name', 'project', 'version', 'release', 'epoch', 'tarball', 'sha256',
               'signing_key', 'license', 'url', 'summary', 'description',
               'buildrequires', 'check', 'check_import_exclude', 'doc', 'locale_domain',
               'drop_after_install'}
PACKAGE_KEYS = {'name', 'kind', 'summary', 'description', 'requires', 'recommends',
                'provides', 'modules', 'tests_path', 'bin', 'bin_symlinks', 'install', 'dirs',
                'symlinks', 'systemd_units', 'sysusers', 'docs', 'licenses',
                'locale', 'doc_dir'}
INSTALL_KEYS = {'src', 'dest', 'mode', 'user', 'group', 'config'}
DIR_KEYS = {'path', 'mode', 'user', 'group'}
# A fixed date keeps the generated spec, and so the SRPM, reproducible.
CHANGELOG_DATE = 'Wed Nov 11 2026'


class DefError(Exception):
    pass


def need(cond, msg):
    if not cond:
        raise DefError(msg)


def load(path):
    with open(path, 'rb') as f:
        d = tomllib.load(f)
    need(set(d) <= {'source', 'package'}, f'{path}: unknown top-level keys {sorted(set(d) - {"source", "package"})}')
    src, pkgs = d.get('source'), d.get('package')
    need(isinstance(src, dict), f'{path}: [source] is required')
    need(isinstance(pkgs, list) and pkgs, f'{path}: at least one [[package]] is required')
    unknown = set(src) - SOURCE_KEYS
    need(not unknown, f'{path}: unknown [source] keys {sorted(unknown)}')
    for k in ('name', 'project', 'version', 'release', 'tarball', 'sha256', 'signing_key',
              'license', 'summary', 'description'):
        need(k in src, f'{path}: [source] needs {k}')
    need(re.fullmatch(r'[0-9a-f]{64}', src['sha256']), f'{path}: sha256 must be 64 lowercase hex digits')
    need(re.fullmatch(r'0x[0-9a-f]{40}', src['signing_key']), f'{path}: signing_key must be 0x + 40 hex digits')
    need(re.fullmatch(r'[A-Za-z0-9.+-]+( (AND|OR) [A-Za-z0-9.+-]+)*', src['license']),
         f'{path}: license must be an SPDX expression')
    need(src.get('check', 'none') in ('none', 'import'), f'{path}: check is "none" or "import"')
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
        if p.get('sysusers'):
            f = os.path.join(FILES_DIR, src['name'], p['sysusers'])
            need(os.path.isfile(f), f'{path}: {p["name"]}: sysusers file {p["sysusers"]} not found')
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
    return seen


def pkg_header(src, p, main):
    """%package line (or nothing for the main package) plus its tags."""
    out = []
    if not main:
        out.append(f'%package -n {p["name"]}')
    if not main:   # the main package's Summary is written with Name, once
        out.append(f'Summary:        {p.get("summary", src["summary"])}')
    for r in p.get('requires', []):
        out.append(f'Requires:       {r}')
    for r in p.get('recommends', []):
        out.append(f'Recommends:     {r}')
    for r in p.get('provides', []):
        out.append(f'Provides:       {r}')
    if p.get('sysusers'):
        out.append('Requires(pre):  shadow-utils')
    if p.get('systemd_units'):
        out.append('%{?systemd_requires}')
    out.append('')
    out.append(f'%description{"" if main else " -n " + p["name"]}')
    out.append(p.get('description', src['description']).strip())
    out.append('')
    return out


def topdir(src):
    t = src['tarball']
    for ext in ('.tar.gz', '.tgz', '.tar.xz'):
        if t.endswith(ext):
            return t[:-len(ext)]
    raise DefError(f'{src["name"]}: cannot derive the top directory from {t}')


def generate(src, pkgs):
    hfiles = hagistack_files(src, pkgs)
    python_pkgs = [p for p in pkgs if p['kind'] == 'python']
    tests_pkgs = [p for p in pkgs if p['kind'] == 'python-tests']
    doc_pkgs = [p for p in pkgs if p['kind'] == 'sphinx-html']
    need(len(python_pkgs) <= 1, f'{src["name"]}: at most one python package per source')
    need(not tests_pkgs or python_pkgs, f'{src["name"]}: a python-tests package needs a python package')
    need(not doc_pkgs or src.get('doc'), f'{src["name"]}: a sphinx-html package needs [source] doc = "<sphinx source dir>"')
    main = next((p for p in pkgs if p['name'] == src['name']), None)
    s = []
    w = s.append
    w('# Generated by rocky10.2/packaging/genspec.py from defs/%s.toml. Edit the definition,' % src['name'])
    w('# not this file. Hagistack packaging; the packaged software keeps its own licence.')
    w(f'%global hagistack_project {src["project"]}')
    w('')
    w(f'Name:           {src["name"]}')
    if src.get('epoch'):
        w(f'Epoch:          {int(src["epoch"])}')
    w(f'Version:        {src["version"]}')
    w(f'Release:        {src["release"]}%{{?dist}}')
    w(f'Summary:        {(main or {}).get("summary", src["summary"])}')
    w(f'License:        {src["license"]}')
    w(f'URL:            {src.get("url", "https://opendev.org/openstack/" + src["project"])}')
    w(f'Source0:        https://tarballs.openstack.org/%{{hagistack_project}}/{src["tarball"]}')
    w(f'Source1:        https://tarballs.openstack.org/%{{hagistack_project}}/{src["tarball"]}.asc')
    w(f'Source2:        https://releases.openstack.org/_static/{src["signing_key"]}.txt')
    for i, f in enumerate(hfiles):
        w(f'Source{100 + i}:      {f}')
    w('BuildArch:      noarch')
    w('')
    w('BuildRequires:  python3-devel')
    w('BuildRequires:  pyproject-rpm-macros')
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
        if p is not main:
            s.extend(pkg_header(src, p, False))

    srcidx = {f: 100 + i for i, f in enumerate(hfiles)}
    need_runtime = src.get('check') == 'import' or bool(doc_pkgs)

    w('%prep')
    w("%{gpgverify} --keyring='%{SOURCE2}' --signature='%{SOURCE1}' --data='%{SOURCE0}'")
    w(f'%autosetup -n {topdir(src)} -p1')
    w('')
    w('%generate_buildrequires')
    # -r adds the runtime requirements too: the import check and Sphinx autodoc
    # both import the package, so they must be installed while it builds.
    w('%pyproject_buildrequires' + (' -r' if need_runtime else ''))
    w('')
    w('%build')
    w('%pyproject_wheel')
    for p in doc_pkgs:
        w(f'PYTHONPATH="$PWD" sphinx-build -b html -d doc-trees {src["doc"]} {p.get("doc_dir", "html")}')
        w(f'rm -rf {p.get("doc_dir", "html")}/.buildinfo')
    w('')
    w('%install')
    w('%pyproject_install')
    if python_pkgs:
        mods = ' '.join(python_pkgs[0].get('modules', []))
        need(mods, f'{src["name"]}: the python package needs modules = [...]')
        w(f'%pyproject_save_files -l {mods}')
    # Catalogues are compiled into /usr/share/locale (packaged through find_lang);
    # the .po copies in site-packages are removed and dropped from the saved file
    # list, which pyproject_save_files builds from the wheel RECORD, not the disk.
    if src.get('locale_domain'):
        dom = src['locale_domain']
        w(f'for po in {dom}/locale/*/LC_MESSAGES/{dom}.po; do')
        w('    lang="$(basename "$(dirname "$(dirname "$po")")")"')
        w(f'    install -d %{{buildroot}}%{{_datadir}}/locale/"$lang"/LC_MESSAGES')
        w(f'    msgfmt -o %{{buildroot}}%{{_datadir}}/locale/"$lang"/LC_MESSAGES/{dom}.mo "$po"')
        w('done')
        w(f'rm -rf %{{buildroot}}%{{python3_sitelib}}/{dom}/locale')
        w(f"sed -i '\\#/{dom}/locale#d' %{{pyproject_files}}")
    if src.get('locale_domain'):
        w(f'%find_lang {src["locale_domain"]}')
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
                if path.endswith('/*'):
                    w(f'install -d -m 0755 %{{buildroot}}{dest}')
                    w(f'install -p -m {mode} {path[:-2]}/*.json %{{buildroot}}{dest}/')
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
    w('')
    if src.get('check') == 'import':
        w('%check')
        excl = ' '.join(f"-e '{e}'" for e in src.get('check_import_exclude', []))
        # -t: top-level modules only. Importing every submodule pulls in test
        # helpers and example plugins whose dependencies are test-only (stevedore
        # ships example setup.py files inside the package; oslo_config.fixture
        # needs fixtures).
        w(f'%pyproject_check_import -t {excl}'.rstrip())
        w('')

    for p in pkgs:
        su = p.get('sysusers')
        units = ' '.join(p.get('systemd_units', []))
        flag = '' if p is main else f' -n {p["name"]}'
        if su:
            w(f'%pre{flag}')
            w(f'%sysusers_create_compat %{{SOURCE{srcidx[su]}}}')
            w('')
        if units:
            w(f'%post{flag}')
            w(f'%systemd_post {units}')
            w('')
            w(f'%preun{flag}')
            w(f'%systemd_preun {units}')
            w('')
            w(f'%postun{flag}')
            w(f'%systemd_postun_with_restart {units}')
            w('')

    for p in pkgs:
        head = '%files' + ('' if p is main else f' -n {p["name"]}')
        k = p['kind']
        if k == 'python':
            if src.get('locale_domain') and p.get('locale', True):
                head += ' -f %{pyproject_files} -f ' + src['locale_domain'] + '.lang'
            else:
                head += ' -f %{pyproject_files}'
        w(head)
        if k == 'python' and tests_pkgs:
            for t in tests_pkgs:
                w(f'%exclude %{{python3_sitelib}}/{t["tests_path"]}')
        if k == 'python-tests':
            w(f'%{{python3_sitelib}}/{p["tests_path"]}')
        if k == 'sphinx-html':
            w(f'%doc {p.get("doc_dir", "html")}')
        for lic in p.get('licenses', []):
            w(f'%license {lic}')
        for doc in p.get('docs', []):
            w(f'%doc {doc}')
        for b in p.get('bin', []):
            w(f'%{{_bindir}}/{b}')
        for link in p.get('bin_symlinks', {}):
            w(f'%{{_bindir}}/{link}')
        for dd in p.get('dirs', []):
            w(f'%dir %attr({dd.get("mode", "0755")}, {dd.get("user", "root")}, {dd.get("group", "root")}) {dd["path"]}')
        for it in p.get('install', []):
            attr = f'%attr({it.get("mode", "0644")}, {it.get("user", "root")}, {it.get("group", "root")})'
            cfg = '%config(noreplace) ' if it.get('config') else ''
            dest = it['dest'] + ('/*.json' if it['src'].endswith('/*') else '')
            w(f'{cfg}{attr} {dest}')
        for ln in p.get('symlinks', []):
            w(ln['path'])
        if p.get('sysusers'):
            w(f'%{{_sysusersdir}}/{p["name"]}.conf')
        w('')
    w('%changelog')
    evr = (f'{int(src["epoch"])}:' if src.get('epoch') else '') + f'{src["version"]}-{src["release"]}'
    w(f'* {CHANGELOG_DATE} Hagistack - {evr}')
    w('- Hagistack packaging of the upstream release')
    return '\n'.join(s) + '\n'


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('definition')
    ap.add_argument('-o', '--output')
    a = ap.parse_args(argv)
    try:
        src, pkgs = load(a.definition)
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
