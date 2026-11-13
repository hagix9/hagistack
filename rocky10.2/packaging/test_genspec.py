#!/usr/bin/python3
"""Tests for genspec.py and for the definitions in defs/. Run: python3 -I test_genspec.py

Static checks only (no rpmbuild): every definition loads and generates; pins
agree with ../gazpacho.manifest; sources come only from OpenStack's release
servers and Hagistack's own files; bad definitions are refused.
"""
import glob
import os
import re
import sys
import tempfile
import unittest

# Never write bytecode next to the sources (packaging/__pycache__ must stay as it is).
sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import genspec  # noqa: E402

MANIFEST = os.path.join(HERE, '..', 'gazpacho.manifest')
DEFS = sorted(glob.glob(os.path.join(HERE, 'defs', '*.toml')))


def manifest_rows():
    rows, keys = {}, {}
    for line in open(MANIFEST):
        f = line.split()
        if not f or f[0].startswith('#'):
            continue
        if f[0] == 'KEY':
            keys[f[1]] = f[2]
        elif len(f) >= 10 and re.fullmatch(r'[0-9a-f]{40}', f[2]):
            rows[f[7]] = f   # keyed by tarball sha256
        elif f[0] == 'PYPI':
            rows[f[5]] = ['PYPI', f[1], '', '', f[3], '', f[4], f[5], f[2], '']
        elif f[0] in ('LICENSE', 'PATCH'):
            keys.setdefault('files', {})[f[-2] if f[0] == 'LICENSE' else f[-2]] = f[-1]
    return rows, keys


class Definitions(unittest.TestCase):
    def test_there_are_definitions(self):
        self.assertGreaterEqual(len(DEFS), 64)

    def test_each_definition_generates(self):
        for d in DEFS:
            with self.subTest(d=os.path.basename(d)):
                src, pkgs = genspec.load(d)
                spec = genspec.generate(src, pkgs)
                self.assertIn(f'Name:           {src["name"]}', spec)
                self.assertNotRegex(spec, r'@[A-Z_]+@')

    def test_pins_match_the_manifest(self):
        rows, keys = manifest_rows()
        for d in DEFS:
            with self.subTest(d=os.path.basename(d)):
                src, _ = genspec.load(d)
                row = rows.get(src['sha256'])
                self.assertIsNotNone(row, 'tarball sha256 not pinned in gazpacho.manifest')
                self.assertEqual(row[6], src['tarball'])
                self.assertEqual(row[4], src['version'])
                self.assertEqual(row[8], src['project'])
                if src.get('origin', 'openstack') == 'openstack':
                    self.assertEqual(row[9], src['signing_key'])
                    self.assertIn(src['signing_key'], keys)
                for it in src.get('patches', []) + src.get('extra_licenses', []):
                    f = os.path.join(HERE, '..', it['path'])
                    self.assertTrue(os.path.isfile(f), it['path'])
                    self.assertEqual(keys.get('files', {}).get(it['path']), it['sha256'],
                                     f'{it["path"]}: pin differs from its LICENSE/PATCH row in gazpacho.manifest')
                    import hashlib
                    with open(f, 'rb') as fh:
                        self.assertEqual(hashlib.sha256(fh.read()).hexdigest(), it['sha256'], it['path'])

    def test_every_licence_and_patch_row_is_used(self):
        _, keys = manifest_rows()
        used = set()
        for d in DEFS:
            src, _ = genspec.load(d)
            used |= {it['path'] for it in src.get('patches', []) + src.get('extra_licenses', [])}
        self.assertEqual(set(keys.get('files', {})), used)

    def test_package_names_are_unique_across_definitions(self):
        seen = {}
        for d in DEFS:
            _, pkgs = genspec.load(d)
            for p in pkgs:
                with self.subTest(pkg=p['name']):
                    self.assertNotIn(p['name'], seen, f'also in {seen.get(p["name"])}')
                seen[p['name']] = os.path.basename(d)

    def test_names_option_lists_every_package(self):
        import contextlib
        import io
        for d in DEFS[:5]:
            _, pkgs = genspec.load(d)
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                self.assertEqual(genspec.main([d, '--names']), 0)
            self.assertEqual(out.getvalue().split(), [p['name'] for p in pkgs])

    def test_sources_are_upstream_or_hagistack_only(self):
        for d in DEFS:
            with self.subTest(d=os.path.basename(d)):
                src, pkgs = genspec.load(d)
                spec = genspec.generate(src, pkgs)
                for line in spec.splitlines():
                    m = re.match(r'(Source|Patch)(\d*):\s*(\S+)', line)
                    if not m:
                        continue
                    v = m.group(3)
                    pinned = {os.path.basename(it['path']) for it in src.get('patches', []) + src.get('extra_licenses', [])}
                    if '/' in v:
                        self.assertRegex(v, r'^https://(tarballs\.openstack\.org|releases\.openstack\.org|files\.pythonhosted\.org)/')
                    elif v in pinned or v == 'HAGISTACK-LICENSE':
                        pass
                    elif v in genspec.DOC_SOURCES:
                        self.assertTrue(os.path.isfile(os.path.join(genspec.DOC_BRANDING_DIR, v)), v)
                    else:
                        self.assertEqual(m.group(1), 'Source')
                        self.assertTrue(os.path.isfile(os.path.join(HERE, 'files', src['name'], v)), v)
                self.assertNotRegex(spec.lower(), r'\brdo\b|delorean|distgit|rdoproject')

    def test_hagistack_files_are_used_and_marked(self):
        for d in DEFS:
            src, pkgs = genspec.load(d)
            used = set(genspec.hagistack_files(src, pkgs))
            fdir = os.path.join(HERE, 'files', src['name'])
            if not os.path.isdir(fdir):
                continue
            present = {f for f in os.listdir(fdir) if f != 'AUTHORING.md'}
            with self.subTest(d=os.path.basename(d)):
                self.assertEqual(used, present, 'every file in files/<name>/ is used, and only those')
                for f in present:
                    with open(os.path.join(fdir, f), 'rb') as fh:
                        self.assertIn(b'Hagistack', fh.read(), f)


