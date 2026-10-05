#!/usr/bin/env python3
"""Apply Hagistack's own edits to pinned third-party RPM packaging, or stop.

RDO's distgit specs are fetched at an exact commit and are never stored in this
repository. What is stored here are edit RULES (rules.py): small, structure-aware
operations that name a section, a macro or a path tail and say what Hagistack
wants instead. See RATIONALE.md for why this replaced the old spec-patches.

Every run is fail-closed. It stops, with exit status 1 and nothing written, when

  * the manifest is malformed or names something this tool does not know,
  * the rules do not know the manifest's version of the package,
  * an input's SHA-256 is not the reviewed one, or the input is already adapted,
  * an operation finds a different number of targets than it expects,
  * an operation finds a different old value than it expects, or
  * the result's SHA-256 is not the reviewed one.

usage:
  adapt.py --manifest FILE --check
  adapt.py --manifest FILE --package NAME --tree DIR [--root DIR]

--check validates every SPEC/PATCH row against the rules and the package rows.
--package adapts the files of one package inside DIR (a staged copy of the pinned
distgit) in place, and installs the package's PATCH files next to them.

Standard library only.
"""
import argparse
import fnmatch
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)


class Stop(Exception):
    """Anything unexpected. Never caught except to report it and exit 1."""


# ---------------------------------------------------------------------------
# manifest
# ---------------------------------------------------------------------------
HEX40 = re.compile(r'^[0-9a-f]{40}$')
HEX64 = re.compile(r'^[0-9a-f]{64}$')
KEYID = re.compile(r'^0x[0-9a-f]{40}$')
PLAIN_NAME = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._+-]*$')


def _need(cond, where, msg):
    if not cond:
        raise Stop('%s: %s' % (where, msg))


def parse_manifest(path):
    """Strict reader. Returns (packages, specs, patches).

    packages: name -> dict(repo, commit, spec, version)
    specs:    name -> {file: (input_sha256, output_sha256)}
    patches:  name -> {relative path: sha256}
    Nothing is skipped: a row that is not one of the known kinds is an error.
    """
    packages, specs, patches = {}, {}, {}
    with open(path, encoding='utf-8') as fh:
        rows = fh.read().splitlines()
    for n, raw in enumerate(rows, 1):
        f = raw.split()
        if not f or f[0].startswith('#'):
            continue
        where = '%s:%d' % (os.path.basename(path), n)
        kind = f[0]
        if kind == 'KEY':
            _need(len(f) == 3 and KEYID.match(f[1]) and HEX64.match(f[2]), where,
                  'KEY needs: KEY 0x<40 hex key id> <64 hex sha256>')
        elif kind == 'PYPI':
            _need(len(f) >= 8 and HEX64.match(f[5]), where,
                  'PYPI needs: PYPI rpm-name pypi-name version sdist sha256 license summary...')
        elif kind == 'SPEC':
            _need(len(f) == 5 and PLAIN_NAME.match(f[1]) and PLAIN_NAME.match(f[2])
                  and HEX64.match(f[3]) and HEX64.match(f[4]), where,
                  'SPEC needs: SPEC package file input-sha256 output-sha256')
            slot = specs.setdefault(f[1], {})
            _need(f[2] not in slot, where, 'duplicate SPEC row for %s %s' % (f[1], f[2]))
            slot[f[2]] = (f[3], f[4])
        elif kind == 'PATCH':
            _need(len(f) == 4 and PLAIN_NAME.match(f[1]) and HEX64.match(f[3]), where,
                  'PATCH needs: PATCH package relative/path sha256')
            p = f[2]
            _need(not p.startswith('/') and '..' not in p.split('/') and p, where,
                  'PATCH path must be relative and stay inside the repository')
            slot = patches.setdefault(f[1], {})
            _need(p not in slot, where, 'duplicate PATCH row for %s %s' % (f[1], p))
            slot[p] = f[3]
        else:
            # a package row: package repo commit spec version release tarball sha256 urlproj [key]
            _need(len(f) in (9, 10) and PLAIN_NAME.match(f[0]) and HEX40.match(f[2])
                  and HEX64.match(f[7]) and (len(f) == 9 or f[9] == '-' or KEYID.match(f[9])),
                  where, 'not a KEY/PYPI/SPEC/PATCH row and not a valid package row: %r' % raw[:60])
            _need(f[0] not in packages, where, 'duplicate package %s' % f[0])
            packages[f[0]] = dict(repo=f[1], commit=f[2], spec=f[3], version=f[4])
    for name in list(specs) + list(patches):
        _need(name in packages, os.path.basename(path), 'SPEC/PATCH row for unknown package %r' % name)
    return packages, specs, patches


