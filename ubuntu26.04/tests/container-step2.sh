#!/usr/bin/env bash
# Step 2 (Keystone) verification, INSIDE an Ubuntu 26.04 container.
# MariaDB is started by hand (no systemd here); the method is recorded.
set -uo pipefail
H=/src/hagistack
R=/out/ks-results.tsv; : > "$R"
P=0; F=0; U=0
rec(){ printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$R"
  case "$2" in
    PASS) P=$((P+1)); printf '  \033[32mPASS\033[0m  %-32s %s\n' "$1" "$3";;
    FAIL) F=$((F+1)); printf '  \033[31mFAIL\033[0m  %-32s %s\n' "$1" "$3";;
    *)    U=$((U+1)); printf '  \033[33mUNVER\033[0m %-32s %s\n' "$1" "$3";;
  esac; }

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq iproute2 openssl curl shellcheck >/dev/null 2>&1
NIC="$(ls /sys/class/net | grep -v '^lo$' | head -1)"; NIC="${NIC:-lo}"
MGMT="$(ip -4 -o addr show "$NIC" | awk '{split($4,a,"/"); print a[1]}' | head -1)"; MGMT="${MGMT:-127.0.0.1}"
ARGS=(all-in-one --env-file /dev/null --ext-nic "$NIC"
      --provider-cidr 172.24.4.0/24 --provider-gateway 172.24.4.1
      --floating-start 172.24.4.100 --floating-end 172.24.4.200 --mgmt-ip "$MGMT")
echo "== env: $(. /etc/os-release; echo "$PRETTY_NAME") $(dpkg --print-architecture); MGMT=$MGMT; systemd dir: $([ -d /run/systemd/system ] && echo present || echo ABSENT) =="

echo
echo "== K0. static + CLI surface after the Step 2 change =="
bash -n "$H" && rec K0a-bash-n PASS "parses" || rec K0a-bash-n FAIL "syntax error"
if command -v shellcheck >/dev/null 2>&1; then
  sc="$(shellcheck -S warning "$H" 2>&1)"
  [ -z "$sc" ] && rec K0b-shellcheck PASS "no warnings (-S warning)" \
               || rec K0b-shellcheck FAIL "$(head -c 400 <<<"$sc")"
else rec K0b-shellcheck UNVERIFIED "shellcheck not installed"; fi
v="$("$H" --version 2>&1)"
grep -qE '^hagistack [0-9]+\.[0-9]+\.[0-9]+-step[0-9]+$' <<<"$v" \
  && rec K0c-version PASS "$v" || rec K0c-version FAIL "$v"
hlp="$("$H" --help 2>&1)"
grep -q -- '--region-name' <<<"$hlp" && rec K0d-region-flag PASS "--region-name documented" \
                                     || rec K0d-region-flag FAIL "flag undocumented"
tr '\n' ' ' <<<"$hlp" | grep -qiE 'does +NOT +give you a working' \
  && rec K0e-help-honest PASS "help states it is not a working OpenStack" \
  || rec K0e-help-honest FAIL "help overclaims"
st="$("$H" status 2>&1)"
grep -q 'keystone' <<<"$st" && rec K0f-status-keystone PASS "status mentions keystone" \
                            || rec K0f-status-keystone FAIL "no keystone in status"
grep -qE 'are NOT installed' <<<"$st" \
  && rec K0g-status-honest PASS "status states what is missing" \
  || rec K0g-status-honest FAIL "status overclaims"

echo
echo "== K1. region validation + precedence =="
cfgval(){ sed -n "s/^[[:space:]]*$2[[:space:]]\+\([^[:space:]]*\)[[:space:]]*\[\(.*\)\]$/\1|\2/p" <<<"$1" | head -1; }
o="$("$H" all-in-one --check "${ARGS[@]:1}" 2>&1)"
[ "$(cfgval "$o" REGION_NAME)" = "RegionOne|default" ] \
  && rec K1a-region-default PASS "RegionOne [default]" \
  || rec K1a-region-default FAIL "got $(cfgval "$o" REGION_NAME)"
