#!/usr/bin/env bash
# Step 6 (Horizon, initial resources, compute-add) verification INSIDE an
# Ubuntu 26.04 container. Deliberately light, and the limits are stated up front.
#
# What this suite CAN prove: the shell parses, ShellCheck is clean, the new
# inputs are validated and cannot execute anything, the config file still
# refuses shell metacharacters in the new keys, compute-add refuses to touch a
# machine it cannot reach or whose credentials were not delivered,
# compute-secrets leaks no database or admin password, nothing in the shell
# deletes an OpenStack resource or edits the dashboard's dpkg conffile, and the
# pinned image digest is the publisher's.
#
# What it CANNOT prove, and does not pretend to: that Horizon serves a login
# page, that anyone can log in, that a guest boots, that a second node's chassis
# appears in OVN, or that Placement learns about it. Those need two real
# machines with systemd and are recorded UNVERIFIED.
set -uo pipefail
H=/src/hagistack
R=/out/s6-results.tsv; : > "$R"
P=0; F=0; U=0
rec(){ printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$R"
  case "$2" in
    PASS) P=$((P+1)); printf '  \033[32mPASS\033[0m  %-32s %s\n' "$1" "$3";;
    FAIL) F=$((F+1)); printf '  \033[31mFAIL\033[0m  %-32s %s\n' "$1" "$3";;
    *)    U=$((U+1)); printf '  \033[33mUNVER\033[0m %-32s %s\n' "$1" "$3";;
  esac; }

export DEBIAN_FRONTEND=noninteractive
printf 'APT::Keep-Downloaded-Packages "false";\n' > /etc/apt/apt.conf.d/01-lean
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq iproute2 openssl curl shellcheck procps python3-minimal >/dev/null 2>&1
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
for t in /src/tests/container-step6.sh /src/tests/container-step5.sh; do
  o="$(shellcheck -S warning "$t" 2>&1)"
  [ -z "$o" ] && rec "S0b2-$(basename "$t" .sh)" PASS "suite clean" \
              || rec "S0b2-$(basename "$t" .sh)" FAIL "$(head -c 200 <<<"$o")"
done
v="$("$H" --version)"
grep -qE '^hagistack [0-9]+\.[0-9]+\.[0-9]+-step[0-9]+$' <<<"$v" && rec S0c-version PASS "$v" || rec S0c-version FAIL "$v"

st="$("$H" status 2>&1)"; stn="$(tr '\n' ' ' <<<"$st")"
hl="$("$H" --help 2>&1 | tr '\n' ' ')"
# implemented and verified must be two separate, labelled claims
if grep -qiE 'implemented' <<<"$stn" && grep -qiE 'verified on hardware' <<<"$stn"; then
  rec S0d-two-claims PASS "status separates implemented from verified"
else rec S0d-two-claims FAIL "status does not separate the two claims"; fi
grep -qiE 'verified on hardware *: *none' <<<"$stn" \
  && rec S0e-verified-none PASS "status says nothing is verified on hardware" \
  || rec S0e-verified-none FAIL "status does not say hardware verification is none"
grep -qiE 'no guest VM has been booted' <<<"$stn" \
  && rec S0f-status-guest PASS "status says no guest was booted" || rec S0f-status-guest FAIL "overclaims"
grep -qiE 'login tested +NO' <<<"$stn" \
  && rec S0g-status-login PASS "status says the dashboard login is untested" || rec S0g-status-login FAIL "overclaims"
grep -qiE 'verified *: *none' <<<"$hl" \
  && rec S0h-help-verified PASS "--help states nothing is verified" || rec S0h-help-verified FAIL "--help overclaims"
# the step 1 wording must be gone from the file header
head -40 "$H" | grep -qiE 'STEP 1 of the rebuild|Keystone.*are NOT implemented' \
  && rec S0i-stale-header FAIL "the stale STEP 1 header comment is still there" \
  || rec S0i-stale-header PASS "no stale STEP 1 header comment"
grep -qiE 'not implemented yet' <<<"$hl" \
  && rec S0j-no-stub FAIL "--help still advertises an unimplemented subcommand" \
  || rec S0j-no-stub PASS "no subcommand is advertised as a stub"
