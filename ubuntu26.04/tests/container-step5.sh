#!/usr/bin/env bash
# Step 5 (Nova) verification, INSIDE an Ubuntu 26.04 container — deliberately light.
#
# Scope, decided before running: syntax, ShellCheck, input validation,
# configuration generation, the compute databases, and secret handling. It does
# NOT try to bring the whole control plane up again: the step 4 run showed that
# this container cannot keep Keystone, Apache and memcached alive together, and
# repeating that proves nothing about a real host. Everything that needs a live
# control plane — the compute API, cell host discovery, the hypervisor and any
# guest boot — is recorded UNVERIFIED and sent to the GCE acceptance.
set -uo pipefail
H=/src/hagistack
R=/out/s5-results.tsv; : > "$R"
P=0; F=0; U=0
rec(){ printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$R"
  case "$2" in
    PASS) P=$((P+1)); printf '  \033[32mPASS\033[0m  %-30s %s\n' "$1" "$3";;
    FAIL) F=$((F+1)); printf '  \033[31mFAIL\033[0m  %-30s %s\n' "$1" "$3";;
    *)    U=$((U+1)); printf '  \033[33mUNVER\033[0m %-30s %s\n' "$1" "$3";;
  esac; }
digest_of(){ [ -f "$1" ] || { echo ABSENT; return; }; sha256sum "$1" | cut -d' ' -f1; }
ini_val(){ awk -v s="[$2]" -v k="$3" '
    $0 ~ /^\[/ { insec = ($0 == s); next }
    insec && $0 ~ "^"k"[ \t]*=" { sub(/^[^=]*=[ \t]*/, ""); print; exit }' "$1" 2>/dev/null; }
ini_is(){ [ "$(ini_val "$1" "$2" "$3")" = "$4" ]; }

export DEBIAN_FRONTEND=noninteractive
cat > /etc/dpkg/dpkg.cfg.d/01-nodoc <<'EOF'
path-exclude /usr/share/doc/*
path-exclude /usr/share/man/*
path-exclude /usr/share/locale/*
EOF
printf 'APT::Keep-Downloaded-Packages "false";\n' > /etc/apt/apt.conf.d/01-lean
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq iproute2 openssl curl shellcheck jq procps >/dev/null 2>&1
free_mb(){ df -m / | awk 'NR==2{print $4}'; }
NIC="$(for d in /sys/class/net/*; do n="${d##*/}"; [ "$n" = lo ] || { echo "$n"; break; }; done)"; NIC="${NIC:-lo}"
MGMT="$(ip -4 -o addr show "$NIC" | awk '{split($4,a,"/"); print a[1]}' | head -1)"; MGMT="${MGMT:-127.0.0.1}"
BASE=(--env-file /dev/null --ext-nic "$NIC" --provider-cidr 172.24.4.0/24 --provider-gateway 172.24.4.1
      --floating-start 172.24.4.100 --floating-end 172.24.4.200 --mgmt-ip "$MGMT")
echo "== env: $(. /etc/os-release; echo "$PRETTY_NAME") $(dpkg --print-architecture); NIC=$NIC MGMT=$MGMT"
echo "   systemd: $([ -d /run/systemd/system ] && echo present || echo ABSENT); free disk: $(free_mb)MB"

echo
echo "== S0. static + surface =="
bash -n "$H" && rec S0a-bash-n PASS "parses" || rec S0a-bash-n FAIL "syntax error"
sc="$(shellcheck -S warning "$H" 2>&1)"
[ -z "$sc" ] && rec S0b-shellcheck PASS "no warnings (-S warning)" || rec S0b-shellcheck FAIL "$(head -c 400 <<<"$sc")"
for t in /src/tests/container-step5.sh /src/tests/container-step4.sh; do
  o="$(shellcheck -S warning "$t" 2>&1)"
  [ -z "$o" ] && rec "S0b2-shellcheck-$(basename "$t" .sh)" PASS "suite clean" \
              || rec "S0b2-shellcheck-$(basename "$t" .sh)" FAIL "$(head -c 200 <<<"$o")"
done
v="$("$H" --version)"
grep -qE '^hagistack [0-9]+\.[0-9]+\.[0-9]+-step[0-9]+$' <<<"$v" && rec S0c-version PASS "$v" || rec S0c-version FAIL "$v"
st="$("$H" status 2>&1)"; stn="$(tr '\n' ' ' <<<"$st")"
grep -qi 'compute' <<<"$st" && grep -qE 'nova' <<<"$st" \
  && rec S0d-status-compute PASS "status reports the compute layer" || rec S0d-status-compute FAIL "no compute section"
grep -qiE 'no guest VM has been booted|guest boot NOT verified' <<<"$stn" \
  && rec S0e-status-honest PASS "status says guest boot is not verified" || rec S0e-status-honest FAIL "overclaims: $(head -c 120 <<<"$stn")"
hl="$("$H" --help 2>&1 | tr '\n' ' ')"
grep -qiE 'does +NOT +give you a working' <<<"$hl" && rec S0f-help-honest PASS "help refuses 'working OpenStack'" || rec S0f-help-honest FAIL "help overclaims"
# nothing anywhere may claim a finished/usable cloud
if grep -RniE 'usable (openstack|cloud)|finished openstack' "$H" | grep -viE 'NOT a usable|NOT usable|no[tn].{0,14}usable|Do not call this a finished' | grep -q .; then
  rec S0g-no-usable-claim FAIL "an unqualified 'usable/finished OpenStack' claim exists"
else rec S0g-no-usable-claim PASS "every such mention is a negation"; fi
grep -q 'nova_compute' <<<"$("$H" status 2>&1)" && rec S0h-phase-listed PASS "nova_compute listed as an implemented phase" \
                                                || rec S0h-phase-listed FAIL "phase not listed"

echo
echo "== S1. input validation (virt type is the step 5 input) =="
bad(){ local label="$1"; shift
  local o rc; o="$("$H" all-in-one --check "${BASE[@]}" "$@" 2>&1)"; rc=$?
  if [ "$rc" = "0" ]; then rec "$label" FAIL "accepted"
  elif grep -qiE "must be 'kvm' or 'qemu'|not a valid|requires a value" <<<"$o"; then rec "$label" PASS "rejected"
  else rec "$label" FAIL "exit $rc without a validation message"; fi; }
bad S1a-virt-bogus   --virt-type xen
bad S1b-virt-inject  --virt-type 'kvm;touch /tmp/S1'
bad S1c-virt-novalue --virt-type
[ -e /tmp/S1 ] && rec S1d-no-exec FAIL "a rejected value executed a command" || rec S1d-no-exec PASS "nothing executed"
for t in kvm qemu; do
  o="$("$H" all-in-one --check "${BASE[@]}" --virt-type "$t" 2>&1)"
  grep -qE "VIRT_TYPE +$t" <<<"$o" && rec "S1e-virt-$t" PASS "$t accepted and resolved" || rec "S1e-virt-$t" FAIL "not resolved"
done
o="$(VIRT_TYPE=qemu "$H" all-in-one --check "${BASE[@]}" 2>&1)"
grep -qE 'VIRT_TYPE +qemu +\[environment\]' <<<"$o" && rec S1f-virt-env PASS "environment tier honoured" || rec S1f-virt-env FAIL "env tier ignored"
o="$("$H" all-in-one --check "${BASE[@]}" 2>&1)"
if grep -qE 'VIRT_TYPE +(kvm|qemu)' <<<"$o"; then
  kv="$(grep -oE 'VIRT_TYPE +[a-z]+' <<<"$o" | awk '{print $2}')"
  if [ -e /dev/kvm ]; then exp=kvm; else exp=qemu; fi
  [ "$kv" = "$exp" ] && rec S1g-kvm-detect PASS "/dev/kvm $([ -e /dev/kvm ] && echo present || echo absent) -> virt_type=$kv" \
                     || rec S1g-kvm-detect FAIL "detected $kv, expected $exp"
else rec S1g-kvm-detect FAIL "no VIRT_TYPE in the resolved configuration"; fi

echo
echo "== S2. with no services, both nova phases must skip honestly =="
rm -rf /etc/hagistack /var/lib/hagistack
o="$("$H" all-in-one "${BASE[@]}" 2>&1)"; rc=$?
echo "$o" > /out/s5-noservices.log
[ "$rc" = "4" ] && rec S2a-exit4 PASS "exit 4" || rec S2a-exit4 FAIL "exit $rc"
grep -q "phase 'nova' SKIPPED" <<<"$o" && rec S2b-nova-skip PASS "nova skip reported" || rec S2b-nova-skip FAIL "no skip"
grep -q "phase 'nova_compute' SKIPPED" <<<"$o" && rec S2c-compute-skip PASS "nova_compute skip reported" || rec S2c-compute-skip FAIL "no skip"
for m in nova nova_compute; do
  [ -e "/var/lib/hagistack/state/$m.done" ] && rec "S2d-$m-no-marker" FAIL "marked done after a skip" \
                                            || rec "S2d-$m-no-marker" PASS "no state marker"
done
grep -qE 'STEP [0-9]+ COMPLETE' <<<"$o" && rec S2e-no-false-complete FAIL "claimed COMPLETE" || rec S2e-no-false-complete PASS "no COMPLETE claim"
# the package default must still be there: nothing of ours written while skipping
if [ -f /etc/nova/nova.conf ]; then
  c="$(ini_val /etc/nova/nova.conf database connection)"
  case "$c" in mysql*) rec S2f-no-half-config FAIL "nova.conf was configured during a skip" ;;
               *)      rec S2f-no-half-config PASS "nova.conf still carries the package default" ;; esac
