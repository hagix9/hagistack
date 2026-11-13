#!/usr/bin/python3
"""Unit tests for the branding and notices checks of ../release_check.py.

Run: python3 -B -I tests/test_release_check.py

No rpm is needed: stub `rpm` and `rpm2cpio` programs answer from files next to
each fake package (<pkg>.cpio holds its payload as a newc cpio archive,
<pkg>.json its header fields), so the checks' logic is tested on any host.
The checks themselves are run against real RPMs by make-rpm-release.sh.
"""
import hashlib
import importlib.util
import json
import os
import stat
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True   # importing release_check must not write bytecode
HERE = os.path.dirname(os.path.abspath(__file__))
TOP = os.path.dirname(HERE)
spec = importlib.util.spec_from_file_location('release_check', os.path.join(TOP, 'release_check.py'))
rc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rc)

STUB_RPM2CPIO = '''#!/usr/bin/env python3
import sys
sys.stdout.buffer.write(open(sys.argv[1] + '.cpio', 'rb').read())
'''
STUB_RPM = '''#!/usr/bin/env python3
import json, re, sys
a = sys.argv[1:]
fmt, path = a[a.index('--qf') + 1], a[-1]
meta = json.load(open(path + '.json'))
if 'FILEFLAGS' in fmt:
    sys.stdout.write(''.join(f + '\\t' + fl + '\\n' for f, fl in meta.get('FILEFLAGS', [])))
elif fmt.startswith('['):
    sys.stdout.write(''.join(line + '\\n' for line in meta.get('CHANGELOGTEXT', [])))
else:
    sys.stdout.write(re.sub(r'%\\{(\\w+)\\}', lambda m: meta[m.group(1)], fmt))
'''


def cpio(files):
    out = b''
    ino = 1
    for name, data in list(files.items()) + [('TRAILER!!!', b'')]:
        mode = 0o100644 if name != 'TRAILER!!!' else 0
        nb = name.encode() + b'\0'
        hdr = b'070701' + b''.join(b'%08X' % v for v in
                                   (ino, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(nb), 0))
        out += hdr + nb
        out += b'\0' * ((-len(out)) % 4)
        out += data
        out += b'\0' * ((-len(out)) % 4)
        ino += 1
    return out


MARK = rc.MARK.decode()
NOTICE_SPEC = """Name: x
%prep
test -f 'x/marked.py' || { echo 'x/marked.py: the file to mark is missing' >&2; exit 1; }
cat > HAGISTACK-CHANGES <<'HAGISTACK_CHANGES_EOF'
Changes Hagistack made
- 100%% done in %%prep
HAGISTACK_CHANGES_EOF
%changelog
"""
NOTICE_TEXT = b"Changes Hagistack made\n- 100% done in %prep\n"


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.d = self.tmp.name
        self.bin = os.path.join(self.d, 'bin')
        os.makedirs(self.bin)
        for name, body in (('rpm', STUB_RPM), ('rpm2cpio', STUB_RPM2CPIO)):
            p = os.path.join(self.bin, name)
            with open(p, 'w') as f:
                f.write(body)
            os.chmod(p, 0o755)
        self.old_path = os.environ['PATH']
        os.environ['PATH'] = self.bin + os.pathsep + self.old_path
        self.set = os.path.join(self.d, 'set')
        os.makedirs(os.path.join(self.set, 'repo'))
        os.makedirs(os.path.join(self.set, 'srpms'))
        self.saved_logos = dict(rc.UPSTREAM_LOGOS)

    def tearDown(self):
        os.environ['PATH'] = self.old_path
        rc.UPSTREAM_LOGOS.clear()
        rc.UPSTREAM_LOGOS.update(self.saved_logos)
        self.tmp.cleanup()

    def pkg(self, where, name, files, **meta):
        p = os.path.join(self.set, where, name)
        open(p, 'wb').close()
        with open(p + '.cpio', 'wb') as f:
            f.write(cpio(files))
        with open(p + '.json', 'w') as f:
            json.dump(meta, f)

    def refused(self, fn, *args, want=''):
        with self.assertRaises(rc.Bad) as cm:
            fn(*args)
        self.assertIn(want, str(cm.exception))


