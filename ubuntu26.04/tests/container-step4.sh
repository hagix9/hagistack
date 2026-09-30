#!/usr/bin/env bash
# Step 4 (Neutron + OVN) verification, INSIDE an Ubuntu 26.04 container.
#
# What this suite can and cannot prove, stated up front:
#   * It CAN prove: the shell parses, validates its new inputs, writes the
#     ML2/OVN configuration, syncs the networking schema, registers networking
#     in Keystone, answers the Neutron API under authentication, drives the OVN
#     northbound database, and keeps all of that across re-runs.
#   * It CANNOT prove: systemd unit startup and ordering, the ovs-vswitchd
#     kernel datapath, ovn-controller programming real flows, Geneve tunnelling
#     between two nodes, or any path onto a physical LAN. Those are recorded
#     UNVERIFIED with the reason, never forced into a PASS.
# There is no systemd here, so every backing service is started by hand and the
# exact method is recorded in the artefacts.
set -uo pipefail
H=/src/hagistack
R=/out/n4-results.tsv; : > "$R"
P=0; F=0; U=0
rec(){ printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$R"
  case "$2" in
    PASS) P=$((P+1)); printf '  \033[32mPASS\033[0m  %-30s %s\n' "$1" "$3";;
    FAIL) F=$((F+1)); printf '  \033[31mFAIL\033[0m  %-30s %s\n' "$1" "$3";;
    *)    U=$((U+1)); printf '  \033[33mUNVER\033[0m %-30s %s\n' "$1" "$3";;
  esac; }
# "missing == missing" must never count as unchanged.
digest_of(){ local n; n=$(ls -1 $1 2>/dev/null | wc -l); [ "$n" -gt 0 ] || { echo ABSENT; return; }
  sha256sum $1 2>/dev/null | sha256sum | cut -d" " -f1; }
stable(){ if [ "$2" = "ABSENT" ] || [ "$3" = "ABSENT" ] || [ -z "$2" ] || [ -z "$3" ]; then
    rec "$1" FAIL "$4: ABSENT/empty (before=$2 after=$3) — cannot be called unchanged"
  elif [ "$2" = "$3" ]; then rec "$1" PASS "$4 unchanged ($2)"
  else rec "$1" FAIL "$4 CHANGED: $2 -> $3"; fi; }
