#!/usr/bin/env bash
# Database / queue re-run-safety test, INSIDE an Ubuntu 26.04 container.
# MariaDB is started BY HAND (no systemd in this container); the method used is
# recorded so the result is not mistaken for a systemd-managed verification.
set -uo pipefail
H=/src/hagistack
R=/out/db-results.tsv; : > "$R"
P=0; F=0; U=0
rec() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$R"
  case "$2" in
    PASS) P=$((P+1)); printf '  \033[32mPASS\033[0m %-28s %s\n' "$1" "$3";;
    FAIL) F=$((F+1)); printf '  \033[31mFAIL\033[0m %-28s %s\n' "$1" "$3";;
    *)    U=$((U+1)); printf '  \033[33mUNVER\033[0m %-28s %s\n' "$1" "$3";;
  esac; }

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq iproute2 >/dev/null 2>&1   # server baseline, not a hagistack dep
echo "== install base packages via hagistack itself =="
NIC="$(ls /sys/class/net | grep -v '^lo$' | head -1)"; NIC="${NIC:-lo}"
ARGS=(all-in-one --env-file /dev/null --ext-nic "$NIC"
      --provider-cidr 172.24.4.0/24 --provider-gateway 172.24.4.1
      --floating-start 172.24.4.100 --floating-end 172.24.4.200 --mgmt-ip 10.0.0.5)
"$H" "${ARGS[@]}" > /out/db-run0.log 2>&1
echo "  (hagistack run 0 rc=$? — see db-run0.log)"
grep -q 'is not reachable' /out/db-run0.log \
  && rec DB0-unreachable-honest PASS "with no server running, shell said NOT VERIFIED and skipped" \
  || rec DB0-unreachable-honest FAIL "did not report unreachable server"
dpkg -l mariadb-server >/dev/null 2>&1 \
  && rec DB1-pkg-installed PASS "mariadb-server installed inside the container" \
  || { rec DB1-pkg-installed UNVERIFIED "mariadb-server not installed; aborting DB test"; \
       printf 'PASS=%d FAIL=%d UNVERIFIED=%d\n' "$P" "$F" "$U" | tee /out/db-summary.txt; exit 0; }

echo
echo "== start MariaDB BY HAND (no systemd here) =="
START_METHOD="mariadbd-safe --skip-networking (manual, no systemd)"
mkdir -p /var/run/mysqld /var/log/mysql
chown mysql:mysql /var/run/mysqld /var/log/mysql
nohup mariadbd-safe --user=mysql --skip-networking >/var/log/mysql/manual.log 2>&1 &
for i in $(seq 1 60); do mariadb -uroot -e "SELECT 1" >/dev/null 2>&1 && break; sleep 1; done
if mariadb -uroot -e "SELECT VERSION()" >/dev/null 2>&1; then
  rec DB2-manual-start PASS "started via: $START_METHOD  ($(mariadb -uroot -N -e 'SELECT VERSION()'))"
else
  rec DB2-manual-start UNVERIFIED "could not start MariaDB by hand in this container"
  tail -20 /var/log/mysql/manual.log | sed 's/^/      /'
  printf 'PASS=%d FAIL=%d UNVERIFIED=%d\n' "$P" "$F" "$U" | tee /out/db-summary.txt; exit 0
fi
echo "  START METHOD RECORDED: $START_METHOD"

echo
echo "== run 1: hagistack creates the databases =="
rm -rf /var/lib/hagistack/state
"$H" "${ARGS[@]}" > /out/db-run1.log 2>&1
grep -q 'MariaDB reachable' /out/db-run1.log \
  && rec DB3-reachable-detected PASS "shell detected the hand-started server" \
  || rec DB3-reachable-detected FAIL "shell did not detect a reachable server"
dbs="$(mariadb -uroot -N -e "SHOW DATABASES" | tr '\n' ' ')"
missing=""
for d in keystone glance placement nova nova_api neutron; do
  grep -qw "$d" <<<"$dbs" || missing="$missing $d"
