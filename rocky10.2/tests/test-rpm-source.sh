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
run_hs c2 "REMOTE_COMPUTE=1 CONTROLLER_RPM_SET=$SET_SHA RPM_SET_SHA256=5555555555555555555555555555555555555555555555555555555555555555; deploy_load; rpm_guard_consistency"
expect_fail "guard: a compute node refuses a set different from the controller's" "not the controller's"
run_hs c3 "REMOTE_COMPUTE=1 CONTROLLER_RPM_SET=$SET_SHA RPM_SET_SHA256=$SET_SHA; deploy_load; rpm_guard_consistency"
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

# ---------------------------------------------------------------- B-3: controller RPM set identity
run_hs i1 "REMOTE_COMPUTE=1 CONTROLLER_RPM_SET=''; deploy_load; controller_rpm_set_check"
expect_fail "identity: a new compute node without the controller's RPM set identity stops" "has no RPM_SET_SHA256"
run_hs i2 "REMOTE_COMPUTE=1 CONTROLLER_RPM_SET=not-a-digest; deploy_load; controller_rpm_set_check"
expect_fail "identity: a malformed controller identity stops (value not shown)" "neither a SHA-256 nor 'repo-url'"
grep -q "not-a-digest" <<<"$OUT" && fail "identity: malformed value must not be echoed" "$OUT" || pass "identity: malformed value is not echoed"
run_hs i3 "deploy_set ROLE compute RPM_SET_SHA256 $SET_SHA; deploy_load; REMOTE_COMPUTE=1 CONTROLLER_RPM_SET='' RPM_SET_SHA256=$SET_SHA; rpm_guard_consistency"
expect_ok "identity: re-run of a recorded compute node with an old secrets file keeps its recorded set"
run_hs i4 "deploy_set ROLE compute RPM_SET_SHA256 $SET_SHA; deploy_load; REMOTE_COMPUTE=1 CONTROLLER_RPM_SET='' RPM_SET_SHA256=4444444444444444444444444444444444444444444444444444444444444444; rpm_guard_consistency"
expect_fail "identity: that re-run still refuses a different set" "does not do upgrades implicitly"
run_hs i5 "deploy_set ROLE controller RPM_SET_SHA256 $SET_SHA; deploy_load; REMOTE_COMPUTE=1 CONTROLLER_RPM_SET=''; controller_rpm_set_check"
expect_fail "identity: the exception is limited to recorded compute nodes" "has no RPM_SET_SHA256"
run_hs i6 "REMOTE_COMPUTE=1 CONTROLLER_RPM_SET=repo-url RPM_SET_SHA256=repo-url; deploy_load; rpm_guard_consistency"
expect_ok "identity: --repo-url on both sides is accepted"
grep -q "cannot verify they install the same RPMs" <<<"$OUT" && pass "identity: --repo-url limitation is reported" || fail "identity: repo-url warning" "$OUT"
run_hs i7 "REMOTE_COMPUTE=1 CONTROLLER_RPM_SET=repo-url RPM_SET_SHA256=$SET_SHA; deploy_load; rpm_guard_consistency"
expect_fail "identity: controller --repo-url vs node verified set stops" "different kinds of RPM source"
run_hs i8 "REMOTE_COMPUTE=1 CONTROLLER_RPM_SET=$SET_SHA RPM_SET_SHA256=repo-url; deploy_load; rpm_guard_consistency"
expect_fail "identity: controller verified set vs node --repo-url stops" "different kinds of RPM source"
# phase_secrets: the stop happens before anything is downloaded or installed
mkdir -p "$T/state-i9/etc"; printf 'RABBIT_PASS=x\nNOVA_SERVICE_PASS=x\nPLACEMENT_SERVICE_PASS=x\nNEUTRON_SERVICE_PASS=x\nMETADATA_PROXY_SECRET=x\n' > "$T/state-i9/etc/secrets.env"
run_hs i9 "REMOTE_COMPUTE=1 SUBCOMMAND=compute-add RPM_SOURCE=github; phase_secrets"
expect_fail "identity: phase_secrets stops a new node whose secrets lack the identity" "has no RPM_SET_SHA256"
no_build_no_dnf "identity: missing identity"
printf 'RPM_SET_SHA256=%s\n' "$SET_SHA" >> "$T/state-i9/etc/secrets.env"
run_hs i9 "REMOTE_COMPUTE=1 SUBCOMMAND=compute-add RPM_SOURCE=bundle; phase_secrets; echo EXP=\$RPM_SET_EXPECTED"
grep -q "EXP=$SET_SHA" <<<"$OUT" && pass "identity: a valid identity from secrets becomes the bundle's expected set" || fail "identity: bundle expected" "$OUT"