else rec S2f-no-half-config UNVERIFIED "nova.conf absent (nova packages not installed at this point)"; fi

echo
echo "== S3. the packaging facts the code relies on (measured here, not assumed) =="
apt-get install -y -qq nova-common nova-api nova-api-metadata nova-conductor nova-scheduler >/dev/null 2>&1
echo "   (nova control packages installed; free disk $(free_mb)MB)"
if ! dpkg-query -W -f='${Status}' nova-common 2>/dev/null | grep -q "install ok installed"; then
  for t in S3a-api-vhost S3b-metadata-vhost S3c-no-api-unit S3d-units S3e-conf-mode S3f-auth-strategy S3g-meta-secret S3h-nova-manage; do
    rec "$t" UNVERIFIED "the nova packages could not be installed in this container"
  done
else
  unit_of(){ ls /usr/lib/systemd/system/"$1".service /lib/systemd/system/"$1".service 2>/dev/null | head -1; }
  if grep -qE '^[[:space:]]*Listen[[:space:]]+8774' /etc/apache2/sites-available/nova-api.conf 2>/dev/null \
     && [ -L /etc/apache2/sites-enabled/nova-api.conf ]; then
    rec S3a-api-vhost PASS "nova-api vhost listens on 8774 and is enabled by the package"
  else rec S3a-api-vhost FAIL "vhost missing, wrong port, or not enabled"; fi
  if grep -qE '^[[:space:]]*Listen[[:space:]]+8775' /etc/apache2/sites-available/nova-api-metadata.conf 2>/dev/null; then
    rec S3b-metadata-vhost PASS "nova-api-metadata vhost listens on 8775"
  else rec S3b-metadata-vhost FAIL "metadata vhost missing or on another port"; fi
  [ -z "$(unit_of nova-api)" ] && rec S3c-no-api-unit PASS "nova-api ships no systemd unit (the API is the vhost)" \
                               || rec S3c-no-api-unit FAIL "a nova-api unit exists; the code assumes none"
  miss=""
  for u in nova-conductor nova-scheduler; do [ -n "$(unit_of "$u")" ] || miss="$miss $u"; done
  if [ -z "$miss" ]; then
    usr="$(grep -h '^User=' "$(unit_of nova-conductor)" | head -1)"
    rec S3d-units PASS "nova-conductor and nova-scheduler units exist ($usr)"
  else rec S3d-units FAIL "missing unit(s):$miss"; fi
  # The .deb stores nova.conf 0644 root:root, but nova-common's postinst chowns
  # /etc/nova to root:nova and chmods files 0640. The property that matters is
  # the installed one, and that hagistack keeps it after writing credentials.
  m="$(stat -c '%a %U:%G' /etc/nova/nova.conf)"
  [ "$m" = "640 root:nova" ] && rec S3e-conf-mode PASS "installed nova.conf is $m (postinst tightens what the archive stores as 644 root:root)" \
                             || rec S3e-conf-mode FAIL "installed nova.conf is $m — credentials would be readable"
  if grep -qE 'chmod 0640 "\$NOVA_CONF"' "$H"; then
    rec S3e2-conf-mode-enforced PASS "the phase re-applies 0640 after writing credentials"
  else rec S3e2-conf-mode-enforced FAIL "the phase does not enforce the mode it depends on"; fi
  # options the code deliberately does or does not set
  if grep -rq "auth_strategy" /usr/lib/python3/dist-packages/nova/conf/api.py 2>/dev/null; then
    rec S3f-auth-strategy UNVERIFIED "[api] auth_strategy exists after all; the code does not set it"
  else rec S3f-auth-strategy PASS "[api] auth_strategy does not exist in nova 33 — correctly not invented"; fi
  if grep -q "metadata_proxy_shared_secret" /usr/lib/python3/dist-packages/nova/conf/neutron.py 2>/dev/null; then
    rec S3g-meta-secret PASS "[neutron] metadata_proxy_shared_secret is defined in nova/conf/neutron.py"
  else rec S3g-meta-secret FAIL "the option the code writes is not defined there"; fi
  command -v nova-manage >/dev/null && nova-manage --help 2>&1 | grep -qE 'cell_v2' \
    && rec S3h-nova-manage PASS "nova-manage offers the cell_v2 category" || rec S3h-nova-manage FAIL "cell_v2 category not offered"