class HagistackLicence(unittest.TestCase):
    def test_licence_copy_matches_the_repository_licence(self):
        root = os.path.join(HERE, '..', '..', 'LICENSE')
        if not os.path.exists(root):        # builder mounts rocky10.2/ only
            self.skipTest('repository LICENSE not visible here')
        with open(root, 'rb') as a, open(os.path.join(HERE, 'HAGISTACK-LICENSE'), 'rb') as b:
            self.assertEqual(a.read(), b.read())

    def test_packages_with_hagistack_files_say_mit_and_ship_the_text(self):
        for d in DEFS:
            src, pkgs = genspec.load(d)
            spec = genspec.generate(src, pkgs)
            self.assertIn('Source99:       HAGISTACK-LICENSE', spec)
            ids = lambda e: set(re.findall(r'[A-Za-z0-9.+-]+', e)) - {'AND', 'OR', 'WITH'}
            srpm_tag = re.search(r'^License:\s+(.+)$', spec, re.M).group(1)
            for p in pkgs:
                if genspec.ships_hagistack_text(src, p):
                    with self.subTest(pkg=p['name']):
                        self.assertIn('MIT', ids(genspec.pkg_license(src, p)))
                        # the source package's tag covers what the SRPM carries
                        self.assertIn('MIT', ids(srpm_tag))
            for tag in re.findall(r'^License:\s+(.+)$', spec, re.M):
                with self.subTest(d=os.path.basename(d), tag=tag):
                    terms = re.findall(r'[A-Za-z0-9.+-]+', tag)
                    named = [t for t in terms if t not in ('AND', 'OR', 'WITH')]
                    self.assertEqual(len(named), len(set(named)), 'a licence named twice')

    def test_with_mit(self):
        self.assertEqual(genspec.with_mit('Apache-2.0'), 'Apache-2.0 AND MIT')
        self.assertEqual(genspec.with_mit('Apache-2.0 AND MIT'), 'Apache-2.0 AND MIT')
        self.assertEqual(genspec.with_mit('MIT'), 'MIT')
        self.assertEqual(genspec.with_mit('MIT-0'), 'MIT-0 AND MIT')
        self.assertEqual(genspec.with_mit('CC-BY-4.0 AND OFL-1.1 AND MIT'), 'CC-BY-4.0 AND OFL-1.1 AND MIT')


