#!/usr/bin/env python3
"""Tests for spec-adapt: the engine, the manifest pins, the rules against the REAL
pinned RDO inputs, and the third-party Neutron patches.

  python3 rocky10.2/spec-adapt/test_adapt.py            run everything
  SPEC_ADAPT_INPUTS=DIR  keep downloaded RDO inputs in DIR/<package>/<file>
  SPEC_ADAPT_SKIP_NETWORK=1  skip the tests that need the network (reported as skipped)

The RDO inputs are not stored in this repository. They are fetched at the commit and
file the manifest names and are only used if their SHA-256 is the pinned one, so what
these tests run against is exactly what the build runs against. Test mutations are
written as patterns over that fetched text; no whole RDO line is quoted here.
"""
import hashlib
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import adapt  # noqa: E402
import rules  # noqa: E402

GAZPACHO = os.path.join(ROOT, 'gazpacho.manifest')
EPOXY = os.path.join(ROOT, 'epoxy.manifest')
PKGS, SPECS, PATCHES = adapt.parse_manifest(GAZPACHO)
NETWORK = not os.environ.get('SPEC_ADAPT_SKIP_NETWORK')
INPUTS = os.environ.get('SPEC_ADAPT_INPUTS') or tempfile.mkdtemp(prefix='spec-adapt-inputs-')
# the 28.0.2 tag of openstack/neutron
NEUTRON_28_0_2 = 'd87ec8ef84f76a1fdd501cb70bef519c3b82e7b1'


def sha(b):
    return hashlib.sha256(b).hexdigest()


def fetch(url):
    with urllib.request.urlopen(url, timeout=60) as r:
        return r.read()