# ---------------------------------------------------------------------------
# operations
# ---------------------------------------------------------------------------
HEADER = re.compile(
    r'^%(prep|conf|build|install|check|clean|generate_buildrequires|files|package|description|'
    r'changelog|pre|post|preun|postun|pretrans|posttrans|preuntrans|postuntrans|'
    r'trigger\w*|filetrigger\w*)\b')


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def split_lines(text):
    """Split on newline ONLY (str.splitlines also splits on form feeds and the like)."""
    out = re.findall(r'[^\n]*\n|[^\n]+', text)
    assert ''.join(out) == text
    return out


def scopes(lines):
    """For every line, the section header it sits under ('preamble' before the first)."""
    cur, out = 'preamble', []
    for ln in lines:
        if HEADER.match(ln):
            cur = ' '.join(ln.split())
        out.append(cur)
    return out


def _is_code(ln):
    s = ln.strip()
    return bool(s) and not s.startswith('#')


def _picks(ln, scope, op):
    if op['scope'] != 'any' and not fnmatch.fnmatchcase(scope, op['scope']):
        return False
    if not _is_code(ln):
        return False
    sel, s = op['sel'], ln.strip()
    if 'has' in sel and not all(t in ln for t in sel['has']):
        return False
    if 'starts' in sel and not s.startswith(sel['starts']):
        return False
    if 'ends' in sel and not any(s.endswith(t) for t in sel['ends']):
        return False
    return True


def _targets(lines, op):
    sc = scopes(lines)
    found = [i for i, ln in enumerate(lines) if _picks(ln, sc[i], op)]
    if len(found) != op['expect']:
        raise Stop('%s: expected %d line(s) in scope %r matching %r, found %d'
                   % (op['op'], op['expect'], op['scope'], op['sel'], len(found)))
    return found


def _global_line(lines, name, plain):
    pat = re.compile(r'^(%%global\s+%s\s+)(.*?)\s*$' % re.escape(name))
    hit = [i for i, ln in enumerate(lines)
           if pat.match(ln) and (not plain or '%%{%s}' % name not in ln)]
    if len(hit) != 1:
        raise Stop('%s: %d matching %%global definition(s), expected exactly 1' % (name, len(hit)))
    return hit[0], pat.match(lines[hit[0]])


def op_global_set(lines, op):
    i, m = _global_line(lines, op['name'], plain=False)
    if m.group(2) != op['old']:
        raise Stop('global_set %s: value is %r, expected %r' % (op['name'], m.group(2), op['old']))
    lines[i] = m.group(1) + op['new'] + '\n'


def op_global_prepend(lines, op):
    # only the plain definition, not the ones that extend the macro with itself
    i, m = _global_line(lines, op['name'], plain=True)
    have = m.group(2).split()
    for w in op['words']:
        if w in have:
            raise Stop('global_prepend %s: %r is already present' % (op['name'], w))
    lines[i] = m.group(1) + ' '.join(op['words'] + have) + '\n'


def op_replace_lines(lines, op):
    found = _targets(lines, op)
    drop = set(found)
    first = found[0]
    # A comment block that belongs to the removed lines goes with them. Its length is
    # part of the contract: a different length means the comment, and so probably the
    # code around it, is not what was reviewed.
    want = op['absorb']
    if want:
        j, above = first - 1, 0
        while j >= 0 and lines[j].lstrip().startswith('#'):
            above += 1
            j -= 1
        if above != want:
            raise Stop('replace_lines: expected a block of %d comment line(s) above the target, found %d'
                       % (want, above))
        drop.update(range(first - want, first))
        first -= want
    new = []
    for i, ln in enumerate(lines):
        if i == first:
            new.extend(op['text'])
        if i not in drop:
            new.append(ln)
    lines[:] = new


