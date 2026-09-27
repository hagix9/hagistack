#!/usr/bin/env bash
# Regression suite for the five Step 1 audit findings. Ubuntu 26.04 container.
set -uo pipefail
H=/src/hagistack
R=/out/audit-results.tsv; : > "$R"
P=0; F=0; U=0
rec(){ printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$R"
  case "$2" in
    PASS) P=$((P+1)); printf '  \033[32mPASS\033[0m  %-30s %s\n' "$1" "$3";;
    FAIL) F=$((F+1)); printf '  \033[31mFAIL\033[0m  %-30s %s\n' "$1" "$3";;
    *)    U=$((U+1)); printf '  \033[33mUNVER\033[0m %-30s %s\n' "$1" "$3";;
  esac; }
NIC="$(ls /sys/class/net | grep -v '^lo$' | head -1)"; NIC="${NIC:-lo}"
BASE=(--provider-cidr 172.24.4.0/24 --provider-gateway 172.24.4.1
      --floating-start 172.24.4.100 --floating-end 172.24.4.200)
MGMTDEF=(--mgmt-ip 10.0.0.5)
cfgval(){ sed -n "s/^[[:space:]]*$2[[:space:]]\+\([^[:space:]]*\)[[:space:]]*\[\(.*\)\]$/\1|\2/p" <<<"$1" | head -1; }

echo "=== 1. env file must never execute code ==="
# Each payload would run if the file were sourced. The marker file is the proof.
i=0
for payload in 'TENANT_CIDR=$(touch /tmp/M1)' \
               'TENANT_CIDR=`touch /tmp/M2`' \
               'TENANT_CIDR=x;touch /tmp/M3' \
               'TENANT_CIDR=$(touch /tmp/M4) ' \
               'DNS_SERVER=${IFS}$(touch /tmp/M5)' ; do
  i=$((i+1)); rm -f "/tmp/M$i"
  printf 'EXT_NIC=%s\n%s\n' "$NIC" "$payload" > /tmp/e$i.env
  out="$("$H" all-in-one --check --env-file /tmp/e$i.env "${BASE[@]}" "${MGMTDEF[@]}" 2>&1)"; rc=$?
  if [ -e "/tmp/M$i" ]; then
    rec "1.$i-no-exec" FAIL "payload $i EXECUTED (marker created)"
  elif [ "$rc" = "0" ]; then
    rec "1.$i-no-exec" FAIL "payload $i accepted silently (rc=0) — should be refused"
  else
    rec "1.$i-no-exec" PASS "refused, rc=$rc, no marker"
  fi
  rm -f "/tmp/M$i"
done
# the rejection message must not echo the value back
out="$("$H" all-in-one --check --env-file /tmp/e1.env "${BASE[@]}" "${MGMTDEF[@]}" 2>&1)"
grep -q 'touch /tmp/M1' <<<"$out" && rec 1.6-no-value-leak FAIL "error text echoed the value" \
                                  || rec 1.6-no-value-leak PASS "value not echoed in the error"
# unknown key
printf 'EXT_NIC=%s\nEVIL_KEY=1\n' "$NIC" > /tmp/u.env
out="$("$H" all-in-one --check --env-file /tmp/u.env "${BASE[@]}" "${MGMTDEF[@]}" 2>&1)"; rc=$?
[ "$rc" != "0" ] && grep -qi "unknown key" <<<"$out" \
  && rec 1.7-unknown-key PASS "unknown key refused" || rec 1.7-unknown-key FAIL "rc=$rc"
# duplicate key
printf 'EXT_NIC=%s\nTENANT_CIDR=10.1.0.0/24\nTENANT_CIDR=10.2.0.0/24\n' "$NIC" > /tmp/d.env
out="$("$H" all-in-one --check --env-file /tmp/d.env "${BASE[@]}" "${MGMTDEF[@]}" 2>&1)"; rc=$?
[ "$rc" != "0" ] && grep -qi "duplicate key" <<<"$out" \
  && rec 1.8-duplicate-key PASS "duplicate key refused" || rec 1.8-duplicate-key FAIL "rc=$rc"
