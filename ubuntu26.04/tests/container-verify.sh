#!/usr/bin/env bash
# Step 1 verification, run INSIDE an Ubuntu 26.04 container.
# Records PASS / FAIL / UNVERIFIED per item. Never fakes a PASS.
set -uo pipefail
H=/src/hagistack
R=/out/results.tsv
: > "$R"
P=0; F=0; U=0

rec() { # rec <id> <status> <detail>
    printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$R"
    case "$2" in
        PASS) P=$((P+1)); printf '  \033[32mPASS\033[0m %-26s %s\n' "$1" "$3" ;;
        FAIL) F=$((F+1)); printf '  \033[31mFAIL\033[0m %-26s %s\n' "$1" "$3" ;;
        *)    U=$((U+1)); printf '  \033[33mUNVER\033[0m %-26s %s\n' "$1" "$3" ;;
    esac
}
# expect_exit <id> <want_rc> <grep-regex|-> <cmd...>
expect_exit() {
    local id="$1" want="$2" pat="$3"; shift 3
    local out rc
    out="$("$@" 2>&1)"; rc=$?
    if [ "$rc" != "$want" ]; then rec "$id" FAIL "exit $rc, wanted $want"; return; fi
    if [ "$pat" != "-" ] && ! grep -qE "$pat" <<<"$out"; then
        rec "$id" FAIL "exit ok but output lacked /$pat/"; return
    fi
    rec "$id" PASS "exit $rc"
}

echo "== environment =="
. /etc/os-release; echo "  $PRETTY_NAME  $(dpkg --print-architecture)"
echo "  systemd dir /run/systemd/system: $([ -d /run/systemd/system ] && echo present || echo ABSENT)"
echo "  PID1: $(cat /proc/1/comm)"
echo

echo "== A. static checks =="
expect_exit A1-bash-n 0 - bash -n "$H"
if command -v shellcheck >/dev/null 2>&1; then
    sc="$(shellcheck -S warning "$H" 2>&1)"; rc=$?
    if [ $rc -eq 0 ] && [ -z "$sc" ]; then rec A2-shellcheck PASS "no warnings (-S warning)"
    else rec A2-shellcheck FAIL "$(head -c 300 <<<"$sc")"; fi
    echo "$sc" > /out/shellcheck.txt
else
    rec A2-shellcheck UNVERIFIED "shellcheck not installed"
fi

echo
echo "== B. CLI surface =="
expect_exit B1-help            0 'usage:'                       "$H" --help
expect_exit B2-no-args-help    0 'usage:'                       "$H"
expect_exit B3-version         0 '^hagistack [0-9]+\.[0-9]+\.[0-9]+-step[0-9]+'     "$H" --version
expect_exit B4-bad-command     2 'unknown command'              "$H" frobnicate
expect_exit B5-bad-option      2 'unknown option'               "$H" all-in-one --nope
expect_exit B6-compute-add-NI  3 'not implemented yet'          "$H" compute-add
expect_exit B7-status          0 'phases pending'               "$H" status
# NOTE: never pipe straight into `grep -q` under `set -o pipefail` — grep exits
# on first match, the producer gets SIGPIPE and the pipeline returns 141.
help_out="$("$H" --help 2>&1)"
tr '\n' ' ' <<<"$help_out" | grep -qiE 'does +NOT +give you a working' \
    && rec B8-help-honest PASS "help states it is not a working OpenStack" \
    || rec B8-help-honest FAIL "help does not disclose incompleteness"
status_out="$("$H" status 2>&1)"
if grep -q 'keystone' <<<"$status_out" && grep -q 'nova' <<<"$status_out"; then
    rec B9-status-pending PASS "pending phases listed"
else rec B9-status-pending FAIL "pending phases not listed"; fi

echo
echo "== C. input validation (preflight, --check) =="
BASE=(--provider-cidr 172.24.4.0/24 --provider-gateway 172.24.4.1
      --floating-start 172.24.4.100 --floating-end 172.24.4.200 --mgmt-ip 10.0.0.5)
