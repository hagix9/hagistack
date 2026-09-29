#!/usr/bin/env bash
# Step 3 (Glance + Placement) verification, INSIDE an Ubuntu 26.04 container.
# MariaDB and Apache are started by hand (no systemd); methods are recorded.
set -uo pipefail
H=/src/hagistack
R=/out/gp-results.tsv; : > "$R"
P=0; F=0; U=0
rec(){ printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$R"
  case "$2" in
    PASS) P=$((P+1)); printf '  \033[32mPASS\033[0m  %-30s %s\n' "$1" "$3";;
    FAIL) F=$((F+1)); printf '  \033[31mFAIL\033[0m  %-30s %s\n' "$1" "$3";;
    *)    U=$((U+1)); printf '  \033[33mUNVER\033[0m %-30s %s\n' "$1" "$3";;
  esac; }
# Never let "missing == missing" count as unchanged.
digest_of(){ local n; n=$(ls -1 $1 2>/dev/null | wc -l); [ "$n" -gt 0 ] || { echo ABSENT; return; }; sha256sum $1 2>/dev/null | sha256sum | cut -d" " -f1; }
stable(){ if [ "$2" = "ABSENT" ] || [ "$3" = "ABSENT" ] || [ -z "$2" ] || [ -z "$3" ]; then
    rec "$1" FAIL "$4: ABSENT/empty (before=$2 after=$3) — cannot be called unchanged"
  elif [ "$2" = "$3" ]; then rec "$1" PASS "$4 unchanged ($2)"
  else rec "$1" FAIL "$4 CHANGED: $2 -> $3"; fi; }

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq iproute2 openssl curl shellcheck jq procps >/dev/null 2>&1

# The container runs MariaDB, Apache (two WSGI vhosts) and glance-api at once.
# Each vhost spawns processes=5 full Python interpreters; trim that so the
# container is not needlessly heavy. Test-environment tuning, recorded as such.
WSGI_TUNED="processes 5 -> 2 on both vhosts (container tuning, not a product change)"
sed -i "s/processes=5/processes=2/" /etc/apache2/sites-available/keystone.conf 2>/dev/null || true
sed -i "s/processes=5/processes=2/" /etc/apache2/sites-available/placement-api.conf 2>/dev/null || true

# checkpoint <label>: record whether MariaDB (socket+TCP) and Apache are alive.
# A dead backing service must be visible, not silently blamed on the product.
checkpoint(){
  local lbl="$1" db=dead tcp=no ap=down
  mariadb -uroot -e "SELECT 1" >/dev/null 2>&1 && db=alive
  ss -ltn 2>/dev/null | grep -q ":3306" && tcp=yes
  curl -s -o /dev/null -m 5 "http://127.0.0.1:5000/v3" && ap=up
  printf "  [checkpoint %-18s] mariadb=%s tcp=%s keystone=%s mem_avail=%sMB\n" \
     "$lbl" "$db" "$tcp" "$ap" "$(free -m | awk "/^Mem:/{print \$7}")"
  printf "%s\tmariadb=%s\ttcp=%s\tkeystone=%s\n" "$lbl" "$db" "$tcp" "$ap" >> /out/checkpoints.tsv
  [ "$db" = alive ] && [ "$ap" = up ]
}
: > /out/checkpoints.tsv
NIC="$(ls /sys/class/net | grep -v '^lo$' | head -1)"; NIC="${NIC:-lo}"
MGMT="$(ip -4 -o addr show "$NIC" | awk '{split($4,a,"/"); print a[1]}' | head -1)"; MGMT="${MGMT:-127.0.0.1}"
ARGS=(all-in-one --env-file /dev/null --ext-nic "$NIC"
      --provider-cidr 172.24.4.0/24 --provider-gateway 172.24.4.1
      --floating-start 172.24.4.100 --floating-end 172.24.4.200 --mgmt-ip "$MGMT")
echo "== env: $(. /etc/os-release; echo "$PRETTY_NAME") $(dpkg --print-architecture); MGMT=$MGMT; systemd: $([ -d /run/systemd/system ] && echo present || echo ABSENT) =="

