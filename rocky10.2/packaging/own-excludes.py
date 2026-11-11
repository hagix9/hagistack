#!/usr/bin/python3
"""Keep the package names Hagistack builds out of every other repository.

  own-excludes.py apply <names-file> <dnf.conf> <repo-dir> [<repo-dir> ...]
  own-excludes.py check <names-file> <dnf.conf> <repo-dir> [<repo-dir> ...]

A build dependency on a library this build has not built yet must wait for it,
never be met by a package of the same name from RDO, EPEL, Rocky or any other
repository: a package installed early stays installed and feeds every later
build. So every section of every *.repo file is given these names to exclude,
whether the section is enabled or not (it may be enabled later), except
hagistack-own.repo, the repository of this build.

apply rewrites each repository file so that every section excludes the names:

  * a section with exclude= or excludepkgs= lines keeps them; the names are
    appended to each of them (DNF reads one value per key, so every one carries
    them, whichever DNF takes);
  * a section without one gets an excludepkgs= line after its header.

Each line apply writes is preceded by a "# hagistack-own-orig:" comment holding
the original line(s) (or null for an added line), so a second run first restores
the original and then applies again: the result does not grow, and unrelated
packages of the repository stay available. A file is rewritten atomically and
only if its content changes.

check reports every section that does not exclude all the names, and every
repository section in dnf.conf (other than [main]), which apply does not touch.
Exit status: 0 done / every section covered; 1 something is not covered or a
file could not be read or written.
"""
import json
import os
import re
import sys
import tempfile

MARK = '# hagistack-own-orig: '
OWN_FILE = 'hagistack-own.repo'
SECTION = re.compile(r'\s*\[([^\]]+)\]\s*$')
KEY = re.compile(r'(exclude|excludepkgs)\s*=(.*)$')


def repo_files(dirs):
    for d in dirs:
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if f.endswith('.repo') and f != OWN_FILE:
                yield os.path.join(d, f)


def restore(lines):
    """Undo what apply wrote: the original lines back, apply's lines out."""
    out, i = [], 0
    while i < len(lines):
        if lines[i].startswith(MARK):
            orig = json.loads(lines[i][len(MARK):])
            out.extend(orig or [])
            i += 2              # the marker and the one line apply wrote
            continue
        out.append(lines[i])
        i += 1
    return out


def entries(lines):
    """Split into (kind, lines): 'section' headers, exclude 'key' entries with
    their continuation lines, and 'other' lines."""
    res, i = [], 0
    while i < len(lines):
        line = lines[i]
        if SECTION.match(line):
            res.append(('section', [line]))
            i += 1
        elif KEY.match(line):
            j = i + 1
            while j < len(lines) and lines[j][:1] in (' ', '\t') and lines[j].strip():
                j += 1
            res.append(('key', lines[i:j]))
            i = j
        else:
            res.append(('other', [line]))
            i += 1
    return res


def values(key_lines):
    m = KEY.match(key_lines[0])
    text = ' '.join([m.group(2)] + [x.strip() for x in key_lines[1:]])
    return m.group(1), [v for v in re.split(r'[\s,]+', text) if v]


def apply_lines(lines, names):
    base = restore(lines)
    ents = entries(base)
    out = []
    for n, (kind, ls) in enumerate(ents):
        if kind == 'section':
            out.extend(ls)
            has_key = False
            for k2, _ in ents[n + 1:]:
                if k2 == 'section':
                    break
                if k2 == 'key':
                    has_key = True
                    break
            if not has_key:
                out.append(MARK + 'null')
                out.append('excludepkgs=' + ' '.join(names))
        elif kind == 'key':
            key, vals = values(ls)
            out.append(MARK + json.dumps(ls))
            out.append(key + '=' + ' '.join(vals + [x for x in names if x not in vals]))
        else:
            out.extend(ls)
    return out


def uncovered(lines, names, where):
    """Sections whose exclusion misses one of the names."""
    bad, section, got = [], None, None
    want = set(names)

    def close():
        if section is not None and not want <= (got or set()):
            bad.append(f'{where} [{section}]: {len(want - (got or set()))} of our names not excluded')
    for kind, ls in entries(lines):
        if kind == 'section':
            close()
            section, got = SECTION.match(ls[0]).group(1), set()
        elif kind == 'key' and section is not None:
            got |= set(values(ls)[1])
    close()
    return bad


def write_atomic(path, text):
    st = os.stat(path)
    fd, tmp = tempfile.mkstemp(prefix='.' + os.path.basename(path) + '.', suffix='.tmp',
                               dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, 'w') as fh:
            fh.write(text)
        os.chmod(tmp, st.st_mode & 0o7777)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def main(argv):
    if len(argv) < 4 or argv[0] not in ('apply', 'check'):
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 1
    mode, names_file, dnf_conf, dirs = argv[0], argv[1], argv[2], argv[3:]
    try:
        names = open(names_file).read().split()
    except OSError as e:
        print(f'own-excludes: cannot read {names_file}: {e}', file=sys.stderr)
        return 1
    if not names:
        print(f'own-excludes: {names_file} lists no names', file=sys.stderr)
        return 1
    problems = []
    if os.path.exists(dnf_conf):
        try:
            for kind, ls in entries(open(dnf_conf).read().splitlines()):
                if kind == 'section' and SECTION.match(ls[0]).group(1).strip() != 'main':
                    problems.append(f'{dnf_conf} defines repository [{SECTION.match(ls[0]).group(1)}]; '
                                    'own-excludes does not edit dnf.conf')
        except OSError as e:
            problems.append(f'{dnf_conf}: {e}')
    for f in repo_files(dirs):
        try:
            text = open(f).read()
            lines = text.splitlines()
            if mode == 'apply':
                new = '\n'.join(apply_lines(lines, names)) + '\n'
                if new != text:
                    write_atomic(f, new)
                lines = new.splitlines()
            problems += uncovered(lines, names, f)
        except (OSError, ValueError) as e:
            problems.append(f'{f}: {e}')
    for p in problems:
        print('own-excludes: ' + p, file=sys.stderr)
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