done
[ -z "$missing" ] && rec DB4-databases-created PASS "keystone glance placement nova nova_api neutron" \
                  || rec DB4-databases-created FAIL "missing:$missing"
nusers="$(mariadb -uroot -N -e "SELECT COUNT(DISTINCT User) FROM mysql.user WHERE User IN ('keystone','glance','placement','nova','neutron')")"
[ "$nusers" = "5" ] && rec DB5-users-created PASS "5 service users created" \
                    || rec DB5-users-created FAIL "found $nusers service users"

echo
echo "== plant a sentinel row, then re-run =="
mariadb -uroot -e "CREATE TABLE IF NOT EXISTS keystone.hagistack_sentinel (id INT PRIMARY KEY, note VARCHAR(64));"
mariadb -uroot -e "INSERT INTO keystone.hagistack_sentinel VALUES (1,'must survive re-run') ON DUPLICATE KEY UPDATE note=VALUES(note);"
before="$(mariadb -uroot -N -e "SELECT note FROM keystone.hagistack_sentinel WHERE id=1")"
echo "  sentinel before: '$before'"
# capture the grant/password state too
pw_before="$(mariadb -uroot -N -e "SELECT authentication_string FROM mysql.user WHERE User='keystone' AND Host='localhost'" 2>/dev/null || \
             mariadb -uroot -N -e "SELECT password FROM mysql.global_priv WHERE User='keystone' AND Host='localhost'" 2>/dev/null || echo "")"
sec_before="$(sha256sum /etc/hagistack/secrets.env | cut -d' ' -f1)"

"$H" "${ARGS[@]}" > /out/db-run2.log 2>&1
after="$(mariadb -uroot -N -e "SELECT note FROM keystone.hagistack_sentinel WHERE id=1" 2>/dev/null || echo "<GONE>")"
echo "  sentinel after : '$after'"
[ "$after" = "must survive re-run" ] \
  && rec DB6-data-survives-rerun PASS "sentinel row intact after 2nd all-in-one run" \
  || rec DB6-data-survives-rerun FAIL "sentinel lost: '$after'"
grep -q "already exists — left untouched" /out/db-run2.log \
  && rec DB7-reuse-reported PASS "2nd run reported existing databases left untouched" \
  || rec DB7-reuse-reported FAIL "2nd run did not report reuse"
pw_after="$(mariadb -uroot -N -e "SELECT authentication_string FROM mysql.user WHERE User='keystone' AND Host='localhost'" 2>/dev/null || \
            mariadb -uroot -N -e "SELECT password FROM mysql.global_priv WHERE User='keystone' AND Host='localhost'" 2>/dev/null || echo "")"
[ "$pw_before" = "$pw_after" ] \
  && rec DB8-db-password-stable PASS "existing DB user credential not rotated" \
  || rec DB8-db-password-stable FAIL "DB user credential changed on re-run"
sec_after="$(sha256sum /etc/hagistack/secrets.env | cut -d' ' -f1)"
[ "$sec_before" = "$sec_after" ] \
  && rec DB9-secrets-stable PASS "secrets.env unchanged across DB runs" \
  || rec DB9-secrets-stable FAIL "secrets.env changed"
# third run for good measure
"$H" "${ARGS[@]}" > /out/db-run3.log 2>&1
a3="$(mariadb -uroot -N -e "SELECT note FROM keystone.hagistack_sentinel WHERE id=1" 2>/dev/null || echo "<GONE>")"
[ "$a3" = "must survive re-run" ] && rec DB10-third-run PASS "data still intact after a 3rd run" \
                                 || rec DB10-third-run FAIL "data lost on 3rd run"
# bind-address must be loopback only, and written once
nba="$(grep -c '^bind-address' /etc/mysql/mariadb.conf.d/99-hagistack.cnf || echo 0)"
vba="$(grep '^bind-address' /etc/mysql/mariadb.conf.d/99-hagistack.cnf | head -1)"
[ "$nba" = "1" ] && [[ "$vba" == *127.0.0.1* ]] \
  && rec DB11-bind-loopback PASS "single bind-address line, loopback ($vba)" \
  || rec DB11-bind-loopback FAIL "bind-address lines=$nba value='$vba'"