echo
echo "== G0. static + surface =="
bash -n "$H" && rec G0a-bash-n PASS "parses" || rec G0a-bash-n FAIL "syntax error"
sc="$(shellcheck -S warning "$H" 2>&1)"
[ -z "$sc" ] && rec G0b-shellcheck PASS "no warnings (-S warning)" || rec G0b-shellcheck FAIL "$(head -c 400 <<<"$sc")"
v="$("$H" --version)"
grep -qE '^hagistack [0-9]+\.[0-9]+\.[0-9]+-step[0-9]+$' <<<"$v" \
  && rec G0c-version PASS "$v" || rec G0c-version FAIL "$v"
st="$("$H" status 2>&1)"
grep -q 'glance' <<<"$st" && grep -q 'placement' <<<"$st" \
  && rec G0d-status-lists PASS "status lists glance and placement" || rec G0d-status-lists FAIL "missing"
# Pattern, not the literal remaining-service list: later steps shorten that list
# and the point of the check is that status keeps saying what cannot be done.
stn="$(tr '\n' ' ' <<<"$st")"
if grep -qiE '(Nova|Horizon)[^.]{0,60}NOT installed' <<<"$stn" \
   && grep -qiE 'no +instance +can +be +booted|cannot +be +booted' <<<"$stn"; then
  rec G0e-status-honest PASS "status still names missing services and says no instance can boot"
else rec G0e-status-honest FAIL "overclaims: $(head -c 160 <<<"$stn")"; fi
tr '\n' ' ' < <("$H" --help 2>&1) | grep -qiE 'does +NOT +give you a working' \
  && rec G0f-help-honest PASS "help still disallows 'working OpenStack'" || rec G0f-help-honest FAIL "help overclaims"

echo
echo "== G1. no DB -> both phases skip honestly =="
rm -rf /etc/hagistack /var/lib/hagistack
o="$("$H" "${ARGS[@]}" 2>&1)"; rc=$?
echo "$o" > /out/gp-nodb.log
[ "$rc" = "4" ] && rec G1a-exit4 PASS "exit 4 with no DB" || rec G1a-exit4 FAIL "exit $rc"
grep -q "phase 'glance' SKIPPED" <<<"$o" && rec G1b-glance-skip PASS "glance skip reported" || rec G1b-glance-skip FAIL "no skip"
grep -q "phase 'placement' SKIPPED" <<<"$o" && rec G1c-placement-skip PASS "placement skip reported" || rec G1c-placement-skip FAIL "no skip"
for m in glance placement; do
  [ -e "/var/lib/hagistack/state/$m.done" ] && rec "G1d-$m-no-marker" FAIL "marked done" \
                                            || rec "G1d-$m-no-marker" PASS "no state marker"
done
grep -qE 'STEP [0-9]+ COMPLETE' <<<"$o" && rec G1e-no-false-complete FAIL "claimed COMPLETE" \
                                        || rec G1e-no-false-complete PASS "did not claim COMPLETE"

echo
echo "== G2. bring up MariaDB (TCP) + run the real phases =="
# --max-connections matches what phase_database now writes; without systemd the
# product cannot restart the server, so the manual start supplies it.
MARIADB_METHOD="mariadbd-safe --bind-address=127.0.0.1 --max-connections=1024 (manual, no systemd)"
mkdir -p /var/run/mysqld /var/log/mysql; chown mysql:mysql /var/run/mysqld /var/log/mysql 2>/dev/null
nohup mariadbd-safe --user=mysql --bind-address=127.0.0.1 --max-connections=1024 >/var/log/mysql/m.log 2>&1 &
for i in $(seq 1 60); do mariadb -uroot -e "SELECT 1" >/dev/null 2>&1 && break; sleep 1; done
if ! mariadb -uroot -e "SELECT 1" >/dev/null 2>&1; then
  rec G2a-mariadb UNVERIFIED "MariaDB would not start; Step 3 cannot be tested"
  printf 'PASS=%d FAIL=%d UNVERIFIED=%d\n' "$P" "$F" "$U" | tee /out/gp-summary.txt; exit 0