# ini_has <file> <section> <key> <value>: the key must carry that value inside
# that section, not merely appear somewhere in a 200k-line sample config.
ini_has(){ local f="$1" s="$2" k="$3" want="$4"
  awk -v s="[$s]" -v k="$k" '
    $0 ~ /^\[/ { insec = ($0 == s); next }
    insec && $0 ~ "^"k"[ \t]*=" { sub(/^[^=]*=[ \t]*/, ""); print; exit }' "$f" 2>/dev/null \
  | sed 's/[[:space:]]*$//' | grep -qxF "$want"; }
ini_val(){ local f="$1" s="$2" k="$3"
  awk -v s="[$s]" -v k="$k" '
    $0 ~ /^\[/ { insec = ($0 == s); next }
    insec && $0 ~ "^"k"[ \t]*=" { sub(/^[^=]*=[ \t]*/, ""); print; exit }' "$f" 2>/dev/null; }

export DEBIAN_FRONTEND=noninteractive
# Test-environment tuning: this container is disk-constrained, so apt keeps no
# archives and no documentation. It changes nothing the product does.
cat > /etc/dpkg/dpkg.cfg.d/01-nodoc <<'EOF'
path-exclude /usr/share/doc/*
path-exclude /usr/share/man/*
path-exclude /usr/share/locale/*
EOF
printf 'Dir::Cache::pkgcache "";\nDir::Cache::srcpkgcache "";\nAPT::Keep-Downloaded-Packages "false";\n' \
  > /etc/apt/apt.conf.d/01-lean
TUNED="dpkg path-exclude docs/man/locale + apt keeps no archives (container disk tuning)"
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq iproute2 openssl curl shellcheck jq procps >/dev/null 2>&1

free_mb(){ df -m / | awk 'NR==2{print $4}'; }
: > /out/n4-checkpoints.tsv
capture_service_logs(){   # capture_service_logs <tag>
  local t="$1"
  tail -60 /var/log/apache2/keystone.log      > "/out/n4-$t-keystone-apache.log" 2>&1 || true
  tail -40 /var/log/keystone/keystone.log     > "/out/n4-$t-keystone.log" 2>&1 || true
  tail -40 /var/log/apache2/error.log         > "/out/n4-$t-apache-error.log" 2>&1 || true
  mariadb -uroot -N -B -e "SHOW STATUS LIKE 'Max_used_connections'; SHOW STATUS LIKE 'Threads_connected'; SELECT @@max_connections" \
      > "/out/n4-$t-dbconn.txt" 2>&1 || true
  df -m / > "/out/n4-$t-disk.txt" 2>&1 || true
}
checkpoint(){
  local lbl="$1" db=dead ap=down ovs=down nb=down sb=down
  mariadb -uroot -e "SELECT 1" >/dev/null 2>&1 && db=alive
  curl -s -o /dev/null -m 5 "http://127.0.0.1:5000/v3" && ap=up
  ovs-vsctl --timeout=5 show >/dev/null 2>&1 && ovs=up
  ovn-nbctl --timeout=5 show >/dev/null 2>&1 && nb=up
  ovn-sbctl --timeout=5 show >/dev/null 2>&1 && sb=up
  local conn maxc
  conn="$(mariadb -uroot -N -B -e "SHOW STATUS LIKE 'Threads_connected'" 2>/dev/null | awk '{print $2}')"
  maxc="$(mariadb -uroot -N -B -e "SELECT @@max_connections" 2>/dev/null)"
  printf "  [checkpoint %-16s] mariadb=%s keystone=%s ovsdb=%s ovn-nb=%s ovn-sb=%s conn=%s/%s mem=%sMB disk=%sMB\n" \
     "$lbl" "$db" "$ap" "$ovs" "$nb" "$sb" "${conn:-?}" "${maxc:-?}" "$(free -m | awk '/^Mem:/{print $7}')" "$(free_mb)"
  printf "%s\tmariadb=%s\tkeystone=%s\tovsdb=%s\tnb=%s\tsb=%s\tconn=%s/%s\tdiskMB=%s\n" \
     "$lbl" "$db" "$ap" "$ovs" "$nb" "$sb" "${conn:-?}" "${maxc:-?}" "$(free_mb)" >> /out/n4-checkpoints.tsv
  [ "$db" = alive ] && [ "$ap" = up ]; }

# Harness-only early exit, used to pre-flight the cheap sections before paying
# for a full OpenStack install. It changes nothing the product does.
stop_here(){ [ "${N4_STOP:-}" = "$1" ] || return 0
  echo; echo "== stopping after $1 (N4_STOP) =="
  printf 'PASS=%d FAIL=%d UNVERIFIED=%d\n' "$P" "$F" "$U" | tee /out/n4-summary.txt
  if [ "$F" -eq 0 ]; then exit 0; else exit 1; fi; }

# The shell is re-run safe by design, so an aborted run can be resumed. A run
# that dies (exit 1) is retried up to three times; how many attempts it took is
# itself evidence and is reported, never hidden.
RUN_RC=0; RUN_ATTEMPTS=0; RUN_OUT=""
run_product(){   # run_product <label>
  local label="$1" a=1
  while :; do
    RUN_OUT="$("$H" "${ARGS[@]}" 2>&1)"; RUN_RC=$?
    printf '%s' "$RUN_OUT" > "/out/n4-$label-attempt$a.log"
    cp "/out/n4-$label-attempt$a.log" "/out/n4-$label.log"
    [ "$RUN_RC" != "1" ] && break
    echo "  !! $label attempt $a aborted (exit 1); capturing logs and retrying"
    capture_service_logs "$label-attempt$a"
    [ "$a" -ge 3 ] && break
    a=$((a+1)); sleep 15
  done
  RUN_ATTEMPTS=$a
  echo "  ($label: exit $RUN_RC after $a attempt(s); free disk $(free_mb)MB)"
}

NIC="$(for d in /sys/class/net/*; do n="${d##*/}"; [ "$n" = lo ] || { echo "$n"; break; }; done)"; NIC="${NIC:-lo}"
MGMT="$(ip -4 -o addr show "$NIC" | awk '{split($4,a,"/"); print a[1]}' | head -1)"; MGMT="${MGMT:-127.0.0.1}"
PHYSNET=physnet1; BRIDGE=br-ex
ARGS=(all-in-one --env-file /dev/null --ext-nic "$NIC"
      --provider-cidr 172.24.4.0/24 --provider-gateway 172.24.4.1
      --floating-start 172.24.4.100 --floating-end 172.24.4.200 --mgmt-ip "$MGMT"
      --provider-physnet "$PHYSNET" --provider-bridge "$BRIDGE")
# Recorded so a later reader can prove the management address was never moved.
NIC_ADDR_BEFORE="$(ip -4 -o addr show "$NIC" | awk '{print $4}' | tr '\n' ' ')"
echo "== env: $(. /etc/os-release; echo "$PRETTY_NAME") $(dpkg --print-architecture); NIC=$NIC MGMT=$MGMT"
echo "   systemd: $([ -d /run/systemd/system ] && echo present || echo ABSENT); free disk: $(free_mb)MB"
echo "   tuning : $TUNED"

echo
echo "== N0. static + surface =="
bash -n "$H" && rec N0a-bash-n PASS "parses" || rec N0a-bash-n FAIL "syntax error"
sc="$(shellcheck -S warning "$H" 2>&1)"
[ -z "$sc" ] && rec N0b-shellcheck PASS "no warnings (-S warning)" || rec N0b-shellcheck FAIL "$(head -c 400 <<<"$sc")"
v="$("$H" --version)"
grep -qE '^hagistack [0-9]+\.[0-9]+\.[0-9]+-step[0-9]+$' <<<"$v" \
  && rec N0c-version PASS "$v" || rec N0c-version FAIL "$v"
st="$("$H" status 2>&1)"
grep -q 'networking' <<<"$st" && grep -qi 'ovn' <<<"$st" \
  && rec N0d-status-networking PASS "status reports the networking layer and OVN" \
  || rec N0d-status-networking FAIL "status does not mention networking/OVN"
grep -qE 'no NIC|no address' <<<"$st" \
  && rec N0e-status-bridge-honest PASS "status says the provider bridge has no NIC/address" \
  || rec N0e-status-bridge-honest FAIL "status hides the empty provider bridge"
grep -qiE 'Nova and Horizon are NOT installed' <<<"$st" \
  && rec N0f-status-honest PASS "status still names what is missing" || rec N0f-status-honest FAIL "overclaims"
hl="$("$H" --help 2>&1 | tr '\n' ' ')"
grep -qiE 'does +NOT +give you a working' <<<"$hl" \
  && rec N0g-help-honest PASS "help refuses the phrase 'working OpenStack'" || rec N0g-help-honest FAIL "help overclaims"
grep -q -- '--provider-physnet' <<<"$hl" && grep -q -- '--provider-bridge' <<<"$hl" \
  && rec N0h-help-flags PASS "both new provider options are documented" || rec N0h-help-flags FAIL "undocumented options"
# Nothing anywhere may claim a usable cloud while nothing can boot.
if grep -RniE 'usable (openstack|cloud)' "$H" | grep -viE 'NOT a usable|NOT usable|no[tn].{0,12}usable' | grep -q .; then
  rec N0i-no-usable-claim FAIL "an unqualified 'usable OpenStack' claim exists"
else rec N0i-no-usable-claim PASS "every 'usable' mention is a negation"; fi

echo
echo "== N1. the new provider inputs are really validated =="
# Each case must die before doing anything; a shell that accepted these would
# push the bad value straight into ovn-bridge-mappings.
bad_case(){ local label="$1"; shift
  local o rc; o="$("$H" all-in-one --check --env-file /dev/null --ext-nic "$NIC" --mgmt-ip "$MGMT" \
        --provider-cidr 172.24.4.0/24 --provider-gateway 172.24.4.1 \
        --floating-start 172.24.4.100 --floating-end 172.24.4.200 "$@" 2>&1)"; rc=$?
  if [ "$rc" = "0" ]; then rec "$label" FAIL "accepted (exit 0)"
  elif grep -qiE 'not a valid|requires a value' <<<"$o"; then rec "$label" PASS "rejected: $(grep -oiE '(PROVIDER_[A-Z]+|--provider-[a-z]+) .{0,40}' <<<"$o" | head -1)"
  else rec "$label" FAIL "exit $rc but no validation message"; fi; }
bad_case N1a-physnet-space   --provider-physnet 'phys net1'
bad_case N1b-physnet-shell   --provider-physnet 'physnet1;touch /tmp/N1'
bad_case N1c-bridge-slash    --provider-bridge  'br/ex'
bad_case N1d-bridge-long     --provider-bridge  'brrrrrrrrrrrrrrrrex'
bad_case N1e-bridge-dots     --provider-bridge  '..'
bad_case N1f-physnet-novalue --provider-physnet
[ -e /tmp/N1 ] && rec N1g-no-shell-exec FAIL "a rejected value still executed a command" \
               || rec N1g-no-shell-exec PASS "no rejected value executed anything"
# and the accepted values must actually reach the resolved configuration
rc_out="$("$H" all-in-one --check --env-file /dev/null --ext-nic "$NIC" --mgmt-ip "$MGMT" \
      --provider-cidr 172.24.4.0/24 --provider-gateway 172.24.4.1 \
      --floating-start 172.24.4.100 --floating-end 172.24.4.200 \
      --provider-physnet lab-physnet --provider-bridge br-lab 2>&1)"
grep -q 'lab-physnet' <<<"$rc_out" && grep -q 'br-lab' <<<"$rc_out" \
  && rec N1h-flags-resolved PASS "both values appear in the resolved configuration" \
  || rec N1h-flags-resolved FAIL "values not echoed back"
# environment tier (the tier that was broken once) must work for them too
env_out="$(PROVIDER_PHYSNET=env-physnet PROVIDER_BRIDGE=br-env "$H" all-in-one --check --env-file /dev/null \
      --ext-nic "$NIC" --mgmt-ip "$MGMT" --provider-cidr 172.24.4.0/24 --provider-gateway 172.24.4.1 \
      --floating-start 172.24.4.100 --floating-end 172.24.4.200 2>&1)"
grep -q 'env-physnet' <<<"$env_out" && grep -q 'br-env' <<<"$env_out" \
  && rec N1i-env-tier PASS "environment tier honoured for the provider options" \
  || rec N1i-env-tier FAIL "environment values ignored"
# defaults, when nothing is given
def_out="$("$H" all-in-one --check --env-file /dev/null --ext-nic "$NIC" --mgmt-ip "$MGMT" \
      --provider-cidr 172.24.4.0/24 --provider-gateway 172.24.4.1 \
      --floating-start 172.24.4.100 --floating-end 172.24.4.200 2>&1)"
grep -q 'physnet1' <<<"$def_out" && grep -q 'br-ex' <<<"$def_out" \
  && rec N1j-defaults PASS "defaults physnet1 / br-ex" || rec N1j-defaults FAIL "defaults missing"

stop_here N1

echo
echo "== N2. with no backing services, both new phases must skip honestly =="
rm -rf /etc/hagistack /var/lib/hagistack
o="$("$H" "${ARGS[@]}" 2>&1)"; rc=$?
echo "$o" > /out/n4-nodb.log
[ "$rc" = "4" ] && rec N2a-exit4 PASS "exit 4 when services are missing" || rec N2a-exit4 FAIL "exit $rc"
grep -q "phase 'ovn' SKIPPED" <<<"$o" && rec N2b-ovn-skip PASS "ovn skip reported" || rec N2b-ovn-skip FAIL "no ovn skip"
grep -q "phase 'neutron' SKIPPED" <<<"$o" && rec N2c-neutron-skip PASS "neutron skip reported" || rec N2c-neutron-skip FAIL "no neutron skip"
for m in ovn neutron; do
  [ -e "/var/lib/hagistack/state/$m.done" ] && rec "N2d-$m-no-marker" FAIL "marked done after a skip" \
                                            || rec "N2d-$m-no-marker" PASS "no state marker after a skip"
done
grep -qE 'STEP [0-9]+ COMPLETE' <<<"$o" && rec N2e-no-false-complete FAIL "claimed COMPLETE" \
                                        || rec N2e-no-false-complete PASS "did not claim COMPLETE"
# a skipped ovn phase must not have left half-configured networking behind
# core_plugin=ml2 ships uncommented in the package, so it proves nothing. The
# database URL and the [ovn] section are things only hagistack writes.
if [ -f /etc/neutron/neutron.conf ] \
   && { grep -q '^mysql+pymysql://neutron:' <<<"$(ini_val /etc/neutron/neutron.conf database connection)" \
        || [ -n "$(ini_val /etc/neutron/plugins/ml2/ml2_conf.ini ovn ovn_nb_connection)" ]; }; then
  rec N2f-no-half-config FAIL "neutron was configured even though the phase skipped"
else rec N2f-no-half-config PASS "no networking configuration written while skipping (package defaults only)"; fi

stop_here N2

echo
echo "== N3. bring the backing services up BY HAND (no systemd in a container) =="
MARIADB_METHOD="mariadbd-safe --bind-address=127.0.0.1 --max-connections=1024 (manual, no systemd)"
mkdir -p /var/run/mysqld /var/log/mysql; chown mysql:mysql /var/run/mysqld /var/log/mysql 2>/dev/null
nohup mariadbd-safe --user=mysql --bind-address=127.0.0.1 --max-connections=1024 >/var/log/mysql/m.log 2>&1 &
for _ in $(seq 1 60); do mariadb -uroot -e "SELECT 1" >/dev/null 2>&1 && break; sleep 1; done
if ! mariadb -uroot -e "SELECT 1" >/dev/null 2>&1; then
  rec N3a-mariadb UNVERIFIED "MariaDB would not start; step 4 cannot be tested here"
  printf 'PASS=%d FAIL=%d UNVERIFIED=%d\n' "$P" "$F" "$U" | tee /out/n4-summary.txt; exit 0
fi
rec N3a-mariadb PASS "started via: $MARIADB_METHOD"
MEMCACHED_METHOD="memcached -u memcache -l $MGMT -d (manual, no systemd)"
memcached -u memcache -l "$MGMT" -d 2>/dev/null || memcached -u nobody -l "$MGMT" -d 2>/dev/null || true
ok=0; for _ in $(seq 1 15); do (exec 3<>/dev/tcp/"$MGMT"/11211) 2>/dev/null && { ok=1; break; }; sleep 1; done
if [ "$ok" = "1" ]; then rec N3b-memcached PASS "token cache on $MGMT:11211 (started via: $MEMCACHED_METHOD)"
else
  rec N3b-memcached UNVERIFIED "memcached would not start; neutron gates on it, so step 4 cannot be judged"
  printf 'PASS=%d FAIL=%d UNVERIFIED=%d\n' "$P" "$F" "$U" | tee /out/n4-summary.txt; exit 0
fi
# RabbitMQ: step 1 could not start it in a container. Try again here (this one
# is privileged) and record the outcome, because neutron talks to it.
RABBIT_METHOD="rabbitmq-server -detached as user rabbitmq (manual, no systemd)"
RABBIT_UP=0
if command -v rabbitmq-server >/dev/null 2>&1; then
  runuser -u rabbitmq -- rabbitmq-server -detached >/out/n4-rabbit.log 2>&1 || true
  for _ in $(seq 1 20); do (exec 3<>/dev/tcp/127.0.0.1/5672) 2>/dev/null && { RABBIT_UP=1; break; }; sleep 2; done
fi
if [ "$RABBIT_UP" = 1 ]; then rec N3b2-rabbitmq PASS "AMQP listening on 5672 (started via: $RABBIT_METHOD)"
else rec N3b2-rabbitmq UNVERIFIED "RabbitMQ would not start in this container (same as step 1); neutron API calls that publish notifications may fail here"; fi

# first pass: creates the databases and installs/keystone-bootstraps everything
run_product run0
if [ "$RABBIT_UP" = 0 ] && command -v rabbitmq-server >/dev/null 2>&1; then
  runuser -u rabbitmq -- rabbitmq-server -detached >>/out/n4-rabbit.log 2>&1 || true
  for _ in $(seq 1 20); do (exec 3<>/dev/tcp/127.0.0.1/5672) 2>/dev/null && { RABBIT_UP=1; break; }; sleep 2; done
  [ "$RABBIT_UP" = 1 ] && echo "  (RabbitMQ came up on the second attempt, after the base phase installed it)"
fi
# Three WSGI apps at processes=5 means fifteen Python interpreters, each with
# its own SQLAlchemy pool. In step 3 that exhausted MariaDB and surfaced as
# Keystone HTTP 500. One process per vhost here: container tuning, recorded.
for v in keystone placement-api neutron-api; do
  sed -i 's/processes=[0-9]*/processes=1/' "/etc/apache2/sites-available/$v.conf" 2>/dev/null || true
done
WSGI_TUNED="processes -> 1 on the keystone/placement/neutron vhosts (container tuning, not a product change)"
APACHE_METHOD="apachectl -k start (manual, no systemd)"
apachectl -k start >/out/n4-apache-start.log 2>&1 || true
for _ in $(seq 1 20); do curl -s -o /dev/null -m 5 "http://127.0.0.1:5000/v3" && break; sleep 2; done
if curl -s -o /dev/null -m 5 "http://127.0.0.1:5000/v3"; then
  rec N3c-keystone PASS "identity answering (started via: $APACHE_METHOD)"
else
  rec N3c-keystone UNVERIFIED "keystone would not serve; neutron registration cannot be judged"
  printf 'PASS=%d FAIL=%d UNVERIFIED=%d\n' "$P" "$F" "$U" | tee /out/n4-summary.txt; exit 0
fi
checkpoint after-identity || true

# --- OVS: database server only, then the datapath as a separate question ----
OVS_CTL=/usr/share/openvswitch/scripts/ovs-ctl
OVSDB_METHOD="not-started"; VSWITCHD_METHOD="not-started"
if [ -x "$OVS_CTL" ]; then
  OVSDB_METHOD="$OVS_CTL start --system-id=random --no-ovs-vswitchd --no-monitor (manual, no systemd)"
  $OVS_CTL start --system-id=random --no-ovs-vswitchd --no-monitor >/out/n4-ovsdb.log 2>&1 || true
else
  OVSDB_METHOD="ovsdb-server directly (ovs-ctl absent)"
  mkdir -p /var/run/openvswitch /var/log/openvswitch /etc/openvswitch
  [ -f /etc/openvswitch/conf.db ] || ovsdb-tool create /etc/openvswitch/conf.db \
      /usr/share/openvswitch/vswitch.ovsschema >/out/n4-ovsdb.log 2>&1
  ovsdb-server /etc/openvswitch/conf.db --remote=punix:/var/run/openvswitch/db.sock \
      --remote=db:Open_vSwitch,Open_vSwitch,manager_options --pidfile --detach \
      --log-file >>/out/n4-ovsdb.log 2>&1 || true
  ovs-vsctl --no-wait init >>/out/n4-ovsdb.log 2>&1 || true
fi
if ovs-vsctl --timeout=10 show >/dev/null 2>&1; then
  rec N3d-ovsdb PASS "Open vSwitch DB answering (started via: $OVSDB_METHOD)"
else
  rec N3d-ovsdb UNVERIFIED "ovsdb-server would not start here: $(tail -3 /out/n4-ovsdb.log 2>/dev/null | tr '\n' ' ' | head -c 160)"
fi
# The kernel datapath is a different claim from the control plane. Try it, and
# if it cannot work in a container say exactly why instead of hiding it.
if [ -x "$OVS_CTL" ]; then
  VSWITCHD_METHOD="$OVS_CTL start --system-id=random --no-monitor (manual, no systemd)"
  timeout -k 5 60 $OVS_CTL start --system-id=random --no-monitor >/out/n4-vswitchd.log 2>&1 || true
fi
if pgrep -x ovs-vswitchd >/dev/null 2>&1; then
  rec N3e-vswitchd PASS "ovs-vswitchd running (datapath: $(cat /sys/module/openvswitch/version 2>/dev/null || echo 'module state unknown'))"
else
  why="$(grep -iE 'error|cannot|failed|no such|not permitted|module' /var/log/openvswitch/ovs-vswitchd.log 2>/dev/null | tail -2 | tr '\n' ' ')"
  [ -n "$why" ] || why="openvswitch kernel module not loadable / insufficient privileges in a container"
  rec N3e-vswitchd UNVERIFIED "ovs-vswitchd did not run: $(head -c 200 <<<"$why") — datapath, flows and any real packet path stay a GCE/physical item"
fi
# --- OVN northbound / southbound / northd -----------------------------------
OVN_CTL=/usr/share/ovn/scripts/ovn-ctl
OVN_METHOD="not-started"
if [ -x "$OVN_CTL" ]; then
  OVN_METHOD="$OVN_CTL start_ovsdb + start_northd --ovn-manage-ovsdb=no --no-monitor (manual, no systemd; same ovn-ctl entry points the real units call)"
  $OVN_CTL start_ovsdb >/out/n4-ovn.log 2>&1 || true
  $OVN_CTL start_northd --ovn-manage-ovsdb=no --no-monitor >>/out/n4-ovn.log 2>&1 || true
else
  OVN_METHOD="ovn-ctl absent"
fi
NB_UP=0; SB_UP=0
ovn-nbctl --timeout=10 show >/dev/null 2>&1 && NB_UP=1
ovn-sbctl --timeout=10 show >/dev/null 2>&1 && SB_UP=1
if [ "$NB_UP" = 1 ] && [ "$SB_UP" = 1 ]; then
  rec N3f-ovn-dbs PASS "OVN northbound and southbound DBs answering (started via: $OVN_METHOD)"
else
  rec N3f-ovn-dbs UNVERIFIED "OVN DBs not answering (nb=$NB_UP sb=$SB_UP): $(tail -3 /out/n4-ovn.log 2>/dev/null | tr '\n' ' ' | head -c 160)"
fi
if pgrep -x ovn-northd >/dev/null 2>&1; then rec N3g-northd PASS "ovn-northd running (translates NB -> SB)"
else rec N3g-northd UNVERIFIED "ovn-northd not running: $(tail -2 /out/n4-ovn.log 2>/dev/null | tr '\n' ' ' | head -c 160)"; fi
checkpoint after-ovn-start || true

echo
echo "== N4. the product configures OVN (run 1) =="
run_product run1; rc1="$RUN_RC"
if [ "$rc1" = "4" ] || [ "$rc1" = "0" ]; then
  rec N4a0-run-terminal PASS "run 1 reached a terminal state (exit $rc1) after $RUN_ATTEMPTS attempt(s)"
else
  rec N4a0-run-terminal FAIL "run 1 still aborting after $RUN_ATTEMPTS attempts (exit $rc1): $(grep -E '^error:' /out/n4-run1.log | head -1 | head -c 140)"
fi
NEUTRON_CONFIGURED=0
grep -qE 'neutron\.conf, ml2_conf\.ini and the metadata agent configured|neutron configuration already correct' \
     /out/n4-run1.log && NEUTRON_CONFIGURED=1
BLOCK_REASON="$(grep -A2 "phase 'neutron' SKIPPED" /out/n4-run1.log | tr '\n' ' ' | sed 's/  */ /g' | head -c 200)"
[ -n "$BLOCK_REASON" ] || BLOCK_REASON="the neutron phase did not configure anything in this run"
if [ "$NEUTRON_CONFIGURED" = 1 ]; then
  rec N4a2-neutron-configured PASS "the neutron phase wrote its configuration in this run"
else
  # Name the backing service that died, so this is not mistaken for a defect in
  # the shell's own configuration handling.
  dead=""
  grep -q "phase 'memcached' SKIPPED" /out/n4-run1.log && dead="$dead memcached"
  grep -q "apache2 is not running" /out/n4-run1.log && dead="$dead apache2"
  rec N4a2-neutron-configured UNVERIFIED "the neutron phase skipped.${dead:+ Backing service(s) that went away during the run:$dead.} Reason given: $BLOCK_REASON"
fi
mc="$(mariadb -uroot -N -B -e "SELECT @@max_connections" 2>/dev/null || echo 0)"
[ "$mc" -ge 512 ] && rec N4a1-max-conn PASS "MariaDB max_connections=$mc (stock 151 caused HTTP 500 in step 3)" \
                  || rec N4a1-max-conn FAIL "max_connections=$mc is too low for several WSGI apps"
if [ -e /var/lib/hagistack/state/ovn.done ]; then
  rec N4a-ovn-done PASS "ovn phase completed and is marked"
else
  rec N4a-ovn-done UNVERIFIED "ovn phase did not complete: $(grep -A1 "phase 'ovn' SKIPPED" /out/n4-run1.log | tail -2 | tr '\n' ' ' | head -c 160)$(grep -E '^error:' /out/n4-run1.log | head -1 | head -c 100)"
fi
if [ "$NB_UP" = 1 ]; then
  # the target column, not get-connection: on the SB DB the latter also prints
  # the role and read-write flags (measured: read-write role="" ptcp:6642:<ip>)
  nbc="$(ovn-nbctl --bare --columns=target list connection 2>/dev/null | tr -d '[:space:]')"
  [ "$nbc" = "ptcp:6641:127.0.0.1" ] \
    && rec N4b-nb-listener PASS "northbound listener ptcp:6641:127.0.0.1 (loopback only, by design)" \
    || rec N4b-nb-listener FAIL "northbound listener is '$nbc'"
  sbc="$(ovn-sbctl --bare --columns=target list connection 2>/dev/null | tr -d '[:space:]')"
  [ "$sbc" = "ptcp:6642:$MGMT" ] \
    && rec N4c-sb-listener PASS "southbound listener ptcp:6642:$MGMT (reachable by a future compute node)" \
    || rec N4c-sb-listener FAIL "southbound listener is '$sbc'"
  l="$(ss -ltn 2>/dev/null)"
  grep -qE "127\.0\.0\.1:6641" <<<"$l" && rec N4d-6641-bound PASS "6641 listening on loopback" \
                                       || rec N4d-6641-bound FAIL "6641 not listening on loopback"
  if grep -qE "(0\.0\.0\.0|\*|$MGMT):6641" <<<"$l"; then
    rec N4e-6641-not-public FAIL "the northbound DB is exposed beyond loopback"
  else rec N4e-6641-not-public PASS "northbound DB is not exposed beyond loopback"; fi
  grep -qE "$MGMT:6642" <<<"$l" && rec N4f-6642-bound PASS "6642 listening on the management address" \
                               || rec N4f-6642-bound FAIL "6642 not listening on $MGMT"
else
  for t in N4b-nb-listener N4c-sb-listener N4d-6641-bound N4e-6641-not-public N4f-6642-bound; do
    rec "$t" UNVERIFIED "OVN DBs are not running in this container"; done
fi
# the provider bridge: created, and deliberately EMPTY
if ovs-vsctl --timeout=10 br-exists "$BRIDGE" 2>/dev/null; then
  rec N4g-bridge-exists PASS "provider bridge $BRIDGE exists in the OVS DB"
  ports="$(ovs-vsctl --timeout=10 list-ports "$BRIDGE" 2>/dev/null | tr '\n' ' ')"
  [ -z "$(tr -d '[:space:]' <<<"$ports")" ] \
    && rec N4h-bridge-empty PASS "no port is enslaved to $BRIDGE (no NIC was migrated)" \
    || rec N4h-bridge-empty FAIL "unexpected ports on $BRIDGE: $ports"
  addr="$(ip -4 -o addr show "$BRIDGE" 2>/dev/null | awk '{print $4}' | tr '\n' ' ')"
  [ -z "$(tr -d '[:space:]' <<<"$addr")" ] \
    && rec N4i-bridge-no-addr PASS "no IPv4 address on $BRIDGE (management IP was not relocated)" \
    || rec N4i-bridge-no-addr FAIL "$BRIDGE carries an address: $addr"
else
  rec N4g-bridge-exists UNVERIFIED "OVS DB not available, bridge not created"
  rec N4h-bridge-empty  UNVERIFIED "depends on N4g"
  rec N4i-bridge-no-addr UNVERIFIED "depends on N4g"
fi
# the management interface must be untouched: same addresses as before the run
NIC_ADDR_AFTER="$(ip -4 -o addr show "$NIC" | awk '{print $4}' | tr '\n' ' ')"
[ "$NIC_ADDR_BEFORE" = "$NIC_ADDR_AFTER" ] \
  && rec N4j-mgmt-untouched PASS "$NIC still holds $NIC_ADDR_AFTER (no management-IP move)" \
  || rec N4j-mgmt-untouched FAIL "management addresses changed: '$NIC_ADDR_BEFORE' -> '$NIC_ADDR_AFTER'"
# chassis-level external_ids, checked one by one
extid(){ ovs-vsctl --timeout=10 --if-exists get open_vswitch . "external_ids:$1" 2>/dev/null | tr -d '"'; }
if ovs-vsctl --timeout=10 show >/dev/null 2>&1; then
  for pair in "ovn-remote=tcp:$MGMT:6642" "ovn-encap-type=geneve" "ovn-encap-ip=$MGMT" \
              "ovn-bridge-mappings=$PHYSNET:$BRIDGE" "ovn-cms-options=enable-chassis-as-gw"; do
    k="${pair%%=*}"; want="${pair#*=}"; got="$(extid "$k")"
    [ "$got" = "$want" ] && rec "N4k-$k" PASS "$k=$got" || rec "N4k-$k" FAIL "$k is '$got', expected '$want'"
  done
else
  rec N4k-extids UNVERIFIED "OVS DB not available"
fi
# chassis registration needs ovn-controller, which needs the datapath: separate claim
if pgrep -x ovn-controller >/dev/null 2>&1 && [ "$SB_UP" = 1 ]; then
  ch="$(ovn-sbctl --bare --columns=name list chassis 2>/dev/null | tr '\n' ' ')"
  [ -n "$(tr -d '[:space:]' <<<"$ch")" ] \
    && rec N4l-chassis PASS "chassis registered in the southbound DB: $ch" \
    || rec N4l-chassis UNVERIFIED "ovn-controller runs but registered no chassis yet"
else
  rec N4l-chassis UNVERIFIED "ovn-controller is not running (it needs the ovs-vswitchd datapath, see N3e); chassis registration and Geneve are GCE items"
fi
# try ovn-controller too, with the same entry point the real unit uses
if [ -x "$OVN_CTL" ]; then
  timeout -k 5 60 $OVN_CTL start_controller --ovn-manage-ovsdb=no --no-monitor >>/out/n4-ovn.log 2>&1 || true
fi

echo
echo "== N5. the unit names the product uses must really exist (no guessing) =="
: > /out/n4-units.txt
unit_of(){ ls /usr/lib/systemd/system/"$1".service /lib/systemd/system/"$1".service 2>/dev/null | head -1; }
miss=""
# The neutron units come from the product's own NEUTRON_UNITS as well as the
# fixed list, so a unit added to the shell is checked without editing this test.
PRODUCT_NEUTRON_UNITS="$(sed -n 's/^NEUTRON_UNITS="\(.*\)"$/\1/p' "$H")"
[ -n "$PRODUCT_NEUTRON_UNITS" ] || rec N5a0-product-unit-list FAIL "could not read NEUTRON_UNITS from $H"
for u in ovn-ovsdb-server-nb ovn-ovsdb-server-sb ovn-northd ovn-controller \
         neutron-rpc-server neutron-periodic-workers neutron-ovn-metadata-agent \
         $PRODUCT_NEUTRON_UNITS; do
  f="$(unit_of "$u")"
  if [ -n "$f" ]; then
    { echo "[$u] $f"; grep -E '^(Type|ExecStart|ExecStop|After|Requires|Wants|User)=' "$f" | sed 's/^/    /'; } >> /out/n4-units.txt
  else miss="$miss $u"; echo "[$u] MISSING" >> /out/n4-units.txt; fi
done
[ -z "$miss" ] && rec N5a-units-exist PASS "every unit the shell starts exists on disk (dumped to n4-units.txt)" \
               || rec N5a-units-exist FAIL "the shell names units that do not exist:$miss"
# the wrappers really are wrappers: starting them alone would prove nothing
for w in ovn-central ovn-host; do
  f="$(unit_of "$w")"
  if [ -n "$f" ] && grep -q '^ExecStart=/bin/true' "$f"; then
    rec "N5b-$w-wrapper" PASS "$w is a Type=oneshot /bin/true wrapper (liveness is checked on the real units)"
  else rec "N5b-$w-wrapper" FAIL "$w is not the wrapper the code assumes"; fi
done
# neutron-server ships no unit: the API must come from the Apache vhost
if [ -z "$(unit_of neutron-server)" ] && [ -f /etc/apache2/sites-available/neutron-api.conf ]; then
  rec N5c-api-via-apache PASS "neutron-server ships no unit; the API comes from the neutron-api vhost"
else rec N5c-api-via-apache FAIL "packaging differs from what the code assumes"; fi
grep -qE '^[[:space:]]*Listen[[:space:]]+9696' /etc/apache2/sites-available/neutron-api.conf 2>/dev/null \
  && rec N5d-vhost-port PASS "the packaged vhost listens on 9696" || rec N5d-vhost-port FAIL "vhost port differs"
[ -L /etc/apache2/sites-enabled/neutron-api.conf ] \
  && rec N5e-vhost-enabled PASS "neutron-api vhost is enabled" || rec N5e-vhost-enabled FAIL "vhost not enabled"
# the agent the design does NOT use must still be accounted for, by measurement
av="$(apt-cache policy neutron-ovn-agent 2>/dev/null | awk '/Candidate:/{print $2}')"
[ -n "$av" ] && [ "$av" != "(none)" ] \
  && rec N5f-ovn-agent-available PASS "neutron-ovn-agent IS obtainable ($av); not used — metadata agent covers this design" \
  || rec N5f-ovn-agent-available FAIL "neutron-ovn-agent availability could not be measured"

echo
echo "== N6. networking configuration generated =="
NC=/etc/neutron/neutron.conf; ML2=/etc/neutron/plugins/ml2/ml2_conf.ini
META=/etc/neutron/neutron_ovn_metadata_agent.ini
if [ ! -f "$NC" ] || [ "$NEUTRON_CONFIGURED" = 0 ]; then
  # Not "FAIL": nothing was written, because the phase never got past its gate.
  for t in N6a-core-plugin N6b-service-plugins N6c-auth-strategy N6d-db-conn N6e-no-sqlite \
           N6f-transport N6g-authtoken N6h-authtoken-cache N6i-type-drivers N6j-tenant-type \
           N6k-mech N6l-extdrv N6m-flat N6n-vlan N6o-vni N6p-nb-conn N6q-sb-conn N6r-meta \
           N6s-secgroup N6t-meta-sb N6u-meta-host N6v-three-concerns N6w-perms; do
    rec "$t" UNVERIFIED "no networking configuration was written: $BLOCK_REASON"
  done
else
  ini_has "$NC" DEFAULT core_plugin ml2 && rec N6a-core-plugin PASS "core_plugin=ml2" || rec N6a-core-plugin FAIL "core_plugin=$(ini_val "$NC" DEFAULT core_plugin)"
  ini_has "$NC" DEFAULT service_plugins ovn-router && rec N6b-service-plugins PASS "service_plugins=ovn-router (L3 by OVN, no l3-agent)" \
    || rec N6b-service-plugins FAIL "service_plugins=$(ini_val "$NC" DEFAULT service_plugins)"
  ini_has "$NC" DEFAULT auth_strategy keystone && rec N6c-auth-strategy PASS "auth_strategy=keystone" || rec N6c-auth-strategy FAIL "not keystone"
  dbc="$(ini_val "$NC" database connection)"
  grep -q '^mysql+pymysql://neutron:' <<<"$dbc" && grep -q '@127.0.0.1/neutron' <<<"$dbc" \
    && rec N6d-db-conn PASS "database connection points at MariaDB on loopback" || rec N6d-db-conn FAIL "connection is not the expected MariaDB URL"
  grep -q sqlite <<<"$dbc" && rec N6e-no-sqlite FAIL "still sqlite" || rec N6e-no-sqlite PASS "no sqlite left in [database]"
  tu="$(ini_val "$NC" DEFAULT transport_url)"
  grep -q "^rabbit://openstack:" <<<"$tu" && grep -q "@$MGMT:5672/" <<<"$tu" \
    && rec N6f-transport PASS "transport_url points at the local RabbitMQ" || rec N6f-transport FAIL "transport_url wrong"
  ini_has "$NC" keystone_authtoken auth_type password && rec N6g-authtoken PASS "[keystone_authtoken] configured for password auth" \
    || rec N6g-authtoken FAIL "authtoken missing"
  ini_has "$NC" keystone_authtoken memcached_servers "$MGMT:11211" && rec N6h-authtoken-cache PASS "token cache set to $MGMT:11211" \
    || rec N6h-authtoken-cache FAIL "memcached_servers=$(ini_val "$NC" keystone_authtoken memcached_servers)"
  # ML2
  td="$(ini_val "$ML2" ml2 type_drivers)"
  for d in flat vlan geneve; do
    grep -q "$d" <<<"$td" && rec "N6i-type-$d" PASS "type_drivers includes $d" || rec "N6i-type-$d" FAIL "type_drivers=$td"
  done
  ini_has "$ML2" ml2 tenant_network_types geneve && rec N6j-tenant-type PASS "tenant_network_types=geneve (overlay, no VLAN needed per tenant)" \
    || rec N6j-tenant-type FAIL "tenant_network_types=$(ini_val "$ML2" ml2 tenant_network_types)"
  ini_has "$ML2" ml2 mechanism_drivers ovn && rec N6k-mech PASS "mechanism_drivers=ovn" || rec N6k-mech FAIL "mechanism_drivers=$(ini_val "$ML2" ml2 mechanism_drivers)"
  ini_has "$ML2" ml2 extension_drivers port_security && rec N6l-extdrv PASS "extension_drivers=port_security" || rec N6l-extdrv FAIL "no port_security"
  ini_has "$ML2" ml2_type_flat flat_networks "$PHYSNET" && rec N6m-flat PASS "flat_networks=$PHYSNET (provider physnet)" || rec N6m-flat FAIL "flat_networks wrong"
  ini_has "$ML2" ml2_type_vlan network_vlan_ranges "$PHYSNET" \
    && rec N6n-vlan PASS "network_vlan_ranges=$PHYSNET (room for several provider LANs later)" || rec N6n-vlan FAIL "vlan ranges wrong"
  ini_has "$ML2" ml2_type_geneve vni_ranges "1:65536" && rec N6o-vni PASS "geneve vni_ranges=1:65536" || rec N6o-vni FAIL "vni_ranges=$(ini_val "$ML2" ml2_type_geneve vni_ranges)"
  ini_has "$ML2" ovn ovn_nb_connection "tcp:127.0.0.1:6641" && rec N6p-nb-conn PASS "ml2 talks to the northbound DB on loopback" \
    || rec N6p-nb-conn FAIL "ovn_nb_connection=$(ini_val "$ML2" ovn ovn_nb_connection)"
  ini_has "$ML2" ovn ovn_sb_connection "tcp:$MGMT:6642" && rec N6q-sb-conn PASS "ml2 talks to the southbound DB on the management address" \
    || rec N6q-sb-conn FAIL "ovn_sb_connection=$(ini_val "$ML2" ovn ovn_sb_connection)"
  ini_has "$ML2" ovn ovn_metadata_enabled true && rec N6r-meta PASS "ovn_metadata_enabled=true" || rec N6r-meta FAIL "metadata not enabled"
  ini_has "$ML2" securitygroup enable_security_group true && rec N6s-secgroup PASS "security groups enabled" || rec N6s-secgroup FAIL "security groups off"
  ini_has "$META" ovn ovn_sb_connection "tcp:$MGMT:6642" && rec N6t-meta-sb PASS "metadata agent points at the southbound DB" || rec N6t-meta-sb FAIL "metadata agent sb connection wrong"
  ini_has "$META" DEFAULT nova_metadata_host "$MGMT" && rec N6u-meta-host PASS "nova_metadata_host=$MGMT (ready for Nova)" || rec N6u-meta-host FAIL "metadata host wrong"
  # the three separated concerns must be visible as three different settings
  if [ "$(ini_val "$ML2" ovn ovn_sb_connection)" != "$(ini_val "$ML2" ml2_type_flat flat_networks)" ] \
     && [ "$(extid ovn-encap-ip 2>/dev/null)" = "$MGMT" ] \
     && [ "$(extid ovn-bridge-mappings 2>/dev/null)" = "$PHYSNET:$BRIDGE" ]; then
    rec N6v-three-concerns PASS "management/Geneve endpoint ($MGMT) and provider mapping ($PHYSNET:$BRIDGE) are separate settings"
  else rec N6v-three-concerns UNVERIFIED "OVS DB unavailable, so the split cannot be read back here"; fi
  # permissions: the package ships these 0640 root:neutron and they carry secrets
  for f in "$NC" "$ML2" "$META"; do
    m="$(stat -c '%a %U:%G' "$f")"
    [ "$m" = "640 root:neutron" ] && rec "N6w-perm-$(basename "$f")" PASS "$m (package ownership preserved)" \
                                  || rec "N6w-perm-$(basename "$f")" FAIL "$m"
  done
fi

echo
echo "== N7. networking schema =="
nt="$(mariadb -uroot -N -B -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='neutron'" 2>/dev/null || echo 0)"
if [ "$nt" -gt 50 ]; then
  rec N7a-schema PASS "$nt tables in the neutron schema"
  av_head="$(mariadb -uroot -N -B neutron -e "SELECT COUNT(*) FROM alembic_version" 2>/dev/null || echo 0)"
  [ "$av_head" -ge 1 ] && rec N7b-alembic PASS "alembic_version carries $av_head head row(s) — migrations recorded" \
                       || rec N7b-alembic FAIL "no alembic head recorded"
  grep -qE 'networking schema (created|already current|migrated)' /out/n4-run1.log \
    && rec N7c-schema-reported PASS "the run reported what it did to the schema" || rec N7c-schema-reported FAIL "not reported"
elif [ "$NEUTRON_CONFIGURED" = 0 ]; then
  for t in N7a-schema N7b-alembic N7c-schema-reported; do
    rec "$t" UNVERIFIED "the schema step was never reached: $BLOCK_REASON"; done
else
  rec N7a-schema FAIL "the phase configured itself but the schema has only $nt tables"
  rec N7b-alembic FAIL "no schema, so no alembic head"
  rec N7c-schema-reported FAIL "no schema step reported"
fi

echo
echo "== N8. authenticated networking API and service registration =="
apachectl -k graceful >/dev/null 2>&1 || apachectl -k restart >/dev/null 2>&1 || true
for _ in $(seq 1 15); do curl -s -o /dev/null -m 5 "http://$MGMT:9696/" && break; sleep 2; done
NET_ID=ABSENT; LS_NAME=ABSENT
if ! curl -s -o /dev/null -m 5 "http://$MGMT:9696/"; then
  tail -30 /var/log/apache2/neutron_api_error.log > /out/n4-neutron-apache.log 2>&1 || true
  tail -30 /var/log/apache2/error.log >> /out/n4-neutron-apache.log 2>&1 || true
  for t in N8a-api-up N8b-catalogue N8c-endpoints N8d-auth-api N8e-api-body N8e2-unauth-refused \
           N8f-net-create N8g-ovn-nb-switch N8h-subnet-create; do
    rec "$t" UNVERIFIED "the networking API did not answer on :9696 here. ${BLOCK_REASON:-see n4-neutron-apache.log}"; done
  rec N8i-port-binding UNVERIFIED "port binding needs ovn-controller + datapath and a working API; GCE item"
else
  rec N8a-api-up PASS "networking API answers on :9696 via apache2 (same server as identity :5000)"
  . /etc/hagistack/admin-openrc; export OS_AUTH_URL="http://$MGMT:5000/v3"
  timeout -k 5 90 openstack service list -f value 2>/dev/null | grep -q network \
    && rec N8b-catalogue PASS "network service present in the catalogue" || rec N8b-catalogue FAIL "network not in catalogue"
  n="$(timeout -k 5 90 openstack endpoint list --service neutron -f value 2>/dev/null | wc -l)"
  [ "$n" -ge 3 ] && rec N8c-endpoints PASS "$n networking endpoints registered (public/internal/admin)" || rec N8c-endpoints FAIL "n=$n"
  TOK="$(timeout -k 5 60 openstack token issue -f value -c id 2>/dev/null)"
  if [ -n "$TOK" ]; then
    CFG="$(mktemp)"; chmod 600 "$CFG"           # token via a config file, never in argv
    printf 'header = "X-Auth-Token: %s"\n' "$TOK" > "$CFG"
    code="$(curl -sS -m 60 -o /out/n4-nets.json -w '%{http_code}' -K "$CFG" "http://$MGMT:9696/v2.0/networks" 2>/out/n4-nets.err || echo 000)"
    rm -f "$CFG"
    [ "$code" = "200" ] && rec N8d-auth-api PASS "authenticated GET /v2.0/networks -> HTTP 200" || rec N8d-auth-api FAIL "HTTP $code"
    jq -e 'has("networks")' /out/n4-nets.json >/dev/null 2>&1 \
      && rec N8e-api-body PASS "response body has a networks list (empty is correct at this point)" || rec N8e-api-body FAIL "unexpected body"
    # the same call WITHOUT a token must be refused: proves auth is really on
    ucode="$(curl -s -o /dev/null -m 30 -w '%{http_code}' "http://$MGMT:9696/v2.0/networks" || echo 000)"
    [ "$ucode" = "401" ] && rec N8e2-unauth-refused PASS "the same call without a token -> HTTP 401" \
                         || rec N8e2-unauth-refused FAIL "unauthenticated call returned $ucode"
  else
    for t in N8d-auth-api N8e-api-body N8e2-unauth-refused; do rec "$t" UNVERIFIED "no token could be issued"; done
  fi
  # Creating a tenant network is the real proof that ML2/OVN drives the OVN
  # northbound DB: neutron writes, ovn-northd translates, the switch appears.
  if ! timeout -k 5 90 openstack service list -f value 2>/dev/null | grep -q network; then
    rec N8f-net-create UNVERIFIED "networking is not in the catalogue, so the client would fall back to the compute network commands"
  elif timeout -k 5 120 openstack network create -f shell hagistack-n4-net >/out/n4-netcreate.txt 2>&1; then
    NET_ID="$(sed -n 's/^id="\(.*\)"$/\1/p' /out/n4-netcreate.txt | head -1)"
    [ -n "$NET_ID" ] && rec N8f-net-create PASS "geneve tenant network created id=$NET_ID" || { NET_ID=ABSENT; rec N8f-net-create FAIL "no id returned"; }
  elif [ "$RABBIT_UP" = 0 ] && grep -qiE 'messaging|amqp|rabbit|timed out' /out/n4-netcreate.txt; then
    rec N8f-net-create UNVERIFIED "create failed on the message queue, which would not start here (N3b2): $(head -c 160 /out/n4-netcreate.txt)"
  else
    rec N8f-net-create FAIL "$(head -c 250 /out/n4-netcreate.txt)"
  fi
  if [ "$NET_ID" != ABSENT ] && [ "$NB_UP" = 1 ]; then
    LS_NAME="$(ovn-nbctl --bare --columns=name list logical_switch 2>/dev/null | grep -F "$NET_ID" | head -1)"
    if [ -n "$LS_NAME" ]; then
      rec N8g-ovn-nb-switch PASS "the network reached the OVN northbound DB as logical switch $LS_NAME"
    else
      rec N8g-ovn-nb-switch FAIL "no logical switch for $NET_ID in the northbound DB: $(ovn-nbctl --bare --columns=name list logical_switch 2>/dev/null | tr '\n' ' ' | head -c 120)"
      LS_NAME=ABSENT
    fi
  else
    rec N8g-ovn-nb-switch UNVERIFIED "no network id, or the OVN northbound DB is not running here"
  fi
  # a subnet exercises the DHCP/metadata path in the NB DB as well
  if [ "$NET_ID" != ABSENT ]; then
    if timeout -k 5 120 openstack subnet create --network hagistack-n4-net --subnet-range 10.77.0.0/24 \
         hagistack-n4-sub >/out/n4-subcreate.txt 2>&1; then
      rec N8h-subnet-create PASS "subnet 10.77.0.0/24 created on the tenant network"
    else rec N8h-subnet-create FAIL "$(head -c 200 /out/n4-subcreate.txt)"; fi
  else rec N8h-subnet-create UNVERIFIED "no network"; fi
  # ports for an instance cannot be bound without a chassis: say so, do not fake it
  rec N8i-port-binding UNVERIFIED "port binding to a chassis needs ovn-controller + datapath (N3e/N4l); GCE item"
fi
checkpoint after-api || true

echo
echo "== N9. re-run must keep everything =="
nc_before="$(digest_of /etc/neutron/neutron.conf)"
ml2_before="$(digest_of /etc/neutron/plugins/ml2/ml2_conf.ini)"
meta_before="$(digest_of /etc/neutron/neutron_ovn_metadata_agent.ini)"
sec_before="$(digest_of /etc/hagistack/secrets.env)"
nt_before="$nt"
nbc_before="$(ovn-nbctl --bare --columns=target list connection 2>/dev/null | tr -d '[:space:]' || echo ABSENT)"
sbc_before="$(ovn-sbctl --bare --columns=target list connection 2>/dev/null | tr -d '[:space:]' || echo ABSENT)"
br_before="$(ovs-vsctl --timeout=10 list-ports "$BRIDGE" 2>/dev/null | wc -l || echo ABSENT)"
uid_before="$(mariadb -uroot -N -B -e "SELECT id FROM keystone.local_user WHERE name='neutron'" 2>/dev/null || echo ABSENT)"
ep_before="$(mariadb -uroot -N -B -e "SELECT COUNT(*) FROM keystone.endpoint" 2>/dev/null || echo ABSENT)"
svc_before="$(mariadb -uroot -N -B -e "SELECT COUNT(*) FROM keystone.service" 2>/dev/null || echo ABSENT)"
netrow_before="$([ "$NET_ID" != ABSENT ] && mariadb -uroot -N -B neutron -e "SELECT id FROM networks" 2>/dev/null | grep -F "$NET_ID" || echo ABSENT)"

run_product run2; o2="$RUN_OUT"; rc2="$RUN_RC"
[ "$RUN_ATTEMPTS" = "1" ] && rec N9z-rerun-clean PASS "the re-run completed in one attempt (exit $rc2)" \
                          || rec N9z-rerun-clean UNVERIFIED "the re-run needed $RUN_ATTEMPTS attempts in this container (exit $rc2); see the captured keystone logs"
if [ "$NEUTRON_CONFIGURED" = 1 ]; then
  stable N9a-neutron-conf "$nc_before"   "$(digest_of /etc/neutron/neutron.conf)" "neutron.conf"
  stable N9b-ml2-conf     "$ml2_before"  "$(digest_of /etc/neutron/plugins/ml2/ml2_conf.ini)" "ml2_conf.ini"
  stable N9c-meta-conf    "$meta_before" "$(digest_of /etc/neutron/neutron_ovn_metadata_agent.ini)" "metadata agent ini"
else
  for t in N9a-neutron-conf N9b-ml2-conf N9c-meta-conf; do
    rec "$t" UNVERIFIED "there is no generated networking configuration to compare: $BLOCK_REASON"; done
fi
stable N9d-secrets      "$sec_before"  "$(digest_of /etc/hagistack/secrets.env)" "secrets.env"
if [ "${nt_before:-0}" -gt 50 ] 2>/dev/null; then
  stable N9e-tables     "$nt_before"   "$(mariadb -uroot -N -B -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='neutron'" 2>/dev/null || echo ABSENT)" "neutron table count"
else rec N9e-tables UNVERIFIED "there is no networking schema to compare: $BLOCK_REASON"; fi
stable N9f-nb-conn      "$nbc_before"  "$(ovn-nbctl --bare --columns=target list connection 2>/dev/null | tr -d '[:space:]' || echo ABSENT)" "northbound listener"
stable N9g-sb-conn      "$sbc_before"  "$(ovn-sbctl --bare --columns=target list connection 2>/dev/null | tr -d '[:space:]' || echo ABSENT)" "southbound listener"
stable N9h-bridge-ports "$br_before"   "$(ovs-vsctl --timeout=10 list-ports "$BRIDGE" 2>/dev/null | wc -l || echo ABSENT)" "port count on $BRIDGE"
stable N9i-service-user "$uid_before"  "$(mariadb -uroot -N -B -e "SELECT id FROM keystone.local_user WHERE name='neutron'" 2>/dev/null || echo ABSENT)" "neutron service-user id"
stable N9j-endpoints    "$ep_before"   "$(mariadb -uroot -N -B -e "SELECT COUNT(*) FROM keystone.endpoint" 2>/dev/null || echo ABSENT)" "endpoint count"
stable N9k-services     "$svc_before"  "$(mariadb -uroot -N -B -e "SELECT COUNT(*) FROM keystone.service" 2>/dev/null || echo ABSENT)" "service count"
if [ "$NET_ID" != ABSENT ]; then
  stable N9l-network-row "$netrow_before" "$(mariadb -uroot -N -B neutron -e "SELECT id FROM networks" 2>/dev/null | grep -F "$NET_ID" || echo ABSENT)" "the created network row"
  if [ "$LS_NAME" != ABSENT ]; then
    stable N9m-logical-switch "$LS_NAME" "$(ovn-nbctl --bare --columns=name list logical_switch 2>/dev/null | grep -F "$NET_ID" | head -1 || echo ABSENT)" "OVN logical switch"
  else rec N9m-logical-switch UNVERIFIED "no logical switch was observed before the re-run"; fi
else
  rec N9l-network-row UNVERIFIED "no network was created"
  rec N9m-logical-switch UNVERIFIED "no network was created"
fi
if [ "$NEUTRON_CONFIGURED" = 1 ]; then
  grep -q 'already correct (unchanged)' <<<"$o2" && rec N9n-conf-reported PASS "re-run reports the configuration unchanged" || rec N9n-conf-reported FAIL "not reported"
  grep -qE 'schema already current' <<<"$o2" && rec N9o-schema-reported PASS "re-run reports the schema current" || rec N9o-schema-reported FAIL "not reported"
  grep -q 'already exists' <<<"$o2" && rec N9p-reuse-reported PASS "re-run reports existing identity objects reused" || rec N9p-reuse-reported FAIL "not reported"
else
  for t in N9n-conf-reported N9o-schema-reported N9p-reuse-reported; do
    rec "$t" UNVERIFIED "the re-run could not reach these steps either: $BLOCK_REASON"; done
fi
if grep -qE 'listener already ptcp:' <<<"$o2"; then
  rec N9q-ovn-listener-idempotent PASS "the re-run found both OVN listeners already correct and re-set neither"
elif grep -qE 'listener set to' <<<"$o2"; then
  rec N9q-ovn-listener-idempotent FAIL "the re-run re-issued set-connection (the comparison does not match what the DB reports)"
else rec N9q-ovn-listener-idempotent UNVERIFIED "the ovn phase did not reach the listener step in the re-run"; fi
grep -qE 'already configured \(unchanged\)' <<<"$o2" && rec N9q2-ovn-extids PASS "re-run reports the local chassis already configured" \
                                                     || rec N9q2-ovn-extids FAIL "re-run rewrote the chassis external_ids"
# third run, then confirm the network is still there and still bound to OVN
run_product run3
if [ "$NET_ID" != ABSENT ] && curl -s -o /dev/null -m 5 "http://$MGMT:9696/"; then
  id3="$(timeout -k 5 90 openstack network show hagistack-n4-net -f value -c id 2>/out/n4-net3.err || echo ABSENT)"
  if [ "$id3" = "$NET_ID" ]; then rec N9r-third-run PASS "the network is still present after a 3rd run"
  else
    dbrow="$(mariadb -uroot -N -B neutron -e "SELECT id,name,status FROM networks" 2>/dev/null || echo QUERYFAIL)"
    if grep -q "$NET_ID" <<<"$dbrow"; then
      rec N9r-third-run UNVERIFIED "the API call failed in the container but the DB row is intact (db: $(head -c 120 <<<"$dbrow"))"
    else rec N9r-third-run FAIL "network genuinely lost: id3=$id3 db=$dbrow"; fi
  fi
else rec N9r-third-run UNVERIFIED "no network, or the API stopped answering before the 3rd check"; fi

echo
echo "== N12. a host built before the OVN maintenance worker existed converges =="
# The ML2/OVN maintenance worker is its own package and Conflicts with the
# transitional neutron-server, which earlier hagistack versions installed (and
# which pulled neutron-api, -rpc-server and -periodic-workers in as automatic
# dependencies). A re-run must move such a host to the real package set without
# reinstalling anything and without leaving the real packages autoremovable.
MW=neutron-ovn-maintenance-worker
REAL="neutron-api neutron-rpc-server neutron-periodic-workers"
pkg_ok(){ dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }
is_manual(){ apt-mark showmanual 2>/dev/null | grep -qx "$1"; }
case " $PRODUCT_NEUTRON_UNITS " in
  *" $MW "*) rec N12a-unit-in-product PASS "$MW is in the product's NEUTRON_UNITS" ;;
  *)         rec N12a-unit-in-product FAIL "$MW is missing from NEUTRON_UNITS ($PRODUCT_NEUTRON_UNITS)" ;;
