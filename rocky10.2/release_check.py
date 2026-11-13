#!/usr/bin/python3 -I
"""release_check.py — checks make-rpm-release.sh runs on a set and its assets.

    release_check.py repo SET_DIR
        repo/ holds exactly the RPMs RPM-SHA256SUMS lists (regular files) and
        repodata/; repodata/ holds exactly repomd.xml and the files it names,
        each with the checksum repomd.xml gives; primary.xml lists exactly the
        listed RPMs, each with its sha256 as package id.
    release_check.py members TAR LIST
        the tar holds exactly the regular files named in LIST (one per line)
        and nothing else (no directories other than parents, no links).
    release_check.py licence SRPM LICENSE
        the source RPM's payload holds HAGISTACK-LICENSE with exactly the bytes
        of LICENSE (read with rpm2cpio).
    release_check.py branding SET_DIR IMAGES_DIR
        no RPM of the set installs a file with the bytes of one of Horizon's
        images that show the OpenStack logo, and openstack-dashboard installs
        Hagistack's images (from IMAGES_DIR) at each place they replace.
    release_check.py notices SET_DIR
        every binary RPM built from a source RPM whose spec writes
        HAGISTACK-CHANGES installs that notice, with exactly the text the spec
        writes, and its changelog lists the changes.

Prints nothing and exits 0 when the check passes; otherwise prints one line
saying what is wrong and exits 1. Runs with python3 -I and the standard library.
"""
import gzip
import hashlib
import os
import stat
import subprocess
import sys
import tarfile
import xml.etree.ElementTree as ET

REPO_NS = '{http://linux.duke.edu/metadata/repo}'

# Horizon 25.7.3 (tarball sha256 0a9a1d90...7c5117): the images that show the
# OpenStack logo, which the packaging replaces (defs/python-django-horizon.toml).
UPSTREAM_LOGOS = {
    'e7d02229f793459c8042ff94e67e7989863ebcd9c777700b6f4fbe3ed547d0c9': 'static/dashboard/img/logo.svg',
    '93056b4a8f80d76cf6d81bc9a729d2050a6c08904394949b3321a78e6ce981a0': 'static/dashboard/img/logo-splash.svg',
    '27b7287de853e2ea7d05cf5636d6b7c70b9fb65b2f4ce9e9fded1bb27921d839': 'static/dashboard/img/favicon.ico',
    'ac86c5f541f6b12e486847c19d7b72ed0c19a8de8a144e1e6141bd4443465c88': 'static/dashboard/img/apple-touch-icon.png',
    '584819e4da0c9a702dd7918dc64bcecf79fab1564730bcd7e0e9f14c08f58312': 'static/dashboard/img/safari-pinned-tab.svg',
    'fb45a0f208713d6a3cbdf70404b00f75e6c578b8ec22d7429eb69809f06c0960': 'material/openstack-one-color.svg',
    'ee70b89c41e40c9150d17fb7183d47a2c4eed088ff8d6d3a2f4f133d7c86c014': 'material/openstack-one-color-alt.svg',
}
# Where openstack-dashboard installs Hagistack's images (the static tree is
# installed twice: the project's own copy and the collected one).
DASH = '/usr/share/openstack-dashboard/'
BRANDING = {
    'hagistack-logo.svg': ['openstack_dashboard/static/dashboard/img/logo.svg', 'static/dashboard/img/logo.svg'],
    'hagistack-logo-splash.svg': ['openstack_dashboard/static/dashboard/img/logo-splash.svg', 'static/dashboard/img/logo-splash.svg'],
    'hagistack-favicon.ico': ['openstack_dashboard/static/dashboard/img/favicon.ico', 'static/dashboard/img/favicon.ico'],
    'hagistack-apple-touch-icon.png': ['openstack_dashboard/static/dashboard/img/apple-touch-icon.png', 'static/dashboard/img/apple-touch-icon.png'],
    'hagistack-safari-pinned-tab.svg': ['openstack_dashboard/static/dashboard/img/safari-pinned-tab.svg', 'static/dashboard/img/safari-pinned-tab.svg'],
    'hagistack-material-brand.svg': ['openstack_dashboard/themes/material/templates/material/openstack-one-color.svg',
                                     'openstack_dashboard/themes/material/templates/material/openstack-one-color-alt.svg'],
}
COMMON_NS = '{http://linux.duke.edu/metadata/common}'


