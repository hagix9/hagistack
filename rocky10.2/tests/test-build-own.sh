#!/usr/bin/env bash
# Tests for packaging/build-own.sh's environment control, with stub dnf/sudo:
#   - every name the definitions produce is excluded from every repository file
#     but hagistack-own.repo (RDO, EPEL, Rocky), in every section, enabled or not,
#     keeping existing exclude= lines, idempotently; a file that cannot be
#     rewritten, or a repository in dnf.conf, stops the run;
#   - a repository DNF still offers one of our names from stops the run;
#   - a waiting definition is retried only once this build produced something new;
#   - the checks refuse a build environment holding one of our names from
#     anywhere but this build, and refuse to call a failed query "clean".
#   bash rocky10.2/tests/test-build-own.sh     (needs python3 >= 3.11 for own_names)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BO="$HERE/../packaging/build-own.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/hs-bo-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2" | head -8; }

# Stubs: sudo runs its arguments; dnf answers from files the tests write.
mkdir -p "$T/bin" "$T/repos" "$T/work/logs"
cat > "$T/bin/sudo" <<'EOS'
#!/bin/sh
exec "$@"
EOS
cat > "$T/bin/dnf" <<'EOS'
#!/bin/sh
# repoquery --whatprovides X (own repository only): listed in $STUB/own-provides
# repoquery --installed: $STUB/installed, or exit $STUB_FAIL
# repoquery <names> (what the repositories offer): $STUB/offered, or exit $STUB_RQ_FAIL
case " $* " in
  *" --whatprovides "*) for a; do last="$a"; done; grep -qxF "$last" "$STUB/own-provides" 2>/dev/null && echo "provider-of-$last"; exit 0 ;;
  *" --installed "*) [ -n "${STUB_FAIL:-}" ] && exit "$STUB_FAIL"; cat "$STUB/installed" 2>/dev/null; exit 0 ;;
  *" repoquery "*) [ -n "${STUB_RQ_FAIL:-}" ] && exit "$STUB_RQ_FAIL"; cat "$STUB/offered" 2>/dev/null; exit 0 ;;
esac
exit 0
EOS
chmod +x "$T/bin/sudo" "$T/bin/dnf"
# own_names runs genspec.py, which needs tomllib (Python >= 3.11).
PY=""
for c in python3 python3.13 python3.12 python3.11; do
    command -v "$c" >/dev/null 2>&1 && "$c" -c 'import tomllib' 2>/dev/null && { PY="$(command -v "$c")"; break; }
done
[ -n "$PY" ] && ln -s "$PY" "$T/bin/python3"
export PATH="$T/bin:$PATH" STUB="$T"

lib() {   # lib <shell code>: run code with build-own.sh's functions loaded
    BUILD_OWN_LIB_ONLY=1 BUILD_OWN_REPO_DIR="$T/repos" BUILD_OWN_DNF_CONF="$T/dnf.conf" WORK="$T/work" HOME="$T/home" \
        bash -c 'source "$1"; shift; eval "$1"' _ "$BO" "$1"
}

echo "== build-own.sh environment control"

# --- the library mode loads the functions and builds nothing -----------------
out="$(lib 'type exclude_own repos_offering_own ready env_not_own own_names missing_deps >/dev/null && echo loaded' 2>&1)"
[ "$out" = loaded ] && pass "library mode loads the functions and runs nothing else" || fail "library mode" "$out"
out="$(BUILD_OWN_LIB_ONLY=1 WORK="$T/work" HOME="$T/home" bash "$BO" 2>&1; echo "rc=$?")"
[ "$out" = "rc=0" ] && pass "library mode executed (not sourced) exits at once" || fail "library mode executed" "$out"

# --- exclusion: RDO, EPEL and Rocky files, every section, existing excludes ----
printf '[main]\ngpgcheck=1\n' > "$T/dnf.conf"
cat > "$T/repos/delorean.repo" <<'EOF'
[delorean]
name=delorean
baseurl=https://example.invalid/current
enabled=1
gpgcheck=0

[delorean-component-common]
name=common
baseurl=https://example.invalid/common
gpgcheck=0
EOF
cat > "$T/repos/delorean-deps.repo" <<'EOF'
[delorean-master-testing]
name=deps
baseurl=https://example.invalid/deps
enabled=1
EOF
cat > "$T/repos/epel.repo" <<'EOF'
[epel]
name=EPEL
metalink=https://example.invalid/epel
enabled=1
exclude=python3-unrelated*