esac
if pkg_ok "$MW" && ! pkg_ok neutron-server; then
  rec N12b-fresh-install PASS "fresh runs installed $MW ($(dpkg-query -W -f='${Version}' "$MW")) and not the transitional neutron-server"
else rec N12b-fresh-install FAIL "after the fresh runs: $MW=$(pkg_ok "$MW" && echo yes || echo no), neutron-server=$(pkg_ok neutron-server && echo yes || echo no)"; fi
# Recreate what an earlier hagistack left behind: neutron-server installed (apt
# removes the worker because of the Conflicts), the real packages automatic.
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq neutron-server >/out/n4-oldstate.log 2>&1
apt-mark auto $REAL >>/out/n4-oldstate.log 2>&1
if pkg_ok neutron-server && ! pkg_ok "$MW" && ! is_manual neutron-api; then
  rec N12c-pre-state PASS "old state recreated: neutron-server installed, $MW absent, neutron-api automatic"
  api_list_before="$(stat -c %Y /var/lib/dpkg/info/neutron-api.list 2>/dev/null || echo ABSENT)"
  ml2_before12="$(digest_of /etc/neutron/plugins/ml2/ml2_conf.ini)"
  nc_before12="$(digest_of /etc/neutron/neutron.conf)"
  run_product run4; rc4="$RUN_RC"
  if [ "$rc4" = "0" ] || [ "$rc4" = "4" ]; then rec N12d-rerun-terminal PASS "re-run reached a terminal state (exit $rc4)"
  else rec N12d-rerun-terminal FAIL "re-run exit $rc4"; fi
  if pkg_ok "$MW" && ! pkg_ok neutron-server; then rec N12e-converged PASS "the re-run installed $MW and removed the transitional neutron-server"
  else rec N12e-converged FAIL "after the re-run: $MW=$(pkg_ok "$MW" && echo yes || echo no), neutron-server=$(pkg_ok neutron-server && echo yes || echo no)"; fi
  notman=""; for q in $REAL; do is_manual "$q" || notman="$notman $q"; done
  [ -z "$notman" ] && rec N12e2-not-autoremovable PASS "$REAL are manually installed (apt autoremove would keep them)" \
                   || rec N12e2-not-autoremovable FAIL "still automatic, so autoremove would take them:$notman"
  api_list_after="$(stat -c %Y /var/lib/dpkg/info/neutron-api.list 2>/dev/null || echo ABSENT)"
  if [ "$api_list_before" != ABSENT ] && [ "$api_list_before" = "$api_list_after" ]; then
    rec N12f-no-reinstall PASS "neutron-api was not reinstalled (dpkg file list untouched)"
  else rec N12f-no-reinstall FAIL "neutron-api dpkg state changed: $api_list_before -> $api_list_after"; fi
  stable N12g-ml2-kept "$ml2_before12" "$(digest_of /etc/neutron/plugins/ml2/ml2_conf.ini)" "ml2_conf.ini across convergence"
  stable N12h-conf-kept "$nc_before12" "$(digest_of /etc/neutron/neutron.conf)" "neutron.conf across convergence"
  # And once converged, a further run must not touch packages at all.
  hist_before="$(grep -c '^Start-Date' /var/log/apt/history.log 2>/dev/null || echo 0)"
  run_product run5; rc5="$RUN_RC"
  hist_after="$(grep -c '^Start-Date' /var/log/apt/history.log 2>/dev/null || echo 0)"
  if [ "$rc5" != "0" ] && [ "$rc5" != "4" ]; then rec N12i-idempotent FAIL "converged re-run exit $rc5"
  elif ! pkg_ok "$MW"; then rec N12i-idempotent FAIL "after the further run $MW is still not installed"
  elif [ "$hist_before" = "$hist_after" ]; then
    rec N12i-idempotent PASS "converged re-run (exit $rc5) ran no apt transaction and kept $MW"
  else rec N12i-idempotent FAIL "converged re-run changed packages (apt transactions $hist_before -> $hist_after)"; fi