fi

echo
echo "== S4. configuration generation, using the shell's own helpers =="
# The helpers are lifted out of the product (the same technique the step 1 audit
# suite uses for gen_secret) and run against the REAL packaged nova.conf, so
# this tests the code that ships rather than a copy of it.
WORK=/tmp/cfg; rm -rf $WORK; mkdir -p $WORK
if [ -f /etc/nova/nova.conf ]; then cp /etc/nova/nova.conf $WORK/nova.conf
else printf '[DEFAULT]\n[database]\n[api_database]\n[neutron]\n[placement]\n[glance]\n[vnc]\n[service_user]\n[keystone_authtoken]\n[oslo_concurrency]\n' > $WORK/nova.conf; fi
{
  echo 'set -u'; echo 'SUDO=""'; echo 'MGMT_IP="10.0.0.5"'; echo 'REGION_NAME="RegionOne"'
  echo 'log_ok(){ :; }; log_info(){ :; }; log_warn(){ :; }; log_error(){ :; }'
  sed -n '/^ini_set()/,/^}/p'            "$H"
  sed -n '/^ini_get()/,/^}/p'            "$H"
  sed -n '/^write_authtoken()/,/^}/p'    "$H"
  # write_service_auth became a thin wrapper around write_service_auth_at in
  # step 6 (a compute node's identity host is the controller, not itself), so
  # both have to be lifted or the extracted wrapper calls a function that is
  # not there and every adapter block silently comes out empty.
  sed -n '/^write_service_auth_at()/,/^}/p' "$H"
  sed -n '/^write_service_auth()/,/^}/p'    "$H"
} > $WORK/lib.sh
# shellcheck disable=SC1090
if ! ( . $WORK/lib.sh ) 2>/dev/null; then
  rec S4a-helpers UNVERIFIED "the helpers could not be extracted from the shell"