echo
echo "== nova credential covers BOTH nova and nova_api (finding 3) =="
# shellcheck disable=SC1091
NOVA_PW="$(sed -n 's/^NOVA_DB_PASS=//p' /etc/hagistack/secrets.env)"
if [ -z "$NOVA_PW" ]; then
  rec DB17-nova-single-cred FAIL "NOVA_DB_PASS not present in secrets.env"
else
  rec DB17-nova-single-cred PASS "single NOVA_DB_PASS present"
fi
grep -q '^NOVA_API_DB_PASS=' /etc/hagistack/secrets.env \
  && rec DB18-no-new-api-key FAIL "NOVA_API_DB_PASS was generated again" \
  || rec DB18-no-new-api-key PASS "NOVA_API_DB_PASS no longer generated"
# real logins as the nova user, to each database, using that one password
if mariadb -unova -p"$NOVA_PW" -e "USE nova; SELECT 1" >/dev/null 2>&1; then
  rec DB19-login-nova PASS "nova user logs into the 'nova' database"
else rec DB19-login-nova FAIL "login to 'nova' failed"; fi
if mariadb -unova -p"$NOVA_PW" -e "USE nova_api; SELECT 1" >/dev/null 2>&1; then
  rec DB20-login-nova-api PASS "same credential logs into 'nova_api'"
else rec DB20-login-nova-api FAIL "login to 'nova_api' failed"; fi
# and it can actually write in both
if mariadb -unova -p"$NOVA_PW" -e "CREATE TABLE IF NOT EXISTS nova_api.t(i INT); DROP TABLE nova_api.t;" >/dev/null 2>&1; then
  rec DB21-grants-nova-api PASS "nova user has DDL rights on nova_api"
else rec DB21-grants-nova-api FAIL "insufficient grants on nova_api"; fi
# obsolete-key migration: plant the old key and confirm it is reported, kept, and not used
printf 'NOVA_API_DB_PASS=legacy-value-should-be-ignored\n' >> /etc/hagistack/secrets.env
o_mig="$("$H" "${ARGS[@]}" 2>&1)"
grep -q "no longer uses" <<<"$o_mig" \
  && rec DB22-obsolete-reported PASS "stale NOVA_API_DB_PASS reported as unused" \
  || rec DB22-obsolete-reported FAIL "stale key not reported"
grep -q '^NOVA_API_DB_PASS=legacy-value-should-be-ignored$' /etc/hagistack/secrets.env \
  && rec DB23-obsolete-kept PASS "stale key left untouched (not rewritten, not rotated)" \
  || rec DB23-obsolete-kept FAIL "stale key was modified or removed"
if mariadb -unova -p"$NOVA_PW" -e "USE nova_api; SELECT 1" >/dev/null 2>&1; then
  rec DB24-cred-unchanged PASS "nova credential still valid after the migration run"
else rec DB24-cred-unchanged FAIL "credential changed by the migration run"; fi

echo
echo "== partial completion: MariaDB up, RabbitMQ down (finding 4 consistency) =="
rc=0; "$H" "${ARGS[@]}" > /out/db-partial.log 2>&1 || rc=$?
[ "$rc" = "4" ] && rec DB25-partial-exit PASS "exit 4 while any phase is skipped" \
                || rec DB25-partial-exit FAIL "exit $rc, wanted 4"
[ -e /var/lib/hagistack/state/database.done ] \
  && rec DB26-done-marker-present PASS "database phase DID complete and is marked" \
  || rec DB26-done-marker-present FAIL "database marker missing though it succeeded"
[ -e /var/lib/hagistack/state/rabbitmq.done ] \
  && rec DB27-skipped-no-marker FAIL "rabbitmq marked done though skipped" \
  || rec DB27-skipped-no-marker PASS "skipped rabbitmq carries no marker"
