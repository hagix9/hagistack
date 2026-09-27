#!/usr/bin/env bash
# Reproduce the five audit findings against a given hagistack. Harmless inputs only.
# usage: repro.sh <path-to-hagistack> <label>
set -uo pipefail
H="$1"; LABEL="$2"
NIC="$(ls /sys/class/net | grep -v '^lo$' | head -1)"; NIC="${NIC:-lo}"
BASE=(--provider-cidr 172.24.4.0/24 --provider-gateway 172.24.4.1
      --floating-start 172.24.4.100 --floating-end 172.24.4.200 --mgmt-ip 10.0.0.5)
echo "################ $LABEL ################"

echo
echo "--- (1) env file code execution ---"
rm -f /tmp/MARKER_PWNED
# The marker value is inert on its own; only `source` would run it.
cat > /tmp/evil.env <<EEOF
EXT_NIC=$NIC
TENANT_CIDR=\$(touch /tmp/MARKER_PWNED)
EEOF
out="$("$H" all-in-one --check --env-file /tmp/evil.env "${BASE[@]}" 2>&1)"; rc=$?
if [ -e /tmp/MARKER_PWNED ]; then
    echo "  RESULT: *** CODE EXECUTED *** /tmp/MARKER_PWNED was created (rc=$rc)"
else
    echo "  RESULT: no marker created (rc=$rc)"
    echo "  message: $(grep -iE 'env file|reject|not allowed|invalid' <<<"$out" | head -2)"
fi
rm -f /tmp/MARKER_PWNED
# backtick variant
rm -f /tmp/MARKER_PWNED2
printf 'EXT_NIC=%s\nDNS_SERVER=`touch /tmp/MARKER_PWNED2`\n' "$NIC" > /tmp/evil2.env
"$H" all-in-one --check --env-file /tmp/evil2.env "${BASE[@]}" >/dev/null 2>&1
[ -e /tmp/MARKER_PWNED2 ] && echo "  backtick variant: *** CODE EXECUTED ***" \
                          || echo "  backtick variant: not executed"
rm -f /tmp/MARKER_PWNED2

echo
echo "--- (2) CLI > env > file precedence for tenant-cidr / dns-server / virt-type ---"
cat > /tmp/prec.env <<EEOF
EXT_NIC=$NIC
TENANT_CIDR=10.3.3.0/24
DNS_SERVER=10.3.3.53
VIRT_TYPE=qemu
EEOF
# file only
o1="$("$H" all-in-one --check --env-file /tmp/prec.env "${BASE[@]}" 2>&1)"
# env should beat file
o2="$(TENANT_CIDR=10.2.2.0/24 DNS_SERVER=10.2.2.53 "$H" all-in-one --check --env-file /tmp/prec.env "${BASE[@]}" 2>&1)"
# CLI should beat both
o3="$(TENANT_CIDR=10.2.2.0/24 DNS_SERVER=10.2.2.53 "$H" all-in-one --check --env-file /tmp/prec.env \
      --tenant-cidr 10.1.1.0/24 --dns-server 10.1.1.53 --virt-type kvm "${BASE[@]}" 2>&1)"
# The fixed shell prints a resolved-config table under --check; the old one
# printed nothing, so fall back to the old marker when the table is absent.
show() { sed -n 's/^[[:space:]]*\(TENANT_CIDR\|DNS_SERVER\|VIRT_TYPE\)[[:space:]]\+\([^[:space:]]*\)[[:space:]]*\[\(.*\)\]$/\1=\2[\3]/p' <<<"$1" | tr '\n' ' '
         grep -oE 'virt_type=[a-z]+' <<<"$1" | tr '\n' ' '; }
echo "  file only        : $(show "$o1")"
echo "  env over file    : $(show "$o2")   (want tenant=10.2.2.0/24 dns=10.2.2.53)"
echo "  CLI over env+file: $(show "$o3")   (want tenant=10.1.1.0/24 dns=10.1.1.53 virt_type=kvm)"

echo
echo "--- (3) nova / nova_api credential keys ---"
if grep -qE '^\s+PLACEMENT_DB_PASS NOVA_DB_PASS NOVA_API_DB_PASS' "$H"; then
    echo "  RESULT: NOVA_API_DB_PASS is still GENERATED as a secret"
else
    echo "  RESULT: NOVA_API_DB_PASS no longer generated"
fi
echo "  nova_api mapping: $(grep -oE 'nova_api\) *passvar="[A-Z_]+"' "$H" | head -1)"
grep -q 'OBSOLETE_SECRET_KEYS' "$H" && echo "  obsolete-key migration: handled" \
                                    || echo "  obsolete-key migration: none"

echo
echo "--- (4) premature 'COMPLETE' with no reachable services ---"
rm -rf /etc/hagistack /var/lib/hagistack
o="$("$H" all-in-one --env-file /dev/null --ext-nic "$NIC" "${BASE[@]}" 2>&1)"; rc=$?
echo "  exit code: $rc"
grep -qE 'STEP [0-9]+ COMPLETE' <<<"$o" && echo "  RESULT: *** claimed COMPLETE despite skipping services ***" \
                                  || echo "  RESULT: did not claim completion"
grep -qE 'INCOMPLETE|not verified|NOT VERIFIED' <<<"$o" && echo "  (an incomplete/unverified notice was present)"
echo "  phase markers: $(ls /var/lib/hagistack/state 2>/dev/null | tr '\n' ' ')"

echo
echo "--- (5) gen_secret /dev/urandom fallback under pipefail ---"
# Extract gen_secret and exercise the no-openssl path exactly as the shell would.
{ echo 'set -Eeuo pipefail'; echo 'have(){ return 1; }'   # force the fallback branch
  sed -n '/^gen_secret() {/,/^}$/p' "$H"
  echo 's="$(gen_secret 32)"; rc=$?'
  echo 'printf "  rc=%s len=%s charset_ok=%s\n" "$rc" "${#s}" "$(printf %s "$s" | tr -d "A-Za-z0-9" | wc -c)"'
} > /tmp/gs.sh
gout="$(bash /tmp/gs.sh 2>&1)"; grc=$?
echo "  script exit: $grc"
echo "$gout" | sed 's/^/  /'
[ "$grc" != "0" ] && echo "  RESULT: *** fallback path ABORTED (SIGPIPE/pipefail) ***" \
                  || echo "  RESULT: fallback path completed"
echo