def op_token_replace(lines, op):
    for i in _targets(lines, op):
        if lines[i].count(op['old']) != 1:
            raise Stop('token_replace: %r occurs %d times in one line'
                       % (op['old'], lines[i].count(op['old'])))
        lines[i] = lines[i].replace(op['old'], op['new'])


def op_word_remove(lines, op):
    for i in _targets(lines, op):
        words = lines[i].split(' ')
        if words.count(op['word']) != 1:
            raise Stop('word_remove: %r occurs %d times' % (op['word'], words.count(op['word'])))
        words.remove(op['word'])
        lines[i] = ' '.join(words)


def op_insert(lines, op):
    if op['text'][0] in lines:
        raise Stop('insert: the text is already present (spec already adapted?)')
    at = _targets(lines, op)[0] + (1 if op['where'] == 'after' else 0)
    lines[at:at] = op['text']


OPS = {k[3:]: f for k, f in globals().items() if k.startswith('op_')}


def apply_rules(rules, texts):
    """rules: {'files': [...], 'ops': [(file, op), ...]}; texts: file -> str. Returns file -> str."""
    lines = {name: split_lines(texts[name]) for name in rules['files']}
    for fname, op in rules['ops']:
        if op['op'] not in OPS:
            raise Stop('unknown operation %r' % op['op'])
        OPS[op['op']](lines[fname], op)
    return {name: ''.join(ln) for name, ln in lines.items()}


# ---------------------------------------------------------------------------
# one package
# ---------------------------------------------------------------------------
def resolve(pkg, packages, specs, patches, rules_table):
    """The consistency checks that need no file contents. Returns (rules, spec pins, patch pins) or None."""
    rules = rules_table.get(pkg)
    pins, extra = specs.get(pkg, {}), patches.get(pkg, {})
    if rules is None and not pins and not extra:
        return None
    if rules is None:
        raise Stop('%s: the manifest has SPEC/PATCH rows but rules.py has no rules for it' % pkg)
    if not pins:
        raise Stop('%s: rules.py has rules but the manifest pins no SPEC input; refusing to build '
                   'a package that was meant to be adapted without adapting it' % pkg)
    have = packages[pkg]['version']
    if rules['version'] != have:
        raise Stop('%s: rules are written for version %s, the manifest builds %s'
                   % (pkg, rules['version'], have))
    if set(pins) != set(rules['files']):
        raise Stop('%s: SPEC rows %s do not match the files the rules edit %s'
                   % (pkg, sorted(pins), sorted(rules['files'])))
    if packages[pkg]['spec'] not in pins:
        raise Stop('%s: the manifest spec %s has no SPEC row' % (pkg, packages[pkg]['spec']))
    if set(extra) != set(rules.get('patches', [])):
        raise Stop('%s: PATCH rows %s do not match the patches the rules expect %s'
                   % (pkg, sorted(extra), sorted(rules.get('patches', []))))
    return rules, pins, extra


def adapt_texts(pkg, rules, pins, read):
    """read(name) -> bytes. Returns {name: bytes}. Writes nothing."""
    texts = {}
    for name in rules['files']:
        data = read(name)
        want_in, want_out = pins[name]
        got = sha256(data)
        if got == want_out:
            raise Stop('%s/%s: already adapted (its SHA-256 is the reviewed OUTPUT, %s); '
                       'refusing to adapt twice' % (pkg, name, got[:16]))
        if got != want_in:
            raise Stop('%s/%s: input SHA-256 %s is not the reviewed %s'
                       % (pkg, name, got[:16], want_in[:16]))
        try:
            texts[name] = data.decode('utf-8')
        except UnicodeDecodeError as e:
            raise Stop('%s/%s: not UTF-8: %s' % (pkg, name, e))
    done = apply_rules(rules, texts)
    out = {}
    for name, text in done.items():
        data = text.encode('utf-8')
        got = sha256(data)
        if got != pins[name][1]:
            raise Stop('%s/%s: output SHA-256 %s is not the reviewed %s'
                       % (pkg, name, got[:16], pins[name][1][:16]))
        out[name] = data
    return out