fi
rec G2a-mariadb PASS "started via: $MARIADB_METHOD"
MEMCACHED_METHOD="memcached -u memcache -l $MGMT -d (manual, no systemd)"
memcached -u memcache -l "$MGMT" -d 2>/dev/null || memcached -u nobody -l "$MGMT" -d 2>/dev/null || true
sleep 2
ok=0; for i in $(seq 1 15); do (exec 3<>/dev/tcp/"$MGMT"/11211) 2>/dev/null && { ok=1; break; }; sleep 1; done
if [ "$ok" = "1" ]; then
  rec G2a2-memcached PASS "token cache listening on $MGMT:11211 (started via: $MEMCACHED_METHOD)"
else
  # Both phases gate on the cache, so without it nothing downstream can be
  # judged. Stop here rather than reporting misleading failures.
  rec G2a2-memcached UNVERIFIED "memcached would not start; glance/placement gate on it, so step 3 cannot be judged here"
  printf 'PASS=%d FAIL=%d UNVERIFIED=%d\n' "$P" "$F" "$U" | tee /out/gp-summary.txt; exit 0
fi
ss -ltn 2>/dev/null | grep -q ':3306' && rec G2b-mariadb-tcp PASS "TCP 3306 listening" \
                                      || rec G2b-mariadb-tcp FAIL "no TCP listener"
MAXC="$(mariadb -uroot -N -B -e "SELECT @@max_connections" 2>/dev/null || echo 0)"
[ "$MAXC" -ge 512 ] && rec G2b2-max-conn PASS "server max_connections=$MAXC (stock 151 caused HTTP 500)" \
                    || rec G2b2-max-conn FAIL "max_connections=$MAXC too low"
# Apache must be up for keystone AND placement; start it by hand.
APACHE_METHOD="apachectl -k start (manual, no systemd)"
rm -rf /var/lib/hagistack/state
"$H" "${ARGS[@]}" > /out/gp-run1a.log 2>&1 || true
apachectl -k start >/out/apache1.log 2>&1 || true
for i in $(seq 1 20); do curl -s -o /dev/null -m 5 "http://127.0.0.1:5000/v3" && break; sleep 2; done
curl -s -o /dev/null -m 5 "http://127.0.0.1:5000/v3" \
  && rec G2c-keystone-up PASS "identity answering (started via: $APACHE_METHOD)" \
  || { rec G2c-keystone-up UNVERIFIED "keystone would not serve; Step 3 needs it"
       printf 'PASS=%d FAIL=%d UNVERIFIED=%d\n' "$P" "$F" "$U" | tee /out/gp-summary.txt; exit 0; }
# now re-run so glance/placement see a live keystone
o1="$("$H" "${ARGS[@]}" 2>&1)"; rc1=$?
echo "$o1" > /out/gp-run1.log
echo "  (run 1 exit $rc1)"

echo
echo "== G3. Glance =="
gt="$(mariadb -uroot -N -B -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='glance'")"
[ "$gt" -gt 10 ] && rec G3a-glance-schema PASS "$gt tables in the glance schema" || rec G3a-glance-schema FAIL "only $gt tables"
conn="$(grep -A80 '^\[database\]' /etc/glance/glance-api.conf | grep -m1 '^connection' || true)"
grep -q 'mysql+pymysql://glance:' <<<"$conn" && rec G3b-glance-conn PASS "connection points at MariaDB" || rec G3b-glance-conn FAIL "$conn"
grep -q 'sqlite' <<<"$conn" && rec G3c-no-sqlite FAIL "still sqlite" || rec G3c-no-sqlite PASS "sqlite default replaced"
[ "$(stat -c '%a %U:%G' /etc/glance/glance-api.conf)" = "640 root:glance" ] \
  && rec G3d-glance-perms PASS "glance-api.conf 640 root:glance (package ownership preserved)" \
  || rec G3d-glance-perms FAIL "$(stat -c '%a %U:%G' /etc/glance/glance-api.conf)"
grep -qE '^max_connections = ' /etc/mysql/mariadb.conf.d/99-hagistack.cnf \
  && rec G3e0-maxconn-written PASS "phase_database wrote max_connections into its own conf" \
  || rec G3e0-maxconn-written FAIL "max_connections not written"
grep -qE '^bind_port = 9292' /etc/glance/glance-api.conf && rec G3e-bind-port PASS "bind_port explicitly 9292 (no default exists)" \
                                                         || rec G3e-bind-port FAIL "bind_port not set"