# ---------------------------------------------------------------- B-2: remote compute database settings
NOVA_STUBS='NOVA_CONF="$HAGISTACK_STATE/nova.conf"; CONTROLLER_IP=192.0.2.10; NOVA_SERVICE_PASS=x
_write_nova_common() { :; }; write_authtoken() { :; }; chown() { :; }; chmod() { :; }
phase_nova_compute() { echo SERVICE-TOUCHED; }; service_apply() { echo SERVICE-TOUCHED; }'
seed_nova() {  # seed_nova <state> <content>
    mkdir -p "$T/state-$1/var"; printf '%s\n' "$2" > "$T/state-$1/var/nova.conf"
}
no_service() { if grep -q SERVICE-TOUCHED <<<"$OUT"; then fail "$1: nova-compute must not be started" "$OUT"; else pass "$1: nova-compute not started or restarted"; fi; }

seed_nova d1 $'[DEFAULT]\nhost = n\n[database]\nconnection = mysql+pymysql://nova:x@192.0.2.10/nova\nslave_connection = mysql+pymysql://nova:x@192.0.2.10/nova\n[api_database]\nconnection = mysql+pymysql://nova:x@192.0.2.10/nova_api'
run_hs d1 "$NOVA_STUBS
nova_effective_db_keys() { echo ''; }
phase_compute_nova; echo; grep -nE '^[^#].*connection' \"\$NOVA_CONF\" || echo NO-ACTIVE-LINES"
expect_ok "db: every database/api_database connection (incl. slave_connection) is commented out, then nova-compute starts"
grep -q NO-ACTIVE-LINES <<<"$OUT" && pass "db: no active connection line remains in nova.conf" || fail "db: active lines remain" "$OUT"
grep -q SERVICE-TOUCHED <<<"$OUT" && pass "db: the normal compute path still starts nova-compute" || fail "db: normal path" "$OUT"

seed_nova d2 $'[database]\nconnection = mysql+pymysql://nova:x@192.0.2.10/nova'
run_hs d2 "$NOVA_STUBS
nova_effective_db_keys() { echo 'database.connection'; }
phase_compute_nova"
expect_fail "db: a connection still in effect elsewhere (oslo.config) stops the run" "would still open a database: database.connection"
no_service "db: effective connection left"

seed_nova d3 $'[database]\nconnection = mysql+pymysql://nova:x@192.0.2.10/nova'
run_hs d3 "$NOVA_STUBS
nova_effective_db_keys() { echo 'check failed: boom'; return 3; }
phase_compute_nova"
expect_fail "db: when the effective check cannot run, the run stops (fail closed)" "could not determine nova-compute's effective database settings"
no_service "db: check unavailable"

seed_nova d4 $'[database]\nconnection = mysql+pymysql://nova:x@192.0.2.10/nova'
run_hs d4 "$NOVA_STUBS
nova_effective_db_keys() { echo ''; }
compute_assert_no_db"
expect_fail "db: an active line in nova.conf itself stops the run" "nova.conf still has an active database setting: \[database\] connection"

seed_nova d5 $'[database]\n# connection = mysql+pymysql://nova:x@192.0.2.10/nova\n;connection = old\n[DEFAULT]\ntransport_url = rabbit://x\n# commented out by hagistack: connection = whatever'
run_hs d5 "$NOVA_STUBS
nova_effective_db_keys() { echo ''; }
compute_assert_no_db"
expect_ok "db: commented-out lines and comment text are not mistaken for settings"

run_hs d6 "getent() { echo 'nova:x:1:1::/var/lib/nova:/sbin/nologin'; }
runuser() { printf 'Warning: connection is deprecated\\nHS-DB-KEYS:\\n'; }
echo \"KEYS=[\$(nova_effective_db_keys)]\""
grep -q 'KEYS=\[\]' <<<"$OUT" && pass "db: stray warning output from the check is never read as a key" || fail "db: warning parsing" "$OUT"
run_hs d7 "getent() { echo 'nova:x:1:1::/var/lib/nova:/sbin/nologin'; }
runuser() { printf 'HS-DB-KEYS:database.connection api_database.connection\\n'; }
echo \"KEYS=[\$(nova_effective_db_keys)]\""
grep -q 'KEYS=\[database.connection api_database.connection\]' <<<"$OUT" && pass "db: keys reported by the check are passed through" || fail "db: key pass-through" "$OUT"
run_hs d8 "getent() { echo 'nova:x:1:1::/var/lib/nova:/sbin/nologin'; }
runuser() { echo 'Traceback ...'; return 1; }
nova_effective_db_keys || echo RC=\$?"
grep -q 'RC=3' <<<"$OUT" && pass "db: a failing check returns 'could not check' (3)" || fail "db: check failure code" "$OUT"
run_hs d9 "getent() { :; }
nova_effective_db_keys || echo RC=\$?"
grep -q 'RC=3' <<<"$OUT" && pass "db: no nova user means 'could not check' (3)" || fail "db: no nova user" "$OUT"