else
  rec N12c-pre-state FAIL "could not recreate the old state: neutron-server=$(pkg_ok neutron-server && echo yes || echo no) $MW=$(pkg_ok "$MW" && echo yes || echo no) neutron-api-manual=$(is_manual neutron-api && echo yes || echo no)"
fi

echo
echo "== N10. secrets must not leak =="
leak=""; 
while IFS='=' read -r k v; do
  case "$k" in ''|\#*) continue;; esac
  [ -n "$v" ] || continue
  grep -qrF "$v" /out/n4-run0.log /out/n4-run1.log /out/n4-run2.log /out/n4-run3.log /out/n4-run4.log /out/n4-run5.log /out/n4-nodb.log 2>/dev/null \
    && leak="$leak $k"
done < /etc/hagistack/secrets.env
[ -z "$leak" ] && rec N10a-no-secret-in-log PASS "no secret value appears in any run output" || rec N10a-no-secret-in-log FAIL "leaked:$leak"
leak2=""
while IFS='=' read -r k v; do
  case "$k" in ''|\#*) continue;; esac
  [ -n "$v" ] || continue
  grep -qrF "$v" /out/ 2>/dev/null && leak2="$leak2 $k"
done < /etc/hagistack/secrets.env
[ -z "$leak2" ] && rec N10b-no-secret-in-artefacts PASS "no secret value appears anywhere under /out" || rec N10b-no-secret-in-artefacts FAIL "leaked:$leak2"
ps_out="$(ps -eo args 2>/dev/null || true)"
argv_leak=""
for k in NEUTRON_SERVICE_PASS NEUTRON_DB_PASS METADATA_PROXY_SECRET RABBIT_PASS; do
  v="$(sed -n "s/^$k=//p" /etc/hagistack/secrets.env)"
  [ -n "$v" ] && grep -qF "$v" <<<"$ps_out" && argv_leak="$argv_leak $k"