o="$(REGION_NAME=EnvRegion "$H" all-in-one --check "${ARGS[@]:1}" 2>&1)"
[ "$(cfgval "$o" REGION_NAME)" = "EnvRegion|environment" ] \
  && rec K1b-region-env PASS "EnvRegion [environment]" \
  || rec K1b-region-env FAIL "got $(cfgval "$o" REGION_NAME)"
o="$(REGION_NAME=EnvRegion "$H" all-in-one --check "${ARGS[@]:1}" --region-name CliRegion 2>&1)"
[ "$(cfgval "$o" REGION_NAME)" = "CliRegion|command line" ] \
  && rec K1c-region-cli PASS "CliRegion [command line]" \
  || rec K1c-region-cli FAIL "got $(cfgval "$o" REGION_NAME)"
out="$("$H" all-in-one --check "${ARGS[@]:1}" --region-name 'bad region!' 2>&1)"; rc=$?
[ "$rc" != "0" ] && grep -q 'is not valid' <<<"$out" \
  && rec K1d-region-invalid PASS "bad region refused (rc=$rc)" || rec K1d-region-invalid FAIL "rc=$rc"
printf 'EXT_NIC=%s\nREGION_NAME=$(touch /tmp/KSPWN)\n' "$NIC" > /tmp/ks.env
rm -f /tmp/KSPWN
"$H" all-in-one --check --env-file /tmp/ks.env "${ARGS[@]:3}" >/dev/null 2>&1
[ -e /tmp/KSPWN ] && rec K1e-region-no-exec FAIL "config value executed" \
                  || rec K1e-region-no-exec PASS "command substitution in REGION_NAME not executed"

echo
echo "== K2. run all-in-one with NO database (must skip keystone honestly) =="
rm -rf /etc/hagistack /var/lib/hagistack
o="$("$H" "${ARGS[@]}" 2>&1)"; rc=$?
echo "$o" > /out/ks-nodb.log
[ "$rc" = "4" ] && rec K2a-exit4 PASS "exit 4 with no DB" || rec K2a-exit4 FAIL "exit $rc"
grep -q "phase 'keystone' SKIPPED" <<<"$o" && rec K2b-skip-reported PASS "keystone skip reported" \
                                           || rec K2b-skip-reported FAIL "no skip message"
[ -e /var/lib/hagistack/state/keystone.done ] && rec K2c-no-marker FAIL "keystone marked done" \
                                              || rec K2c-no-marker PASS "no keystone state marker"
grep -q 'STEP 2 COMPLETE' <<<"$o" && rec K2d-no-false-complete FAIL "claimed COMPLETE" \
                                  || rec K2d-no-false-complete PASS "did not claim COMPLETE"

echo
echo "== K3. start MariaDB by hand and run the real keystone phase =="
# --bind-address=127.0.0.1, NOT --skip-networking: Keystone talks to MariaDB
# with mysql+pymysql over TCP, so a socket-only server cannot serve it. Measured:
# skip-networking -> db_sync creates 0 tables; loopback TCP -> 49 tables.
START_METHOD="mariadbd-safe --bind-address=127.0.0.1 (manual, no systemd)"
mkdir -p /var/run/mysqld /var/log/mysql; chown mysql:mysql /var/run/mysqld /var/log/mysql 2>/dev/null
nohup mariadbd-safe --user=mysql --bind-address=127.0.0.1 >/var/log/mysql/manual.log 2>&1 &
for i in $(seq 1 60); do mariadb -uroot -e "SELECT 1" >/dev/null 2>&1 && break; sleep 1; done
if ! mariadb -uroot -e "SELECT 1" >/dev/null 2>&1; then
  rec K3a-mariadb-start UNVERIFIED "MariaDB would not start; keystone DB work cannot be tested"
  printf 'PASS=%d FAIL=%d UNVERIFIED=%d\n' "$P" "$F" "$U" | tee /out/ks-summary.txt; exit 0