else
  rec S4a-helpers PASS "ini_set/ini_get/write_authtoken/write_service_auth extracted from the product"
  cat > $WORK/apply.sh <<'APPLY'
. /tmp/cfg/lib.sh
C=/tmp/cfg/nova.conf
NOVA_DB_PASS=dbpass123 ; NOVA_SERVICE_PASS=svcpass123
PLACEMENT_SERVICE_PASS=plpass123 ; NEUTRON_SERVICE_PASS=nepass123
RABBIT_PASS=rabbit123 ; METADATA_PROXY_SECRET=metasecret123
ini_set "$C" DEFAULT my_ip "$MGMT_IP" >/dev/null
ini_set "$C" DEFAULT transport_url "rabbit://openstack:${RABBIT_PASS}@${MGMT_IP}:5672/" >/dev/null
ini_set "$C" api_database connection "mysql+pymysql://nova:${NOVA_DB_PASS}@127.0.0.1/nova_api?charset=utf8mb4" >/dev/null
ini_set "$C" database connection "mysql+pymysql://nova:${NOVA_DB_PASS}@127.0.0.1/nova?charset=utf8mb4" >/dev/null
write_authtoken "$C" nova "$NOVA_SERVICE_PASS"
write_service_auth "$C" service_user nova "$NOVA_SERVICE_PASS"
ini_set "$C" service_user send_service_user_token true >/dev/null
write_service_auth "$C" placement placement "$PLACEMENT_SERVICE_PASS" internal
write_service_auth "$C" neutron neutron "$NEUTRON_SERVICE_PASS" internal
ini_set "$C" glance valid_interfaces internal >/dev/null
ini_set "$C" neutron service_metadata_proxy true >/dev/null
ini_set "$C" neutron metadata_proxy_shared_secret "$METADATA_PROXY_SECRET" >/dev/null
ini_set "$C" vnc enabled true >/dev/null
ini_set "$C" vnc server_listen "$MGMT_IP" >/dev/null
ini_set "$C" vnc server_proxyclient_address "$MGMT_IP" >/dev/null
ini_set "$C" oslo_concurrency lock_path /var/lib/nova/tmp >/dev/null
APPLY
  bash $WORK/apply.sh >/dev/null 2>&1
  C=$WORK/nova.conf
  chk(){ ini_is "$C" "$2" "$3" "$4" && rec "$1" PASS "[$2] $3 = $4" || rec "$1" FAIL "[$2] $3 is '$(ini_val "$C" "$2" "$3")'"; }
  chk S4b-my-ip            DEFAULT      my_ip 10.0.0.5
  chk S4c-transport        DEFAULT      transport_url "rabbit://openstack:rabbit123@10.0.0.5:5672/"
  chk S4d-api-db           api_database connection "mysql+pymysql://nova:dbpass123@127.0.0.1/nova_api?charset=utf8mb4"
  chk S4e-db               database     connection "mysql+pymysql://nova:dbpass123@127.0.0.1/nova?charset=utf8mb4"
  chk S4f-authtoken        keystone_authtoken username nova
  chk S4g-authtoken-cache  keystone_authtoken memcached_servers "10.0.0.5:11211"
  chk S4h-service-user     service_user send_service_user_token true
  chk S4i-placement-user   placement    username placement
  chk S4j-placement-iface  placement    valid_interfaces internal
  chk S4k-neutron-user     neutron      username neutron
  chk S4l-meta-proxy       neutron      service_metadata_proxy true
  chk S4m-meta-secret      neutron      metadata_proxy_shared_secret metasecret123
  chk S4n-glance-iface     glance       valid_interfaces internal
  chk S4o-vnc-listen       vnc          server_listen 10.0.0.5
  chk S4p-lock-path        oslo_concurrency lock_path /var/lib/nova/tmp
  # the sqlite defaults the package ships must be gone from both sections
  for sec in database api_database; do
    case "$(ini_val "$C" "$sec" connection)" in
      *sqlite*) rec "S4q-no-sqlite-$sec" FAIL "[$sec] still sqlite" ;;
      *)        rec "S4q-no-sqlite-$sec" PASS "[$sec] sqlite default replaced" ;;
    esac
  done
  # idempotence: applying the same values again must not change a byte
  d1="$(digest_of $C)"; bash $WORK/apply.sh >/dev/null 2>&1; d2="$(digest_of $C)"
  if [ "$d1" = ABSENT ] || [ "$d2" = ABSENT ]; then rec S4r-idempotent FAIL "the file vanished"
  elif [ "$d1" = "$d2" ]; then rec S4r-idempotent PASS "a second application changed nothing ($d1)"
  else rec S4r-idempotent FAIL "the file changed on re-application"; fi
  # a changed value must be rewritten in place, not appended
  bash -c '. /tmp/cfg/lib.sh; ini_set /tmp/cfg/nova.conf DEFAULT my_ip 10.0.0.9 >/dev/null'
  n="$(grep -c '^my_ip = ' $C)"
  [ "$n" = "1" ] && [ "$(ini_val "$C" DEFAULT my_ip)" = "10.0.0.9" ] \
    && rec S4s-rewrite-in-place PASS "a changed value is rewritten once, not appended" \
    || rec S4s-rewrite-in-place FAIL "my_ip occurrences=$n value=$(ini_val "$C" DEFAULT my_ip)"
