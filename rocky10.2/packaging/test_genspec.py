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
    return rows, keys


class Definitions(unittest.TestCase):
    def test_there_are_definitions(self):
        self.assertGreaterEqual(len(DEFS), 3)

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
                self.assertEqual(row[9], src['signing_key'])
                self.assertIn(src['signing_key'], keys)

    def test_sources_are_upstream_or_hagistack_only(self):
        for d in DEFS:
            with self.subTest(d=os.path.basename(d)):
                src, pkgs = genspec.load(d)
                spec = genspec.generate(src, pkgs)
                for line in spec.splitlines():
                    m = re.match(r'(Source|Patch)\d*:\s*(\S+)', line)
                    if not m:
                        continue
                    self.assertEqual(m.group(1), 'Source', 'no patches in phase 1')
                    v = m.group(2)
                    if '/' in v:
                        self.assertRegex(v, r'^https://(tarballs|releases)\.openstack\.org/')
                    else:
                        self.assertTrue(os.path.isfile(os.path.join(HERE, 'files', src['name'], v)), v)
                self.assertNotRegex(spec.lower(), r'rdo|delorean|distgit')

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
                    self.assertIn('Hagistack', open(os.path.join(fdir, f)).read(), f)


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

    def test_bad_mode(self):
        self.refused(self.BASE + '[[package]]\nname = "a"\nkind = "files"\n'
                     'dirs = [{ path = "/x" }]\ninstall = [{ src = "upstream:x", dest = "/x", mode = "755" }]\n')


if __name__ == '__main__':
    unittest.main(verbosity=1)