fi
rec K3a-mariadb-start PASS "started via: $START_METHOD ($(mariadb -uroot -N -e 'SELECT VERSION()'))"
if ss -ltn 2>/dev/null | grep -q ':3306'; then
  rec K3a2-mariadb-tcp PASS "MariaDB is listening on TCP 3306 (what pymysql needs)"
else
  rec K3a2-mariadb-tcp FAIL "no TCP listener on 3306; keystone cannot connect"
fi
echo "  START METHOD RECORDED: $START_METHOD"
rm -rf /var/lib/hagistack/state
o1="$("$H" "${ARGS[@]}" 2>&1)"; rc1=$?
echo "$o1" > /out/ks-run1.log
echo "  (run 1 exit $rc1)"

grep -q 'keystone.conf updated' <<<"$o1" && rec K3b-conf-written PASS "keystone.conf updated" \
                                         || rec K3b-conf-written FAIL "conf not updated"
conn="$(grep -A50 '^\[database\]' /etc/keystone/keystone.conf | grep -m1 '^connection' || true)"
grep -q 'mysql+pymysql://keystone:' <<<"$conn" && rec K3c-conn-mysql PASS "connection points at MariaDB" \
                                               || rec K3c-conn-mysql FAIL "conn='$conn'"
grep -q 'sqlite' <<<"$conn" && rec K3d-no-sqlite FAIL "still sqlite" || rec K3d-no-sqlite PASS "sqlite default replaced"
[ "$(stat -c '%a %U:%G' /etc/keystone/keystone.conf)" = "640 keystone:keystone" ] \
  && rec K3e-conf-perms PASS "keystone.conf 640 keystone:keystone" \
  || rec K3e-conf-perms FAIL "$(stat -c '%a %U:%G' /etc/keystone/keystone.conf)"
tbl="$(mariadb -uroot -N -B -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='keystone'")"
[ "$tbl" -gt 20 ] && rec K3f-db-sync PASS "$tbl tables in the keystone schema" \
                  || rec K3f-db-sync FAIL "only $tbl tables"
[ -s /etc/keystone/fernet-keys/0 ] && rec K3g-fernet PASS "fernet keys present ($(ls /etc/keystone/fernet-keys | tr '\n' ' '))" \
                                   || rec K3g-fernet FAIL "no fernet keys"
[ -s /etc/keystone/credential-keys/0 ] && rec K3h-credkeys PASS "credential keys present" \
                                       || rec K3h-credkeys FAIL "no credential keys"
own="$(stat -c '%U:%G' /etc/keystone/fernet-keys/0)"
[ "$own" = "keystone:keystone" ] && rec K3i-key-owner PASS "fernet key owned by keystone" \
                                 || rec K3i-key-owner FAIL "owned by $own"
adm="$(mariadb -uroot -N -B -e "SELECT COUNT(*) FROM keystone.local_user WHERE name='admin'" 2>/dev/null || echo 0)"
[ "$adm" = "1" ] && rec K3j-bootstrap-user PASS "admin user present in the identity DB" \
                 || rec K3j-bootstrap-user FAIL "admin rows=$adm"
ep="$(mariadb -uroot -N -B -e "SELECT COUNT(*) FROM keystone.endpoint" 2>/dev/null || echo 0)"
[ "$ep" -ge 3 ] && rec K3k-bootstrap-endpoints PASS "$ep identity endpoints in the catalogue" \
                || rec K3k-bootstrap-endpoints FAIL "endpoints=$ep"
