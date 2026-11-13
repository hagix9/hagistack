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
        else:
            print('usage: release_check.py repo SET_DIR | members TAR LIST | licence SRPM LICENSE')
            return 2
    except (Bad, OSError, ET.ParseError, tarfile.TarError, ValueError, AttributeError) as e:
        print(str(e) if isinstance(e, Bad) else '%s: %s' % (type(e).__name__, e))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
