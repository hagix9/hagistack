#!/usr/bin/env bash
# Tests for hagistack's RPM-source logic: GitHub-release download (against a
# local HTTP server standing in for GitHub), bundle, verification, cache reuse,
# failure handling and the role/consistency guards.
#
#   sudo dnf -y install rpm-build createrepo_c python3   # once
#   bash rocky10.2/tests/test-rpm-source.sh
#
# Runs on Rocky/EL 10 as an ordinary user. It changes nothing outside a
# temporary directory: hagistack is sourced with HAGISTACK_LIB_ONLY=1 and its
# state/etc paths point into that directory. No OpenStack is installed.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HS="$HERE/../hagistack"
for t in rpmbuild createrepo_c python3 curl tar; do
    command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; exit 2; }
done

T="$(mktemp -d "${TMPDIR:-/tmp}/hs-rpmsrc-test.XXXXXX")"
PORT=$((20000 + RANDOM % 20000))
SRV_PID=""
cleanup() { [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2" | head -12; }

# ---------------------------------------------------------------- fixtures
mkdir -p "$T/rpmbuild/SPECS" "$T/set/repo" "$T/www"
for n in alpha beta gamma; do
    cat > "$T/rpmbuild/SPECS/hs-test-$n.spec" <<EOF
Name: hs-test-$n
Version: 1.0
Release: 1
Summary: hagistack test fixture $n
License: MIT
BuildArch: noarch
%description
fixture
%install
mkdir -p %{buildroot}/usr/share/hs-test
echo $n > %{buildroot}/usr/share/hs-test/$n
%files
/usr/share/hs-test/$n
EOF
    rpmbuild --define "_topdir $T/rpmbuild" -bb "$T/rpmbuild/SPECS/hs-test-$n.spec" >/dev/null 2>&1 \
        || { echo "fixture rpmbuild failed" >&2; exit 2; }
done
find "$T/rpmbuild/RPMS" -name '*.rpm' -exec cp {} "$T/set/repo/" \;
createrepo_c --quiet --general-compress-type=gz "$T/set/repo"
( cd "$T/set/repo" && ls *.rpm | LC_ALL=C sort | while read -r n; do
    printf '%s  %s\n' "$(sha256sum "$n" | cut -d' ' -f1)" "$n"; done ) > "$T/set/RPM-SHA256SUMS"
SET_SHA="$(sha256sum "$T/set/RPM-SHA256SUMS" | cut -d' ' -f1)"
mk_asset() {   # mk_asset <set-dir> <out-tar>
    tar -cf "$2" --owner=0 --group=0 -C "$1" RPM-SHA256SUMS repo
}
mkdir -p "$T/www/v-test"
mk_asset "$T/set" "$T/www/v-test/asset.tar"
ASHA="$(sha256sum "$T/www/v-test/asset.tar" | cut -d' ' -f1)"
ASIZE="$(stat -c %s "$T/www/v-test/asset.tar")"
MSHA="$(sha256sum "$HERE/../gazpacho.manifest" | cut -d' ' -f1)"

write_lock() {  # write_lock <file> [KEY=VAL overrides...]
    local f="$1"; shift
    local -A L=([LOCK_FORMAT]=1 [LOCK_STATUS]=published [RELEASE_TAG]=v-test
                [BASE_URL]="http://127.0.0.1:$PORT" [ASSET_NAME]=asset.tar
                [ASSET_SHA256]="$ASHA" [ASSET_SIZE]="$ASIZE" [RPM_SET_SHA256]="$SET_SHA"
                [RPM_COUNT]=3 [MANIFEST_SHA256]="$MSHA")
    local kv
    for kv in "$@"; do L[${kv%%=*}]="${kv#*=}"; done
    : > "$f"
    for k in LOCK_FORMAT LOCK_STATUS RELEASE_TAG BASE_URL ASSET_NAME ASSET_SHA256 ASSET_SIZE RPM_SET_SHA256 RPM_COUNT MANIFEST_SHA256; do
        [ -n "${L[$k]:-}" ] && printf '%s=%s\n' "$k" "${L[$k]}" >> "$f"
    done
}

start_server() {
    ( cd "$T/www" && exec python3 -I -m http.server "$PORT" --bind 127.0.0.1 ) >/dev/null 2>&1 &
    SRV_PID=$!
    local _; for _ in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && return 0; sleep 0.1; done
    echo "server did not start" >&2; exit 2
}
stop_server() { [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null; wait "$SRV_PID" 2>/dev/null; SRV_PID=""; }

# Run a snippet with hagistack's functions loaded and a private state tree.
# Usage: run_hs <state-name> '<bash code>'   -> sets OUT and RC
run_hs() {
    local st="$T/state-$1"; mkdir -p "$st/etc" "$st/var"
    OUT="$(HAGISTACK_LIB_ONLY=1 HAGISTACK_ETC="$st/etc" HAGISTACK_STATE="$st/var" NO_COLOR=1 \
        bash -c '
            set -euo pipefail
            source "$1"
            SUDO=""; trap - ERR
            _need_privilege() { :; }
            podman() { echo "PODMAN-CALLED" >&2; return 99; }
            dnf_install() { echo "DNF-CALLED $*" >&2; return 99; }
            eval "$2"
        ' _ "$HS" "$2" 2>&1)"
    RC=$?
}

expect_ok()   { if [ "$RC" -eq 0 ]; then pass "$1"; else fail "$1" "rc=$RC: $OUT"; fi; }
expect_fail() {  # expect_fail <name> <regex-in-output>
    if [ "$RC" -ne 0 ] && grep -qE "$2" <<<"$OUT"; then pass "$1"
    else fail "$1" "rc=$RC, wanted /$2/: $OUT"; fi
}
no_build_no_dnf() {
    if grep -qE 'PODMAN-CALLED|DNF-CALLED' <<<"$OUT"; then fail "$1: no build/dnf attempted" "$OUT"
    else pass "$1: no build or package install attempted (no silent fallback)"; fi
}

echo "== hagistack RPM source tests (fixture set ${SET_SHA:0:16}…, port $PORT) =="
start_server

# 1. github: download, verify, install into the store
write_lock "$T/lock.good"
run_hs g1 "RPM_SOURCE=github RPM_LOCK_FILE=$T/lock.good; rpm_source_resolve; rpm_prepare_github; echo SET=\$RPM_SET_SHA256 DIR=\$RPM_SET_DIR"
expect_ok "github: published release downloads and verifies"
grep -q "SET=$SET_SHA" <<<"$OUT" && pass "github: set identity is the pinned one" || fail "github: set identity" "$OUT"
[ -f "$T/state-g1/var/rpms/github-v-test-${SET_SHA:0:16}/.hagistack-verified" ] \
    && pass "github: verified marker written" || fail "github: verified marker"
! compgen -G "$T/state-g1/var/rpms/.staging.*" >/dev/null && pass "github: no staging left behind" || fail "github: staging left"

# 2. cache reuse: server down, second run must not download
stop_server
run_hs g1 "RPM_SOURCE=github RPM_LOCK_FILE=$T/lock.good; rpm_source_resolve; rpm_prepare_github"
expect_ok "github: re-run reuses the verified cache with the server unreachable"
grep -q "not downloaded again" <<<"$OUT" && pass "github: re-run says it reused the cache" || fail "github: reuse message" "$OUT"

# 3. network failure without cache
run_hs g3 "RPM_SOURCE=github RPM_LOCK_FILE=$T/lock.good; rpm_prepare_github"
expect_fail "github: network failure stops" "could not download"
no_build_no_dnf "github: network failure"
start_server

# 4. 404 (release tag that does not exist)
write_lock "$T/lock.404" RELEASE_TAG=v-missing
run_hs g4 "RPM_SOURCE=github RPM_LOCK_FILE=$T/lock.404; rpm_prepare_github"
expect_fail "github: 404 stops" "could not download"
no_build_no_dnf "github: 404"

# 5. checksum mismatch
write_lock "$T/lock.badsha" ASSET_SHA256=0000000000000000000000000000000000000000000000000000000000000000
run_hs g5 "RPM_SOURCE=github RPM_LOCK_FILE=$T/lock.badsha; rpm_prepare_github"
expect_fail "github: asset SHA-256 mismatch stops" "does not match the pinned release"
no_build_no_dnf "github: checksum mismatch"
[ ! -e "$T/state-g5/var/rpms/github-v-test-${SET_SHA:0:16}" ] && pass "github: mismatched asset not installed" || fail "github: mismatched asset installed"

# 6. size mismatch
write_lock "$T/lock.badsize" ASSET_SIZE=1
run_hs g6 "RPM_SOURCE=github RPM_LOCK_FILE=$T/lock.badsize; rpm_prepare_github"
expect_fail "github: asset size mismatch stops" "does not match the pinned release"

# 7. set identity mismatch (asset fine, RPM set different from the lock)
write_lock "$T/lock.badset" RPM_SET_SHA256=1111111111111111111111111111111111111111111111111111111111111111
run_hs g7 "RPM_SOURCE=github RPM_LOCK_FILE=$T/lock.badset; rpm_prepare_github"
expect_fail "github: RPM set identity mismatch stops" "identity mismatch"

# 8. incomplete set: one RPM missing but still listed
rm -rf "$T/inc"; cp -a "$T/set" "$T/inc"; rm -f "$T/inc/repo/"hs-test-beta*.rpm
mkdir -p "$T/www/v-inc"; mk_asset "$T/inc" "$T/www/v-inc/asset.tar"
write_lock "$T/lock.inc" RELEASE_TAG=v-inc ASSET_SHA256="$(sha256sum "$T/www/v-inc/asset.tar" | cut -d' ' -f1)" ASSET_SIZE="$(stat -c %s "$T/www/v-inc/asset.tar")"
run_hs g8 "RPM_SOURCE=github RPM_LOCK_FILE=$T/lock.inc; rpm_prepare_github"
expect_fail "github: incomplete RPM set stops" "do not match RPM-SHA256SUMS"

# 9. repodata inconsistent: an RPM present and listed in RPM-SHA256SUMS but not in repodata
rm -rf "$T/rd"; cp -a "$T/set" "$T/rd"; mv "$T/rd/repo/"hs-test-gamma*.rpm "$T/"
createrepo_c --quiet --general-compress-type=gz "$T/rd/repo"; mv "$T/"hs-test-gamma*.rpm "$T/rd/repo/"
mkdir -p "$T/www/v-rd"; mk_asset "$T/rd" "$T/www/v-rd/asset.tar"
write_lock "$T/lock.rd" RELEASE_TAG=v-rd ASSET_SHA256="$(sha256sum "$T/www/v-rd/asset.tar" | cut -d' ' -f1)" ASSET_SIZE="$(stat -c %s "$T/www/v-rd/asset.tar")"
run_hs g9 "RPM_SOURCE=github RPM_LOCK_FILE=$T/lock.rd; rpm_prepare_github"
expect_fail "github: repodata that omits an RPM stops" "not in the metadata"

# 10. repodata metadata file altered (checksum in repomd no longer matches)
rm -rf "$T/rd2"; cp -a "$T/set" "$T/rd2"
f="$(ls "$T/rd2/repo/repodata/"*filelists.xml.gz | head -1)"; printf 'x' >> "$f"
mkdir -p "$T/www/v-rd2"; mk_asset "$T/rd2" "$T/www/v-rd2/asset.tar"
write_lock "$T/lock.rd2" RELEASE_TAG=v-rd2 ASSET_SHA256="$(sha256sum "$T/www/v-rd2/asset.tar" | cut -d' ' -f1)" ASSET_SIZE="$(stat -c %s "$T/www/v-rd2/asset.tar")"
run_hs g10 "RPM_SOURCE=github RPM_LOCK_FILE=$T/lock.rd2; rpm_prepare_github"
expect_fail "github: altered repodata file stops" "checksum mismatch"

# 11. unsafe tar member
mkdir -p "$T/evil/repo"; cp "$T/set/RPM-SHA256SUMS" "$T/evil/"; echo x > "$T/evil/x"
mkdir -p "$T/www/v-evil"
python3 -I - "$T/www/v-evil/asset.tar" "$T/evil/x" <<'PYEOF'
import sys, tarfile
with tarfile.open(sys.argv[1], "w") as t:
    t.add(sys.argv[2], arcname="../escape")
PYEOF
write_lock "$T/lock.evil" RELEASE_TAG=v-evil ASSET_SHA256="$(sha256sum "$T/www/v-evil/asset.tar" | cut -d' ' -f1)" ASSET_SIZE="$(stat -c %s "$T/www/v-evil/asset.tar")"
run_hs g11 "RPM_SOURCE=github RPM_LOCK_FILE=$T/lock.evil; rpm_prepare_github"
expect_fail "github: tar with '../' member is refused before extraction" "unsafe member|refusing to unpack"
[ ! -e "$T/state-g11/escape" ] && [ ! -e "$T/state-g11/var/escape" ] && pass "github: nothing escaped the staging directory" || fail "github: file escaped"

# 12. unpublished lock
printf 'LOCK_FORMAT=1\nLOCK_STATUS=unpublished\n' > "$T/lock.unpub"
run_hs g12 "RPM_SOURCE=github RPM_LOCK_FILE=$T/lock.unpub; rpm_prepare_github"
expect_fail "github: unpublished lock stops with guidance" "no published RPM release"
no_build_no_dnf "github: unpublished lock"
run_hs g12b "RPM_SOURCE=github; rpm_prepare_github"
expect_fail "github: the shipped rpm-release.lock is unpublished" "no published RPM release"

# 13. manifest mismatch
write_lock "$T/lock.man" MANIFEST_SHA256=2222222222222222222222222222222222222222222222222222222222222222
run_hs g13 "RPM_SOURCE=github RPM_LOCK_FILE=$T/lock.man; rpm_prepare_github"
expect_fail "github: release built from another manifest stops" "different gazpacho.manifest"

# 14. lock file with an unsafe value or unknown key
printf 'LOCK_FORMAT=1\nLOCK_STATUS=published\nBASE_URL=http://x/$(id)\n' > "$T/lock.meta"
run_hs g14 "RPM_SOURCE=github RPM_LOCK_FILE=$T/lock.meta; rpm_prepare_github"
expect_fail "lock: shell metacharacters refused" "not allowed"
printf 'LOCK_FORMAT=1\nEVIL=1\n' > "$T/lock.unk"
run_hs g14b "RPM_SOURCE=github RPM_LOCK_FILE=$T/lock.unk; rpm_prepare_github"
expect_fail "lock: unknown key refused" "unknown key"

# 15. broken cache: a cached RPM altered -> re-download, broken copy kept aside
run_hs g15 "RPM_SOURCE=github RPM_LOCK_FILE=$T/lock.good; rpm_prepare_github"
c="$T/state-g15/var/rpms/github-v-test-${SET_SHA:0:16}"
printf 'x' >> "$(ls "$c/repo/"hs-test-alpha*.rpm)"
run_hs g15 "RPM_SOURCE=github RPM_LOCK_FILE=$T/lock.good; rpm_prepare_github"
expect_ok "github: a corrupted cache is not trusted; the asset is fetched again"
ls -d "$c".broken.* >/dev/null 2>&1 && pass "github: corrupted cache moved aside, not deleted" || fail "github: broken cache kept"

# 16. bundle: right and wrong identity
mk_asset "$T/set" "$T/bundle.tar"
run_hs b1 "RPM_SOURCE=bundle RPM_BUNDLE=$T/bundle.tar RPM_SET_EXPECTED=$SET_SHA; rpm_source_resolve; rpm_prepare_bundle"
expect_ok "bundle: verified against the expected identity"
run_hs b2 "RPM_SOURCE=bundle RPM_BUNDLE=$T/bundle.tar RPM_SET_EXPECTED=3333333333333333333333333333333333333333333333333333333333333333; rpm_prepare_bundle"
expect_fail "bundle: wrong identity stops" "identity mismatch|not the RPM set"
run_hs b3 "RPM_SOURCE=bundle RPM_BUNDLE=$T/bundle.tar; rpm_prepare_bundle"
expect_fail "bundle: no expected identity stops" "needs the identity"

# 17. source resolution rules
run_hs r1 "REPO_URL=http://repo.example/x; rpm_source_resolve; echo SRC=\$RPM_SOURCE"
grep -q "SRC=repo-url" <<<"$OUT" && pass "resolve: --repo-url alone means repo-url (compatibility)" || fail "resolve: repo-url compat" "$OUT"
run_hs r2 "rpm_source_resolve; echo SRC=\$RPM_SOURCE"
grep -q "SRC=github" <<<"$OUT" && pass "resolve: default is github" || fail "resolve: default" "$OUT"
run_hs r3 "RPM_SOURCE=github REPO_URL=http://repo.example/x; rpm_source_resolve"
expect_fail "resolve: --repo-url with --rpm-source github refused" "cannot be combined"
run_hs r4 "RPM_SOURCE=repo-url REPO_URL='http://x/a b'; rpm_source_resolve"
expect_fail "resolve: malformed --repo-url refused" "must be http"
run_hs r5 "RPM_SOURCE=magic; rpm_source_resolve"
expect_fail "resolve: unknown source refused" "must be one of"
run_hs r6 "RPM_SOURCE=build BUILD_IMAGE=quay.io/x:latest; rpm_source_resolve"
expect_fail "resolve: build image not pinned by digest refused" "pinned by digest"
run_hs r7 "RPM_SOURCE=repo-url REPO_URL=file:///opt/repo; rpm_source_resolve; echo SRC=\$RPM_SOURCE"
expect_ok "resolve: file:/// repository accepted"

# 18. consistency guard
run_hs c1 "deploy_set RPM_SET_SHA256 aaaa; deploy_load; RPM_SET_SHA256=bbbb; rpm_guard_consistency"
expect_fail "guard: a deployed host refuses a different RPM set" "does not do upgrades implicitly"
run_hs c2 "REMOTE_COMPUTE=1 CONTROLLER_RPM_SET=aaaa RPM_SET_SHA256=bbbb; deploy_load; rpm_guard_consistency"
expect_fail "guard: a compute node refuses a set different from the controller's" "not the controller's"
run_hs c3 "REMOTE_COMPUTE=1 CONTROLLER_RPM_SET=aaaa RPM_SET_SHA256=aaaa; deploy_load; rpm_guard_consistency"
expect_ok "guard: same set as the controller is accepted"
run_hs c4 "deploy_set RPM_SOURCE build; deploy_load; rpm_source_resolve; echo SRC=\$RPM_SOURCE"
grep -q "SRC=build" <<<"$OUT" && pass "resolve: a re-run keeps the recorded source" || fail "resolve: recorded source" "$OUT"
[ "$(stat -c %a "$T/state-c4/etc/deployment.env")" = 600 ] && pass "deployment.env is mode 0600" || fail "deployment.env mode"

# 19. role guard
rg() { run_hs "$1" "deploy_set ROLE '$2'; deploy_load; SUBCOMMAND=$3 LOCAL_COMPUTE=$4; role_guard"; }
rg rg1 controller controller 0;   expect_ok   "role: controller re-run on a controller"
rg rg2 controller all-in-one 0;   expect_ok   "role: controller -> all-in-one allowed"
rg rg3 controller compute-add 1;  expect_ok   "role: compute-add --local on a controller"
rg rg4 all-in-one controller 0;   expect_fail "role: all-in-one -> controller refused" "already all-in-one"
rg rg5 controller compute-add 0;  expect_fail "role: remote compute-add on a controller refused" "separate host"
rg rg6 compute all-in-one 0;      expect_fail "role: compute -> all-in-one refused" "compute node"
run_hs rg7 "SUBCOMMAND=compute-add LOCAL_COMPUTE=1; deploy_load; role_guard"
expect_fail "role: compute-add --local without a controller refused" "runs on a hagistack controller"
rg rg8 compute compute-add 0;     expect_ok   "role: compute-add re-run on a compute node"

# 20. a bundle's own repodata is never trusted: garbage metadata is replaced
rm -rf "$T/bb"; cp -a "$T/set" "$T/bb"; echo garbage > "$T/bb/repo/repodata/repomd.xml"
mk_asset "$T/bb" "$T/bundle-badmeta.tar"
run_hs b4 "RPM_SOURCE=bundle RPM_BUNDLE=$T/bundle-badmeta.tar RPM_SET_EXPECTED=$SET_SHA; rpm_prepare_bundle"
expect_ok "bundle: shipped repodata is discarded and regenerated locally"

# 21. a deployed host re-uses its recorded set without consulting the source
run_hs g1 "deploy_set RPM_SOURCE github RPM_SET_DIR $T/state-g1/var/rpms/github-v-test-${SET_SHA:0:16} RPM_SET_SHA256 $SET_SHA; deploy_load; RPM_SOURCE=github RPM_LOCK_FILE=$T/lock.unpub; phase_rpm_source; echo REPO=\$REPO_URL"
expect_ok "re-run: the recorded set is re-verified and used (lock not even needed)"
grep -q "REPO=file://$T/state-g1/var/rpms/github-v-test-" <<<"$OUT" && pass "re-run: repository points at the recorded set" || fail "re-run: repository path" "$OUT"

# 22. a bundle-deployed host re-runs without the bundle file (found on GCE)
run_hs b1 "deploy_set RPM_SOURCE bundle RPM_SET_DIR $T/state-b1/var/rpms/bundle-${SET_SHA:0:16} RPM_SET_SHA256 $SET_SHA; deploy_load; rpm_source_resolve; phase_rpm_source"
expect_ok "re-run: bundle-deployed host needs no --rpm-bundle when its set still verifies"
run_hs b5 "deploy_set RPM_SOURCE bundle RPM_SET_DIR $T/nonexistent RPM_SET_SHA256 $SET_SHA; deploy_load; RPM_SET_EXPECTED=$SET_SHA; rpm_source_resolve; phase_rpm_source"
expect_fail "re-run: a bundle host whose set is gone asks for --rpm-bundle" "no\s*$|Pass --rpm-bundle"

echo
echo "result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