fi
# the phase must actually contain those writes (the helpers above prove behaviour,
# this proves the phase asks for it)
missing=""
for pair in "DEFAULT my_ip" "DEFAULT transport_url" "api_database connection" "database connection" \
            "glance valid_interfaces" "neutron service_metadata_proxy" "neutron metadata_proxy_shared_secret" \
            "vnc server_listen" "vnc server_proxyclient_address" "oslo_concurrency lock_path" \
            "service_user send_service_user_token"; do
  grep -qE "ini_set \"\\\$NOVA_CONF\" ${pair% *} +${pair#* }" "$H" || missing="$missing [${pair% *}]${pair#* }"
done
[ -z "$missing" ] && rec S4t-phase-writes PASS "phase_nova writes every key this suite checked" \
                  || rec S4t-phase-writes FAIL "phase_nova does not write:$missing"

echo
echo "== S5. the compute databases (MariaDB only — light, and it is what step 5 adds) =="
apt-get install -y -qq mariadb-server memcached >/dev/null 2>&1
MARIADB_METHOD="mariadbd-safe --bind-address=127.0.0.1 --max-connections=1024 (manual, no systemd)"
mkdir -p /var/run/mysqld /var/log/mysql; chown mysql:mysql /var/run/mysqld /var/log/mysql 2>/dev/null
nohup mariadbd-safe --user=mysql --bind-address=127.0.0.1 --max-connections=1024 >/var/log/mysql/m.log 2>&1 &
for _ in $(seq 1 60); do mariadb -uroot -e "SELECT 1" >/dev/null 2>&1 && break; sleep 1; done
if ! mariadb -uroot -e "SELECT 1" >/dev/null 2>&1; then
  for t in S5a-mariadb S5b-dbs S5c-cell0 S5d-login S5e-grants S5f-rerun; do
    rec "$t" UNVERIFIED "MariaDB would not start in this container"; done