[epel-testing]
name=EPEL testing
metalink=https://example.invalid/epel-testing
enabled=0
EOF
cat > "$T/repos/rocky.repo" <<'EOF'
# Rocky base
[baseos]
name=BaseOS
mirrorlist=https://example.invalid/baseos
enabled=1
excludepkgs=kernel-rt
  kernel-rt-debug
[appstream]
name=AppStream
mirrorlist=https://example.invalid/appstream
enabled=1
exclude=foo
excludepkgs=bar
EOF
printf '[hagistack-own]\nname=own\nbaseurl=file:///x\nenabled=1\npriority=1\n' > "$T/repos/hagistack-own.repo"
for f in "$T"/repos/*.repo; do cp "$f" "$T/orig-$(basename "$f")"; done
printf 'python3-oslo-log\npython3-oslo-db+mysql\n' > "$T/names"
lib "exclude_own '$T/names'" || fail "exclude_own ran" "rc=$?"
for f in delorean delorean-deps epel rocky; do cp "$T/repos/$f.repo" "$T/once-$f.repo"; done
lib "exclude_own '$T/names'" || fail "exclude_own ran twice" "rc=$?"

# what a strict INI parser (DNF's files are INI) reads as each section's exclusion
python3 -I - "$T/repos" > "$T/sections.out" 2>&1 <<'PY'
import configparser, glob, os, sys
for f in sorted(glob.glob(os.path.join(sys.argv[1], '*.repo'))):
    c = configparser.ConfigParser(interpolation=None, strict=True)
    c.read(f)
    for s in c.sections():
        vals = set()
        for k in ('exclude', 'excludepkgs'):
            if c.has_option(s, k):
                vals |= set(c.get(s, k).split())
        print(os.path.basename(f), s, ' '.join(sorted(vals)))
PY
[ "$(grep -v '^hagistack-own.repo' "$T/sections.out" | grep -c 'python3-oslo-db+mysql python3-oslo-log')" -eq 7 ] \
    && pass "every section of the RDO, EPEL and Rocky files excludes our names, enabled or not (7 sections, strict INI parse)" \
    || fail "sections excluded" "$(cat "$T/sections.out")"
grep -qx 'epel.repo epel python3-oslo-db+mysql python3-oslo-log python3-unrelated\*' "$T/sections.out" \
    && grep -qx 'rocky.repo baseos kernel-rt kernel-rt-debug python3-oslo-db+mysql python3-oslo-log' "$T/sections.out" \
    && pass "an existing exclude= / excludepkgs= (also with a continuation line) is kept and extended" \
    || fail "existing excludes" "$(cat "$T/sections.out")"
grep -q '^exclude=foo python3-oslo-log python3-oslo-db+mysql$' "$T/repos/rocky.repo" \
    && grep -q '^excludepkgs=bar python3-oslo-log python3-oslo-db+mysql$' "$T/repos/rocky.repo" \
    && pass "a section with both exclude= and excludepkgs= gets our names on each (whichever DNF takes)" \
    || fail "both keys" "$(cat "$T/repos/rocky.repo")"
grep -q '^hagistack-own.repo hagistack-own $' "$T/sections.out" \
    && cmp -s "$T/repos/hagistack-own.repo" "$T/orig-hagistack-own.repo" \
    && pass "hagistack-own.repo, this build's repository, is left alone (nothing excluded from it)" \
    || fail "hagistack-own.repo changed" "$(cat "$T/repos/hagistack-own.repo")"
same=1; for f in delorean delorean-deps epel rocky; do cmp -s "$T/repos/$f.repo" "$T/once-$f.repo" || same=0; done
[ "$same" -eq 1 ] && pass "a second run changes nothing (idempotent)" || fail "idempotent" "$(diff "$T/once-epel.repo" "$T/repos/epel.repo")"
grep -q '^metalink=https://example.invalid/epel-testing$' "$T/repos/epel.repo" && grep -q '^# Rocky base$' "$T/repos/rocky.repo" \
    && pass "the rest of each repository file is kept" || fail "repository file kept"
OE="$HERE/../packaging/own-excludes.py" python3 -I - "$T" <<'PY' && pass "the original files come back exactly from the recorded lines: only our names were added" || fail "restore"
import importlib.util, os, sys
t = sys.argv[1]
spec = importlib.util.spec_from_file_location('oe', os.environ['OE'])
oe = importlib.util.module_from_spec(spec); spec.loader.exec_module(oe)
for f in ('delorean', 'delorean-deps', 'epel', 'rocky'):
    now = open(os.path.join(t, 'repos', f + '.repo')).read().splitlines()
    orig = open(os.path.join(t, 'orig-' + f + '.repo')).read().splitlines()
    assert oe.restore(now) == orig, f
PY
# a repository file added later (a package dropping one) is covered by the next call
printf '[late]\nname=late\nbaseurl=https://example.invalid/late\nenabled=0\n' > "$T/repos/late.repo"
lib "exclude_own '$T/names'" && grep -q '^excludepkgs=python3-oslo-log python3-oslo-db+mysql$' "$T/repos/late.repo" \
    && grep -q 'exclude_own "$WORK/own-names.txt" > "$log.excludes.log" 2>&1' "$BO" \
    && pass "a repository file added later is covered: every dependency install re-applies the exclusion first" \
    || fail "late repository file" "$(cat "$T/repos/late.repo")"

# failures stop the run
mkdir "$T/repos/broken.repo"
lib "exclude_own '$T/names'" 2>/dev/null && fail "a repository file that cannot be rewritten passed" \
    || pass "a repository file that cannot be read or rewritten makes exclude_own fail"
rmdir "$T/repos/broken.repo"
printf '[main]\ngpgcheck=1\n[sneaky]\nbaseurl=https://example.invalid/s\n' > "$T/dnf.conf"
lib "exclude_own '$T/names'" 2>/dev/null && fail "a repository in dnf.conf passed" \
    || pass "a repository defined in dnf.conf (not edited) makes exclude_own fail"
printf '[main]\ngpgcheck=1\n' > "$T/dnf.conf"
lib "exclude_own '$T/names'" || fail "exclude_own after the failures" "rc=$?"
grep -q 'exclude_own "$WORK/own-names.txt" > "$LOGDIR/excludes.log" 2>&1 \\$' "$BO" \
    && grep -A1 'exclude_own "$WORK/own-names.txt" > "$LOGDIR/excludes.log"' "$BO" | grep -q '|| die' \
    && grep -A1 'exclude_own "$WORK/own-names.txt" > "$log.excludes.log"' "$BO" | grep -q '|| die' \
    && pass "a failed exclusion stops the run (STOP), before the first build and before every dependency install" \
    || fail "exclusion failure does not stop the run"

# what DNF itself still offers under our names
printf 'python3-oslo-log hagistack-own\npython3-oslo-log @System\n' > "$T/offered"
out="$(lib "repos_offering_own '$T/names'"; echo "rc=$?")"
[ "$out" = "rc=0" ] && pass "our names offered only by hagistack-own (or installed) count as none" || fail "own offers" "$out"
printf 'python3-oslo-log epel\npython3-oslo-log hagistack-own\npython3-oslo-db+mysql baseos\n' > "$T/offered"
out="$(lib "repos_offering_own '$T/names'" | tr '\n' ';')"
[ "$out" = "python3-oslo-log epel;python3-oslo-db+mysql baseos;" ] \
    && pass "negative case: a name EPEL or Rocky still offers is reported, with its repository" || fail "external offers" "$out"
STUB_RQ_FAIL=1 lib "repos_offering_own '$T/names'" >/dev/null; rc=$?
[ "$rc" -eq 2 ] && pass "a failed repository query is not taken as none" || fail "failed repository query" "rc=$rc"
grep -q '\[ -z "$leak" \] || die "a repository still offers' "$BO" && grep -q '\[ -z "$leak" \] || die "at the end, a repository offers' "$BO" \
    && [ "$(grep -c 'leak="$(repos_offering_own "$WORK/own-names.txt")"' "$BO")" -eq 2 ] \
    && pass "an offer from another repository, or a failed query, stops the run before the first build and at the end" \
    || fail "offer check does not stop the run"

# this build's repository wins
grep -q '^priority=1$' "$BO" && grep -q '^\[hagistack-own\]$' "$BO" \
    && pass "this build's repository is published as hagistack-own with priority=1" || fail "hagistack-own priority"

# --- own_names: every package of every definition, once ------------------------
if [ -n "$PY" ]; then
    out="$(lib 'own_names' 2>&1)"; n=$(printf '%s\n' "$out" | grep -c .); u=$(printf '%s\n' "$out" | sort -u | grep -c .)
    want=$(cat "$HERE"/../packaging/defs/*.toml | grep -c '^\[\[package\]\]')
    [ "$n" -eq "$want" ] && [ "$u" -eq "$n" ] && printf '%s\n' "$out" | grep -qx 'python3-oslo-log' \
        && pass "own_names lists all $n package names of the definitions, each once" \
        || fail "own_names" "listed=$n unique=$u packages-in-defs=$want"
else
    fail "own_names" "no python3 >= 3.11 with tomllib here; not run"
fi

# --- missing_deps / ready -------------------------------------------------------
printf 'error: Failed build dependencies:\n\tpython3dist(oslo-log) >= 4.6.1 is needed by python-x-1.0-1.el10.noarch\n\tpython3dist(fixtures) is needed by python-x-1.0-1.el10.noarch\n' \
    > "$T/work/logs/python-x.rpmbuild.log"
got="$(lib 'missing_deps python-x' | tr '\n' ' ')"
[ "$got" = "python3dist(fixtures) python3dist(oslo-log) " ] && pass "missing_deps reads rpmbuild's missing build dependencies" || fail "missing_deps" "$got"
lib 'missing_deps python-x > "$LOGDIR/python-x.missing"'
: > "$T/own-provides"
echo 3 > "$T/work/logs/python-x.since"
lib 'OWN_BUILT=3; ready python-x' && fail "ready: nothing new built, yet retried" || pass "a waiting definition is not retried while this build has produced nothing new since its attempt"
lib 'OWN_BUILT=4; ready python-x' && pass "it is retried once this build produced a new package since its attempt (a dependency missed indirectly)" || fail "ready after a new package"
echo 'python3dist(oslo-log)' > "$T/own-provides"
lib 'OWN_BUILT=3; ready python-x' && pass "it is retried once a dependency it missed is provided by this build" || fail "ready after the dependency is built"
lib 'ready python-y' && pass "a definition with no record of what it missed is retried" || fail "ready without a record"
grep -q 'OWN_BUILT=$((OWN_BUILT + 1))' "$BO" && grep -q 'echo "$OWN_BUILT" > "$LOGDIR/$n.since"' "$BO" \
    && grep -q '\[ "$built" -gt 0 \] || break' "$BO" \
    && pass "the count of packages built is recorded with each wait, and the rounds end when a round builds nothing (no endless retry)" \
    || fail "ready bookkeeping"

# --- the final check --------------------------------------------------------------
printf 'python3-oslo-log\npython3-oslo-db\n' > "$T/work/own-names.txt"
printf 'bash @System\npython3-oslo-log hagistack-own\npython3-oslo-db hagistack-own\n' > "$T/installed"
out="$(lib 'env_not_own'; echo "rc=$?")"
[ "$out" = "rc=0" ] && pass "a build environment whose packages with our names all came from this build is clean" || fail "clean environment" "$out"
printf 'bash @System\npython3-oslo-log delorean-component-common\npython3-oslo-db hagistack-own\n' > "$T/installed"
out="$(lib 'env_not_own')"
[ "$out" = "python3-oslo-log delorean-component-common" ] && pass "one of our names from RDO trunk is reported, with its repository" || fail "stray package" "$out"
: > "$T/installed"
lib 'env_not_own' >/dev/null; rc=$?
[ "$rc" -eq 2 ] && pass "an empty installed-package list is not taken as clean" || fail "empty query" "rc=$rc"
STUB_FAIL=1 lib 'env_not_own' >/dev/null; rc=$?
[ "$rc" -eq 2 ] && pass "a failed query is not taken as clean" || fail "failed query" "rc=$rc"

# --- the main run wires the pieces in order --------------------------------------
# Each step's line, looked up on its own, so the order is really checked.
at() { grep -n -E "$1" "$BO" | sed -n "${2:-1}p" | cut -d: -f1; }
m="$(at '^for n in "\$\{WANT\[@\]\}"; do stage') $(at '^own_names >') $(at '^exclude_own ') $(at '^leak=') $(at '^stray=') $(at '^round=0') $(at '^write_lock$') $(at '^leak=' 2) $(at '^stray=' 2)"
set -- $m
ordered=1; prev=0
for x in "$@"; do [ "$x" -gt "$prev" ] || ordered=0; prev="$x"; done
[ "$#" -eq 9 ] && [ "$ordered" -eq 1 ] \
    && pass "the run stages, lists our names, excludes them, asks DNF, checks what is installed, builds, writes the lock, asks DNF and checks again" \
    || fail "order in the main run" "lines: $m"
grep -q 'stray="$(env_not_own)" || die' "$BO" && grep -q '\[ -z "$stray" \] || die' "$BO" \
    && pass "a stray package or a failed check stops the run (STOP)" || fail "the check does not stop the run"
grep -q '|| die "before the first build, the build environment already holds packages with our names' "$BO" \
    && [ "$(grep -c 'stray="$(env_not_own)" || die' "$BO")" -eq 2 ] \
    && pass "a package with one of our names installed from elsewhere before the first build stops the run" \
    || fail "the check before the first build is missing"
grep -q 'sed -i.*hagistack-own' "$BO" && fail "publish_repo still rewrites the exclusion per build" || pass "the exclusion is no longer recomputed from what is built so far"

echo
echo "build-own.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