def real_input(pkg, name):
    """The pinned RDO file, fetched once and checked against the manifest's pin."""
    path = os.path.join(INPUTS, pkg, name)
    if not os.path.isfile(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        p = PKGS[pkg]
        data = fetch('https://raw.githubusercontent.com/rdo-packages/%s/%s/%s'
                     % (p['repo'], p['commit'], name))
        with open(path, 'wb') as fh:
            fh.write(data)
    with open(path, 'rb') as fh:
        data = fh.read()
    assert sha(data) == SPECS[pkg][name][0], 'fetched %s/%s is not the pinned input' % (pkg, name)
    return data


def real_inputs(pkg):
    return {n: real_input(pkg, n) for n in rules.RULES[pkg]['files']}


def run_pkg(pkg, files, pins=None, rule=None):
    """Adapt `files` ({name: bytes}) with the pinned rules; returns {name: bytes}."""
    return adapt.adapt_texts(pkg, rule or rules.RULES[pkg], pins or SPECS[pkg], files.__getitem__)


def repin(pkg, files, keep_output=False):
    """Pins that accept `files` as the input, so that the OPERATION checks are what fires."""
    return {n: (sha(b), SPECS[pkg][n][1] if keep_output else '0' * 64) for n, b in files.items()}


# --- mutations, as patterns over bytes -------------------------------------------------
def drop(rx):
    return lambda b: re.sub(rx + rb'.*\n', b'', b, count=1, flags=re.M)


def dup(rx):
    return lambda b: re.sub(rb'(^' + rx + rb'.*\n)', rb'\1\1', b, count=1, flags=re.M)


def sub(rx, rep, count=1):
    return lambda b: re.sub(rx, rep, b, count=count)


def snapshot(tree):
    out = {}
    for n in os.listdir(tree):
        with open(os.path.join(tree, n), 'rb') as fh:
            out[n] = fh.read()
    return out


def mutate(files, per_file):
    return {n: per_file.get(n, lambda b: b)(b) for n, b in files.items()}


def needs_network(cls):
    return unittest.skipIf(not NETWORK, 'SPEC_ADAPT_SKIP_NETWORK is set')(cls)


# ===========================================================================
# 1. the engine, on text written for this test (no third-party text at all)
# ===========================================================================
TOY = ('%global flag 1\n'
       '%global brs a b\n'
       '%global brs %{brs} c\n'
       'Name: toy\n'
       'BuildArch: noarch\n'
       'Requires: x+extra = 1\n'
       '%prep\n'
       '# about the next line\n'
       'old-thing arg\n'
       '%install\n'
       'install QQ %{buildroot}/one\n'
       'subpkg one two three\n'
       '%files\n'
       '/usr/bin/one\n'
       '/usr/bin/two\n'
       '%files sub\n'
       '/usr/bin/three\n')


def toy_rules(*ops):
    return dict(version='1', files=['t.spec'], ops=[('t.spec', o[1]) for o in ops])


def toy_run(*ops, text=TOY):
    return adapt.apply_rules(toy_rules(*ops), {'t.spec': text})['t.spec']


class EngineTests(unittest.TestCase):
    def stops(self, pattern, *ops, text=TOY):
        with self.assertRaisesRegex(adapt.Stop, pattern):
            toy_run(*ops, text=text)

    def test_global_set(self):
        out = toy_run(rules.global_set('t.spec', 'flag', '1', '0'))
        self.assertIn('%global flag 0\n', out)
        self.stops('value is', rules.global_set('t.spec', 'flag', '2', '0'))        # old value
        self.stops('0 matching', rules.global_set('t.spec', 'nope', '1', '0'))      # missing
        self.stops('2 matching', rules.global_set('t.spec', 'brs', 'a', 'b'))       # not unique

    def test_global_prepend(self):
        out = toy_run(rules.global_prepend('t.spec', 'brs', ['z', 'y']))
        self.assertIn('%global brs z y a b\n', out)
        self.assertIn('%global brs %{brs} c\n', out)          # the self-extending line is untouched
        self.stops('already present', rules.global_prepend('t.spec', 'brs', ['a']))

    def test_replace_lines_and_absorb(self):
        out = toy_run(rules.replace_lines('t.spec', '%files*', 2, text=['/usr/bin/new'],
                                          ends=('/two', '/three')))
        self.assertIn('/usr/bin/new\n', out)
        self.assertNotIn('/two', out)
        self.assertNotIn('/three', out)
        out = toy_run(rules.replace_lines('t.spec', '%prep', 1, absorb=1, has=('old-thing',)))
        self.assertNotIn('about the next line', out)
        self.assertNotIn('old-thing', out)
        self.stops('comment line', rules.replace_lines('t.spec', '%prep', 1, absorb=2, has=('old-thing',)))
        # without absorb the comment stays
        self.assertIn('about the next line',
                      toy_run(rules.replace_lines('t.spec', '%prep', 1, has=('old-thing',))))

    def test_selector_count_is_exact(self):
        self.stops('expected 2 line.*found 1', rules.replace_lines('t.spec', '%files*', 2, ends=('/one',)))
        self.stops('expected 1 line.*found 3', rules.replace_lines('t.spec', '%files*', 1, starts='/usr/bin'))
        self.stops('found 0', rules.replace_lines('t.spec', '%files nonesuch', 1, ends=('/one',)))  # scope
        self.stops('found 0', rules.replace_lines('t.spec', '%files*', 1, ends=('/gone',)))        # missing

    def test_comments_are_never_targets(self):
        self.stops('found 0', rules.replace_lines('t.spec', 'any', 1, has=('about the next',)))

    def test_token_replace_and_word_remove(self):
        out = toy_run(rules.token_replace('t.spec', '%install', 1, 'QQ', 'ZZ', starts='install'),
                      rules.word_remove('t.spec', '%install', 1, 'two', starts='subpkg'))
        self.assertIn('install ZZ %{buildroot}/one\n', out)
        self.assertIn('subpkg one three\n', out)
        self.stops('occurs 2 times', rules.token_replace('t.spec', '%install', 1, 'QQ', 'ZZ', starts='install'),
                   text=TOY.replace('install QQ', 'install QQ QQ'))
        self.stops('occurs 0 times', rules.word_remove('t.spec', '%install', 1, 'zzz', starts='subpkg'))

    def test_insert_before_after_and_already_applied(self):
        op = rules.insert('t.spec', 'preamble', 'before', ['# Hagistack was here'], starts='BuildArch:')
        out = toy_run(op)
        self.assertLess(out.index('# Hagistack was here'), out.index('BuildArch:'))
        out = toy_run(rules.insert('t.spec', 'preamble', 'after', ['# after'], starts='BuildArch:'))
        self.assertLess(out.index('BuildArch:'), out.index('# after'))
        self.stops('already present', op, text=out.replace('# after', '# Hagistack was here'))

    def test_unknown_operation(self):
        with self.assertRaisesRegex(adapt.Stop, 'unknown operation'):
            toy_run(('t.spec', dict(op='sed')))

    def test_line_splitting_is_newline_only(self):
        text = 'a\x0cb\nc\u2028d\n'
        self.assertEqual(adapt.split_lines(text), ['a\x0cb\n', 'c\u2028d\n'])
        self.assertEqual(adapt.split_lines('no newline'), ['no newline'])

    def test_sections(self):
        self.assertEqual(adapt.scopes(['x\n', '%prep\n', 'y\n', '%files  api\n', 'z\n']),
                         ['preamble', '%prep', '%prep', '%files api', '%files api'])


# ===========================================================================
# 2. the manifest: strict parser and consistency with the rules
# ===========================================================================
SHA_A, SHA_B = 'a' * 64, 'b' * 64
COMMIT = 'c' * 40
PKG_ROW = 'pkg  pkg-distgit  %s  pkg.spec  1.0  1  pkg-1.0.tar.gz  %s  pkg  0x%s\n' % (COMMIT, SHA_A, 'd' * 40)


class ManifestTests(unittest.TestCase):
    def parse(self, text):
        with tempfile.NamedTemporaryFile('w', suffix='.manifest', delete=False) as fh:
            fh.write(text)
        try:
            return adapt.parse_manifest(fh.name)
        finally:
            os.unlink(fh.name)

    def rejects(self, text, pattern):
        with self.assertRaisesRegex(adapt.Stop, pattern):
            self.parse(text)

    def test_the_real_manifests_parse_and_agree_with_the_rules(self):
        adapt.check_manifest(GAZPACHO, rules.RULES)
        adapt.check_manifest(EPOXY, rules.RULES)

    def test_a_valid_row_set(self):
        pk, sp, pa = self.parse(PKG_ROW + 'SPEC pkg pkg.spec %s %s\nPATCH pkg x/y.patch %s\n' % (SHA_A, SHA_B, SHA_A))
        self.assertEqual(sp['pkg']['pkg.spec'], (SHA_A, SHA_B))
        self.assertEqual(pa['pkg']['x/y.patch'], SHA_A)
        self.assertEqual(pk['pkg']['commit'], COMMIT)

    def test_unknown_or_malformed_rows_are_errors_not_skipped(self):
        self.rejects('SPECS pkg pkg.spec %s %s\n' % (SHA_A, SHA_B), 'not a KEY/PYPI/SPEC/PATCH row')
        self.rejects(PKG_ROW + 'SPEC pkg pkg.spec %s\n' % SHA_A, 'SPEC needs')
        self.rejects(PKG_ROW + 'SPEC pkg pkg.spec %s %s extra\n' % (SHA_A, SHA_B), 'SPEC needs')
        self.rejects(PKG_ROW + 'SPEC pkg pkg.spec %s %s\n' % ('g' * 64, SHA_B), 'SPEC needs')
        self.rejects(PKG_ROW + 'SPEC pkg pkg.spec %s %s\n' % (SHA_A.upper(), SHA_B), 'SPEC needs')
        self.rejects(PKG_ROW + 'PATCH pkg ../escape.patch %s\n' % SHA_A, 'stay inside')
        self.rejects(PKG_ROW + 'PATCH pkg /abs.patch %s\n' % SHA_A, 'stay inside')
        self.rejects(PKG_ROW + 'PATCH pkg x.patch\n', 'PATCH needs')
        self.rejects(PKG_ROW.replace(COMMIT, COMMIT[:39]), 'not a KEY/PYPI/SPEC/PATCH row')
        self.rejects('KEY 0x1234 abc\n', 'KEY needs')
        self.rejects('PYPI only three fields\n', 'PYPI needs')

    def test_duplicates_and_orphans(self):
        self.rejects(PKG_ROW + PKG_ROW, 'duplicate package')
        spec = 'SPEC pkg pkg.spec %s %s\n' % (SHA_A, SHA_B)
        self.rejects(PKG_ROW + spec + spec, 'duplicate SPEC')
        self.rejects(PKG_ROW + 'PATCH pkg a.patch %s\nPATCH pkg a.patch %s\n' % (SHA_A, SHA_A), 'duplicate PATCH')
        self.rejects(spec, 'unknown package')

    def test_unknown_version_stops(self):
        # the rules are written for one version of each package; a manifest that moves on must stop
        pk = {k: dict(v) for k, v in PKGS.items()}
        pk['nova']['version'] = '33.0.3'
        with self.assertRaisesRegex(adapt.Stop, 'written for version 33.0.2, the manifest builds 33.0.3'):
            adapt.resolve('nova', pk, SPECS, PATCHES, rules.RULES)

    def test_spec_rows_without_rules_stop(self):
        sp = dict(SPECS, glance={'openstack-glance.spec': (SHA_A, SHA_B)})
        with self.assertRaisesRegex(adapt.Stop, 'no rules for it'):
            adapt.resolve('glance', PKGS, sp, PATCHES, rules.RULES)

    def test_rules_without_spec_rows_stop(self):
        sp = {k: v for k, v in SPECS.items() if k != 'nova'}
        with self.assertRaisesRegex(adapt.Stop, 'pins no SPEC input'):
            adapt.resolve('nova', PKGS, sp, PATCHES, rules.RULES)

    def test_spec_rows_must_cover_exactly_the_files_the_rules_edit(self):
        sp = dict(SPECS, placement={'openstack-placement.spec': SPECS['placement']['openstack-placement.spec']})
        with self.assertRaisesRegex(adapt.Stop, 'do not match the files'):
            adapt.resolve('placement', PKGS, sp, PATCHES, rules.RULES)

    def test_patch_rows_must_match_what_the_rules_expect(self):
        with self.assertRaisesRegex(adapt.Stop, 'do not match the patches'):
            adapt.resolve('neutron', PKGS, SPECS, {}, rules.RULES)
        one = {'neutron': dict(list(PATCHES['neutron'].items())[:1])}
        with self.assertRaisesRegex(adapt.Stop, 'do not match the patches'):
            adapt.resolve('neutron', PKGS, SPECS, one, rules.RULES)

    def test_a_package_without_rules_or_rows_is_left_alone(self):
        self.assertIsNone(adapt.resolve('glance', PKGS, SPECS, PATCHES, rules.RULES))

    def test_every_rule_package_is_pinned_and_vice_versa(self):
        self.assertEqual(set(rules.RULES), set(SPECS))
        self.assertEqual(sum(len(v) for v in SPECS.values()), 12)
        self.assertEqual(len(rules.RULES), 11)

    def test_epoxy_does_not_silently_skip_the_rules(self):
        # epoxy.manifest has keystone but no SPEC row for it: building it must stop rather
        # than build an unadapted spec. (The old spec-patches applied cleanly to the 2025.1
        # specs of all five epoxy packages that had one, so a 2025.1 build silently received
        # 2026.1 edits; epoxy is a research record only, and refusing is the safer behaviour.)
        pk, sp, pa = adapt.parse_manifest(EPOXY)
        self.assertIn('keystone', pk)
        with self.assertRaisesRegex(adapt.Stop, 'pins no SPEC input'):
            adapt.resolve('keystone', pk, sp, pa, rules.RULES)


# ===========================================================================
# 3. the rules against the real pinned RDO inputs
# ===========================================================================
def code(text):
    return [ln for ln in text.splitlines() if ln.strip() and not ln.lstrip().startswith('#')]


@needs_network
class PinnedInputTests(unittest.TestCase):
    PACKAGES = sorted(rules.RULES)

    def adapt_one(self, pkg):
        return run_pkg(pkg, real_inputs(pkg))

    def attempt(self, pkg, per_file, pattern, repin_input=True, keep_output=False, source=None, rule=None):
        files = mutate(source if source is not None else real_inputs(pkg), per_file)
        pins = repin(pkg, files, keep_output) if repin_input else None
        with self.assertRaisesRegex(adapt.Stop, pattern):
            run_pkg(pkg, files, pins, rule)

    # --- normal ---------------------------------------------------------------------
    def test_all_eleven_packages_reach_their_pinned_output(self):
        for pkg in self.PACKAGES:
            with self.subTest(pkg=pkg):
                out = self.adapt_one(pkg)
                for name, data in out.items():
                    self.assertEqual(sha(data), SPECS[pkg][name][1])

    def test_adaptation_is_deterministic(self):
        for pkg in self.PACKAGES:
            self.assertEqual(self.adapt_one(pkg), self.adapt_one(pkg))

    def test_the_intended_changes_are_in_the_output(self):
        o = {p: {n: b.decode() for n, b in self.adapt_one(p).items()} for p in self.PACKAGES}
        i = {p: {n: b.decode() for n, b in real_inputs(p).items()} for p in self.PACKAGES}

        def n(text, rx):
            return len([ln for ln in code(text) if re.search(rx, ln)])

        # cliff: no entry for the tests directory is left in any %files
        s = 'python-cliff.spec'
        self.assertEqual(n(i['cliff'][s], r'/%\{modname\}/tests$'), 2)
        self.assertEqual(n(o['cliff'][s], r'/%\{modname\}/tests$'), 0)
        # horizon: docs off, catalogs copied before %find_lang
        s = 'python-django-horizon.spec'
        self.assertRegex(o['horizon'][s], r'(?m)^%global with_doc 0$')
        self.assertLess(o['horizon'][s].index('-name \'*.mo\''), o['horizon'][s].index('%find_lang'))
        # keystone: the uwsgi file replaces the wsgi one everywhere, the two scripts are gone
        s = 'openstack-keystone.spec'
        self.assertEqual(n(o['keystone'][s], r'/keystone-wsgi-(admin|public)'), 0)
        self.assertEqual(n(o['keystone'][s], r'(?<!u)wsgi-keystone\.conf'), 0)
        self.assertEqual(n(o['keystone'][s], r'uwsgi-keystone\.conf'), 2)
        # neutron: the two Patch lines, and neither generated script
        s = 'openstack-neutron.spec'
        self.assertEqual(n(o['neutron'][s], r'^Patch000[12]:'), 2)
        self.assertEqual(n(o['neutron'][s], r'/neutron-(api|server)$'), 0)
        # nova / os-ken / placement: the entries for scripts that no longer exist
        self.assertEqual(n(o['nova']['openstack-nova.spec'], r'/nova-(api\*|metadata-wsgi)$'), 0)
        self.assertEqual(n(o['os-ken']['python-os-ken.spec'], r'/%\{binname\}(-manager)?$'), 0)
        self.assertEqual(n(o['placement']['openstack-placement.spec'], r'/placement-api$'), 0)
        self.assertEqual(n(o['placement']['openstack-placement.spec'], r'@SITELIB@'), 1)
        self.assertEqual(n(o['placement']['placement-api.conf'], r'/usr/bin/placement-api'), 0)
        self.assertEqual(n(o['placement']['placement-api.conf'], r'@SITELIB@/placement/wsgi/api\.py'), 2)
        # PEP 625 metadata directories
        for p, f in (('oslo-cache', 'python-oslo-cache.spec'), ('oslo-privsep', 'python-oslo-privsep.spec')):
            self.assertEqual(n(o[p][f], r'%\{tarsources\}-.*\.dist-info'), 1, p)
            self.assertEqual(n(o[p][f], r'%\{pypi_name\}-.*\.dist-info'), 0, p)
        # oslo-utils / tooz: exclusions and the vanished extra
        self.assertRegex(o['oslo-utils']['python-oslo-utils.spec'], r'(?m)^%global excluded_brs tzdata ')
        t = o['tooz']['python-tooz.spec']
        self.assertRegex(t, r'(?m)^%global excluded_brs kubernetes python-consul2 sherlock sysv-ipc ')
        self.assertEqual(n(t, r'\+zake'), 0)
        self.assertEqual(n(t, r'pyproject_extras_subpkg.*\bzake\b'), 0)

    def test_keystone_whitespace_difference_is_shell_equivalent(self):
        # D3: the one place where the result is not byte-identical to what the old patch
        # produced is a run of two spaces between two arguments of an install command.
        out = self.adapt_one('keystone')['openstack-keystone.spec'].decode()
        (line,) = [ln for ln in out.splitlines() if 'uwsgi-keystone.conf' in ln and ln.startswith('install')]
        # one install command: flags, the source path, the destination; spacing is irrelevant
        words = shlex.split(line)
        self.assertEqual(words[:6], ['install', '-p', '-D', '-m', '644', 'httpd/uwsgi-keystone.conf'])
        self.assertEqual(len(words), 7)
        self.assertTrue(words[6].endswith('/keystone/'))

    # --- negative: every one must stop ----------------------------------------------
    def test_input_sha_mismatch(self):
        for pkg in self.PACKAGES:
            name = rules.RULES[pkg]['files'][0]
            with self.subTest(pkg=pkg):
                self.attempt(pkg, {name: lambda b: b + b'# changed upstream\n'}, 'input SHA-256', repin_input=False)

    def test_already_applied_is_recognised_by_its_output_hash(self):
        for pkg in self.PACKAGES:
            with self.subTest(pkg=pkg):
                out = self.adapt_one(pkg)
                self.attempt(pkg, {}, 'already adapted', repin_input=False, source=out)

    def test_already_applied_stops_in_the_operations_too(self):
        # even with the hash checks out of the way, every package's rules refuse a second run
        for pkg in self.PACKAGES:
            with self.subTest(pkg=pkg):
                out = self.adapt_one(pkg)
                with self.assertRaises(adapt.Stop):
                    run_pkg(pkg, out, repin(pkg, out))

    def test_selector_missing(self):
        cases = [('nova', 'openstack-nova.spec', drop(rb'.*/nova-metadata-wsgi'), r'expected 2 line.*found 1'),
                 ('keystone', 'openstack-keystone.spec', drop(rb'.*/keystone-wsgi-public'), r'expected 2 line.*found 1'),
                 ('oslo-utils', 'python-oslo-utils.spec', drop(rb'%global excluded_brs '), r'0 matching'),
                 ('tooz', 'python-tooz.spec', drop(rb'Requires:.*\+zake'), r'expected 1 line.*found 0'),
                 ('placement', 'placement-api.conf', drop(rb'Alias /placement-api'), r'expected 2 line.*found 1'),
                 ('neutron', 'openstack-neutron.spec', drop(rb'BuildArch:'), r'expected 1 line.*found 0')]
        for pkg, name, fn, pattern in cases:
            with self.subTest(pkg=pkg):
                self.attempt(pkg, {name: fn}, pattern)

    def test_duplicate_selector(self):
        cases = [('os-ken', 'python-os-ken.spec', dup(rb'.*/%\{binname\}-manager')),
                 ('neutron', 'openstack-neutron.spec', dup(rb'.*/neutron-api')),
                 ('cliff', 'python-cliff.spec', dup(rb'.*/%\{modname\}/tests')),
                 ('horizon', 'python-django-horizon.spec', dup(rb'%global with_doc'))]
        for pkg, name, fn in cases:
            with self.subTest(pkg=pkg):
                self.attempt(pkg, {name: fn}, r'found [3-9]|2 matching')

    def test_structural_drift(self):
        cases = [('nova', 'openstack-nova.spec', sub(rb'(?m)^%files api\b', b'%files compute-api'), 'found 0'),
                 ('horizon', 'python-django-horizon.spec', sub(rb'%global with_doc\b', b'%global with_documentation'),
                  '0 matching'),
                 ('keystone', 'openstack-keystone.spec', sub(rb'(?m)^%install\b', b'%installing'), 'found 0'),
                 ('tooz', 'python-tooz.spec', sub(rb'%pyproject_extras_subpkg', b'%pyproject_extra_subpkg'), 'found 0')]
        for pkg, name, fn, pattern in cases:
            with self.subTest(pkg=pkg):
                self.attempt(pkg, {name: fn}, pattern)

    def test_comment_block_above_a_target_changed(self):
        # keystone's first rule takes the comment above the targets with it; if that comment is
        # not the one-line block that was reviewed, the surrounding code is not either
        self.attempt('keystone', {'openstack-keystone.spec': sub(
            rb'(?m)^(#[^\n]*\n)(?=[^\n]*httpd/wsgi-keystone\.conf)', rb'# one more\n\1')}, 'comment line')

    def test_unexpected_old_value(self):
        self.attempt('horizon', {'python-django-horizon.spec': sub(rb'(%global with_doc )1', rb'\g<1>0')},
                     r'value is')
        self.attempt('horizon', {'python-django-horizon.spec': sub(rb'(%global with_doc )1', rb'\g<1>yes')},
                     r'value is')

    def test_token_occurring_twice_in_a_line(self):
        self.attempt('oslo-cache', {'python-oslo-cache.spec': sub(
            rb'(?m)^(.*)(%\{pypi_name\})(.*\.dist-info.*)$', rb'\1\2\2\3')}, r'occurs 2 times')

    def test_over_wide_selector(self):
        self.attempt('neutron', {'openstack-neutron.spec': sub(
            rb'(?m)^(.*/neutron-status)$', rb'\1\n%{_bindir}/another/neutron-api')}, r'found 3')

    def test_unexpected_output(self):
        # a rule edited without re-reviewing the result: the output pin catches it
        rule = dict(rules.RULES['tooz'])
        rule['ops'] = [(f, dict(o, words=o['words'] + ['extra'])) if o['op'] == 'global_prepend' else (f, o)
                       for f, o in rule['ops']]
        self.attempt('tooz', {}, 'output SHA-256', repin_input=False, rule=rule)

    def test_file_that_is_not_utf8(self):
        self.attempt('nova', {'openstack-nova.spec': lambda b: b + b'\xff\xfe\n'}, 'not UTF-8')

    # --- the CLI: nothing is written on failure -------------------------------------
    def stage(self, pkg, tree):
        for name, data in real_inputs(pkg).items():
            with open(os.path.join(tree, name), 'wb') as fh:
                fh.write(data)

    def cli(self, *args):
        return subprocess.run([sys.executable, os.path.join(HERE, 'adapt.py'), *args],
                              capture_output=True, text=True)

    def test_cli_applies_and_installs_the_neutron_patches(self):
        with tempfile.TemporaryDirectory() as tree:
            self.stage('neutron', tree)
            r = self.cli('--manifest', GAZPACHO, '--package', 'neutron', '--tree', tree)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(sorted(os.listdir(tree)), sorted(
                ['openstack-neutron.spec'] + [os.path.basename(p) for p in PATCHES['neutron']]))
            with open(os.path.join(tree, 'openstack-neutron.spec'), 'rb') as fh:
                self.assertEqual(sha(fh.read()), SPECS['neutron']['openstack-neutron.spec'][1])

    def test_cli_failure_exits_1_and_writes_nothing(self):
        with tempfile.TemporaryDirectory() as tree:
            self.stage('placement', tree)
            conf = os.path.join(tree, 'placement-api.conf')
            with open(conf, 'ab') as fh:
                fh.write(b'# tampered\n')          # only the SECOND of the two files is wrong
            before = snapshot(tree)
            r = self.cli('--manifest', GAZPACHO, '--package', 'placement', '--tree', tree)
            self.assertEqual(r.returncode, 1)
            self.assertIn('STOP:', r.stderr)
            self.assertEqual(before, snapshot(tree))

    def test_cli_second_run_stops(self):
        with tempfile.TemporaryDirectory() as tree:
            self.stage('nova', tree)
            self.assertEqual(self.cli('--manifest', GAZPACHO, '--package', 'nova', '--tree', tree).returncode, 0)
            r = self.cli('--manifest', GAZPACHO, '--package', 'nova', '--tree', tree)
            self.assertEqual(r.returncode, 1)
            self.assertIn('already adapted', r.stderr)

    def test_cli_missing_input_file_stops(self):
        with tempfile.TemporaryDirectory() as tree:
            r = self.cli('--manifest', GAZPACHO, '--package', 'nova', '--tree', tree)
            self.assertEqual(r.returncode, 1)
            self.assertIn('is not in the staged distgit', r.stderr)

    def test_cli_refuses_a_patch_name_that_already_exists_in_the_distgit(self):
        with tempfile.TemporaryDirectory() as tree:
            self.stage('neutron', tree)
            clash = os.path.join(tree, os.path.basename(sorted(PATCHES['neutron'])[0]))
            with open(clash, 'wb') as fh:
                fh.write(b'not the pinned patch\n')
            before = snapshot(tree)
            r = self.cli('--manifest', GAZPACHO, '--package', 'neutron', '--tree', tree)
            self.assertEqual(r.returncode, 1)
            self.assertIn('already exists in the staged distgit', r.stderr)
            self.assertEqual(before, snapshot(tree))

    def test_cli_unknown_package_and_bad_usage(self):
        with tempfile.TemporaryDirectory() as tree:
            self.assertEqual(self.cli('--manifest', GAZPACHO, '--package', 'nonesuch', '--tree', tree).returncode, 1)
            self.assertEqual(self.cli('--manifest', GAZPACHO, '--package', 'nova').returncode, 1)
            self.assertEqual(self.cli('--manifest', GAZPACHO, '--check', '--package', 'nova',
                                      '--tree', tree).returncode, 1)
            self.assertEqual(self.cli('--manifest', '/nonexistent', '--check').returncode, 1)

    def test_cli_package_without_rules_is_a_noop(self):
        with tempfile.TemporaryDirectory() as tree:
            r = self.cli('--manifest', GAZPACHO, '--package', 'glance', '--tree', tree)
            self.assertEqual(r.returncode, 0)
            self.assertIn('no adaptation declared', r.stdout)
            self.assertEqual(os.listdir(tree), [])

    def test_cli_patch_hash_mismatch_and_missing(self):
        with tempfile.TemporaryDirectory() as root, tempfile.TemporaryDirectory() as tree:
            third = os.path.join(root, 'third-party', 'neutron')
            os.makedirs(third)
            self.stage('neutron', tree)
            args = ('--manifest', GAZPACHO, '--package', 'neutron', '--tree', tree, '--root', root)
            r = self.cli(*args)                                    # patches missing
            self.assertEqual(r.returncode, 1)
            self.assertIn('is missing', r.stderr)
            for rel in PATCHES['neutron']:
                shutil.copy(os.path.join(ROOT, rel), os.path.join(root, rel))
            victim = os.path.join(root, sorted(PATCHES['neutron'])[0])
            with open(victim, 'ab') as fh:
                fh.write(b'\n')                                    # one byte more
            r = self.cli(*args)
            self.assertEqual(r.returncode, 1)
            self.assertIn('the manifest pins', r.stderr)
            self.assertEqual(sorted(os.listdir(tree)), ['openstack-neutron.spec'])   # nothing was written


# ===========================================================================
# 4. the third-party Neutron patches
# ===========================================================================
TP = os.path.join(ROOT, 'third-party', 'neutron')
NEUTRON_FILES = ('neutron/common/ovn/constants.py',
                 'neutron/plugins/ml2/drivers/ovn/mech_driver/mech_driver.py',
                 'neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/impl_idl_ovn.py',
                 'neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/maintenance.py')


class ThirdPartyTests(unittest.TestCase):
    def read(self, name):
        with open(os.path.join(TP, name), 'rb') as fh:
            return fh.read()

    def test_layout_is_exactly_what_the_manifest_pins(self):
        self.assertEqual(sorted(os.listdir(TP)), sorted(
            ['LICENSE', 'NOTICE.md'] + [os.path.basename(p) for p in PATCHES['neutron']]))
        for rel, want in PATCHES['neutron'].items():
            with open(os.path.join(ROOT, rel), 'rb') as fh:
                self.assertEqual(sha(fh.read()), want, rel)

    def test_the_spec_rule_names_the_pinned_patch_files(self):
        spec_rule = [o for f, o in rules.RULES['neutron']['ops'] if o['op'] == 'insert'][0]
        named = re.findall(r'^Patch000\d:\s+(\S+)', ''.join(spec_rule['text']), re.M)
        self.assertEqual(sorted(named), sorted(os.path.basename(p) for p in PATCHES['neutron']))
        self.assertEqual(sorted(rules.NEUTRON_PATCHES), sorted(PATCHES['neutron']))

    def test_each_patch_records_its_upstream_commit_and_author(self):
        for name, commit in (('0001-Ensure-MaintenanceWorker-lock-set-before-connect.patch',
                              '83f1d8305651a0ab23629c88d70bfa237055158c'),
                             ('0002-Only-set-the-maintenance-worker-lock-on-the-worker.patch',
                              '91abb5e720e1c515dbfbe9b2313fbdff92b2abbf')):
            text = self.read(name).decode()
            self.assertIn('(cherry picked from commit %s)' % commit, text)
            self.assertIn('Signed-off-by: Terry Wilson <twilson@redhat.com>', text)
            self.assertIn(commit, self.read('NOTICE.md').decode())

    def test_the_patches_touch_exactly_the_four_expected_neutron_files(self):
        touched = set()
        for rel in PATCHES['neutron']:
            with open(os.path.join(ROOT, rel)) as fh:
                touched |= set(re.findall(r'^diff --git a/(\S+) b/', fh.read(), re.M))
        self.assertEqual(touched, set(NEUTRON_FILES))

    def test_apache_licence_is_complete_and_notice_is_honest(self):
        lic = self.read('LICENSE').decode()
        self.assertEqual(sha(lic.encode()), 'cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30')
        for marker in ('Apache License', 'Version 2.0, January 2004', '9. Accepting Warranty',
                       'END OF TERMS AND CONDITIONS', 'APPENDIX: How to apply the Apache License'):
            self.assertIn(marker, lic)
        notice = self.read('NOTICE.md').decode()
        for must in ('Copyright 2019 Red Hat, Inc.', 'Apache License, Version 2.0', 'Terry Wilson',
                     '28.0.2', '83f1d8305651a0ab23629c88d70bfa237055158c',
                     '91abb5e720e1c515dbfbe9b2313fbdff92b2abbf', 'Upstream NOTICE file'):
            self.assertIn(must, notice)

    @needs_network
    def test_patches_apply_to_neutron_28_0_2_and_do_what_they_claim(self):
        """Apply both, in order, to the real 28.0.2 sources (patch -p1, as %autosetup -S git does)."""
        with tempfile.TemporaryDirectory() as tree:
            for f in NEUTRON_FILES:
                os.makedirs(os.path.join(tree, os.path.dirname(f)), exist_ok=True)
                with open(os.path.join(tree, f), 'wb') as fh:
                    fh.write(fetch('https://raw.githubusercontent.com/openstack/neutron/%s/%s'
                                   % (NEUTRON_28_0_2, f)))

            def text(f):
                with open(os.path.join(tree, f)) as fh:
                    return fh.read()

            maint = 'neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/maintenance.py'
            impl = 'neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/impl_idl_ovn.py'
            self.assertIn('self._idl.set_lock(MAINTENANCE_NB_IDL_LOCK_NAME)', text(maint))   # the bug is there
            for rel in sorted(PATCHES['neutron']):
                r = subprocess.run(['patch', '-p1', '-F0', '-d', tree, '-i', os.path.join(ROOT, rel)],
                                   capture_output=True, text=True)
                self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            self.assertNotIn('set_lock', text(maint))                          # no longer taken in the worker's __init__
            self.assertIn('MAINTENANCE_NB_IDL_LOCK_NAME = "ovn_db_inconsistencies_periodics"',
                          text('neutron/common/ovn/constants.py'))
            self.assertIn('idl_.set_lock(worker_class.lock_name)', text(impl))   # taken before connecting, per class
            self.assertNotIn('idl_.set_lock(ovn_const.', text(impl))             # 0002 replaced 0001's unconditional form
            self.assertIn('worker_class.lock_name = ovn_const.MAINTENANCE_NB_IDL_LOCK_NAME',
                          text('neutron/plugins/ml2/drivers/ovn/mech_driver/mech_driver.py'))

    @needs_network
    def test_0001_alone_would_be_wrong(self):
        # why the two are carried together: with only 0001 the unconditional request is made
        # for every worker class that shares the code path
        with tempfile.TemporaryDirectory() as tree:
            impl = 'neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/impl_idl_ovn.py'
            for f in (impl, 'neutron/common/ovn/constants.py',
                      'neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/maintenance.py'):
                os.makedirs(os.path.join(tree, os.path.dirname(f)), exist_ok=True)
                with open(os.path.join(tree, f), 'wb') as fh:
                    fh.write(fetch('https://raw.githubusercontent.com/openstack/neutron/%s/%s'
                                   % (NEUTRON_28_0_2, f)))
            first = sorted(PATCHES['neutron'])[0]
            subprocess.run(['patch', '-p1', '-F0', '-d', tree, '-i', os.path.join(ROOT, first)],
                           check=True, capture_output=True)
            with open(os.path.join(tree, impl)) as fh:
                self.assertIn('idl_.set_lock(ovn_const.MAINTENANCE_NB_IDL_LOCK_NAME)', fh.read())


# ===========================================================================
# 5. repository-level invariants of the migration
# ===========================================================================
class RepositoryTests(unittest.TestCase):
    def test_the_old_patches_are_gone(self):
        self.assertFalse(os.path.exists(os.path.join(ROOT, 'spec-patches')))

    def test_no_rdo_spec_is_tracked_next_to_the_rules(self):
        for here, _dirs, names in os.walk(ROOT):
            for n in names:
                self.assertFalse(n.endswith('.spec'), os.path.join(here, n))
                self.assertFalse(n == 'placement-api.conf', os.path.join(here, n))

    def test_build_rpms_runs_the_check_and_the_adaptation_and_no_longer_patches(self):
        with open(os.path.join(ROOT, 'build-rpms.sh')) as fh:
            s = fh.read()
        self.assertIn('--check', s)
        self.assertIn('--package "$pkg" --tree "$dir"', s)
        self.assertNotRegex(s, r'(?m)^\s*patch -p1')
        self.assertNotIn('spec-patches', s)
        self.assertIn('SPEC|PATCH', s)


# ===========================================================================
# 6. licensing: Hagistack's own files are MIT, third-party/ keeps its licence
# ===========================================================================
REPO_ROOT = os.path.dirname(ROOT)


def squash(text):
    return re.sub(r'\s+', ' ', text).strip()


class LicensingTests(unittest.TestCase):
    def read(self, *path):
        with open(os.path.join(REPO_ROOT, *path), encoding='utf-8') as fh:
            return fh.read()

    def test_root_licence_is_the_standard_mit_text_with_the_chosen_holder(self):
        text = self.read('LICENSE')
        self.assertTrue(text.startswith('MIT License\n\nCopyright (c) 2026 Shiro Hagihara\n\n'))
        # whitespace-normalised, so line wrapping does not matter; any edit to the words does
        self.assertEqual(hashlib.sha256(squash(text).encode()).hexdigest(),
                         '5264cba202bc15304bbed289ce294c1a96490a3fa8c8c2e5a34aa96abb8b2e53')
        self.assertEqual(text.count('Copyright'), 1)

    def test_only_one_root_licence_file_and_it_is_not_the_apache_text(self):
        names = [n for n in os.listdir(REPO_ROOT) if re.match(r'(?i)(licen[cs]e|copying|notice)', n)]
        self.assertEqual(names, ['LICENSE'])
        self.assertNotIn('Apache', self.read('LICENSE'))

    def test_third_party_keeps_its_licence_and_says_the_mit_licence_does_not_apply(self):
        self.assertIn('Apache License', self.read('rocky10.2', 'third-party', 'neutron', 'LICENSE'))
        self.assertNotIn('MIT License', self.read('rocky10.2', 'third-party', 'neutron', 'LICENSE'))
        notice = self.read('rocky10.2', 'third-party', 'neutron', 'NOTICE.md')
        self.assertIn('MIT License', notice)
        self.assertIn('does not apply to the two patch files', notice)
        self.assertTrue(os.path.isfile(os.path.join(TP, '..', '..', '..', 'LICENSE')))

    def test_root_readmes_state_the_licence_and_its_boundary(self):
        for name, head, scope in (('README.md', '## License', 'not a statement about the terms of earlier revisions'),
                                  ('README.ja.md', '## ライセンス', '過去のリビジョンの条件について')):
            text = self.read(name)
            self.assertIn(head, text, name)
            section = squash(text[text.index(head):])   # line wrapping must not matter
            for must in ('MIT License', 'Shiro Hagihara', 'rocky10.2/third-party/neutron/', 'Apache License 2.0', scope):
                self.assertIn(must, section, name + ': ' + must)
            self.assertNotIn('retroactive', section.lower(), name)

    def test_readmes_do_not_point_at_the_deleted_patches(self):
        for name in ('README.md', 'README.ja.md', 'rocky10.2/README.md', 'rocky10.2/README.ja.md'):
            text = self.read(*name.split('/'))
            self.assertNotIn('spec-patches', text, name)
            self.assertNotIn('spec patches', text, name)
            self.assertNotIn('spec パッチ', text, name)


if __name__ == '__main__':
    unittest.main(verbosity=2)