def adapt_tree(manifest, pkg, tree, root, rules_table):
    packages, specs, patches = parse_manifest(manifest)
    if pkg not in packages:
        raise Stop('%s: not a package in %s' % (pkg, os.path.basename(manifest)))
    got = resolve(pkg, packages, specs, patches, rules_table)
    if got is None:
        print('  adapt: no adaptation declared for %s' % pkg)
        return
    rules, pins, extra = got

    def read(name):
        p = os.path.join(tree, name)
        if not os.path.isfile(p):
            raise Stop('%s: %s is not in the staged distgit' % (pkg, name))
        with open(p, 'rb') as fh:
            return fh.read()

    out = adapt_texts(pkg, rules, pins, read)
    third = {}
    for rel, want in sorted(extra.items()):
        p = os.path.join(root, rel)
        if not os.path.isfile(p):
            raise Stop('%s: third-party patch %s is missing' % (pkg, rel))
        with open(p, 'rb') as fh:
            data = fh.read()
        if sha256(data) != want:
            raise Stop('%s: third-party patch %s has SHA-256 %s, the manifest pins %s'
                       % (pkg, rel, sha256(data)[:16], want[:16]))
        dest = os.path.join(tree, os.path.basename(rel))
        if os.path.exists(dest):
            raise Stop('%s: %s already exists in the staged distgit' % (pkg, os.path.basename(rel)))
        third[dest] = data

    # Everything has passed. Stage every result next to its destination first and only
    # then rename them into place, so an I/O error cannot leave a half-adapted tree
    # (a rename within one directory is atomic; the staged files are removed on error).
    writes = [(os.path.join(tree, name), data) for name, data in out.items()] + sorted(third.items())
    staged = []
    try:
        for dest, data in writes:
            tmp = dest + '.adapt-tmp'
            with open(tmp, 'wb') as fh:
                fh.write(data)
            staged.append((tmp, dest))
    except OSError:
        for tmp, _ in staged:
            os.unlink(tmp)
        raise
    for tmp, dest in staged:
        os.replace(tmp, dest)
    for name in out:
        print('  adapt: %s/%s  %s -> %s  (%s@%s)' % (
            pkg, name, pins[name][0][:12], pins[name][1][:12],
            packages[pkg]['repo'], packages[pkg]['commit'][:12]))
    for dest, data in sorted(third.items()):
        print('  adapt: %s/%s  third-party patch installed  %s' % (
            pkg, os.path.basename(dest), sha256(data)[:12]))


def check_manifest(manifest, rules_table):
    packages, specs, patches = parse_manifest(manifest)
    for pkg in sorted(set(specs) | set(patches)):
        if resolve(pkg, packages, specs, patches, rules_table) is None:
            raise Stop('%s: SPEC/PATCH rows without rules' % pkg)
    print('manifest %s: %d package rows, %d adapted (%d SPEC, %d PATCH) - consistent with rules.py'
          % (os.path.basename(manifest), len(packages), len(specs),
             sum(map(len, specs.values())), sum(map(len, patches.values()))))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--manifest', required=True)
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--package')
    ap.add_argument('--tree')
    ap.add_argument('--root', default=os.path.dirname(HERE),
                    help='directory PATCH paths are relative to (default: the rocky10.2 directory)')
    a = ap.parse_args(argv)
    try:
        import rules
        if a.check == bool(a.package) or (a.package and not a.tree):
            raise Stop('usage: --check, or --package NAME --tree DIR')
        if a.check:
            check_manifest(a.manifest, rules.RULES)
        else:
            adapt_tree(a.manifest, a.package, a.tree, a.root, rules.RULES)
    except Stop as e:
        print('STOP: %s' % e, file=sys.stderr)
        return 1
    except OSError as e:
        print('STOP: %s' % e, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