class Bad(Exception):
    pass


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def regular(path):
    st = os.lstat(path)
    return stat.S_ISREG(st.st_mode)


def read_sums(path):
    sums = {}
    with open(path, encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\n')
            sha, sep, name = line.partition('  ')
            if not sep or len(sha) != 64 or '/' in name or not name.endswith('.rpm') or name in sums:
                raise Bad('RPM-SHA256SUMS has a line that is not "<sha256>  <name>.rpm": %r' % line)
            sums[name] = sha
    if not sums:
        raise Bad('RPM-SHA256SUMS is empty')
    return sums


def check_repo(set_dir):
    sums = read_sums(os.path.join(set_dir, 'RPM-SHA256SUMS'))
    repo = os.path.join(set_dir, 'repo')
    entries = set(os.listdir(repo))
    extra = entries - set(sums) - {'repodata'}
    if extra:
        raise Bad('repo/ holds files RPM-SHA256SUMS does not list (would be published): %s'
                  % ', '.join(sorted(extra)))
    missing = set(sums) - entries
    if missing:
        raise Bad('repo/ lacks listed RPMs: %s' % ', '.join(sorted(missing)))
    for n in sums:
        if not regular(os.path.join(repo, n)):
            raise Bad('repo/%s is not a regular file' % n)
    rd = os.path.join(repo, 'repodata')
    if not stat.S_ISDIR(os.lstat(rd).st_mode):
        raise Bad('repo/repodata is not a directory')
    rd_entries = set(os.listdir(rd))
    for n in rd_entries:
        if not regular(os.path.join(rd, n)):
            raise Bad('repo/repodata/%s is not a regular file' % n)
    if 'repomd.xml' not in rd_entries:
        raise Bad('repo/repodata/repomd.xml is missing')
    root = ET.parse(os.path.join(rd, 'repomd.xml')).getroot()
    named = {'repomd.xml'}
    primary = None
    for data in root.findall(REPO_NS + 'data'):
        loc = data.find(REPO_NS + 'location').get('href', '')
        csum = data.find(REPO_NS + 'checksum')
        if not loc.startswith('repodata/') or '/' in loc[len('repodata/'):]:
            raise Bad('repomd.xml names a file outside repodata/: %s' % loc)
        name = loc[len('repodata/'):]
        if name not in rd_entries:
            raise Bad('repomd.xml names %s, which is missing' % loc)
        if csum is None or csum.get('type') != 'sha256' or sha256_file(os.path.join(rd, name)) != (csum.text or '').strip():
            raise Bad('%s does not have the sha256 repomd.xml gives' % loc)
        named.add(name)
        if data.get('type') == 'primary':
            primary = os.path.join(rd, name)
    if rd_entries - named:
        raise Bad('repo/repodata holds files repomd.xml does not name (would be published): %s'
                  % ', '.join(sorted(rd_entries - named)))
    if primary is None:
        raise Bad('repomd.xml names no primary metadata')
    opener = gzip.open if primary.endswith('.gz') else open
    with opener(primary, 'rb') as f:
        proot = ET.parse(f).getroot()
    seen = {}
    for pkg in proot.findall(COMMON_NS + 'package'):
        href = pkg.find(COMMON_NS + 'location').get('href', '')
        cs = pkg.find(COMMON_NS + 'checksum')
        if href in seen:
            raise Bad('primary metadata lists %s twice' % href)
        if cs is None or cs.get('type') != 'sha256':
            raise Bad('primary metadata gives no sha256 for %s' % href)
        seen[href] = (cs.text or '').strip()
    if set(seen) != set(sums):
        diff = sorted(set(seen) ^ set(sums))
        raise Bad('primary metadata and RPM-SHA256SUMS list different RPMs: %s' % ', '.join(diff[:5]))
    for n, sha in sums.items():
        if seen[n] != sha:
            raise Bad('primary metadata gives another sha256 for %s' % n)


def check_members(tar_path, list_path):
    with open(list_path, encoding='utf-8') as f:
        want = [ln.rstrip('\n') for ln in f if ln.strip()]
    want_set = set(want)
    if len(want_set) != len(want):
        raise Bad('the expected member list has duplicates')
    parents = set()
    for w in want:
        parts = w.split('/')
        for i in range(1, len(parts)):
            parents.add('/'.join(parts[:i]))
    got = set()
    with tarfile.open(tar_path, 'r:') as t:
        for m in t.getmembers():
            n = m.name[2:] if m.name.startswith('./') else m.name
            n = n.rstrip('/') if m.isdir() else n
            if m.isdir() and n in parents:
                continue
            if not m.isfile():
                raise Bad('%s: member %s is not a regular file' % (tar_path, m.name))
            if n in got:
                raise Bad('%s: member %s appears twice' % (tar_path, m.name))
            got.add(n)
    if got != want_set:
        diff = sorted(got ^ want_set)
        raise Bad('%s holds other members than expected: %s' % (tar_path, ', '.join(diff[:5])))


def payload(path):
    """(name, bytes) of every regular file in an RPM's payload (rpm2cpio)."""
    p = subprocess.run(['rpm2cpio', path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if p.returncode != 0:
        raise Bad('rpm2cpio cannot read %s' % os.path.basename(path))
    d = p.stdout
    i = 0
    while i + 110 <= len(d):
        if d[i:i + 6] not in (b'070701', b'070702'):
            raise Bad('%s: payload is not a newc cpio archive' % os.path.basename(path))
        mode = int(d[i + 14:i + 22], 16)
        fsize = int(d[i + 54:i + 62], 16)
        nsize = int(d[i + 94:i + 102], 16)
        name = d[i + 110:i + 110 + nsize - 1].decode('utf-8', 'replace')
        p0 = i + 110 + nsize
        p0 += (-p0) % 4
        if name == 'TRAILER!!!':
            return
        if stat.S_ISREG(mode):
            yield (name[1:] if name.startswith('./') else name), d[p0:p0 + fsize]
        i = p0 + fsize
        i += (-i) % 4
    raise Bad('%s: payload ends without a trailer' % os.path.basename(path))


def rpm_query(path, fmt):
    p = subprocess.run(['rpm', '-qp', '--nosignature', '--qf', fmt, path], stdout=subprocess.PIPE,
                       stderr=subprocess.DEVNULL)
    if p.returncode != 0:
        raise Bad('rpm cannot read %s' % os.path.basename(path))
    return p.stdout.decode('utf-8', 'replace')


def check_branding(set_dir, images_dir):
    want = {}
    for img, places in BRANDING.items():
        with open(os.path.join(images_dir, img), 'rb') as f:
            data = f.read()
        for pl in places:
            want[DASH + pl] = data
    repo = os.path.join(set_dir, 'repo')
    dash = None
    for n in sorted(os.listdir(repo)):
        if not n.endswith('.rpm'):
            continue
        is_dash = rpm_query(os.path.join(repo, n), '%{NAME}') == 'openstack-dashboard'
        if is_dash:
            if dash is not None:
                raise Bad('two openstack-dashboard RPMs in the set')
            dash = n
        found = {}
        for name, data in payload(os.path.join(repo, n)):
            h = hashlib.sha256(data).hexdigest()
            if h in UPSTREAM_LOGOS:
                raise Bad('%s installs %s, which is upstream\'s %s (the OpenStack logo)' % (n, name, UPSTREAM_LOGOS[h]))
            if is_dash and name in want:
                found[name] = data
        if is_dash:
            for path, data in want.items():
                if found.get(path) != data:
                    raise Bad('%s does not install Hagistack\'s image at %s' % (n, path))
    if dash is None:
        raise Bad('openstack-dashboard is not in the set')


def spec_notice(srpm):
    """The HAGISTACK-CHANGES text a source RPM's spec writes, or None."""
    specs = [data for name, data in payload(srpm) if name.endswith('.spec') and '/' not in name]
    if len(specs) != 1:
        raise Bad('%s holds %d spec files, not 1' % (os.path.basename(srpm), len(specs)))
    text = specs[0].decode('utf-8')
    start = "cat > HAGISTACK-CHANGES <<'HAGISTACK_CHANGES_EOF'\n"
    if text.count(start) == 0:
        return None
    if text.count(start) != 1:
        raise Bad('%s: the spec writes HAGISTACK-CHANGES twice' % os.path.basename(srpm))
    body = text.split(start, 1)[1].split('\nHAGISTACK_CHANGES_EOF\n', 1)[0]
    return (body + '\n').replace('%%', '%').encode('utf-8')


def check_notices(set_dir):
    srpms = os.path.join(set_dir, 'srpms')
    notices = {}
    for s in sorted(os.listdir(srpms)):
        if s.endswith('.src.rpm'):
            n = spec_notice(os.path.join(srpms, s))
            if n is not None:
                notices[s] = n
    if not notices:
        raise Bad('no source RPM declares changes to upstream (HAGISTACK-CHANGES): expected some')
    repo = os.path.join(set_dir, 'repo')
    covered = set()
    for n in sorted(os.listdir(repo)):
        if not n.endswith('.rpm'):
            continue
        path = os.path.join(repo, n)
        src = rpm_query(path, '%{SOURCERPM}')
        if src not in notices:
            continue
        covered.add(src)
        got = [data for name, data in payload(path) if name.startswith('/usr/share/doc/')
               and name.endswith('/HAGISTACK-CHANGES')]
        if len(got) != 1:
            raise Bad('%s (from %s) installs %d HAGISTACK-CHANGES files, not 1' % (n, src, len(got)))
        if got[0] != notices[src]:
            raise Bad('%s: HAGISTACK-CHANGES differs from the text its spec writes' % n)
        log = rpm_query(path, '[%{CHANGELOGTEXT}\n]')
        if 'Changes to the upstream sources' not in log:
            raise Bad('%s: the changelog does not list the changes to upstream' % n)
    if covered != set(notices):
        raise Bad('no binary RPM from %s' % ', '.join(sorted(set(notices) - covered)))


def check_licence(srpm, licence):
    with open(licence, 'rb') as f:
        want = f.read()
    p = subprocess.run(['rpm2cpio', srpm], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if p.returncode != 0:
        raise Bad('rpm2cpio cannot read %s' % srpm)
    d = p.stdout
    i = 0
    found = []
    while i + 110 <= len(d):
        if d[i:i + 6] not in (b'070701', b'070702'):
            raise Bad('%s: payload is not a newc cpio archive' % srpm)
        fsize = int(d[i + 54:i + 62], 16)
        nsize = int(d[i + 94:i + 102], 16)
        name = d[i + 110:i + 110 + nsize - 1].decode('utf-8', 'replace')
        p0 = i + 110 + nsize
        p0 += (-p0) % 4
        if name == 'TRAILER!!!':
            break
        if name.lstrip('./') == 'HAGISTACK-LICENSE':
            found.append(d[p0:p0 + fsize])
        i = p0 + fsize
        i += (-i) % 4
    if len(found) != 1:
        raise Bad('%s holds %d HAGISTACK-LICENSE files, not 1' % (os.path.basename(srpm), len(found)))
    if found[0] != want:
        raise Bad('%s: HAGISTACK-LICENSE differs from LICENSE' % os.path.basename(srpm))


def main(argv):
    try:
        if len(argv) == 3 and argv[1] == 'repo':
            check_repo(argv[2])
        elif len(argv) == 4 and argv[1] == 'members':
            check_members(argv[2], argv[3])
        elif len(argv) == 4 and argv[1] == 'licence':
            check_licence(argv[2], argv[3])
        elif len(argv) == 4 and argv[1] == 'branding':
            check_branding(argv[2], argv[3])
        elif len(argv) == 3 and argv[1] == 'notices':
            check_notices(argv[2])
        else:
            print('usage: release_check.py repo SET_DIR | members TAR LIST | licence SRPM LICENSE | '
                  'branding SET_DIR IMAGES_DIR | notices SET_DIR')
            return 2
    except (Bad, OSError, ET.ParseError, tarfile.TarError, ValueError, AttributeError, UnicodeDecodeError) as e:
        print(str(e) if isinstance(e, Bad) else '%s: %s' % (type(e).__name__, e))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