# malformed line
printf 'EXT_NIC=%s\nthis is not an assignment\n' "$NIC" > /tmp/m.env
out="$("$H" all-in-one --check --env-file /tmp/m.env "${BASE[@]}" "${MGMTDEF[@]}" 2>&1)"; rc=$?
[ "$rc" != "0" ] && rec 1.9-malformed-line PASS "malformed line refused (rc=$rc)" \
                 || rec 1.9-malformed-line FAIL "accepted"
# a legitimate file with quotes and comments still works
printf '# comment\n\nEXT_NIC="%s"\nTENANT_CIDR=10.9.0.0/24   \n' "$NIC" > /tmp/g.env
out="$("$H" all-in-one --check --env-file /tmp/g.env "${BASE[@]}" "${MGMTDEF[@]}" 2>&1)"; rc=$?
v="$(cfgval "$out" TENANT_CIDR)"
[ "$rc" = "0" ] && [ "${v%%|*}" = "10.9.0.0/24" ] \
  && rec 1.10-valid-file-ok PASS "quoted value + comment + trailing blanks accepted" \
  || rec 1.10-valid-file-ok FAIL "rc=$rc value='$v'"

echo
echo "=== 2. precedence CLI > env > file, for every option ==="
cat > /tmp/p.env <<PEOF
EXT_NIC=$NIC
TENANT_CIDR=10.3.3.0/24
DNS_SERVER=10.3.3.53
VIRT_TYPE=qemu
MGMT_IP=10.3.3.9
PEOF
o_file="$("$H" all-in-one --check --env-file /tmp/p.env "${BASE[@]}" 2>&1)"
o_env="$(TENANT_CIDR=10.2.2.0/24 DNS_SERVER=10.2.2.53 VIRT_TYPE=kvm MGMT_IP=10.2.2.9 \
         "$H" all-in-one --check --env-file /tmp/p.env "${BASE[@]}" 2>&1)"
o_cli="$(TENANT_CIDR=10.2.2.0/24 DNS_SERVER=10.2.2.53 VIRT_TYPE=kvm MGMT_IP=10.2.2.9 \
         "$H" all-in-one --check --env-file /tmp/p.env \
         "${BASE[@]}" \
         --tenant-cidr 10.1.1.0/24 --dns-server 10.1.1.53 --virt-type qemu --mgmt-ip 10.1.1.9 2>&1)"
chk(){ # chk <id> <output> <key> <want-value> <want-source>
  local got; got="$(cfgval "$2" "$3")"
  if [ "${got%%|*}" = "$4" ] && [ "${got##*|}" = "$5" ]; then
     rec "$1" PASS "$3=$4 [$5]"
  else rec "$1" FAIL "$3 got '${got}' want '$4|$5'"; fi; }
chk 2.1-file-tenant  "$o_file" TENANT_CIDR 10.3.3.0/24 "config file"
chk 2.2-file-dns     "$o_file" DNS_SERVER  10.3.3.53   "config file"
chk 2.3-file-virt    "$o_file" VIRT_TYPE   qemu        "config file"
chk 2.4-env-tenant   "$o_env"  TENANT_CIDR 10.2.2.0/24 "environment"
chk 2.5-env-dns      "$o_env"  DNS_SERVER  10.2.2.53   "environment"
chk 2.6-env-virt     "$o_env"  VIRT_TYPE   kvm         "environment"
chk 2.7-env-mgmt     "$o_env"  MGMT_IP     10.2.2.9    "environment"
chk 2.8-cli-tenant   "$o_cli"  TENANT_CIDR 10.1.1.0/24 "command line"
chk 2.9-cli-dns      "$o_cli"  DNS_SERVER  10.1.1.53   "command line"
chk 2.10-cli-virt    "$o_cli"  VIRT_TYPE   qemu        "command line"
chk 2.11-cli-mgmt    "$o_cli"  MGMT_IP     10.1.1.9    "command line"
# default tier
o_def="$("$H" all-in-one --check --env-file /dev/null --ext-nic "$NIC" "${BASE[@]}" "${MGMTDEF[@]}" 2>&1)"
chk 2.12-default-tenant "$o_def" TENANT_CIDR 10.10.10.0/24 "default"
chk 2.13-default-dns    "$o_def" DNS_SERVER  172.24.4.1    "default"
# explicit empty must be an error, not a silent fall-through
out="$("$H" all-in-one --check --env-file /dev/null --ext-nic "$NIC" "${BASE[@]}" "${MGMTDEF[@]}" --tenant-cidr "" 2>&1)"; rc=$?
[ "$rc" != "0" ] && grep -qi "empty value" <<<"$out" \
  && rec 2.14-explicit-empty-cli PASS "--tenant-cidr '' rejected (rc=$rc)" \
  || rec 2.14-explicit-empty-cli FAIL "rc=$rc"