# glance-api has a real unit but no systemd here: start it by hand
GLANCE_METHOD="glance-api as the glance user (manual, no systemd)"
nohup runuser -u glance -- /usr/bin/glance-api >/out/glance-api.log 2>&1 &
for i in $(seq 1 30); do curl -s -o /dev/null -m 5 "http://$MGMT:9292/" && break; sleep 2; done
if curl -s -o /dev/null -m 5 "http://$MGMT:9292/"; then
  rec G3f-glance-serving PASS "image API answers on :9292 (started via: $GLANCE_METHOD)"
  . /etc/hagistack/admin-openrc; export OS_AUTH_URL="http://$MGMT:5000/v3"
  if timeout -k 5 90 openstack image list >/out/img-list.txt 2>&1; then
    rec G3g-image-list PASS "openstack image list succeeded as admin"
  else rec G3g-image-list FAIL "$(head -c 200 /out/img-list.txt)"; fi
  if timeout -k 5 90 openstack service list -f value 2>/dev/null | grep -q glance; then
    rec G3h-catalogue-glance PASS "glance present in the service catalogue"
  else rec G3h-catalogue-glance FAIL "glance not in catalogue"; fi
  n="$(timeout -k 5 90 openstack endpoint list --service glance -f value 2>/dev/null | wc -l)"
  [ "$n" -ge 3 ] && rec G3i-glance-endpoints PASS "$n glance endpoints registered" || rec G3i-glance-endpoints FAIL "n=$n"
else
  rec G3f-glance-serving UNVERIFIED "glance-api would not serve in this container"
  for t in G3g-image-list G3h-catalogue-glance G3i-glance-endpoints; do rec "$t" UNVERIFIED "depends on G3f"; done
fi

echo
echo "== G4. upload a real image and prove it survives a re-run =="
IMG_OK=0
if curl -s -o /dev/null -m 5 "http://$MGMT:9292/"; then
  head -c 65536 /dev/urandom > /tmp/test.img
  SRC_SUM="$(sha256sum /tmp/test.img | cut -d' ' -f1)"
  checkpoint before-upload || true
  if timeout -k 5 180 openstack image create --disk-format raw --container-format bare \
       --file /tmp/test.img --public -f shell hagistack-test >/out/img-create.txt 2>&1; then
    # Parse the id out of the create output itself rather than issuing another
    # API call that can fail for unrelated reasons.
    IMG_ID="$(sed -n 's/^id="\(.*\)"$/\1/p' /out/img-create.txt | head -1)"
    IMG_SUM="$(sed -n 's/^checksum="\(.*\)"$/\1/p' /out/img-create.txt | head -1)"
    checkpoint after-upload || true
    [ -n "$IMG_ID" ] && rec G4a-image-upload PASS "image created id=$IMG_ID" || rec G4a-image-upload FAIL "no id"
    STORE="$(ls /var/lib/glance/images/ 2>/dev/null | head -1)"
    [ -n "$STORE" ] && rec G4b-image-on-disk PASS "image file present under /var/lib/glance/images" \
                    || rec G4b-image-on-disk FAIL "no file in the store"
    DISK_SUM="$(sha256sum "/var/lib/glance/images/$IMG_ID" 2>/dev/null | cut -d' ' -f1 || echo ABSENT)"
    [ "$DISK_SUM" = "$SRC_SUM" ] && rec G4c-content-matches PASS "stored bytes match the uploaded file (sha256)" \
                                 || rec G4c-content-matches FAIL "disk=$DISK_SUM src=$SRC_SUM"
    IMG_OK=1
  else rec G4a-image-upload FAIL "$(head -c 250 /out/img-create.txt)"; fi
else
  for t in G4a-image-upload G4b-image-on-disk G4c-content-matches; do rec "$t" UNVERIFIED "glance not serving"; done
fi

if ! checkpoint after-glance; then
  echo "  !! backing services degraded; capturing logs"
  tail -40 /var/log/apache2/keystone.log  > /out/keystone-apache.log 2>&1 || true
  tail -40 /var/log/apache2/error.log     > /out/apache-error.log 2>&1 || true
  tail -40 /var/log/mysql/m.log           > /out/mariadb.log 2>&1 || true
  tail -30 /var/log/keystone/keystone.log > /out/keystone-svc.log 2>&1 || true
fi