[ "$(stat -c '%a' /etc/hagistack/admin-openrc)" = "600" ] \
  && rec K3l-openrc-perms PASS "admin-openrc mode 600" \
  || rec K3l-openrc-perms FAIL "mode $(stat -c '%a' /etc/hagistack/admin-openrc 2>/dev/null)"

echo
echo "== K4. secrets must not leak =="
leak=0; which=""
while IFS='=' read -r k v; do
  case "$k" in ''|\#*) continue;; esac
  [ -n "$v" ] && grep -qF "$v" /out/ks-run1.log && { leak=1; which="$which $k"; }
done < /etc/hagistack/secrets.env
[ "$leak" = "0" ] && rec K4a-no-secret-in-log PASS "no secret value appears in the run output" \
                  || rec K4a-no-secret-in-log FAIL "leaked:$which"
# the DB password must be in keystone.conf (it has to be) but the file must stay 0640
grep -q "$(sed -n 's/^KEYSTONE_DB_PASS=//p' /etc/hagistack/secrets.env)" /etc/keystone/keystone.conf \
  && rec K4b-conn-has-pass PASS "DB password present in keystone.conf (0640, expected)" \
  || rec K4b-conn-has-pass FAIL "connection string lacks the password"
ps_out="$(ps -eo args 2>/dev/null || true)"
grep -q "$(sed -n 's/^ADMIN_PASSWORD=//p' /etc/hagistack/secrets.env)" <<<"$ps_out" \
  && rec K4c-no-pass-in-argv FAIL "admin password visible in process args" \
  || rec K4c-no-pass-in-argv PASS "admin password not visible in process args"
grep -qE 'bootstrap-password|OS_BOOTSTRAP_PASSWORD=' /out/ks-run1.log \
  && rec K4d-no-bootstrap-echo FAIL "bootstrap password echoed" \
  || rec K4d-no-bootstrap-echo PASS "bootstrap password never echoed"

echo
echo "== K5. re-run safety: data, keys and credentials must survive =="
mariadb -uroot -e "CREATE TABLE IF NOT EXISTS keystone.hagistack_sentinel (id INT PRIMARY KEY, note VARCHAR(64));"
mariadb -uroot -e "INSERT INTO keystone.hagistack_sentinel VALUES (1,'keystone must survive') ON DUPLICATE KEY UPDATE note=VALUES(note);"
# digest_of <glob-or-path>: prints a digest ONLY if something is really there,
# otherwise prints the literal ABSENT. Without this, "missing == missing"
# compares equal and a stability check passes vacuously.
digest_of(){ local n; n=$(ls -1 $1 2>/dev/null | wc -l); [ "$n" -gt 0 ] || { echo ABSENT; return; }; sha256sum $1 2>/dev/null | sha256sum | cut -d" " -f1; }
f_before="$(digest_of '/etc/keystone/fernet-keys/*')"
c_before="$(digest_of '/etc/keystone/credential-keys/*')"
s_before="$(digest_of /etc/hagistack/secrets.env)"
r_before="$(digest_of /etc/hagistack/admin-openrc)"
k_before="$(digest_of /etc/keystone/keystone.conf)"
u_before="$(mariadb -uroot -N -B -e "SELECT COUNT(*) FROM keystone.user" 2>/dev/null || echo ABSENT)"
aid_before="$(mariadb -uroot -N -B -e "SELECT id FROM keystone.local_user WHERE name='admin'" 2>/dev/null || echo ABSENT)"
pw_before="$(mariadb -uroot -N -B -e "SELECT password_hash FROM keystone.password ORDER BY id DESC LIMIT 1" 2>/dev/null || echo ABSENT)"
o2="$("$H" "${ARGS[@]}" 2>&1)"; echo "$o2" > /out/ks-run2.log
sent="$(mariadb -uroot -N -B -e "SELECT note FROM keystone.hagistack_sentinel WHERE id=1" 2>/dev/null || echo '<GONE>')"
[ "$sent" = "keystone must survive" ] && rec K5a-data-survives PASS "sentinel row intact after re-run" \
                                      || rec K5a-data-survives FAIL "sentinel='$sent'"
