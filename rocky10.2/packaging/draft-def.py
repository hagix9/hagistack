#!/usr/bin/python3
"""Draft a package definition (defs/<srpm>.toml) for a library from FACTS only.

Inputs, and nothing else:
  * rc4's binary RPM metadata as JSON (package names, epoch, file paths, modes,
    owners) — produced by reading RPM headers, not spec files;
  * the unpacked upstream source (PKG-INFO, pyproject.toml / setup.cfg,
    doc/source/conf.py, locale directories);
  * ../gazpacho.manifest for the pins (tarball, SHA-256, signing key, version).

It never opens a spec file or a distgit file. The draft is reviewed by hand
before it is committed; anything the tool cannot place is listed under
`# REVIEW:` comments at the top of the draft and makes the exit status 3.

  draft-def.py --meta rc4-meta.json --upstream <dir of unpacked tarballs> SRPM-NAME...
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MANIFEST = os.path.join(HERE, '..', 'gazpacho.manifest')
SITE = '/usr/lib/python3.12/site-packages/'

# Sphinx extension (module prefix) -> what to BuildRequire for the HTML build.
DOC_EXT = {
    'openstackdocstheme': 'python3dist(openstackdocstheme)',
    'oslo_config.': 'python3dist(oslo-config)',
    'oslo_policy.': 'python3dist(oslo-policy)',
    'reno.': 'python3dist(reno)',
    'sphinxcontrib.apidoc': 'python3dist(sphinxcontrib-apidoc)',
    'sphinxcontrib.rsvgconverter': 'python3dist(sphinxcontrib-svg2pdfconverter)',
    'sphinx_feature_classification': 'python3dist(sphinx-feature-classification)',
    'stevedore.': 'python3dist(stevedore)',
    'cliff.': 'python3dist(cliff)',
}


def manifest():
    pins, pypi, lic = {}, {}, {}
    for line in open(MANIFEST):
        f = line.split()
        if not f or f[0].startswith('#'):
            continue
        if f[0] == 'PYPI':
            pypi[f[1]] = dict(pypi=f[2], version=f[3], tarball=f[4], sha256=f[5], license=f[6].replace(',', ' AND '),
                              summary=' '.join(f[7:]))
        elif f[0] == 'LICENSE':
            lic.setdefault(f[1], []).append((f[2], f[3]))
        elif len(f) >= 10 and re.fullmatch(r'[0-9a-f]{40}', f[2]):
            pins[f[6]] = dict(version=f[4], release=f[5], tarball=f[6], sha256=f[7], project=f[8], key=f[9])
    return pins, pypi, lic


def q(s):
    return json.dumps(s, ensure_ascii=False)


def pkginfo_summary(udir):
    p = os.path.join(udir, 'PKG-INFO')
    if os.path.exists(p):
        for line in open(p, errors='replace'):
            if line.startswith('Summary:'):
                return line.split(':', 1)[1].strip()
    return ''


def doc_buildrequires(udir):
    c = os.path.join(udir, 'doc', 'source', 'conf.py')
    out = ['python3dist(sphinx)']
    if not os.path.exists(c):
        return out
    t = open(c, errors='replace').read()
    m = re.search(r'^extensions\s*=\s*\[(.*?)\]', t, re.S | re.M)
    for e in re.findall(r"['\"]([\w.]+)['\"]", m.group(1) if m else ''):
        for k, v in DOC_EXT.items():
            if (e == k or e.startswith(k)) and v not in out:
                out.append(v)
    if 'openstackdocstheme' in t and 'python3dist(openstackdocstheme)' not in out:
        out.append('python3dist(openstackdocstheme)')
    return out


def draft(srpm, meta, udirs, pins, pypi, lic):
    review = []
    bins = {n: v for n, v in meta.items() if v['sourcerpm'].rsplit('-', 2)[0] == srpm}
    if not bins:
        raise SystemExit(f'{srpm}: no rc4 binary package comes from this SRPM')
    any_bin = next(iter(bins.values()))
    version, release, epoch = any_bin['version'], any_bin['release'].split('.el10')[0], any_bin['epoch']
    is_pypi = srpm.startswith('python3-') and srpm in pypi
    if is_pypi:
        pin = pypi[srpm]
        tarball, sha, project = pin['tarball'], pin['sha256'], pin['pypi']
    else:
        cand = [p for p in pins.values() if p['version'] == version and
                re.sub(r'[-_.]', '', p['project'].lower()) in re.sub(r'[-_.]', '', srpm.lower())]
        if len(cand) != 1:
            raise SystemExit(f'{srpm}: cannot match a manifest row for version {version} ({len(cand)} candidates)')
        pin = cand[0]
        tarball, sha, project = pin['tarball'], pin['sha256'], pin['project']
        if pin['release'] != release:
            review.append(f'manifest release {pin["release"]} != rc4 release {release}')
    stem = tarball[:-7]
    udir = udirs.get(stem)
    if not udir:
        raise SystemExit(f'{srpm}: upstream tree for {tarball} not found')
    top = os.path.basename(udir)
    summary = pkginfo_summary(udir) or (pin.get('summary') if is_pypi else '') or project
    lines = ['# Hagistack package definition. Facts only: pins, names, files. See ../README.md.',
             '# Drafted by draft-def.py from rc4 RPM metadata and the upstream source; reviewed by hand.']
    S = [f'name = {q(srpm)}']
    if is_pypi:
        S.append('origin = "pypi"')
    S.append(f'project = {q(project)}')
    S.append(f'version = {q(version)}')
    S.append(f'release = {q(release)}')
    if epoch:
        S.append(f'epoch = {epoch}')
    S.append(f'tarball = {q(tarball)}')
    if top != stem:
        S.append(f'topdir = {q(top)}')
    S.append(f'sha256 = {q(sha)}')
    if not is_pypi:
        S.append(f'signing_key = {q(pin["key"])}')
    licence = pin['license'] if is_pypi else 'Apache-2.0'
    if not is_pypi:
        lt = open(os.path.join(udir, 'LICENSE'), errors='replace').read() if os.path.exists(os.path.join(udir, 'LICENSE')) else ''
        if 'Apache License' not in lt or 'Version 2.0' not in lt:
            review.append('upstream LICENSE is not plainly Apache-2.0: set license by hand')
    S.append(f'license = {q(licence)}')
    S.append(f'summary = {q(summary)}')
    S.append('description = """\n' + f'{summary.rstrip(".")}.\n\nThe upstream {project} {version} release, packaged by Hagistack.\n' + '"""')
    if is_pypi and srpm in lic:
        S.append('extra_licenses = [' + ', '.join(f'{{ path = {q(p)}, sha256 = {q(h)} }}' for p, h in lic[srpm]) + ']')

    P = []
    mods, locale_dom, docpkg = set(), None, None
    for n in sorted(bins, key=lambda n: (n.endswith('-doc'), '+' in n, n.endswith('-tests'), n.endswith('-lang'), n)):
        v = bins[n]
        files = v['files']
        site = [f[0][len(SITE):] for f in files if f[0].startswith(SITE)]
        docs = sorted({os.path.relpath(f[0], f'/usr/share/doc/{n}') for f in files
                       if f[0].startswith(f'/usr/share/doc/{n}/') and f[0].count('/') == 5})
        lics = sorted({os.path.basename(f[0]) for f in files if f[0].startswith(f'/usr/share/licenses/{n}/')})
        bin_ = sorted(os.path.basename(f[0]) for f in files if f[0].startswith('/usr/bin/') and not f[5])
        links = {os.path.basename(f[0]): f[5] for f in files if f[0].startswith('/usr/bin/') and f[5]}
        mo = [f[0] for f in files if re.match(r'/usr/share/locale/[^/]+/LC_MESSAGES/[^/]+\.mo$', f[0])]
        other = [f[0] for f in files if not (f[0].startswith(SITE) or f[0].startswith('/usr/bin/') or
                 f[0].startswith('/usr/share/doc/') or f[0].startswith('/usr/share/licenses/') or
                 f[0].startswith('/usr/share/locale/'))]
        L = [f'name = {q(n)}']
        if n.endswith('-doc'):
            L.append('kind = "sphinx-html"')
            html = [f[0] for f in files if f[0].startswith(f'/usr/share/doc/{n}/')]
            sub = sorted({p.split('/')[5] for p in html if p.count('/') >= 6})
            if sub != ['html']:
                review.append(f'{n}: doc directory is {sub}, not html')
            docs = [d for d in docs if d != 'html']
            docpkg = n
            L.append(f'summary = {q("Documentation for " + project)}')
            L.append('description = """\nHTML documentation for ' + project + ', built from the upstream sources.\n"""')
        elif '+' in n:
            L.append('kind = "extras"')
            L.append(f'extras = [{q(n.split("+", 1)[1])}]')
            if docs or lics or bin_ or other:
                review.append(f'{n}: extras package has files outside the metadata directory')
            P.append(L)
            continue
        elif n.endswith('-tests'):
            L.append('kind = "python-tests"')
            tops = sorted({'/'.join(p.split('/')[:2]) for p in site if '/tests' in p or p.split('/')[1:2] == ['tests']})
            tdirs = sorted({re.match(r'(.*?/tests)(/|$)', p).group(1) for p in site if re.match(r'.*?/tests(/|$)', p)})
            if not tdirs:
                review.append(f'{n}: no tests directory found')
            L.append(f'tests_path = {q(tdirs[0]) if len(tdirs) == 1 else "[" + ", ".join(q(t) for t in tdirs) + "]"}')
            L.append(f'summary = {q("Tests for " + project)}')
            L.append('description = """\nThe upstream test suite of ' + project + '.\n"""')
        elif n.endswith('-lang'):
            L.append('kind = "lang"')
            doms = sorted({os.path.basename(p)[:-3] for p in mo})
            if len(doms) != 1:
                review.append(f'{n}: catalogue domains {doms}')
            locale_dom = doms[0] if doms else None
            L.append(f'summary = {q("Translations for " + project)}')
            L.append('description = """\nCompiled message catalogues for ' + project + '.\n"""')
        elif site:
            L.append('kind = "python"')
            for p in site:
                t = p.split('/')[0]
                if t.endswith(('.dist-info', '.egg-info')) or t == '__pycache__':
                    continue
                if t.endswith('.pth'):
                    review.append(f'{n}: {t} is not reproduced by a pyproject build')
                    continue
                mods.add(t[:-3] if t.endswith('.py') else t)
            L.append(f'modules = [{", ".join(q(m) for m in sorted(mods))}]')
            if mo:
                doms = sorted({os.path.basename(p)[:-3] for p in mo})
                locale_dom = doms[0]
        else:
            L.append('kind = "files"')
            if other:
                review.append(f'{n}: files outside site-packages need install entries: {other[:6]}')
        if bin_:
            L.append(f'bin = [{", ".join(q(b) for b in bin_)}]')
        if links:
            L.append('bin_symlinks = { ' + ', '.join(f'{q(k)} = {q(v)}' for k, v in sorted(links.items())) + ' }')
        if docs:
            L.append(f'docs = [{", ".join(q(d) for d in docs)}]')
        if lics:
            L.append(f'licenses = [{", ".join(q(x) for x in lics)}]')
        if other and L[1] != 'kind = "files"':
            review.append(f'{n}: files outside site-packages: {other[:6]}')
        P.append(L)
    html_in_main = any('docs = [' in l and '"html"' in l for L in P for l in L)
    if docpkg or html_in_main:
        if not os.path.isdir(os.path.join(udir, 'doc', 'source')):
            review.append('rc4 has a -doc package but upstream has no doc/source')
        S.append('doc = "doc/source"')
    S.append('check = "import"')
    br = doc_buildrequires(udir) if (docpkg or html_in_main) else []
    if br:
        S.append(f'buildrequires = [{", ".join(q(b) for b in br)}]')
    if locale_dom:
        S.append(f'locale_domain = {q(locale_dom)}')
        lp = None
        for m in sorted(mods):
            if os.path.isdir(os.path.join(udir, m, 'locale')):
                lp = f'{m}/locale'
        if lp and lp != f'{locale_dom}/locale':
            S.append(f'locale_path = {q(lp)}')
        if not lp:
            review.append(f'locale domain {locale_dom} but no <module>/locale in upstream')
    out = lines + [f'# REVIEW: {r}' for r in review] + ['[source]'] + S + ['']
    for L in P:
        out += ['[[package]]'] + L + ['']
    return '\n'.join(out), review


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--meta', required=True)
    ap.add_argument('--upstream', required=True)
    ap.add_argument('--out', default=os.path.join(HERE, 'defs'))
    ap.add_argument('srpm', nargs='+')
    a = ap.parse_args()
    meta = json.load(open(a.meta))
    udirs = {d: os.path.join(a.upstream, d) for d in os.listdir(a.upstream)}
    # unpacked trees are keyed by their top directory; map tarball stems too
    pins, pypi, lic = manifest()
    for p in list(pins.values()) + list(pypi.values()):
        stem = p['tarball'][:-7]
        if stem not in udirs:
            for d in os.listdir(a.upstream):
                if d.lower().replace('-', '_') == stem.lower().replace('-', '_'):
                    udirs[stem] = os.path.join(a.upstream, d)
    rc = 0
    for s in a.srpm:
        text, review = draft(s, meta, udirs, pins, pypi, lic)
        with open(os.path.join(a.out, s + '.toml'), 'w') as f:
            f.write(text)
        print(f'{s}: {"REVIEW " + "; ".join(review) if review else "ok"}')
        rc = rc or (3 if review else 0)
    return rc


if __name__ == '__main__':
    sys.exit(main())