# missing everything
expect_exit C1-missing-required 1 'missing required settings' "$H" all-in-one --check --env-file /dev/null
# bad NIC name
expect_exit C2-bad-nic-chars 1 'not a valid interface name' \
    "$H" all-in-one --check --env-file /dev/null --ext-nic 'bad;name' "${BASE[@]}"
# nonexistent NIC
expect_exit C3-nic-absent 1 'does not exist on this host' \
    "$H" all-in-one --check --env-file /dev/null --ext-nic zzz99 "${BASE[@]}"
NIC="$(ls /sys/class/net | grep -v '^lo$' | head -1)"; NIC="${NIC:-lo}"
echo "  (using real NIC '$NIC' for the positive cases)"
# bad CIDR
expect_exit C4-bad-cidr 1 'not a valid IPv4 CIDR' \
    "$H" all-in-one --check --env-file /dev/null --ext-nic "$NIC" \
    --provider-cidr 172.24.4.0/33 --provider-gateway 172.24.4.1 \
    --floating-start 172.24.4.100 --floating-end 172.24.4.200 --mgmt-ip 10.0.0.5
# non-CIDR string
expect_exit C5-cidr-no-prefix 1 'not a valid IPv4 CIDR' \
    "$H" all-in-one --check --env-file /dev/null --ext-nic "$NIC" \
    --provider-cidr 172.24.4.0 --provider-gateway 172.24.4.1 \
    --floating-start 172.24.4.100 --floating-end 172.24.4.200 --mgmt-ip 10.0.0.5
# gateway outside cidr
expect_exit C6-gw-outside 1 'outside PROVIDER_CIDR' \
    "$H" all-in-one --check --env-file /dev/null --ext-nic "$NIC" \
    --provider-cidr 172.24.4.0/24 --provider-gateway 192.168.99.1 \
    --floating-start 172.24.4.100 --floating-end 172.24.4.200 --mgmt-ip 10.0.0.5
# pool reversed
expect_exit C7-pool-reversed 1 'is above FLOATING_END' \
    "$H" all-in-one --check --env-file /dev/null --ext-nic "$NIC" \
    --provider-cidr 172.24.4.0/24 --provider-gateway 172.24.4.1 \
    --floating-start 172.24.4.200 --floating-end 172.24.4.100 --mgmt-ip 10.0.0.5
# gateway inside pool
expect_exit C8-gw-in-pool 1 'falls inside the floating IP pool' \
    "$H" all-in-one --check --env-file /dev/null --ext-nic "$NIC" \
    --provider-cidr 172.24.4.0/24 --provider-gateway 172.24.4.150 \
    --floating-start 172.24.4.100 --floating-end 172.24.4.200 --mgmt-ip 10.0.0.5
# bad octet
expect_exit C9-bad-ip-octet 1 'not a valid IPv4 address' \
    "$H" all-in-one --check --env-file /dev/null --ext-nic "$NIC" \
    --provider-cidr 172.24.4.0/24 --provider-gateway 172.24.4.999 \
    --floating-start 172.24.4.100 --floating-end 172.24.4.200 --mgmt-ip 10.0.0.5
# A line that is not an assignment must be refused outright.
printf 'EXT_NIC=%s\nrm -rf /tmp/pwned\n' "$NIC" > /tmp/bad.env
expect_exit C10-envfile-malformed 1 'not a KEY=VALUE assignment' \
    "$H" all-in-one --check --env-file /tmp/bad.env
# The real hazard: a well-formed KEY=VALUE whose VALUE is a command
# substitution. Under the old `source` implementation this executed. The marker
# file is positive proof either way — it does not exist unless code ran.
rm -f /tmp/CODEEXEC_MARKER
printf 'EXT_NIC=%s\nTENANT_CIDR=$(touch /tmp/CODEEXEC_MARKER)\n' "$NIC" > /tmp/exec.env
"$H" all-in-one --check --env-file /tmp/exec.env "${BASE[@]}" >/dev/null 2>&1 || true
if [ -e /tmp/CODEEXEC_MARKER ]; then
    rec C11-envfile-no-exec FAIL "config file value was EXECUTED (marker created)"