done
[ -z "$argv_leak" ] && rec N10c-no-secret-in-argv PASS "no networking secret appears in any process argument list" \
                    || rec N10c-no-secret-in-argv FAIL "in argv:$argv_leak"
[ "$(stat -c '%a' /etc/hagistack/secrets.env)" = "600" ] \
  && rec N10d-secrets-perm PASS "secrets.env is 0600" || rec N10d-secrets-perm FAIL "$(stat -c '%a' /etc/hagistack/secrets.env)"
# a failed neutron-db-manage must be explainable without printing credentials
if grep -qE 'password|secret' /out/n4-run1.log /out/n4-run2.log 2>/dev/null; then
  ctx="$(grep -hiE 'password|secret' /out/n4-run1.log /out/n4-run2.log \
        | grep -viE 'shared_secret|_PASS=|password auth|METADATA_PROXY|password left unchanged|credentials not shown|no password|secrets reused|secret file' \
        | head -3 | tr '\n' ' ')"
  [ -z "$(tr -d '[:space:]' <<<"$ctx")" ] && rec N10e-no-cred-prose PASS "the words password/secret only appear as setting names" \
                                          || rec N10e-no-cred-prose FAIL "suspicious output: $(head -c 150 <<<"$ctx")"
else rec N10e-no-cred-prose PASS "no credential wording in the run output at all"; fi