# nothing anywhere may claim a finished/usable cloud
if grep -RniE 'usable (openstack|cloud)|finished openstack|fully verified|production[- ]ready' "$H" \
   | grep -viE 'NOT a usable|NOT usable|no[tn].{0,14}usable|Do not call this a finished' | grep -q .; then
  rec S0k-no-usable-claim FAIL "an unqualified 'usable/finished' claim exists"
else rec S0k-no-usable-claim PASS "every such mention is a negation"; fi
for p in horizon bootstrap_resources compute_ovn compute_nova compute_metadata; do
  grep -q "$p" <<<"$stn" && rec "S0l-phase-$p" PASS "listed by status" || rec "S0l-phase-$p" FAIL "not listed"
done
# compute-add must no longer be a stub that exits 3
"$H" compute-add --help >/dev/null 2>&1
o="$("$H" compute-add --env-file /dev/null 2>&1)"; rc=$?
[ "$rc" = "3" ] && rec S0m-not-stub FAIL "compute-add still exits 3" \
                || rec S0m-not-stub PASS "compute-add is no longer a not-implemented stub (exit $rc)"

echo
echo "== S1. input validation for the new settings =="
bad(){ local label="$1"; shift
  local o rc; o="$("$H" all-in-one --check "${BASE[@]}" "$@" 2>&1)"; rc=$?
  if [ "$rc" = "0" ]; then rec "$label" FAIL "accepted"
  elif grep -qiE 'not a valid|requires a value|must be|not allowed|not an acceptable|does not exist|refus' <<<"$o"; then
    rec "$label" PASS "rejected"
  else rec "$label" FAIL "exit $rc without a validation message"; fi; }
rm -f /tmp/S1MARK
bad S1a-sha-short     --image-sha256 abc123
bad S1b-sha-upper     --image-sha256 7D6355852AEB6DBCD191BCDA7CD74F1536CFE5CBF8A10495A7283A8396E4B75B
bad S1c-sha-inject    --image-sha256 '7d63;touch /tmp/S1MARK'
bad S1d-sha-novalue   --image-sha256
bad S1e-url-scheme    --image-url ftp://example.invalid/x.img
bad S1f-url-query     --image-url 'https://example.invalid/x.img?a=1'
bad S1g-url-inject    --image-url 'https://example.invalid/$(touch /tmp/S1MARK).img'
bad S1h-name-slash    --image-name 'a/b'
bad S1i-name-space    --image-name 'a b'
bad S1j-file-relative --image-file relative/path.img
bad S1k-file-dotdot   --image-file /var/lib/../etc/shadow
bad S1l-file-missing  --image-file /var/lib/hagistack/definitely-absent.img
[ -e /tmp/S1MARK ] && rec S1m-no-exec FAIL "a rejected value executed a command" \
                   || rec S1m-no-exec PASS "nothing executed by any rejected value"

badc(){ local label="$1"; shift
  local o rc; o="$("$H" compute-add --check --env-file /dev/null "$@" 2>&1)"; rc=$?
  if [ "$rc" = "0" ]; then rec "$label" FAIL "accepted"
  elif grep -qiE 'not usable|not a valid|requires a value|needs --controller-ip|equals this node' <<<"$o"; then
    rec "$label" PASS "rejected"
  else rec "$label" FAIL "exit $rc without a validation message: $(head -c 120 <<<"$o")"; fi; }
badc S1n-ctl-missing
badc S1o-ctl-loopback  --controller-ip 127.0.0.1
badc S1p-ctl-zero      --controller-ip 0.0.0.0
badc S1q-ctl-linklocal --controller-ip 169.254.1.1
badc S1r-ctl-multicast --controller-ip 239.1.1.1
badc S1s-ctl-bogus     --controller-ip 10.0.0.256
badc S1t-ctl-inject    --controller-ip '10.0.0.5;touch /tmp/S1MARK'
badc S1u-ctl-self      --controller-ip "$MGMT" --mgmt-ip "$MGMT"
[ -e /tmp/S1MARK ] && rec S1v-no-exec2 FAIL "a rejected controller-ip executed a command" \
                   || rec S1v-no-exec2 PASS "nothing executed by any rejected controller-ip"