else
    rec C11-envfile-no-exec PASS "command substitution in a value did not execute"
fi
rm -f /tmp/CODEEXEC_MARKER
# happy path preflight
expect_exit C12-preflight-ok 0 'preflight passed' \
    "$H" all-in-one --check --env-file /dev/null --ext-nic "$NIC" "${BASE[@]}"
# --check must change nothing
rm -rf /etc/hagistack /var/lib/hagistack
"$H" all-in-one --check --env-file /dev/null --ext-nic "$NIC" "${BASE[@]}" >/dev/null 2>&1
if [ ! -e /etc/hagistack ] && [ ! -e /var/lib/hagistack ]; then
    rec C13-check-no-writes PASS "no /etc/hagistack, no /var/lib/hagistack"
else rec C13-check-no-writes FAIL "--check created state"; fi
# wrong-OS gate: fake os-release in a subshell copy
sed 's/^VERSION_ID=.*/VERSION_ID="24.04"/' /etc/os-release > /tmp/os-release.fake
cp /etc/os-release /tmp/os-release.real
cp /tmp/os-release.fake /etc/os-release
expect_exit C14-wrong-ubuntu-ver 1 'targets 26\.04' \
    "$H" all-in-one --check --env-file /dev/null --ext-nic "$NIC" "${BASE[@]}"
sed 's/^ID=ubuntu/ID=rocky/' /tmp/os-release.real > /etc/os-release
expect_exit C15-wrong-os 1 'unsupported OS' \
    "$H" all-in-one --check --env-file /dev/null --ext-nic "$NIC" "${BASE[@]}"
cp /tmp/os-release.real /etc/os-release
rec C16-osrelease-restored PASS "os-release restored ($(. /etc/os-release; echo "$ID $VERSION_ID"))"