else
  rec S5a-mariadb PASS "started via: $MARIADB_METHOD"
  memcached -u memcache -l "$MGMT" -d 2>/dev/null || memcached -u nobody -l "$MGMT" -d 2>/dev/null || true
  rm -rf /var/lib/hagistack/state
  "$H" all-in-one "${BASE[@]}" > /out/s5-run1.log 2>&1 || true
  miss=""
  for d in nova nova_api nova_cell0; do
    mariadb -uroot -e "USE \`$d\`" >/dev/null 2>&1 || miss="$miss $d"
  done
  [ -z "$miss" ] && rec S5b-dbs PASS "nova, nova_api and nova_cell0 all created" || rec S5b-dbs FAIL "missing:$miss"
  # cell0's name is not a free choice: nova derives it from [database] connection
  if grep -q 'nova_cell0' "$H"; then rec S5c-cell0 PASS "nova_cell0 is provisioned under the name nova derives (<db>_cell0)"
  else rec S5c-cell0 FAIL "nova_cell0 is not provisioned"; fi
  np="$(sed -n 's/^NOVA_DB_PASS=//p' /etc/hagistack/secrets.env 2>/dev/null)"
  ok=1; for d in nova nova_api nova_cell0; do
    mariadb -unova -p"$np" -h127.0.0.1 -e "USE \`$d\`" >/dev/null 2>&1 || ok=0
  done
  [ "$ok" = 1 ] && rec S5d-login PASS "the single nova credential logs into all three databases" \
                || rec S5d-login FAIL "the nova user cannot reach one of the three"
  g="$(mariadb -uroot -N -B -e "SHOW GRANTS FOR 'nova'@'localhost'" 2>/dev/null | grep -c 'nova_cell0')"
  [ "$g" -ge 1 ] && rec S5e-grants PASS "nova holds privileges on nova_cell0" || rec S5e-grants FAIL "no grant on nova_cell0"
  # a planted row must survive a re-run
  mariadb -uroot -e "CREATE TABLE IF NOT EXISTS nova.hagistack_sentinel (v VARCHAR(40)); DELETE FROM nova.hagistack_sentinel; INSERT INTO nova.hagistack_sentinel VALUES ('must survive');" 2>/dev/null
  s_before="$(digest_of /etc/hagistack/secrets.env)"
  "$H" all-in-one "${BASE[@]}" > /out/s5-run2.log 2>&1 || true
  v2="$(mariadb -uroot -N -B -e "SELECT v FROM nova.hagistack_sentinel" 2>/dev/null)"
  s_after="$(digest_of /etc/hagistack/secrets.env)"
  if [ "$v2" = "must survive" ] && [ "$s_before" = "$s_after" ] && [ "$s_before" != ABSENT ]; then
    rec S5f-rerun PASS "planted row and secrets.env both intact after a second run"
  else rec S5f-rerun FAIL "row='$v2' secrets before=$s_before after=$s_after"; fi
  grep -q 'left untouched' /out/s5-run2.log && rec S5g-reuse-reported PASS "the re-run reports existing databases left untouched" \
                                            || rec S5g-reuse-reported FAIL "not reported"