echo
echo "== S2. config file: the new keys are parsed, never executed =="
rm -f /tmp/S2MARK
cat > /tmp/ok.env <<EEOF
EXT_NIC=$NIC
CONTROLLER_IP=10.99.0.7
IMAGE_NAME=my-image
IMAGE_SHA256=7d6355852aeb6dbcd191bcda7cd74f1536cfe5cbf8a10495a7283a8396e4b75b
EEOF
o="$("$H" all-in-one --check --env-file /tmp/ok.env --provider-cidr 172.24.4.0/24 \
      --provider-gateway 172.24.4.1 --floating-start 172.24.4.100 --floating-end 172.24.4.200 \
      --mgmt-ip "$MGMT" 2>&1)"
grep -qE 'CONTROLLER_IP +10\.99\.0\.7 +\[config file\]' <<<"$o" \
  && rec S2a-file-parsed PASS "CONTROLLER_IP read from the config file" \
  || rec S2a-file-parsed FAIL "not reported as coming from the config file"
grep -qE 'IMAGE_NAME +my-image +\[config file\]' <<<"$o" \
  && rec S2b-image-name PASS "IMAGE_NAME read from the config file" || rec S2b-image-name FAIL "no"
o="$("$H" all-in-one --check --env-file /tmp/ok.env --image-name cli-image --provider-cidr 172.24.4.0/24 \
      --provider-gateway 172.24.4.1 --floating-start 172.24.4.100 --floating-end 172.24.4.200 \
      --mgmt-ip "$MGMT" 2>&1)"
grep -qE 'IMAGE_NAME +cli-image +\[command line\]' <<<"$o" \
  && rec S2c-precedence PASS "command line beats the config file for IMAGE_NAME" \
  || rec S2c-precedence FAIL "precedence wrong"
# regression: a key that falls at the end of a line inside CONFIG_KEYS used to
# be reported as "unknown key" from a config file while working on the command
# line. Every key must be accepted from the file.
fails=""
for k in MGMT_IP EXT_NIC PROVIDER_CIDR PROVIDER_GATEWAY FLOATING_START FLOATING_END \
         DNS_SERVER TENANT_CIDR VIRT_TYPE REGION_NAME PROVIDER_PHYSNET PROVIDER_BRIDGE \
         CONTROLLER_IP IMAGE_NAME IMAGE_URL IMAGE_SHA256 IMAGE_FILE; do
  printf '%s=x\n' "$k" > /tmp/k.env
  if "$H" all-in-one --check --env-file /tmp/k.env "${BASE[@]}" 2>&1 | grep -q "unknown key '$k'"; then
    fails="$fails $k"
  fi
done
[ -z "$fails" ] && rec S2e-every-key PASS "every CONFIG_KEY is accepted from a config file" \
                || rec S2e-every-key FAIL "rejected as unknown:$fails"

printf 'EXT_NIC=%s\nIMAGE_URL=$(touch /tmp/S2MARK)\n' "$NIC" > /tmp/evil6.env
"$H" all-in-one --check --env-file /tmp/evil6.env --provider-cidr 172.24.4.0/24 \
      --provider-gateway 172.24.4.1 --floating-start 172.24.4.100 --floating-end 172.24.4.200 \
      --mgmt-ip "$MGMT" >/dev/null 2>&1
[ -e /tmp/S2MARK ] && rec S2d-no-exec FAIL "the config file executed a command" \
                   || rec S2d-no-exec PASS "IMAGE_URL=\$(...) refused, not run"

echo
echo "== S3. image defaults are the publisher's, and are pinned =="
o="$("$H" all-in-one --check "${BASE[@]}" 2>&1)"
arch="$(dpkg --print-architecture)"
case "$arch" in
  amd64) want=7d6355852aeb6dbcd191bcda7cd74f1536cfe5cbf8a10495a7283a8396e4b75b ;;
  arm64) want=611879b8299363fe60ff0f84982e4da08e63f476e8481170223db982959783cb ;;
  *)     want="" ;;