stable(){ # stable <id> <before> <after> <label>
  if [ "$2" = "ABSENT" ] || [ "$3" = "ABSENT" ]; then
     rec "$1" FAIL "$4: artefact ABSENT (before=$2 after=$3) — cannot be called stable"
  elif [ "$2" = "$3" ]; then rec "$1" PASS "$4 unchanged"
  else rec "$1" FAIL "$4 CHANGED across the re-run"; fi; }
stable K5b-fernet-stable   "$f_before" "$(digest_of '/etc/keystone/fernet-keys/*')"      "fernet keys"
stable K5c-credkeys-stable "$c_before" "$(digest_of '/etc/keystone/credential-keys/*')"  "credential keys"
stable K5d-secrets-stable  "$s_before" "$(digest_of /etc/hagistack/secrets.env)"         "secrets.env"
stable K5e-openrc-stable   "$r_before" "$(digest_of /etc/hagistack/admin-openrc)"        "admin-openrc"
stable K5f-conf-stable     "$k_before" "$(digest_of /etc/keystone/keystone.conf)"        "keystone.conf"
grep -q 'already correct (unchanged)' <<<"$o2" && rec K5g-conf-reported PASS "re-run reports conf unchanged" \
                                               || rec K5g-conf-reported FAIL "not reported"
grep -q 'fernet token keys already present' <<<"$o2" && rec K5h-fernet-reported PASS "re-run reports keys untouched" \
                                                     || rec K5h-fernet-reported FAIL "not reported"
grep -q 'identity schema already current' <<<"$o2" && rec K5i-schema-reported PASS "re-run reports schema current" \
                                                   || rec K5i-schema-reported FAIL "not reported"
u_after="$(mariadb -uroot -N -B -e "SELECT COUNT(*) FROM keystone.user" 2>/dev/null || echo ABSENT)"
if [ "$u_before" = "ABSENT" ] || [ "$u_after" = "ABSENT" ] || [ -z "$u_after" ]; then
  rec K5j-no-dup-users FAIL "keystone.user table not queryable (before=$u_before after=$u_after)"
elif [ "$u_before" = "$u_after" ] && [ "$u_after" -ge 1 ]; then
  rec K5j-no-dup-users PASS "user count stable at $u_after across the re-run"
else rec K5j-no-dup-users FAIL "$u_before -> $u_after"; fi
# the bootstrapped admin must keep its identity and credential across re-runs
aid_after="$(mariadb -uroot -N -B -e "SELECT id FROM keystone.local_user WHERE name='admin'" 2>/dev/null || echo ABSENT)"
if [ "${aid_before:-ABSENT}" = "ABSENT" ] || [ "$aid_after" = "ABSENT" ]; then
  rec K5l-admin-id-stable FAIL "admin row not queryable (before=${aid_before:-ABSENT} after=$aid_after)"
elif [ "$aid_before" = "$aid_after" ]; then
  rec K5l-admin-id-stable PASS "bootstrapped admin keeps the same id across the re-run"
else rec K5l-admin-id-stable FAIL "admin id changed: $aid_before -> $aid_after"; fi
pw_after="$(mariadb -uroot -N -B -e "SELECT password_hash FROM keystone.password ORDER BY id DESC LIMIT 1" 2>/dev/null || echo ABSENT)"
if [ "${pw_before:-ABSENT}" = "ABSENT" ] || [ "$pw_after" = "ABSENT" ]; then
  rec K5m-admin-cred-stable FAIL "password row not queryable"
elif [ "$pw_before" = "$pw_after" ]; then
  rec K5m-admin-cred-stable PASS "stored admin credential unchanged by the re-run"