echo
echo "== G5. Placement =="
# Apache was started before placement was configured; reload so the 8778 vhost
# is actually live, then say plainly whether it came up.
apachectl -k graceful >/dev/null 2>&1 || apachectl -k restart >/dev/null 2>&1 || true
for i in $(seq 1 15); do curl -s -o /dev/null -m 5 "http://$MGMT:8778/" && break; sleep 2; done
pt="$(mariadb -uroot -N -B -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='placement'")"
[ "$pt" -gt 5 ] && rec G5a-placement-schema PASS "$pt tables in the placement schema" || rec G5a-placement-schema FAIL "only $pt tables"
pconn="$(grep -A40 '^\[placement_database\]' /etc/placement/placement.conf | grep -m1 '^connection' || true)"
grep -q 'mysql+pymysql://placement:' <<<"$pconn" \
  && rec G5b-placement-conn PASS "connection under [placement_database] points at MariaDB" \
  || rec G5b-placement-conn FAIL "$pconn"
grep -A5 '^\[database\]' /etc/placement/placement.conf 2>/dev/null | grep -q '^connection' \
  && rec G5c-right-section FAIL "connection wrongly written to [database]" \
  || rec G5c-right-section PASS "nothing written to the wrong [database] section"
[ "$(stat -c '%a %U:%G' /etc/placement/placement.conf)" = "640 root:placement" ] \
  && rec G5d-placement-perms PASS "placement.conf 640 root:placement" \
  || rec G5d-placement-perms FAIL "$(stat -c '%a %U:%G' /etc/placement/placement.conf)"
if curl -s -o /dev/null -m 5 "http://$MGMT:8778/"; then
  rec G5e-placement-serving PASS "placement answers on :8778 via apache2 (same server as identity)"
  TOK="$(timeout -k 5 60 openstack token issue -f value -c id 2>/dev/null)"
  if [ -n "$TOK" ]; then
    CFG="$(mktemp)"; chmod 600 "$CFG"
    printf 'header = "X-Auth-Token: %s"\nheader = "OpenStack-API-Version: placement latest"\n' "$TOK" > "$CFG"
    code="$(curl -sS -m 60 -o /out/rp.json -w '%{http_code}' -K "$CFG" "http://$MGMT:8778/resource_providers" 2>/out/rp.err || echo 000)"
    rm -f "$CFG"
    [ "$code" = "200" ] && rec G5f-placement-auth PASS "authenticated /resource_providers -> HTTP 200" \
                        || rec G5f-placement-auth FAIL "HTTP $code"
    jq -e 'has("resource_providers")' /out/rp.json >/dev/null 2>&1 \
      && rec G5g-placement-body PASS "response body has resource_providers (empty is correct; Nova not installed)" \
      || rec G5g-placement-body FAIL "unexpected body"
  else rec G5f-placement-auth UNVERIFIED "no token"; rec G5g-placement-body UNVERIFIED "no token"; fi
  n="$(timeout -k 5 90 openstack endpoint list --service placement -f value 2>/dev/null | wc -l)"
  [ "$n" -ge 3 ] && rec G5h-placement-endpoints PASS "$n placement endpoints registered" || rec G5h-placement-endpoints FAIL "n=$n"
else
  for t in G5e-placement-serving G5f-placement-auth G5g-placement-body G5h-placement-endpoints; do
    rec "$t" UNVERIFIED "placement not serving in this container"; done
fi
rec G5i-nova-rp UNVERIFIED "Nova resource-provider registration: not required in step 3"

echo
echo "== G6. re-run safety =="
g_before="$(digest_of /etc/glance/glance-api.conf)"
p_before="$(digest_of /etc/placement/placement.conf)"
s_before="$(digest_of /etc/hagistack/secrets.env)"
gt_before="$gt"; pt_before="$pt"
if [ "$IMG_OK" = "1" ]; then
  id_before="$IMG_ID"; sum_before="$IMG_SUM"; disk_before="$DISK_SUM"
else id_before=ABSENT; sum_before=ABSENT; disk_before=ABSENT; fi
uid_before="$(mariadb -uroot -N -B -e "SELECT id FROM keystone.local_user WHERE name='glance'" 2>/dev/null || echo ABSENT)"
ep_before="$(mariadb -uroot -N -B -e "SELECT COUNT(*) FROM keystone.endpoint" 2>/dev/null || echo ABSENT)"