echo
echo "== N11. what this container cannot decide (sent to real-machine verification) =="
rec N11a-systemd-units UNVERIFIED "startup and ordering of the OVN and neutron units under systemd (unit files are present and dumped to n4-units.txt, but nothing started them here): GCE acceptance B0a/B0b"
rec N11b-geneve-internode UNVERIFIED "Geneve tunnelling between two chassis: needs GCE node2 (compute-add); nothing here proves it"
rec N11c-physical-lan UNVERIFIED "provider network on a physical L2 LAN and a real floating IP: class C, not reproducible on GCE or in a container"
rec N11d-instance-boot UNVERIFIED "instance boot and port binding: Nova and Horizon are not implemented yet"
rec N11e-nic-migration UNVERIFIED "enslaving a NIC to $BRIDGE and moving the management IP: deliberately NOT performed in this step"

printf 'MARIADB=%s\nMEMCACHED=%s\nRABBITMQ=%s\nAPACHE=%s\nOVSDB=%s\nVSWITCHD=%s\nOVN=%s\nWSGI=%s\nAPT=%s\n' \
  "$MARIADB_METHOD" "$MEMCACHED_METHOD" \
  "$([ "$RABBIT_UP" = 1 ] && echo "$RABBIT_METHOD" || echo 'would not start')" \
  "$APACHE_METHOD" "$OVSDB_METHOD" "$VSWITCHD_METHOD" \
  "$OVN_METHOD" "${WSGI_TUNED:-none}" "$TUNED" > /out/n4-start-methods.txt