else rec K5m-admin-cred-stable FAIL "admin credential was rewritten"; fi
# third run
"$H" "${ARGS[@]}" > /out/ks-run3.log 2>&1
s3="$(mariadb -uroot -N -B -e "SELECT note FROM keystone.hagistack_sentinel WHERE id=1" 2>/dev/null || echo '<GONE>')"
[ "$s3" = "keystone must survive" ] && rec K5k-third-run PASS "data intact after a 3rd run" \
                                    || rec K5k-third-run FAIL "lost on 3rd run"

echo
echo "== K6. serving + authentication (needs apache; no systemd here) =="
if [ -d /run/systemd/system ]; then
  rec K6a-apache-systemd UNVERIFIED "unexpected: systemd present in container, not the tested path"
else
  if grep -q "phase 'keystone' SKIPPED" /out/ks-run1.log; then
    rec K6a-apache-skip-honest PASS "no systemd -> keystone reported SKIPPED: $(grep -m1 -A1 "phase 'keystone' SKIPPED" /out/ks-run1.log | tail -1 | sed 's/^ *//' | cut -c1-60)"
  else
    rec K6a-apache-skip-honest FAIL "keystone phase neither completed nor reported a skip"
  fi
  [ -e /var/lib/hagistack/state/keystone.done ] \
    && rec K6b-no-marker-unserved FAIL "keystone marked done though not served" \
    || rec K6b-no-marker-unserved PASS "keystone NOT marked done while unserved"
fi
# Try apache by hand so the endpoint/auth path is at least attempted.
APACHE_METHOD="apachectl -k start (manual, no systemd)"
if command -v apachectl >/dev/null 2>&1; then
  apachectl -k start >/out/apache-start.log 2>&1 || true
  ok=0; for i in $(seq 1 20); do
    curl -s -o /dev/null -m 5 "http://127.0.0.1:5000/v3" && { ok=1; break; }; sleep 2
  done
  if [ "$ok" = "1" ]; then
    rec K6c-endpoint-manual PASS "identity endpoint answers (started via: $APACHE_METHOD)"
    . /etc/hagistack/admin-openrc
    export OS_AUTH_URL="http://127.0.0.1:5000/v3"
    if timeout -k 5 60 openstack token issue >/dev/null 2>&1; then
      rec K6d-admin-auth PASS "admin authenticated; token issued (value not shown)"
    else
      rec K6d-admin-auth UNVERIFIED "endpoint answers but 'openstack token issue' failed here"
    fi
    if timeout -k 5 60 openstack endpoint list >/out/endpoints.txt 2>&1; then
      n="$(grep -c keystone /out/endpoints.txt || echo 0)"
      [ "$n" -ge 3 ] && rec K6e-catalogue PASS "$n keystone endpoints in the catalogue" \
                     || rec K6e-catalogue UNVERIFIED "catalogue listed but only $n keystone rows"
    else rec K6e-catalogue UNVERIFIED "endpoint list failed"; fi
  else
    rec K6c-endpoint-manual UNVERIFIED "apache would not serve :5000 in this container"
    rec K6d-admin-auth      UNVERIFIED "depends on K6c"
    rec K6e-catalogue       UNVERIFIED "depends on K6c"
  fi
else
  rec K6c-endpoint-manual UNVERIFIED "apachectl not present"
fi
rec K6f-systemd-startup UNVERIFIED "apache2.service startup + unit ordering: GCE acceptance (B0a/B0b)"
rec K6g-openstack-accept UNVERIFIED "real OpenStack acceptance (Glance..Horizon): not in step 2"

printf 'START_METHOD_MARIADB=%s\n' "$START_METHOD" > /out/ks-start-methods.txt
printf 'START_METHOD_APACHE=%s\n' "${APACHE_METHOD:-not-attempted}" >> /out/ks-start-methods.txt
echo
printf 'PASS=%d FAIL=%d UNVERIFIED=%d\n' "$P" "$F" "$U" | tee /out/ks-summary.txt
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