esac
if [ -n "$want" ] && grep -q "$want" <<<"$o"; then
  rec S3a-digest-default PASS "the $arch default carries a pinned digest"
else rec S3a-digest-default FAIL "no pinned digest in the resolved configuration"; fi
url="$(grep -oE 'https://download\.cirros-cloud\.net/[^ ]*disk\.img' <<<"$o" | head -1)"
if [ -n "$url" ] && curl -fsSL -m 45 https://download.cirros-cloud.net/0.6.3/SHA256SUMS -o /tmp/SUMS 2>/dev/null; then
  if grep -q "^$want  ${url##*/}\$" /tmp/SUMS; then
    rec S3b-digest-upstream PASS "pinned digest matches the publisher's SHA256SUMS"
  else rec S3b-digest-upstream FAIL "pinned digest does NOT match the publisher's SHA256SUMS"; fi
else
  rec S3b-digest-upstream UNVERIFIED "no network in this container; digest not cross-checked"
fi
grep -q 'never fetched without a digest\|without a digest' "$H" \
  && rec S3c-digest-required PASS "a URL without a digest is refused by design" \
  || rec S3c-digest-required FAIL "no such rule in the source"

echo
echo "== S4. compute-add refuses what it must refuse =="
# a controller that is not listening: nothing may be installed or changed
o="$("$H" compute-add --env-file /dev/null --controller-ip 10.99.0.7 --mgmt-ip 10.99.0.8 2>&1)"; rc=$?
if [ "$rc" != "0" ] && grep -qiE 'not reachable on' <<<"$o"; then
  rec S4a-unreachable PASS "refuses an unreachable controller (exit $rc)"
else rec S4a-unreachable FAIL "exit $rc: $(head -c 160 <<<"$o")"; fi
dpkg-query -W -f='${Status}' nova-compute 2>/dev/null | grep -q "install ok installed" \
  && rec S4b-no-install FAIL "nova-compute got installed by a refused run" \
  || rec S4b-no-install PASS "nothing was installed by the refused run"

# now make the controller ports answer, so preflight passes and the run reaches
# the secrets check — which must refuse, because no credentials were delivered.
python3 - <<'PYEOF' &
import socket, threading
def serve(p):
    s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("0.0.0.0", p)); s.listen(8)
    while True:
        try: s.accept()[0].close()
        except Exception: return
for p in (5000, 9292, 8778, 5672, 6642):
    threading.Thread(target=serve, args=(p,), daemon=True).start()
import time; time.sleep(120)
PYEOF
LISTENER=$!
sleep 2
rm -rf /etc/hagistack
o="$("$H" compute-add --env-file /dev/null --controller-ip "$MGMT" --mgmt-ip 10.99.0.8 2>&1)"; rc=$?
if [ "$rc" != "0" ] && grep -qi 'compute-secrets' <<<"$o"; then
  rec S4c-secrets-required PASS "refuses to proceed without delivered credentials, and says how"
else rec S4c-secrets-required FAIL "exit $rc: $(head -c 200 <<<"$o")"; fi
grep -qi 'never generate\|cannot invent' <<<"$o" \
  && rec S4d-no-generate PASS "says plainly that a compute node never generates secrets" \
  || rec S4d-no-generate FAIL "does not say where the secrets come from"
dpkg-query -W -f='${Status}' nova-compute 2>/dev/null | grep -q "install ok installed" \
  && rec S4e-no-install2 FAIL "packages were installed before the secrets check" \
  || rec S4e-no-install2 PASS "the secrets check runs before anything is installed"
# wrong mode must be refused
mkdir -p /etc/hagistack
printf 'RABBIT_PASS=x\nNOVA_SERVICE_PASS=x\nPLACEMENT_SERVICE_PASS=x\nNEUTRON_SERVICE_PASS=x\nMETADATA_PROXY_SECRET=x\n' \
  > /etc/hagistack/secrets.env
chmod 0644 /etc/hagistack/secrets.env
o="$("$H" compute-add --env-file /dev/null --controller-ip "$MGMT" --mgmt-ip 10.99.0.8 2>&1)"; rc=$?
grep -qiE 'mode 644; expected 600|has mode 644' <<<"$o" \
  && rec S4f-mode PASS "refuses a world-readable secrets file" \
  || rec S4f-mode FAIL "exit $rc: $(head -c 160 <<<"$o")"