class Notices(Base):
    def setUp(self):
        super().setUp()
        self.pkg('srpms', 'x-1-1.src.rpm', {'x.spec': NOTICE_SPEC.encode()})
        self.pkg('srpms', 'y-1-1.src.rpm', {'y.spec': b'Name: y\n'})
        self.pkg('repo', 'y-1-1.noarch.rpm', {'./usr/lib/y.py': b''}, NAME='y', SOURCERPM='y-1-1.src.rpm')

    def good(self, name='x-1-1.noarch.rpm', notice=NOTICE_TEXT, log=('- Changes to the upstream sources, also in',),
             licence_file=True, tag='Apache-2.0 AND MIT', where=None, doc_flag=False, logname='Hagistack - 1:2.0-3',
             evr='1:2.0-3.el10', extra=None, marked=True):
        pkg = name[:-15]
        where = where or '/usr/share/hagistack/changes/%s/HAGISTACK-CHANGES' % pkg
        files = {'./usr/lib/x.py': b''}
        if where != 'none':
            files['.' + where] = notice
        if marked:
            files['./usr/lib/python3.12/site-packages/x/marked.py'] = ('#!/usr/bin/python3\n%s\nx = 1\n' % MARK).encode()
        if licence_file:
            files['./usr/share/licenses/%s/HAGISTACK-LICENSE' % pkg] = b'MIT'
        files.update(extra or {})
        flags = [(f[1:], 'd' if (doc_flag and f.endswith('HAGISTACK-CHANGES')) else '') for f in files]
        self.pkg('repo', name, files, NAME=pkg, SOURCERPM='x-1-1.src.rpm', CHANGELOGTEXT=list(log),
                 LICENSE=tag, FILEFLAGS=flags, CHANGELOGNAME=logname, EPOCHNUM=evr.split(':')[0],
                 VERSION=evr.split(':')[1].rsplit('-', 1)[0], RELEASE=evr.rsplit('-', 1)[1])

    def test_every_binary_of_a_changed_source_carries_the_notice(self):
        self.good()
        self.good('x-sub-1-1.noarch.rpm', marked=False)
        rc.check_notices(self.set)

    def test_a_binary_without_the_notice_is_refused(self):
        self.good()
        self.good('x-sub-1-1.noarch.rpm', where='none', marked=False)
        self.refused(rc.check_notices, self.set, want='exactly once')

    def test_the_notice_under_usr_share_doc_or_twice_is_refused(self):
        self.good(where='/usr/share/doc/x/HAGISTACK-CHANGES')
        self.refused(rc.check_notices, self.set, want='exactly once')
        self.good(extra={'./usr/share/doc/x/HAGISTACK-CHANGES': NOTICE_TEXT})
        self.refused(rc.check_notices, self.set, want='exactly once')

    def test_a_notice_flagged_as_documentation_is_refused(self):
        self.good(doc_flag=True)
        self.refused(rc.check_notices, self.set, want='flagged as documentation')

    def test_a_notice_that_differs_from_the_spec_is_refused(self):
        self.good(notice=b'something else\n')
        self.refused(rc.check_notices, self.set, want='differs from the text its spec writes')

    def test_a_changelog_without_the_changes_is_refused(self):
        self.good(log=('- Hagistack packaging of the upstream release',))
        self.refused(rc.check_notices, self.set, want='changelog')

    def test_a_release_without_its_own_changelog_entry_is_refused(self):
        self.good(logname='Hagistack - 1:2.0-2')
        self.refused(rc.check_notices, self.set, want='newest changelog entry is not for 1:2.0-3')
        self.good(logname='Hagistack - 2.0-3', evr='0:2.0-3.el10')
        rc.check_notices(self.set)

    def test_a_marked_file_without_the_mark_is_refused(self):
        self.good(marked=False)
        self.refused(rc.check_notices, self.set, want='marks x/marked.py')

    def test_the_notice_needs_the_mit_text_and_tag(self):
        self.good(licence_file=False)
        self.refused(rc.check_notices, self.set, want='not HAGISTACK-LICENSE')
        self.good(tag='Apache-2.0')
        self.refused(rc.check_notices, self.set, want='does not name MIT')
        self.good(tag='Apache-2.0 AND MIT-0')
        self.refused(rc.check_notices, self.set, want='does not name MIT')

    def test_a_changed_source_without_binaries_is_refused(self):
        self.refused(rc.check_notices, self.set, want='no binary RPM from x-1-1.src.rpm')

    def test_a_set_where_no_source_declares_changes_is_refused(self):
        os.remove(os.path.join(self.set, 'srpms', 'x-1-1.src.rpm'))
        self.refused(rc.check_notices, self.set, want='no source RPM declares changes')

    def test_the_mark_is_the_one_genspec_writes(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('genspec', os.path.join(TOP, 'packaging', 'genspec.py'))
        try:
            gs = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(gs)
        except ModuleNotFoundError:          # genspec needs Python 3.11 (tomllib)
            self.skipTest('genspec needs Python 3.11+')
        self.assertEqual(rc.MARK.decode(), gs.MARK)
        self.assertEqual(rc.CHANGES_DIR, '/usr/share/hagistack/changes/')


class Branding(Base):
    def setUp(self):
        super().setUp()
        self.images = os.path.join(self.d, 'images')
        os.makedirs(self.images)
        self.files = {}
        for img in rc.BRANDING:
            data = ('Hagistack image ' + img).encode()
            with open(os.path.join(self.images, img), 'wb') as f:
                f.write(data)
            for pl in rc.BRANDING[img]:
                self.files['.' + rc.DASH + pl] = data
        self.docs = os.path.join(self.d, 'docs')
        os.makedirs(self.docs)
        self.doc_files = {}
        for rel, img in rc.DOC_BRANDING.items():
            data = ('Hagistack doc image ' + img).encode()
            with open(os.path.join(self.docs, img), 'wb') as f:
                f.write(data)
            self.doc_files['./usr/share/doc/python-x-doc/html/_static/' + rel] = data
        self.logo = b'upstream logo bytes'
        rc.UPSTREAM_LOGOS[hashlib.sha256(self.logo).hexdigest()] = 'static/dashboard/img/logo.svg'

    def dash(self, files):
        self.pkg('repo', 'openstack-dashboard-1-2.noarch.rpm', files, NAME='openstack-dashboard')

    def doc(self, files, name='python-x-doc'):
        files = dict(files)
        files['./usr/share/doc/%s/html/index.html' % name] = b'<html>OpenStack docs</html>'
        self.pkg('repo', name + '-1-2.noarch.rpm', files, NAME=name)

    def check(self):
        rc.check_branding(self.set, self.images, self.docs)

    def test_hagistack_images_in_every_place_pass(self):
        self.dash(self.files)
        self.doc(self.doc_files)
        self.pkg('repo', 'other-1-1.noarch.rpm', {'./usr/share/x.svg': b'x', './usr/share/doc/o/README': b'OpenStack'},
                 NAME='other')
        self.check()

    def test_an_upstream_logo_anywhere_is_refused(self):
        self.dash(self.files)
        self.doc(self.doc_files)
        self.pkg('repo', 'other-1-1.noarch.rpm', {'./usr/share/doc/x/logo.svg': self.logo}, NAME='other')
        self.refused(self.check, want='the OpenStack logo')

    def test_the_real_docs_theme_logo_hashes_are_refused(self):
        # the five hashes of the documentation theme are in the table
        self.assertEqual(sum('docs theme' in v for v in rc.UPSTREAM_LOGOS.values()), 5)
        self.dash(self.files)
        files = dict(self.doc_files)
        h = hashlib.sha256(b'theme logo').hexdigest()
        rc.UPSTREAM_LOGOS[h] = 'docs theme images/logo-full.svg'
        files['./usr/share/doc/python-x-doc/html/_static/images/logo-full.svg'] = b'theme logo'
        self.doc(files)
        self.refused(self.check, want='docs theme images/logo-full.svg')

    def test_a_missing_or_wrong_dashboard_image_is_refused(self):
        self.doc(self.doc_files)
        files = dict(self.files)
        files.pop('.' + rc.DASH + 'static/dashboard/img/favicon.ico')
        self.dash(files)
        self.refused(self.check, want='static/dashboard/img/favicon.ico')
        files['.' + rc.DASH + 'static/dashboard/img/favicon.ico'] = b'other'
        self.dash(files)
        self.refused(self.check, want='static/dashboard/img/favicon.ico')

    def test_a_doc_tree_missing_or_with_a_wrong_image_is_refused(self):
        self.dash(self.files)
        for rel in ('favicon.ico', 'images/openstack-logo-vert.png'):
            with self.subTest(rel=rel):
                files = dict(self.doc_files)
                files.pop('./usr/share/doc/python-x-doc/html/_static/' + rel)
                self.doc(files)
                self.refused(self.check, want=rel)
                files['./usr/share/doc/python-x-doc/html/_static/' + rel] = b'not ours'
                self.doc(files)
                self.refused(self.check, want=rel)

    def test_no_doc_tree_is_refused(self):
        self.dash(self.files)
        self.refused(self.check, want='no HTML documentation tree')

    def test_no_dashboard_is_refused(self):
        self.doc(self.doc_files)
        self.pkg('repo', 'other-1-1.noarch.rpm', {'./usr/share/x': b'x'}, NAME='other')
        self.refused(self.check, want='openstack-dashboard is not in the set')

    def test_main_reports_one_line_and_exit_1(self):
        self.dash({})
        self.assertEqual(rc.main(['release_check.py', 'branding', self.set, self.images, self.docs]), 1)
        self.assertEqual(rc.main(['release_check.py', 'branding', self.set, self.images]), 2)


if __name__ == '__main__':
    unittest.main()