class ChangesNotice(unittest.TestCase):
    """B2: every edit of an upstream tree is declared, listed in %changelog and
    installed as HAGISTACK-CHANGES in every binary package with files."""

    EDITED = {'openstack-neutron', 'python-django-horizon', 'python3-qrcode', 'python-barbicanclient',
              'python-keystoneauth1', 'python-keystonemiddleware',
              # stage 6-5-R1: build-time changes to installed files
              'openstack-keystone', 'openstack-placement', 'openstack-nova',
              # stage 6-5-R2: rpm's shebang rewriting of a shipped test script
              'python-openstacksdk', 'python-os-ken'}

    def test_exactly_the_edited_sources_declare_changes(self):
        declared = {genspec.load(d)[0]['name'] for d in DEFS if genspec.load(d)[0].get('changes')}
        self.assertEqual(declared, self.EDITED)

    def test_every_html_documentation_build_replaces_the_theme_logos(self):
        built = 0
        for d in DEFS:
            src, pkgs = genspec.load(d)
            dirs = genspec.html_dirs(src, pkgs)
            spec = genspec.generate(src, pkgs)
            with self.subTest(d=os.path.basename(d)):
                if not dirs:
                    self.assertNotIn(genspec.DOC_CHANGE, spec)
                    self.assertNotIn('hagistack-doc-', spec)
                    continue
                built += 1
                self.assertIn(genspec.DOC_CHANGE, genspec.all_changes(src))
                for i, f in enumerate(genspec.DOC_SOURCES):
                    self.assertIn(f'Source{80 + i}:       {f}', spec)
                build = spec.split('%build\n', 1)[1].split('%install\n', 1)[0]
                for h in dirs:
                    after = build.split(f'rm -rf {h}/.buildinfo\n', 1)[1]
                    for rel, f in genspec.DOC_BRANDING:
                        self.assertIn(f"test -f '{h}/_static/{rel}' || {{", after)
                        self.assertIn(f"cp -p '%{{SOURCE{80 + genspec.DOC_SOURCES.index(f)}}}' '{h}/_static/{rel}'", after)
                    # the guard: any logo-named file or icon left under _static that is not Hagistack's stops the build
                    self.assertRegex(after, r"find '%s/_static' -type f .*-iname '\*logo\*' -o -iname '\*\.ico'.* \|\| exit 1" % h)
        self.assertEqual(built, 47)

    def test_release_check_uses_the_same_doc_table(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('release_check', os.path.join(HERE, '..', 'release_check.py'))
        rc = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(rc)
        self.assertEqual(rc.DOC_BRANDING, dict(genspec.DOC_BRANDING))

    def test_doc_branding_files_exist_and_say_hagistack(self):
        for f in genspec.DOC_SOURCES:
            with open(os.path.join(genspec.DOC_BRANDING_DIR, f), 'rb') as fh:
                self.assertIn(b'Hagistack', fh.read(), f)
        self.assertEqual(sorted(os.listdir(genspec.DOC_BRANDING_DIR)), genspec.DOC_SOURCES)

    def test_stated_changes_need_a_dated_entry(self):
        for d in DEFS:
            src, _ = genspec.load(d)
            if genspec.all_changes(src):
                self.assertIn('changelog_date', src, d)

    def test_every_package_installs_the_notice_and_the_changelog_lists_each_change(self):
        for d in DEFS:
            src, pkgs = genspec.load(d)
            if not genspec.all_changes(src):
                continue
            spec = genspec.generate(src, pkgs)
            with self.subTest(d=os.path.basename(d)):
                self.assertIn("cat > HAGISTACK-CHANGES <<'HAGISTACK_CHANGES_EOF'", spec)
                body = spec.split("HAGISTACK_CHANGES_EOF'\n", 1)[1].split('\nHAGISTACK_CHANGES_EOF\n', 1)[0]
                log = spec.split('%changelog\n', 1)[1]
                for c in genspec.all_changes(src):
                    self.assertIn(genspec.rpm_text('- ' + c), body)
                    self.assertIn(genspec.rpm_text('- ' + c), log)
                for i, it in enumerate(src.get('patches', [])):
                    self.assertIn(f'Patch{i + 1:04d}: {os.path.basename(it["path"])}', body)
                    self.assertIn(f'Patch{i + 1:04d}: {os.path.basename(it["path"])}', log)
                self.assertIn(f'{src["release"]}\n', log.splitlines()[0] + '\n')
                files = spec.split('\n%files', )[1:]
                for p in pkgs:
                    if p['kind'] == 'extras':
                        continue
                    sect = next(f for f in files if f.split('\n', 1)[0].split(' -f ')[0].strip() in
                                ('' if p['name'] == src['name'] else f'-n {p["name"]}',))
                    with self.subTest(pkg=p['name']):
                        self.assertIn('%license HAGISTACK-LICENSE', sect)
                        # nodocs-safe: a plain file outside /usr/share/doc, listed once, never %doc
                        path = f'%{{_datadir}}/hagistack/changes/{p["name"]}/HAGISTACK-CHANGES'
                        lines = sect.split('\n%changelog', 1)[0].splitlines()
                        self.assertEqual(lines.count(path), 1)
                        self.assertEqual([ln for ln in lines if 'HAGISTACK-CHANGES' in ln], [path])
                        for d in ('%{_datadir}/hagistack', '%{_datadir}/hagistack/changes',
                                  f'%{{_datadir}}/hagistack/changes/{p["name"]}'):
                            self.assertEqual(lines.count('%dir ' + d), 1, d)
                        self.assertIn(f'install -p -D -m 0644 HAGISTACK-CHANGES %{{buildroot}}{path}', spec)
                        self.assertIn('MIT', genspec.pkg_license(src, p))
                self.assertNotIn('%doc HAGISTACK-CHANGES', spec)
                self.assertNotIn('_docdir}/' + 'HAGISTACK', spec)

    def test_no_spec_puts_the_notice_under_docdir(self):
        for d in DEFS:
            src, pkgs = genspec.load(d)
            spec = genspec.generate(src, pkgs)
            with self.subTest(d=os.path.basename(d)):
                for ln in spec.splitlines():
                    if 'HAGISTACK-CHANGES' in ln and not ln.startswith(('cat >', '- ', 'install -p -D -m 0644 HAGISTACK-CHANGES')):
                        self.assertRegex(ln, r'^%\{_datadir\}/hagistack/changes/[A-Za-z0-9+._-]+/HAGISTACK-CHANGES$|'
                                             r'^(This|The|Changes|listed in) |HAGISTACK-CHANGES under', ln)
                self.assertNotIn('%{_docdir}/', ''.join(l for l in spec.splitlines(True) if 'HAGISTACK-CHANGES' in l))

    def test_marked_files_get_the_comment_and_are_listed(self):
        marked = {}
        for d in DEFS:
            src, pkgs = genspec.load(d)
            if not src.get('mark_files'):
                continue
            marked[src['name']] = len(src['mark_files'])
            spec = genspec.generate(src, pkgs)
            prep = spec.split('%prep\n', 1)[1].split('%generate_buildrequires', 1)[0]
            build = spec.split('%build\n', 1)[1].split('%install\n', 1)[0]
            notice = spec.split("HAGISTACK_CHANGES_EOF'\n", 1)[1].split('\nHAGISTACK_CHANGES_EOF\n', 1)[0]
            with self.subTest(d=os.path.basename(d)):
                for it in src['mark_files']:
                    where = build if it.get('stage') == 'build' else prep
                    self.assertIn(f"test -f '{it['path']}' || {{", where)
                    self.assertIn(f"grep -qxF '{genspec.MARK}' '{it['path']}' || exit 1", where)
                    self.assertIn(f"- {it['path']}", notice)
                if any(it.get('stage') == 'build' for it in src['mark_files']):
                    # marked after the samples are generated and scrubbed
                    self.assertGreater(build.index('grep -qxF'), build.index(src['build_extra'][-1][:40]))
        self.assertEqual(marked, {'openstack-neutron': 26, 'python-django-horizon': 1, 'python3-qrcode': 1,
                                  'openstack-keystone': 2, 'openstack-placement': 2, 'openstack-nova': 1,
                                  'python-openstacksdk': 1, 'python-os-ken': 1})

    def test_mark_text_is_safe_in_the_shell_and_awk(self):
        self.assertNotIn("'", genspec.MARK)
        self.assertNotIn('%', genspec.MARK)
        self.assertTrue(genspec.MARK.startswith('# '))

    def test_percent_is_escaped(self):
        self.assertEqual(genspec.rpm_text('100% and %prep'), '100%% and %%prep')

    def test_the_dashboard_replaces_every_upstream_logo_image(self):
        # Every image of Horizon 25.7.3 that shows the OpenStack logo.
        src, pkgs = genspec.load(os.path.join(HERE, 'defs', 'python-django-horizon.toml'))
        dests = {it['dest'] for it in src['replace_files']}
        self.assertEqual(dests, {f'openstack_dashboard/static/dashboard/img/{n}' for n in
                                 ('logo.svg', 'logo-splash.svg', 'favicon.ico', 'apple-touch-icon.png',
                                  'safari-pinned-tab.svg')} |
                         {f'openstack_dashboard/themes/material/templates/material/{n}' for n in
                          ('openstack-one-color.svg', 'openstack-one-color-alt.svg')})
        spec = genspec.generate(src, pkgs)
        prep = spec.split('%prep\n', 1)[1].split('%generate_buildrequires', 1)[0]
        for it in src['replace_files']:
            self.assertIn(f"test -f '{it['dest']}' || exit 1", prep)
            self.assertRegex(prep, r"cp -p '%\{SOURCE1\d\d\}' '" + re.escape(it['dest']) + "'")
        # replaced before anything is built or collected
        self.assertLess(spec.index("cp -p '%{SOURCE105}'"), spec.index('%pyproject_wheel'))


class Refusals(unittest.TestCase):
    BASE = '''[source]
name = "python-x"
project = "x"
version = "1.0"
release = "1"
tarball = "x-1.0.tar.gz"
sha256 = "%s"
signing_key = "0x%s"
license = "Apache-2.0"
summary = "s"
description = "d"
''' % ('a' * 64, 'b' * 40)

    def load(self, text):
        with tempfile.NamedTemporaryFile('w', suffix='.toml', delete=False) as f:
            f.write(text)
        try:
            return genspec.load(f.name)
        finally:
            os.unlink(f.name)

    def test_minimal_definition_loads(self):
        src, pkgs = self.load(self.BASE + '[[package]]\nname = "python3-x"\nkind = "python"\nmodules = ["x"]\n')
        self.assertIn('%pyproject_save_files -l x', genspec.generate(src, pkgs))

    def refused(self, text):
        with self.assertRaises(genspec.DefError):
            src, pkgs = self.load(text)
            genspec.generate(src, pkgs)

    def test_unknown_key(self):
        self.refused(self.BASE + 'colour = "red"\n[[package]]\nname = "a"\nkind = "python"\n')

    def test_bad_sha(self):
        self.refused(self.BASE.replace('a' * 64, 'A' * 64) + '[[package]]\nname = "a"\nkind = "python"\n')

    def test_bad_kind(self):
        self.refused(self.BASE + '[[package]]\nname = "a"\nkind = "binary"\n')

    def test_missing_hagistack_file(self):
        self.refused(self.BASE + '[[package]]\nname = "a"\nkind = "files"\n'
                     'install = [{ src = "file:nope.service", dest = "/x" }]\n')

    def test_install_source_must_be_upstream_or_file(self):
        self.refused(self.BASE + '[[package]]\nname = "a"\nkind = "files"\n'
                     'install = [{ src = "https://example.invalid/x", dest = "/x" }]\n')

    def test_duplicate_package(self):
        self.refused(self.BASE + '[[package]]\nname = "a"\nkind = "files"\n[[package]]\nname = "a"\nkind = "files"\n')

    def test_tests_package_needs_python_package(self):
        self.refused(self.BASE + '[[package]]\nname = "a"\nkind = "python-tests"\ntests_path = "x/tests"\n')

    def test_edits_without_changes_are_refused(self):
        pkg = '[[package]]\nname = "a"\nkind = "files"\n'
        self.refused(self.BASE + 'prep_extra = ["sed -i s/a/b/ x"]\n' + pkg)

    def test_bad_changes_and_replace_files_are_refused(self):
        pkg = '[[package]]\nname = "a"\nkind = "files"\n'
        self.refused(self.BASE + 'changes = ["two\\nlines"]\n' + pkg)
        self.refused(self.BASE + 'changes = ["x HAGISTACK_CHANGES_EOF"]\n' + pkg)
        self.refused(self.BASE + 'changes = ["c"]\nchangelog_date = "2026-11-13"\n' + pkg)
        self.refused(self.BASE + 'changes = ["c"]\nreplace_files = [{ src = "file:nope.svg", dest = "a/b.svg" }]\n' + pkg)
        self.refused(self.BASE + 'changes = ["c"]\nreplace_files = [{ src = "upstream:x", dest = "a/b.svg" }]\n' + pkg)

    def test_replace_dest_must_stay_in_the_tree(self):
        pkg = '[[package]]\nname = "a"\nkind = "files"\n'
        hz = self.BASE.replace('name = "python-x"', 'name = "python-django-horizon"')
        for dest in ('/etc/passwd', '../x', 'a/../../x', "a'b"):
            with self.subTest(dest=dest):
                self.refused(hz + 'changes = ["c"]\nreplace_files = [{ src = "file:hagistack-logo.svg", dest = "%s" }]\n' % dest + pkg)
        self.load(hz + 'changes = ["c"]\nchangelog_date = "Fri Nov 13 2026"\n'
                  'replace_files = [{ src = "file:hagistack-logo.svg", dest = "a/b.svg" }]\n' + pkg)

    def test_bad_mark_files_are_refused(self):
        base = self.BASE + 'changes = ["c"]\nchangelog_date = "Fri Nov 13 2026"\n'
        pkg = '[[package]]\nname = "a"\nkind = "files"\n'
        for entry in ('{ path = "/etc/x.conf" }', '{ path = "../x.py" }', '{ path = "a/logo.svg" }',
                      '{ path = "x.py", stage = "install" }', '{ path = "x.py", other = 1 }', '{ stage = "prep" }'):
            with self.subTest(entry=entry):
                self.refused(base + 'mark_files = [%s]\n' % entry + pkg)
        self.refused(self.BASE + 'mark_files = [{ path = "x.py" }]\n' + pkg)       # no changes
        self.load(base + 'mark_files = [{ path = "x.py" }, { path = "etc/a.conf.sample", stage = "build" }]\n' + pkg)

    def test_changes_without_a_date_are_refused(self):
        pkg = '[[package]]\nname = "a"\nkind = "files"\n'
        self.refused(self.BASE + 'changes = ["c"]\n' + pkg)
        self.load(self.BASE + 'changes = ["c"]\nchangelog_date = "Fri Nov 13 2026"\n' + pkg)

    def test_bad_mode(self):
        self.refused(self.BASE + '[[package]]\nname = "a"\nkind = "files"\n'
                     'dirs = [{ path = "/x" }]\ninstall = [{ src = "upstream:x", dest = "/x", mode = "755" }]\n')


if __name__ == '__main__':
    unittest.main(verbosity=1)