# an incomplete file must be refused, naming the missing key
chmod 0600 /etc/hagistack/secrets.env
printf 'RABBIT_PASS=x\nNOVA_SERVICE_PASS=x\n' > /etc/hagistack/secrets.env
chmod 0600 /etc/hagistack/secrets.env
o="$("$H" compute-add --env-file /dev/null --controller-ip "$MGMT" --mgmt-ip 10.99.0.8 2>&1)"; rc=$?
grep -q 'PLACEMENT_SERVICE_PASS' <<<"$o" \
  && rec S4g-incomplete PASS "names the credentials that are missing" \
  || rec S4g-incomplete FAIL "exit $rc: $(head -c 160 <<<"$o")"
kill "$LISTENER" 2>/dev/null || true

echo
echo "== S5. compute-secrets leaks nothing a compute node must not have =="
rm -rf /etc/hagistack /var/lib/hagistack
# build a controller-shaped secrets file by hand (all-in-one would need a DB)
mkdir -p /etc/hagistack; chmod 0750 /etc/hagistack
{ echo "# test"; for k in MYSQL_ROOT_PASS RABBIT_PASS KEYSTONE_DB_PASS GLANCE_DB_PASS \
    PLACEMENT_DB_PASS NOVA_DB_PASS NEUTRON_DB_PASS ADMIN_PASSWORD SERVICE_PASSWORD \
    METADATA_PROXY_SECRET GLANCE_SERVICE_PASS PLACEMENT_SERVICE_PASS NEUTRON_SERVICE_PASS \
    NOVA_SERVICE_PASS; do echo "$k=VALUE_OF_$k"; done; } > /etc/hagistack/secrets.env
chmod 0600 /etc/hagistack/secrets.env
out="$("$H" compute-secrets 2>/dev/null)"; rc=$?
if [ "$rc" = "0" ] && [ -n "$out" ]; then
  rec S5a-emits PASS "compute-secrets produced output outside a terminal"
else rec S5a-emits FAIL "exit $rc, output empty"; fi
leaked=""
for k in MYSQL_ROOT_PASS ADMIN_PASSWORD KEYSTONE_DB_PASS GLANCE_DB_PASS PLACEMENT_DB_PASS \
         NOVA_DB_PASS NEUTRON_DB_PASS; do
  grep -qE "^${k}=" <<<"$out" && leaked="$leaked $k"
  grep -q "VALUE_OF_$k" <<<"$out" && leaked="$leaked ${k}(value)"
done
[ -z "$leaked" ] && rec S5b-no-leak PASS "no database or admin credential is emitted" \
                 || rec S5b-no-leak FAIL "leaked:$leaked"
n=0; for k in RABBIT_PASS NOVA_SERVICE_PASS PLACEMENT_SERVICE_PASS NEUTRON_SERVICE_PASS METADATA_PROXY_SECRET; do
  grep -qE "^${k}=VALUE_OF_${k}\$" <<<"$out" && n=$((n+1)); done
[ "$n" = "5" ] && rec S5c-all-five PASS "all five compute credentials are emitted verbatim" \
               || rec S5c-all-five FAIL "only $n of 5 emitted"
grep -qiE 'refus' <<<"$("$H" compute-secrets --help 2>&1; true)" >/dev/null 2>&1 || true
grep -q 'if \[ -t 1 \]' "$H" \
  && rec S5d-tty-guard PASS "refuses to print credentials to a terminal" \
  || rec S5d-tty-guard FAIL "no terminal guard in the source"
rm -rf /etc/hagistack
o="$("$H" discover-hosts 2>&1)"; rc=$?
[ "$rc" != "0" ] && grep -qi 'controller' <<<"$o" \
  && rec S5e-discover-guard PASS "discover-hosts refuses to run off the controller" \
  || rec S5e-discover-guard FAIL "exit $rc: $(head -c 120 <<<"$o")"