fi

echo
echo "== S6. secrets =="
if [ -f /etc/hagistack/secrets.env ]; then
  grep -q '^NOVA_SERVICE_PASS=' /etc/hagistack/secrets.env \
    && rec S6a-nova-secret PASS "NOVA_SERVICE_PASS generated into secrets.env" || rec S6a-nova-secret FAIL "not generated"
  [ "$(stat -c '%a' /etc/hagistack/secrets.env)" = "600" ] && rec S6b-mode PASS "secrets.env is 0600" \
                                                           || rec S6b-mode FAIL "$(stat -c '%a' /etc/hagistack/secrets.env)"
  leak=""
  while IFS='=' read -r k v; do
    case "$k" in ''|\#*) continue;; esac; [ -n "$v" ] || continue
    grep -qrF "$v" /out/ 2>/dev/null && leak="$leak $k"
  done < /etc/hagistack/secrets.env
  [ -z "$leak" ] && rec S6c-no-leak PASS "no secret value appears in any run log or artefact" || rec S6c-no-leak FAIL "leaked:$leak"
  ps_out="$(ps -eo args 2>/dev/null || true)"; al=""
  for k in NOVA_SERVICE_PASS NOVA_DB_PASS RABBIT_PASS METADATA_PROXY_SECRET; do
    v="$(sed -n "s/^$k=//p" /etc/hagistack/secrets.env)"
    [ -n "$v" ] && grep -qF "$v" <<<"$ps_out" && al="$al $k"
  done
  [ -z "$al" ] && rec S6d-no-argv PASS "no compute secret in any process argument list" || rec S6d-no-argv FAIL "in argv:$al"
else
  for t in S6a-nova-secret S6b-mode S6c-no-leak S6d-no-argv; do rec "$t" UNVERIFIED "no secrets file was created"; done
fi
# static guarantee: nova-manage must never be handed a URL containing a password
if grep -nE 'nova_manage .*(--database_connection|--transport-url)' "$H" | grep -q .; then
  rec S6e-no-dsn-argv FAIL "nova-manage is called with a connection/transport URL on the command line"
else
  rec S6e-no-dsn-argv PASS "nova-manage is never given a DSN on the command line (cell0 URL is derived from nova.conf)"
fi
grep -q 'list_cells' "$H" && ! grep -E 'list_cells' "$H" | grep -qE 'log_(info|ok) .*\$\(' \
  && rec S6f-cells-output PASS "cell listings are matched, never printed (they contain passwords)" \
  || rec S6f-cells-output FAIL "a cell listing may be echoed"

echo
echo "== S7. what this container cannot decide (sent to the GCE acceptance) =="
rec S7a-compute-api UNVERIFIED "authenticated compute API (:8774) and 'openstack compute service list': needs a live Keystone/Apache, which this container could not sustain in step 4 (Keystone client pool exhausted). Observed fact, cause not settled — re-check on GCE."
rec S7b-cells-runtime UNVERIFIED "nova-manage api_db/db sync, map_cell0 and create_cell actually running: they need the control plane up"
rec S7c-hypervisor UNVERIFIED "nova-compute, libvirtd, hypervisor registration and cell host discovery: nova-compute pulls libvirt and qemu, and there is no systemd or /dev/kvm here"
rec S7d-guest-boot UNVERIFIED "booting a guest VM: not attempted, and a container cannot prove it"
rec S7e-systemd UNVERIFIED "startup and ordering of nova-conductor/nova-scheduler/nova-compute under systemd: GCE B0a/B0b"
rec S7f-two-node UNVERIFIED "compute-add and Geneve between two nodes: GCE node1+node2"
rec S7g-neutron-api UNVERIFIED "the step 4 Neutron API items stay UNVERIFIED — this run does not revisit or reinterpret them"

printf 'MARIADB=%s\n' "${MARIADB_METHOD:-not started}" > /out/s5-start-methods.txt
df -m / | tail -1 >> /out/s5-start-methods.txt
echo
printf 'PASS=%d FAIL=%d UNVERIFIED=%d\n' "$P" "$F" "$U" | tee /out/s5-summary.txt
if [ "$F" -eq 0 ]; then exit 0; else exit 1; fi