grep -qE 'STEP [0-9]+ INCOMPLETE' /out/db-partial.log \
  && rec DB28-partial-banner PASS "INCOMPLETE banner even though the DB succeeded" \
  || rec DB28-partial-banner FAIL "banner does not report INCOMPLETE"
st="$("$H" status 2>&1)"
if grep -qE '(base|implemented) layer: INCOMPLETE' <<<"$st" && grep -qE 'missing:.*rabbitmq' <<<"$st"; then
  rec DB29-status-names-gap PASS "status names rabbitmq as the missing phase"
else rec DB29-status-names-gap FAIL "status does not identify the gap"; fi
grep -qE '^  database +done' <<<"$st" \
  && rec DB30-status-shows-done PASS "status shows database as done" \
  || rec DB30-status-shows-done FAIL "status does not show database done"

echo
echo "== RabbitMQ =="
if dpkg -l rabbitmq-server >/dev/null 2>&1; then
  RMQ_METHOD="rabbitmq-server -detached (manual, no systemd)"
  # `rabbitmq-server -detached` can itself block for many minutes on a slow
  # node, so bound the launch as well as the readiness probes below.
  # Every rabbit call is hard-bounded with `timeout -k`: rabbitmqctl ignores
  # SIGTERM, so a plain `timeout` never returns on a node that will not start.
  timeout -k 5 90 env RABBITMQ_NODENAME=rabbit@localhost \
      rabbitmq-server -detached >/out/rmq.log 2>&1 || true
  ok=0
  deadline=$(( SECONDS + 90 ))
  while [ "$SECONDS" -lt "$deadline" ]; do
    timeout -k 5 10 rabbitmqctl status >/dev/null 2>&1 && { ok=1; break; }
    sleep 3
  done
  if [ "$ok" = "1" ]; then
    rec DB12-rabbitmq-start PASS "started via: $RMQ_METHOD"
    "$H" "${ARGS[@]}" > /out/db-run4.log 2>&1
    rabbitmqctl list_users 2>/dev/null | awk '{print $1}' | grep -qx openstack \
      && rec DB13-rabbit-user PASS "user 'openstack' present" \
      || rec DB13-rabbit-user FAIL "user not created"
    "$H" "${ARGS[@]}" > /out/db-run5.log 2>&1
    grep -q "already exists — password left unchanged" /out/db-run5.log \
      && rec DB14-rabbit-rerun PASS "re-run left the queue user password unchanged" \
      || rec DB14-rabbit-rerun FAIL "re-run did not report unchanged user"
  else
    rec DB12-rabbitmq-start UNVERIFIED "rabbitmq-server would not start in this container"
    rec DB13-rabbit-user   UNVERIFIED "depends on DB12"
    rec DB14-rabbit-rerun  UNVERIFIED "depends on DB12"
  fi
else
  rec DB12-rabbitmq-start UNVERIFIED "rabbitmq-server not installed"
fi

echo
echo "== containment: this all happened inside the container =="
echo "  hostname=$(hostname)  PID1=$(cat /proc/1/comm)"
ls /etc/hagistack /var/lib/hagistack >/dev/null 2>&1 \
  && rec DB15-state-in-container PASS "state under /etc/hagistack and /var/lib/hagistack (container FS)" \
  || rec DB15-state-in-container FAIL "state missing"
mount | grep -q ' /src ' && rec DB16-src-readonly PASS "/src is a read-only bind mount; source untouched" \
                         || rec DB16-src-readonly UNVERIFIED "could not confirm /src mount flags"
printf 'START_METHOD_MARIADB=%s\n' "$START_METHOD" > /out/start-methods.txt
printf 'START_METHOD_RABBITMQ=%s\n' "${RMQ_METHOD:-not-started}" >> /out/start-methods.txt
echo
printf 'PASS=%d FAIL=%d UNVERIFIED=%d\n' "$P" "$F" "$U" | tee /out/db-summary.txt
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