echo
echo "== S6. destructive-operation audit of the source =="
if grep -nE 'openstack[^|]*\b(delete|remove|unset)\b' "$H" | grep -v '^[0-9]*: *#' | grep -q .; then
  rec S6a-no-delete FAIL "the shell calls an openstack delete/remove: $(grep -nE 'openstack[^|]*\b(delete|remove)\b' "$H" | head -2)"
else rec S6a-no-delete PASS "no openstack delete/remove anywhere"; fi
if grep -nE '\bDROP +(DATABASE|TABLE|USER)\b' "$H" | grep -v '^[0-9]*: *#' | grep -q .; then
  rec S6b-no-drop FAIL "a DROP statement exists"
else rec S6b-no-drop PASS "no DROP DATABASE/TABLE/USER"; fi
if grep -nE 'rm +-rf +/(etc|var|usr)' "$H" | grep -q .; then
  rec S6c-no-rmrf FAIL "an rm -rf against a system path exists"
else rec S6c-no-rmrf PASS "no rm -rf against /etc, /var or /usr"; fi
# the dashboard conffile must never be written
if grep -nE '(tee|>|cp|sed -i|install).*\/etc\/openstack-dashboard\/local_settings\.py' "$H" \
   | grep -v '^[0-9]*: *#' | grep -q .; then
  rec S6d-conffile FAIL "the shell writes the dashboard's dpkg conffile"
else rec S6d-conffile PASS "the dashboard conffile is never written (a local_settings.d snippet is used)"; fi
grep -q 'local_settings.d' "$H" \
  && rec S6e-snippet PASS "settings are delivered through local_settings.d" \
  || rec S6e-snippet FAIL "no local_settings.d snippet"
# the compute node must not be handed a database connection
if sed -n '/^phase_compute_nova/,/^}/p' "$H" | grep -qE 'ini_set +"\$NOVA_CONF" +(api_)?database'; then
  rec S6f-compute-nodb FAIL "compute-add writes a database connection"
else rec S6f-compute-nodb PASS "compute-add writes no [database] connection"; fi
# and must not advertise itself as a gateway chassis
if sed -n '/^phase_compute_ovn/,/^}/p' "$H" | grep -q 'enable-chassis-as-gw'; then
  rec S6g-compute-nogw FAIL "compute-add sets enable-chassis-as-gw"
else rec S6g-compute-nogw PASS "compute-add does not make itself a gateway chassis"; fi

# `set -e` + a plain assignment from a command substitution: the assignment
# takes the substitution's exit status, so a lookup that correctly finds nothing
# aborts the whole run. On a first run the image never exists, which made this
# the single most likely way for all-in-one to die with no banner. Every such
# assignment from a lookup helper must carry an explicit fallback.
bad=""
while IFS= read -r line; do
  case "$line" in *"|| true"*|*"|| echo"*|*"if ! "*) continue ;; esac
  bad="$bad
    $line"
done < <(grep -nE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*="\$\((image_field|horizon_login_page_code|ini_get)' "$H")
[ -z "$bad" ] && rec S6h-errexit-lookups PASS "every lookup assignment has an explicit fallback" \
              || rec S6h-errexit-lookups FAIL "unguarded under set -e:$bad"

echo
echo "== S7. what a container cannot settle (recorded, never forced to PASS) =="
rec S7a-horizon-login  UNVERIFIED "serving and logging into the dashboard needs apache+keystone: GCE"
rec S7b-guest-boot     UNVERIFIED "booting an instance needs libvirt and a real hypervisor: GCE"
rec S7c-resources      UNVERIFIED "creating the flavor/image/networks needs a live control plane: GCE"
rec S7d-ovn-chassis    UNVERIFIED "a second node registering a chassis needs two machines: GCE"
rec S7e-geneve         UNVERIFIED "node-to-node Geneve needs two machines: GCE"
rec S7f-placement-reg  UNVERIFIED "compute-add Placement registration needs a live controller: GCE"
rec S7g-systemd        UNVERIFIED "unit startup and ordering need systemd: GCE"

echo
echo "================ step 6 summary ================"
printf 'PASS %d  FAIL %d  UNVERIFIED %d\n' "$P" "$F" "$U"
echo "free disk: $(free_mb)MB"
[ "$F" -eq 0 ]