# ---------------------------------------------------------------- N-1: build image digest in the cache identity
DA="quay.io/rockylinux/rockylinux:10.2@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
DB="quay.io/rockylinux/rockylinux:10.2@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
DA2="registry.example/other-name:tag@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
run_hs n1 "BUILD_IMAGE=$DA; a=\$(rpm_build_input_id); BUILD_IMAGE=$DB; b=\$(rpm_build_input_id); BUILD_IMAGE=$DA; c=\$(rpm_build_input_id); BUILD_IMAGE=$DA2; d=\$(rpm_build_input_id); BUILD_IMAGE=''; e=\$(rpm_build_input_id); echo \"A=\$a B=\$b C=\$c D=\$d E=\$e\""
A="$(grep -oE 'A=[0-9a-f]+' <<<"$OUT" | cut -d= -f2)"; B="$(grep -oE 'B=[0-9a-f]+' <<<"$OUT" | cut -d= -f2)"
C="$(grep -oE 'C=[0-9a-f]+' <<<"$OUT" | cut -d= -f2)"; D="$(grep -oE 'D=[0-9a-f]+' <<<"$OUT" | cut -d= -f2)"
E="$(grep -oE 'E=[0-9a-f]+' <<<"$OUT" | cut -d= -f2)"
[ -n "$A" ] && [ "$A" != "$B" ] && pass "image: a different image digest gives a different build identity" || fail "image: digest change" "$OUT"
[ -n "$A" ] && [ "$A" = "$C" ] && pass "image: the same digest gives the same build identity" || fail "image: same digest" "$OUT"
[ "$A" = "$D" ] && pass "image: the identity follows the content digest, not the name or tag" || fail "image: name independence" "$OUT"
[ -n "$E" ] && [ "$E" != "$A" ] && pass "image: the default pinned image has its own identity" || fail "image: default" "$OUT"
run_hs n2 "BUILD_IMAGE=quay.io/rockylinux/rockylinux:10.2; rpm_build_input_id"
expect_fail "image: a tag without a digest is refused when computing the identity" "pinned by digest"
# cache: a verified result for digest A is reused for A and NOT for B
run_hs n3 "BUILD_IMAGE=$DA; id=\$(rpm_build_input_id); mkdir -p \"\$RPM_BUILD_ROOT/\${id:0:16}\"; cp -a $T/set \"\$RPM_BUILD_ROOT/\${id:0:16}/out\"; rpm_mark_verified \"\$RPM_BUILD_ROOT/\${id:0:16}/out\" $SET_SHA build; rpm_prepare_build; echo SET=\$RPM_SET_SHA256"
expect_ok "image: same digest and inputs reuse the verified build"
grep -q "not rebuilt" <<<"$OUT" && ! grep -q PODMAN-CALLED <<<"$OUT" && pass "image: reuse did not start a build" || fail "image: reuse" "$OUT"
run_hs n3 "BUILD_IMAGE=$DB; rpm_prepare_build"
expect_fail "image: another digest does not reuse that result (a build is attempted)" "PODMAN-CALLED|could not pull"
run_hs n3 "BUILD_IMAGE=$DA; rpm_prepare_build"
grep -q "not rebuilt" <<<"$OUT" && pass "image: the result for the first digest is kept, not deleted, and still reused" || fail "image: earlier result kept" "$OUT"

# ---------------------------------------------------------------- --repo-url behaviour unchanged
run_hs u1 "RPM_SOURCE=repo-url REPO_URL=http://repo.example/hagistack/; deploy_load; rpm_source_resolve; phase_rpm_source; echo REPO=\$REPO_URL SET=\$RPM_SET_SHA256"
grep -q "REPO=http://repo.example/hagistack/ SET=repo-url" <<<"$OUT" && pass "repo-url: the given repository is used as-is and nothing is downloaded" || fail "repo-url: phase" "$OUT"
no_build_no_dnf "repo-url"

echo
echo "result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