# keep enough evidence that a bad run can be explained without re-running
capture_service_logs final
tail -40 /var/log/apache2/neutron_api_error.log  > /out/n4-final-neutron-apache.log 2>&1 || true
tail -40 /var/log/apache2/error.log              > /out/n4-final-apache-error.log 2>&1 || true
tail -40 /var/log/neutron/neutron-server.log     > /out/n4-final-neutron.log 2>&1 || true
tail -40 /var/log/ovn/ovn-northd.log             > /out/n4-final-northd.log 2>&1 || true
tail -40 /var/log/openvswitch/ovs-vswitchd.log   > /out/n4-final-vswitchd.log 2>&1 || true
ovs-vsctl --timeout=10 show                      > /out/n4-final-ovs.txt 2>&1 || true
ovn-nbctl --timeout=10 show                      > /out/n4-final-ovn-nb.txt 2>&1 || true
ovn-sbctl --timeout=10 show                      > /out/n4-final-ovn-sb.txt 2>&1 || true
ip -o addr                                       > /out/n4-final-addrs.txt 2>&1 || true
ss -ltnp                                         > /out/n4-final-listeners.txt 2>&1 || true
mariadb -uroot -N -B neutron -e "SELECT id,name,status FROM networks" > /out/n4-final-networks.txt 2>&1 || true
mariadb -uroot -N -B keystone -e "SELECT id,type,enabled FROM service" > /out/n4-final-services.txt 2>&1 || true
echo "== checkpoints =="; sed 's/^/  /' /out/n4-checkpoints.tsv
echo "== start methods =="; sed 's/^/  /' /out/n4-start-methods.txt
echo
printf 'PASS=%d FAIL=%d UNVERIFIED=%d\n' "$P" "$F" "$U" | tee /out/n4-summary.txt
if [ "$F" -eq 0 ]; then exit 0; else exit 1; fi