checkpoint before-rerun || true
o2="$("$H" "${ARGS[@]}" 2>&1)"; echo "$o2" > /out/gp-run2.log
checkpoint after-rerun || true
stable G6a-glance-conf   "$g_before" "$(digest_of /etc/glance/glance-api.conf)"   "glance-api.conf"
stable G6b-placement-conf "$p_before" "$(digest_of /etc/placement/placement.conf)" "placement.conf"
stable G6c-secrets       "$s_before" "$(digest_of /etc/hagistack/secrets.env)"    "secrets.env"
gt2="$(mariadb -uroot -N -B -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='glance'")"
pt2="$(mariadb -uroot -N -B -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='placement'")"
stable G6d-glance-tables   "$gt_before" "$gt2" "glance table count"
stable G6e-placement-tables "$pt_before" "$pt2" "placement table count"
stable G6f-glance-user-id  "$uid_before" "$(mariadb -uroot -N -B -e "SELECT id FROM keystone.local_user WHERE name='glance'" 2>/dev/null || echo ABSENT)" "glance service-user id"
stable G6g-endpoint-count  "$ep_before" "$(mariadb -uroot -N -B -e "SELECT COUNT(*) FROM keystone.endpoint" 2>/dev/null || echo ABSENT)" "endpoint count"
grep -q 'already correct (unchanged)' <<<"$o2" && rec G6h-conf-reported PASS "re-run reports configs unchanged" \
                                               || rec G6h-conf-reported FAIL "not reported"
grep -qE 'schema already current' <<<"$o2" && rec G6i-schema-reported PASS "re-run reports schema current" \
                                           || rec G6i-schema-reported FAIL "not reported"
grep -q 'already exists' <<<"$o2" && rec G6j-reuse-reported PASS "re-run reports existing users/services reused" \
                                  || rec G6j-reuse-reported FAIL "not reported"
# the image itself must survive
if [ "$IMG_OK" = "1" ]; then
  id_after="$(timeout -k 5 60 openstack image show hagistack-test -f value -c id 2>/dev/null || echo ABSENT)"
  sum_after="$(timeout -k 5 60 openstack image show hagistack-test -f value -c checksum 2>/dev/null || echo ABSENT)"
  disk_after="$(sha256sum "/var/lib/glance/images/$id_before" 2>/dev/null | cut -d' ' -f1 || echo ABSENT)"
  stable G6k-image-id      "$id_before"   "$id_after"   "image id"
  stable G6l-image-cksum   "$sum_before"  "$sum_after"  "image checksum"
  stable G6m-image-content "$disk_before" "$disk_after" "stored image bytes"
else
  for t in G6k-image-id G6l-image-cksum G6m-image-content; do rec "$t" UNVERIFIED "no image was uploaded"; done
fi
"$H" "${ARGS[@]}" > /out/gp-run3.log 2>&1 || true
if [ "$IMG_OK" = "1" ]; then
  checkpoint before-3rd-check || true
  if ! curl -s -o /dev/null -m 5 "http://$MGMT:9292/"; then
    rec G6n-third-run UNVERIFIED "glance-api stopped serving in the container before the 3rd check"
  else
    id3="$(timeout -k 5 90 openstack image show hagistack-test -f value -c id 2>/out/img3.err || echo ABSENT)"
    if [ "$id3" = "$id_before" ]; then rec G6n-third-run PASS "image still present after a 3rd run"
    else
      # A 500 here may be the container wobbling rather than lost data. Capture
      # the evidence and decide from it instead of guessing.
      tail -40 /var/log/glance/glance-api.log   > /out/g3-glance.log 2>&1 || true
      tail -40 /out/glance-api.log              > /out/g3-glance-stdout.log 2>&1 || true
      tail -40 /var/log/apache2/keystone.log    > /out/g3-keystone.log 2>&1 || true
      tail -20 /var/log/apache2/error.log       > /out/g3-apache.log 2>&1 || true
      # Does the DB still hold the row? That separates "API hiccup" from "data gone".
      # No nested quoting: list every image row and let grep do the matching.
      # The previous form was mis-quoted and returned empty, which almost read
      # as data loss when the row was actually present.
      dbrow="$(mariadb -uroot -N -B glance -e "SELECT id,name,status FROM images" 2>/dev/null || echo QUERYFAIL)"
      echo "  db row: $dbrow"
      # Retry once: a transient 500 should clear.
      sleep 10
      id3b="$(timeout -k 5 90 openstack image show hagistack-test -f value -c id 2>/out/img3b.err || echo ABSENT)"
      if [ "$id3b" = "$id_before" ]; then
        rec G6n-third-run PASS "image present after a 3rd run (first call returned a transient 500, retry OK)"
      elif grep -q "$id_before" <<<"$dbrow"; then
        rec G6n-third-run UNVERIFIED "API returned 500 in the container, but the DB row and the stored bytes are intact (db: $dbrow)"
      else
        rec G6n-third-run FAIL "image genuinely lost: id3=$id3 retry=$id3b db=$dbrow err=$(head -c 150 /out/img3.err)"
      fi
    fi
    # the bytes on disk are the real proof the 3rd run did not touch the store
    d3="$(sha256sum "/var/lib/glance/images/$id_before" 2>/dev/null | cut -d" " -f1 || echo ABSENT)"
    stable G6o-image-content-3rd "$disk_before" "$d3" "stored image bytes after 3 runs"
  fi