echo
echo "== D. ini_set idempotence =="
cat > /tmp/initest.sh <<'IEOF'
set -euo pipefail
SUDO=""
die(){ echo "$*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }
IEOF
sed -n '/^ini_set() {/,/^}$/p' "$H" >> /tmp/initest.sh
cat >> /tmp/initest.sh <<'IEOF'
f=/tmp/t.conf
rm -f "$f"
ini_set "$f" mysqld bind-address 127.0.0.1 && echo "r1=changed" || echo "r1=unchanged"
cp "$f" /tmp/t.after1
ini_set "$f" mysqld bind-address 127.0.0.1 && echo "r2=changed" || echo "r2=unchanged"
cp "$f" /tmp/t.after2
ini_set "$f" mysqld max_connections 200 >/dev/null || true
ini_set "$f" DEFAULT other value >/dev/null || true
ini_set "$f" mysqld bind-address 10.0.0.1 >/dev/null || true
cp "$f" /tmp/t.after3
ini_set "$f" mysqld max_connections 200 >/dev/null && echo "r4=changed" || echo "r4=unchanged"
ini_set "$f" DEFAULT other value >/dev/null && echo "r5=changed" || echo "r5=unchanged"
ini_set "$f" mysqld bind-address 10.0.0.1 >/dev/null && echo "r6=changed" || echo "r6=unchanged"
cp "$f" /tmp/t.after4
IEOF
inio="$(bash /tmp/initest.sh 2>&1)"
echo "$inio" | sed 's/^/    /'
echo "$inio" > /out/ini.txt
cp /tmp/t.after4 /out/ini-final.conf
if grep -q 'r1=changed' <<<"$inio" && grep -q 'r2=unchanged' <<<"$inio"; then
    rec D1-first-write PASS "first write changes, second does not"
else rec D1-first-write FAIL "$inio"; fi
if cmp -s /tmp/t.after1 /tmp/t.after2; then rec D2-byte-identical PASS "file unchanged on 2nd apply"
else rec D2-byte-identical FAIL "$(diff /tmp/t.after1 /tmp/t.after2 | head -5)"; fi
if grep -q 'r4=unchanged' <<<"$inio" && grep -q 'r5=unchanged' <<<"$inio" && grep -q 'r6=unchanged' <<<"$inio"; then
    rec D3-multi-idempotent PASS "3 keys across 2 sections all stable"
else rec D3-multi-idempotent FAIL "$inio"; fi
if cmp -s /tmp/t.after3 /tmp/t.after4; then rec D4-no-dup-append PASS "no duplicate append"
else rec D4-no-dup-append FAIL "file grew on re-apply"; fi
n_ba="$(grep -c '^bind-address' /tmp/t.after4 || true)"
n_sec="$(grep -c '^\[mysqld\]' /tmp/t.after4 || true)"
if [ "$n_ba" = "1" ] && [ "$n_sec" = "1" ]; then rec D5-single-occurrence PASS "1 bind-address, 1 [mysqld]"
else rec D5-single-occurrence FAIL "bind-address x$n_ba, [mysqld] x$n_sec"; fi
if grep -q '^bind-address = 10.0.0.1$' /tmp/t.after4; then rec D6-value-updated PASS "value replaced in place"
else rec D6-value-updated FAIL "value not updated"; fi

echo
echo "== E. secrets =="
rm -rf /etc/hagistack /var/lib/hagistack
sec_run() { "$H" all-in-one --env-file /dev/null --ext-nic "$NIC" "${BASE[@]}" 2>&1; }
# stop before apt by making apt-get fail fast? instead call the phases directly:
cat > /tmp/sectest.sh <<SEOF
set -euo pipefail
HAGISTACK_ETC=/etc/hagistack
SECRETS_FILE="\$HAGISTACK_ETC/secrets.env"
SUDO=""
SEOF
sed -n '/^C_RESET=/,/^fi$/p'                 "$H" | head -20 >> /tmp/sectest.sh || true
cat >> /tmp/sectest.sh <<'SEOF'
C_RESET=''; C_RED=''; C_YEL=''; C_GRN=''; C_BLU=''; C_DIM=''
log_step(){ echo "==> $*"; }; log_info(){ echo "    $*"; }
log_ok(){ echo "    ok   $*"; }; log_warn(){ echo "warn: $*" >&2; }
log_error(){ echo "error: $*" >&2; }; die(){ log_error "$*"; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }
SEOF
sed -n '/^gen_secret() {/,/^}$/p'  "$H" >> /tmp/sectest.sh
sed -n '/^SECRET_KEYS=/,/"$/p' "$H" >> /tmp/sectest.sh
sed -n '/^OBSOLETE_SECRET_KEYS=/p'                   "$H" >> /tmp/sectest.sh
sed -n '/^phase_secrets() {/,/^}$/p' "$H" >> /tmp/sectest.sh
echo 'phase_secrets' >> /tmp/sectest.sh
o1="$(bash /tmp/sectest.sh 2>&1)"; echo "$o1" | sed 's/^/    [run1] /'
perm1="$(stat -c '%a' /etc/hagistack/secrets.env 2>/dev/null || echo none)"
sum1="$(sha256sum /etc/hagistack/secrets.env 2>/dev/null | cut -d' ' -f1)"
dperm="$(stat -c '%a' /etc/hagistack 2>/dev/null || echo none)"
o2="$(bash /tmp/sectest.sh 2>&1)"; echo "$o2" | sed 's/^/    [run2] /'
perm2="$(stat -c '%a' /etc/hagistack/secrets.env 2>/dev/null || echo none)"
sum2="$(sha256sum /etc/hagistack/secrets.env 2>/dev/null | cut -d' ' -f1)"
[ "$perm1" = "600" ] && rec E1-secret-mode PASS "secrets.env mode $perm1" \
                     || rec E1-secret-mode FAIL "mode $perm1, wanted 600"
[ "$dperm" = "750" ] && rec E2-dir-mode PASS "/etc/hagistack mode $dperm" \
                     || rec E2-dir-mode FAIL "dir mode $dperm, wanted 750"
if [ -n "$sum1" ] && [ "$sum1" = "$sum2" ]; then rec E3-values-stable PASS "sha256 identical across runs"
else rec E3-values-stable FAIL "secrets changed on 2nd run"; fi
[ "$perm2" = "600" ] && rec E4-mode-after-rerun PASS "still 600 after re-run" \
                     || rec E4-mode-after-rerun FAIL "mode $perm2"
nkeys="$(grep -cE '^[A-Z_]+=' /etc/hagistack/secrets.env || echo 0)"
want="$(sed -n '/^SECRET_KEYS=/,/"$/p' "$H" | tr -d '\n' \
        | sed 's/.*SECRET_KEYS="//; s/".*//' | wc -w)"
[ "$nkeys" = "$want" ] && rec E5-key-count PASS "$nkeys keys, matching SECRET_KEYS" \
                       || rec E5-key-count FAIL "$nkeys keys, SECRET_KEYS declares $want"
grep -q '^NOVA_API_DB_PASS=' /etc/hagistack/secrets.env \
    && rec E5b-no-nova-api-key FAIL "obsolete NOVA_API_DB_PASS was generated" \
    || rec E5b-no-nova-api-key PASS "obsolete NOVA_API_DB_PASS not generated"
# entropy: no two secrets equal, none short
dups="$(cut -d= -f2 /etc/hagistack/secrets.env | grep -v '^$' | sort | uniq -d | wc -l)"
shortv="$(awk -F= 'length($2)<24 && $0 ~ /^[A-Z_]+=/' /etc/hagistack/secrets.env | wc -l)"
[ "$dups" = "0" ] && [ "$shortv" = "0" ] && rec E6-secret-quality PASS "no duplicates, all >=24 chars" \
    || rec E6-secret-quality FAIL "dups=$dups short=$shortv"
grep -q 'reused unchanged' <<<"$o2" && rec E7-reuse-reported PASS "2nd run reports reuse" \
    || rec E7-reuse-reported FAIL "2nd run did not report reuse"
cp /etc/hagistack/secrets.env /out/secrets-KEYS-ONLY.txt
sed -i 's/=.*/=<redacted>/' /out/secrets-KEYS-ONLY.txt

echo
echo "== F. source hygiene (new files only) =="
cd /src
# Judge CODE, not comments: strip full-line comments and trailing comments.
code() { sed -E 's/[[:space:]]#[^"'"'"']*$//; /^[[:space:]]*#/d' "$1"; }
code hagistack > /tmp/code.sh
code hagistack.env.example > /tmp/code.env
scan() { grep -nEi "$1" /tmp/code.sh; }

bad="$(grep -nE '(PASS|PASSWORD|SECRET|TOKEN)[A-Z_]*=[A-Za-z0-9]' /tmp/code.sh /tmp/code.env \
        | grep -vE '\$\(|\$\{|passvar|SECRET_KEYS|=\$' || true)"
[ -z "$bad" ] && rec F1-no-fixed-password PASS "no literal credential assignment in code" \
              || rec F1-no-fixed-password FAIL "$bad"
# A destructive drop is SQL handed to a DB client. Prose such as the shell's own
# "it does not drop databases" banner must not trip this, so require the client
# invocation on the same line. Positive control below proves it still bites.
DROPPAT='(mysql|mariadb|mysqladmin)[^|]*(drop[[:space:]]+(database|schema|table))'
scan "$DROPPAT" >/dev/null \
    && rec F2-no-drop-db FAIL "destructive drop statement in code" \
    || rec F2-no-drop-db PASS "no drop statement passed to a DB client"
# Positive control: the same scan MUST flag the 2013 shell, otherwise F2 is vacuous.
if [ -f /src/legacy-sample.sh ]; then
    if sed -E 's/[[:space:]]#[^"'"'"']*$//; /^[[:space:]]*#/d' /src/legacy-sample.sh \
        | grep -nEi "$DROPPAT" >/dev/null; then
        rec F2b-scan-positive-control PASS "scan flags the legacy shell as expected"
    else
        rec F2b-scan-positive-control FAIL "scan failed to flag the known-bad legacy shell"
    fi
else
    rec F2b-scan-positive-control UNVERIFIED "legacy sample not staged"
fi
# And the honest banner text must still be present (we did not silence it).
grep -q 'does not drop databases' hagistack \
    && rec F2c-banner-intact PASS "re-run safety banner still states no DB drops" \
    || rec F2c-banner-intact FAIL "banner text lost"
scan 'rm -rf /var/log|rm -rf /etc|rm -rf \$\{?[A-Za-z_]+\}?/\*' >/dev/null \
    && rec F3-no-destructive-rm FAIL "destructive rm in code" \
    || rec F3-no-destructive-rm PASS "no destructive rm of system paths"
scan 'tee -a /etc/(sysctl|bash|libvirt)' >/dev/null \
    && rec F4-no-blind-append FAIL "tee -a into shared system file" \
    || rec F4-no-blind-append PASS "no tee -a into shared system files"
scan 'apparmor_parser -R|setenforce 0' >/dev/null \
    && rec F5-no-mac-disable FAIL "disables AppArmor/SELinux" \
    || rec F5-no-mac-disable PASS "does not disable AppArmor/SELinux"
scan 'auth_tcp *= *"?none|listen_tcp *= *1' >/dev/null \
    && rec F6-no-libvirt-open FAIL "opens libvirt TCP without auth" \
    || rec F6-no-libvirt-open PASS "no unauthenticated libvirt TCP"
scan 'bind[_-]?address *=? *.?0\.0\.0\.0' >/dev/null \
    && rec F7-no-wildcard-bind FAIL "binds a service to 0.0.0.0" \
    || rec F7-no-wildcard-bind PASS "no 0.0.0.0 bind"
scan -- '--force' >/dev/null && rec F8-no-force-bypass FAIL "--force bypass exists" \
                             || rec F8-no-force-bypass PASS "no --force safety bypass"
grep -qE '^set -[A-Za-z]*e[A-Za-z]*uo pipefail' hagistack \
    && rec F9-strict-mode PASS "strict mode: $(grep -m1 -oE '^set -[A-Za-z]+ pipefail' hagistack)" \
    || rec F9-strict-mode FAIL "missing strict mode"
grep -qE "trap '_on_err" hagistack && rec F10-err-trap PASS "ERR trap present" \
                                   || rec F10-err-trap FAIL "no ERR trap"
# Existence is not enough: `trap ... ERR` is NOT inherited by functions without
# `set -E`, so prove the trap actually fires from inside a function.
grep -qE '^set -E[a-z]*euo pipefail|^set -Eeuo' hagistack \
    && rec F10b-errtrace-enabled PASS "set -E present, so ERR fires inside functions" \
    || rec F10b-errtrace-enabled FAIL "no set -E: the ERR trap is dead inside functions"
cat > /tmp/traptest.sh <<'TEOF'
set -Eeuo pipefail
trap 'echo "TRAP_FIRED line=$LINENO"; exit 9' ERR
f() { false; echo "should not reach"; }
f
TEOF
tout="$(bash /tmp/traptest.sh 2>&1)"; trc=$?
if [ "$trc" = "9" ] && grep -q TRAP_FIRED <<<"$tout"; then
    rec F10c-trap-fires-in-fn PASS "ERR trap fires inside a function (exit 9)"
else rec F10c-trap-fires-in-fn FAIL "rc=$trc out=$tout"; fi
# And the real shell must abort, not silently continue, on an internal failure.
aout="$("$H" all-in-one --check --env-file /nonexistent-path-xyz 2>&1)"; arc=$?
if [ "$arc" != "0" ] && grep -qE 'env file not readable' <<<"$aout"; then
    rec F10d-fails-loudly PASS "bad --env-file rejected with a clear message"
else rec F10d-fails-loudly FAIL "rc=$arc out=$(head -c 200 <<<"$aout")"; fi
# Excluded engines must not be INVOKED. A documentation mention is fine.
eng_hit=""
for eng in openstack-ansible kolla-ansible kolla packstack devstack stack.sh; do
    if scan "(^|[^-a-z])$eng" >/dev/null 2>&1; then eng_hit="$eng_hit $eng"; fi
done
[ -z "$eng_hit" ] && rec F11-no-excluded-engines PASS "OSA/Kolla/Packstack/DevStack not invoked in code" \
                  || rec F11-no-excluded-engines FAIL "code references:$eng_hit"

echo
echo "== G. services under no-systemd =="
rm -rf /var/lib/hagistack
o="$("$H" all-in-one --env-file /dev/null --ext-nic "$NIC" "${BASE[@]}" 2>&1 || true)"
echo "$o" > /out/all-in-one-run1.log
echo "$o" > /out/all-in-one-nosystemd.log
if grep -q 'systemd is not running here' <<<"$o"; then
    rec G1-systemd-absent-detected PASS "shell detected no systemd and said so"
else rec G1-systemd-absent-detected FAIL "did not report missing systemd"; fi
if grep -qE 'SKIPPED|NOT VERIFIED' <<<"$o"; then
    rec G2-marks-unverified PASS "reports SKIPPED/NOT VERIFIED instead of claiming success"
else rec G2-marks-unverified FAIL "did not mark unverified"; fi
if grep -qE 'STEP [0-9]+ (COMPLETE|INCOMPLETE)' <<<"$o"; then
    rec G3-stage-banner PASS "prints a stage banner ($(grep -oE 'STEP [0-9]+ [A-Z]+' <<<"$o" | head -1))"
else rec G3-stage-banner FAIL "no stage banner"; fi
# With no systemd the base layer cannot come up, so the run must say INCOMPLETE
# and exit 4 rather than claiming success.
o_rc=0; "$H" all-in-one --env-file /dev/null --ext-nic "$NIC" "${BASE[@]}" >/dev/null 2>&1 || o_rc=$?
[ "$o_rc" = "4" ] && rec G3b-incomplete-exit PASS "exit 4 when the base layer is incomplete" \
                  || rec G3b-incomplete-exit FAIL "exit $o_rc, wanted 4"
grep -qE 'STEP [0-9]+ COMPLETE' <<<"$o" && rec G3c-no-false-complete FAIL "claimed COMPLETE with services down" \
                                  || rec G3c-no-false-complete PASS "did not claim COMPLETE"
rec G4-mariadb-start UNVERIFIED "not started here (no systemd); manual-start case covered in db-results.tsv; systemd case = GCE B0b"
rec G5-rabbitmq-start UNVERIFIED "not started here; would not start manually either (see db-results.tsv); GCE B0b"
rec G6-unit-ordering UNVERIFIED "systemd unit ordering; GCE acceptance item B0a"
rec G7-openstack-services UNVERIFIED "no OpenStack service implemented in step 1"
rec G8-kvm-guest-boot UNVERIFIED "no /dev/kvm and no nova; GCE acceptance item B4"
rec G9-physical-lan UNVERIFIED "no provider network in step 1; class C item"

echo
echo "== H. re-run safety of the whole command =="
o2h="$("$H" all-in-one --env-file /dev/null --ext-nic "$NIC" "${BASE[@]}" 2>&1 || true)"
echo "$o2h" > /out/all-in-one-run2.log
sum_after2="$(sha256sum /etc/hagistack/secrets.env | cut -d' ' -f1)"
[ "$sum_after2" = "$sum2" ] && rec H1-secrets-survive PASS "secrets unchanged after full re-run" \
                            || rec H1-secrets-survive FAIL "secrets rotated"
if grep -q 'already done (state marker)' <<<"$o2h"; then
    rec H2-phase-skip PASS "completed phase skipped on re-run"
else rec H2-phase-skip UNVERIFIED "base_packages did not complete in run1 (apt may have been skipped)"; fi
[ -f /var/lib/hagistack/state/base_packages.done ] \
    && rec H3-state-marker PASS "state marker written" \
    || rec H3-state-marker UNVERIFIED "base_packages phase did not finish here"

echo
printf 'PASS=%d FAIL=%d UNVERIFIED=%d\n' "$P" "$F" "$U" | tee /out/summary.txt
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