printf 'EXT_NIC=%s\nTENANT_CIDR=\n' "$NIC" > /tmp/empty.env
out="$("$H" all-in-one --check --env-file /tmp/empty.env "${BASE[@]}" "${MGMTDEF[@]}" 2>&1)"; rc=$?
[ "$rc" != "0" ] && grep -qi "empty value" <<<"$out" \
  && rec 2.15-explicit-empty-file PASS "blank value in file rejected (rc=$rc)" \
  || rec 2.15-explicit-empty-file FAIL "rc=$rc"
# a flag at end of line with no value must not swallow the next thing
out="$("$H" all-in-one --check --env-file /dev/null --ext-nic 2>&1)"; rc=$?
[ "$rc" != "0" ] && rec 2.16-flag-missing-value PASS "trailing flag without value rejected (rc=$rc)" \
                 || rec 2.16-flag-missing-value FAIL "accepted"

# Repeating a flag: the last occurrence wins. Asserted so it stays deliberate.
o_dup="$("$H" all-in-one --check --env-file /dev/null --ext-nic "$NIC" "${BASE[@]}" \
         --mgmt-ip 10.7.7.7 --mgmt-ip 10.8.8.8 2>&1)"
chk 2.17-last-flag-wins "$o_dup" MGMT_IP 10.8.8.8 "command line"

echo
echo "=== 5. gen_secret fallback under pipefail ==="
{ echo 'set -Eeuo pipefail'; echo 'have(){ [ "$1" != openssl ]; }'   # force /dev/urandom
  echo 'die(){ echo "die: $*" >&2; exit 1; }'
  sed -n '/^gen_secret() {/,/^}$/p' "$H"
  echo 'for i in 1 2 3 4 5; do s="$(gen_secret 32)"; printf "%s %s\n" "${#s}" "$(printf %s "$s" | tr -d "A-Za-z0-9" | wc -c)"; done'
} > /tmp/gs.sh
fails=0; lens_ok=1
for i in $(seq 1 100); do
  o="$(bash /tmp/gs.sh 2>&1)" || fails=$((fails+1))
  while read -r L C; do [ "$L" = "32" ] && [ "$C" = "0" ] || lens_ok=0; done <<<"$o"
done
[ "$fails" = "0" ] && rec 5.1-fallback-exit PASS "100 runs x5 secrets, no nonzero exit" \
                   || rec 5.1-fallback-exit FAIL "$fails/100 runs exited nonzero"
[ "$lens_ok" = "1" ] && rec 5.2-fallback-shape PASS "every secret 32 chars, charset [A-Za-z0-9]" \
                     || rec 5.2-fallback-shape FAIL "wrong length or charset"
# no consumer-side head left in gen_secret
sed -n '/^gen_secret() {/,/^}$/p' "$H" | grep -qE '\|[[:space:]]*head' \
  && rec 5.3-no-pipe-to-head FAIL "gen_secret still pipes into head" \
  || rec 5.3-no-pipe-to-head PASS "no consumer-side head in gen_secret"