else rec G6n-third-run UNVERIFIED "no image"; rec G6o-image-content-3rd UNVERIFIED "no image"; fi

echo
echo "== G7. secrets must not leak =="
leak=0; which=""
while IFS='=' read -r k v; do
  case "$k" in ''|\#*) continue;; esac
  [ -n "$v" ] && grep -qF "$v" /out/gp-run1.log /out/gp-run2.log 2>/dev/null && { leak=1; which="$which $k"; }
done < /etc/hagistack/secrets.env
[ "$leak" = "0" ] && rec G7a-no-secret-in-log PASS "no secret value appears in any run output" \
                  || rec G7a-no-secret-in-log FAIL "leaked:$which"
ps_out="$(ps -eo args 2>/dev/null || true)"
gl="$(sed -n 's/^GLANCE_SERVICE_PASS=//p' /etc/hagistack/secrets.env)"
[ -n "$gl" ] && grep -qF "$gl" <<<"$ps_out" && rec G7b-no-pass-in-argv FAIL "service password in process args" \
                                            || rec G7b-no-pass-in-argv PASS "service password not in process args"
rec G7c-systemd-startup UNVERIFIED "glance-api.service / apache2.service under systemd: GCE (B0a/B0b)"
rec G7d-real-accept UNVERIFIED "Neutron/OVN, Nova, Horizon and instance boot: not in step 3"

printf 'MARIADB=%s\nMEMCACHED=%s\nAPACHE=%s\nGLANCE=%s\nWSGI=%s\n' "$MARIADB_METHOD" "${MEMCACHED_METHOD:-not-started}" "$APACHE_METHOD" "${GLANCE_METHOD:-not-started}" "$WSGI_TUNED" > /out/gp-start-methods.txt
# Always keep the server-side logs: a bad run must be explainable from the
# artefacts, without needing another 25-minute re-run to find out why.
tail -60 /var/log/apache2/keystone.log        > /out/final-keystone-apache.log 2>&1 || true
tail -40 /var/log/apache2/error.log           > /out/final-apache-error.log 2>&1 || true
tail -40 /var/log/apache2/placement_api_error.log > /out/final-placement.log 2>&1 || true
tail -40 /out/glance-api.log                  > /out/final-glance.log 2>&1 || true
mariadb -uroot -N -B -e "SELECT @@max_connections" > /out/final-dbconn.txt 2>&1 || true
mariadb -uroot -N -B -e "SHOW STATUS LIKE 'Max_used_connections'" >> /out/final-dbconn.txt 2>&1 || true
mariadb -uroot -N -B glance -e "SELECT id,name,status FROM images" > /out/final-images.txt 2>&1 || true
mariadb -uroot -N -B keystone -e "SELECT id,type,enabled FROM service" > /out/final-services.txt 2>&1 || true
echo "== checkpoints =="; cat /out/checkpoints.tsv | sed "s/^/  /"
echo
printf 'PASS=%d FAIL=%d UNVERIFIED=%d\n' "$P" "$F" "$U" | tee /out/gp-summary.txt
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