# openssl path too
if command -v openssl >/dev/null 2>&1; then
  { echo 'set -Eeuo pipefail'; echo 'die(){ echo "die: $*" >&2; exit 1; }'
    echo 'have(){ command -v "$1" >/dev/null 2>&1; }'
    sed -n '/^gen_secret() {/,/^}$/p' "$H"
    echo 'have openssl || { echo "openssl branch not taken"; exit 2; }'
    echo 'for i in 1 2 3; do s="$(gen_secret 48)"; printf "%s\n" "${#s}"; done'
  } > /tmp/gs2.sh
  o="$(bash /tmp/gs2.sh 2>&1)"; rc=$?
  [ "$rc" = "0" ] && [ "$(sort -u <<<"$o")" = "48" ] \
    && rec 5.4-openssl-path PASS "openssl branch: 48-char secrets, exit 0" \
    || rec 5.4-openssl-path FAIL "rc=$rc out=$o"
else
  rec 5.4-openssl-path UNVERIFIED "openssl not installed in this container"
fi
# the secret itself must never be printed by the shell
rm -rf /etc/hagistack /var/lib/hagistack
o="$("$H" all-in-one --env-file /dev/null --ext-nic "$NIC" "${BASE[@]}" "${MGMTDEF[@]}" 2>&1 || true)"
leak=0
if [ -f /etc/hagistack/secrets.env ]; then
  while IFS='=' read -r k v; do
    case "$k" in ''|\#*) continue;; esac
    [ -n "$v" ] && grep -qF "$v" <<<"$o" && leak=1
  done < /etc/hagistack/secrets.env
fi
[ "$leak" = "0" ] && rec 5.5-no-secret-in-output PASS "no generated secret appears in stdout/stderr" \
                  || rec 5.5-no-secret-in-output FAIL "a secret value was printed"

echo
echo "=== 4. no 'COMPLETE' when a service is unreachable ==="
rm -rf /etc/hagistack /var/lib/hagistack
o="$("$H" all-in-one --env-file /dev/null --ext-nic "$NIC" "${BASE[@]}" "${MGMTDEF[@]}" 2>&1)"; rc=$?
[ "$rc" = "4" ] && rec 4.1-exit-code PASS "exit 4 when base layer incomplete" \
                || rec 4.1-exit-code FAIL "exit $rc, wanted 4"
grep -qE 'STEP [0-9]+ INCOMPLETE' <<<"$o" && rec 4.2-banner PASS "INCOMPLETE banner shown" \
                                    || rec 4.2-banner FAIL "no INCOMPLETE banner"
grep -qE 'STEP [0-9]+ COMPLETE' <<<"$o" && rec 4.3-no-false-complete FAIL "still claims COMPLETE" \
                                  || rec 4.3-no-false-complete PASS "does not claim COMPLETE"
grep -qE 'Skipped +: .*database' <<<"$o" && rec 4.4-lists-skipped PASS "names the skipped phases" \
                                         || rec 4.4-lists-skipped FAIL "skipped phases not named"
[ -e /var/lib/hagistack/state/database.done ] && rec 4.5-no-marker FAIL "database marked done though skipped" \
                                              || rec 4.5-no-marker PASS "no state marker for a skipped phase"
[ -e /var/lib/hagistack/state/memcached.done ] && rec 4.6-memcached-marker FAIL "memcached marked done though never started" \
                                               || rec 4.6-memcached-marker PASS "memcached not marked done"
st="$("$H" status 2>&1)"
grep -qE '(base|implemented) layer: INCOMPLETE' <<<"$st" && rec 4.7-status-agrees PASS "status reports INCOMPLETE" \
                                          || rec 4.7-status-agrees FAIL "status disagrees with the banner"
grep -q 'exits 4' <<<"$st" && rec 4.8-status-mentions-exit PASS "status explains the exit code" \
                           || rec 4.8-status-mentions-exit FAIL "status does not mention exit 4"
printf 'PASS=%d FAIL=%d UNVERIFIED=%d\n' "$P" "$F" "$U" | tee /out/audit-summary.txt
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
