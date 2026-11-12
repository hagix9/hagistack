#!/usr/bin/env bash
# Tests for hagistack's config-file reader (hagistack.env) and the precedence
# command line > config file > default (environment variables are not read).
#
#   bash rocky10.2/tests/test-env-file.sh
#
# Needs only bash 4 or later (hagistack uses associative arrays) and coreutils.
# It changes nothing outside a temporary directory: hagistack is sourced with
# HAGISTACK_LIB_ONLY=1 and its state/etc paths point into that directory.
#
# Regression for stage 6-1 run h6n121: CONFIG_KEYS_FLAT was referenced but never
# defined, so every hagistack.env aborted with "unbound variable".
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HS="$HERE/../hagistack"
[ "${BASH_VERSINFO[0]}" -ge 4 ] || { echo "needs bash 4 or later (this is $BASH_VERSION)" >&2; exit 2; }

T="$(mktemp -d "${TMPDIR:-/tmp}/hs-envfile-test.XXXXXX")" && [ -d "$T" ] || { echo "cannot create a temporary directory" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2" | head -12; }

# Run a snippet with hagistack's functions loaded, a private state tree and
# the working directory $T/<name>/cwd. Extra environment comes before the
# snippet as NAME=VALUE words. Usage: run_hs <name> [VAR=val ...] '<code>'
# -> sets OUT and RC
run_hs() {
    local name="$1"; shift
    local st="$T/$name"; mkdir -p "$st/etc" "$st/var" "$st/cwd"
    local code="${*: -1}"; local -a extra=("${@:1:$#-1}")
    # env -i: the snippet sees only what is passed here, so a key exported in
    # the caller's shell cannot leak into a result.
    OUT="$(cd "$st/cwd" && env -i PATH="$PATH" HOME="$st" HAGISTACK_LIB_ONLY=1 \
        HAGISTACK_ETC="$st/etc" HAGISTACK_STATE="$st/var" NO_COLOR=1 ${extra[@]+"${extra[@]}"} \
        bash -c '
            set -euo pipefail
            source "$1"
            SUDO=""; trap - ERR
            _capture_defaults; _capture_env
            eval "$2"
        ' _ "$HS" "$code" 2>&1)"
    RC=$?
}
q() { printf '%q' "$1"; }   # quote a path for the eval'd snippet
cfg() { mkdir -p "$(dirname "$1")"; cat > "$1"; }
no_unbound() { ! grep -q "unbound variable" <<<"$OUT"; }

# Every allowed key, including those that end a line of CONFIG_KEYS.
ALL_KEYS="$(HAGISTACK_LIB_ONLY=1 bash -c 'source "$1"; printf "%s\n" $CONFIG_KEYS' _ "$HS")"
[ "$(wc -l <<<"$ALL_KEYS")" -ge 20 ] && pass "CONFIG_KEYS read from hagistack ($(( $(wc -l <<<"$ALL_KEYS") )) keys)" \
    || fail "CONFIG_KEYS read from hagistack" "$ALL_KEYS"

# ------------------------------------------------ e1: the h6n121 settings
cfg "$T/e1/cwd/hagistack.env" <<'EOF'
# provider network on a dummy NIC
EXT_NIC=hgext0
PROVIDER_CIDR=192.0.2.0/24
PROVIDER_GATEWAY="192.0.2.1"
FLOATING_START =192.0.2.100
FLOATING_END='192.0.2.200'
EOF
run_hs e1 'load_env_file; resolve_config; for k in EXT_NIC PROVIDER_CIDR PROVIDER_GATEWAY FLOATING_START FLOATING_END REGION_NAME; do echo "V $k=${!k} [${CONFIG_SOURCE[$k]}]"; done'
if [ "$RC" -eq 0 ] && no_unbound \
   && grep -qx "V EXT_NIC=hgext0 \[config file\]" <<<"$OUT" \
   && grep -qx "V PROVIDER_CIDR=192.0.2.0/24 \[config file\]" <<<"$OUT" \
   && grep -qx "V PROVIDER_GATEWAY=192.0.2.1 \[config file\]" <<<"$OUT" \
   && grep -qx "V FLOATING_START=192.0.2.100 \[config file\]" <<<"$OUT" \
   && grep -qx "V FLOATING_END=192.0.2.200 \[config file\]" <<<"$OUT" \
   && grep -qx "V REGION_NAME=RegionOne \[default\]" <<<"$OUT" \
   && grep -q "config file: ./hagistack.env (parsed, not executed)" <<<"$OUT"; then
    pass "./hagistack.env with the h6n121 settings is read (quotes, a blank before =, comments)"
else fail "./hagistack.env with the h6n121 settings" "rc=$RC $OUT"; fi

# ------------------------------------------------ e2: every allowed key
: > "$T/e2.env"
while read -r k; do echo "$k=v-$k" >> "$T/e2.env"; done <<<"$ALL_KEYS"
run_hs e2 "ENV_FILE=$(q "$T/e2.env"); load_env_file; resolve_config; for k in \$CONFIG_KEYS; do echo \"V \$k=\${!k} [\${CONFIG_SOURCE[\$k]}]\"; done"
bad=""
while read -r k; do grep -qx "V $k=v-$k \[config file\]" <<<"$OUT" || bad="$bad $k"; done <<<"$ALL_KEYS"
[ "$RC" -eq 0 ] && no_unbound && [ -z "$bad" ] && pass "every key in CONFIG_KEYS is accepted from the file, wherever its line breaks" \
    || fail "every key accepted from the file (missing:$bad)" "rc=$RC $OUT"

# ------------------------------------------------ e3: unknown and partial keys
for k in NOT_A_KEY MGMT IP _IP SET_EXPECTED; do
    printf '%s=x\n' "$k" > "$T/e3-$k.env"
    run_hs "e3-$k" "ENV_FILE=$(q "$T/e3-$k.env"); load_env_file; echo LOADED"
    if [ "$RC" -ne 0 ] && no_unbound && ! grep -q LOADED <<<"$OUT" \
       && grep -q "line 1: unknown key '$k'" <<<"$OUT" && grep -q "Allowed keys: MGMT_IP EXT_NIC" <<<"$OUT" \
       && grep -q "RPM_SET_EXPECTED$" <<<"$OUT"; then
        pass "unknown key '$k' is refused and the allowed keys are listed"
    else fail "unknown key '$k'" "rc=$RC $OUT"; fi
done

# ------------------------------------------------ e4: duplicate, bad value, bad line, empty value
printf 'EXT_NIC=a\nEXT_NIC=b\n' > "$T/e4a.env"
run_hs e4a "ENV_FILE=$(q "$T/e4a.env"); load_env_file; echo LOADED"
[ "$RC" -ne 0 ] && ! grep -q LOADED <<<"$OUT" && grep -q "line 2: duplicate key 'EXT_NIC'" <<<"$OUT" \
    && pass "a duplicate key is refused" || fail "duplicate key" "rc=$RC $OUT"

printf 'EXT_NIC=eth0;touch-SECRETVALUE\n' > "$T/e4b.env"
run_hs e4b "ENV_FILE=$(q "$T/e4b.env"); load_env_file; echo LOADED"
[ "$RC" -ne 0 ] && ! grep -q LOADED <<<"$OUT" && grep -q "the value of 'EXT_NIC' contains characters" <<<"$OUT" \
    && ! grep -q SECRETVALUE <<<"$OUT" \
    && pass "a value with shell metacharacters is refused and not echoed" || fail "bad value" "rc=$RC $OUT"

printf 'export EXT_NIC=eth0\n' > "$T/e4c.env"
run_hs e4c "ENV_FILE=$(q "$T/e4c.env"); load_env_file; echo LOADED"
[ "$RC" -ne 0 ] && ! grep -q LOADED <<<"$OUT" && grep -q "line 1: not a KEY=VALUE assignment" <<<"$OUT" \
    && pass "a line that is not KEY=VALUE is refused" || fail "bad line" "rc=$RC $OUT"

printf 'REGION_NAME=\n' > "$T/e4d.env"
run_hs e4d "ENV_FILE=$(q "$T/e4d.env"); load_env_file; resolve_config; echo RESOLVED"
[ "$RC" -ne 0 ] && ! grep -q RESOLVED <<<"$OUT" && grep -q "REGION_NAME was given an empty value on the config file" <<<"$OUT" \
    && pass "an empty value in the file is an error, not a fall-back to the default" || fail "empty value" "rc=$RC $OUT"

printf 'EXT_NIC= eth0\n' > "$T/e4e.env"
run_hs e4e "ENV_FILE=$(q "$T/e4e.env"); load_env_file; echo LOADED"
[ "$RC" -ne 0 ] && ! grep -q LOADED <<<"$OUT" && grep -q "the value of 'EXT_NIC' contains characters" <<<"$OUT" \
    && pass "a blank after = is refused, as on Ubuntu (only trailing blanks are trimmed)" || fail "blank after =" "rc=$RC $OUT"

# ------------------------------------------------ e5: precedence
# The README says the Rocky script does not read environment variables: an
# exported key must be ignored, so the file (or the default) applies.
printf 'EXT_NIC=from-file\nPROVIDER_CIDR=198.51.100.0/24\n' > "$T/e5.env"
run_hs e5 EXT_NIC=from-env PROVIDER_CIDR=203.0.113.0/24 REGION_NAME=EnvRegion \
    "ENV_FILE=$(q "$T/e5.env"); _cli_set EXT_NIC from-cli; load_env_file; resolve_config; for k in EXT_NIC PROVIDER_CIDR REGION_NAME; do echo \"V \$k=\${!k} [\${CONFIG_SOURCE[\$k]}]\"; done"
if [ "$RC" -eq 0 ] && grep -qx "V EXT_NIC=from-cli \[command line\]" <<<"$OUT" \
   && grep -qx "V PROVIDER_CIDR=198.51.100.0/24 \[config file\]" <<<"$OUT" \
   && grep -qx "V REGION_NAME=RegionOne \[default\]" <<<"$OUT"; then
    pass "precedence: command line > config file > default; environment variables are not read"
else fail "precedence" "rc=$RC $OUT"; fi

# ------------------------------------------------ e6: search order and no file
if [ -e "$HERE/../hagistack.env" ]; then
    echo "  SKIP  search of \$HAGISTACK_ETC: a hagistack.env sits beside the script"
else
    printf 'EXT_NIC=from-etc\n' | cfg "$T/e6/etc/hagistack.env"
    run_hs e6 'load_env_file; resolve_config; echo "V EXT_NIC=$EXT_NIC"'
    [ "$RC" -eq 0 ] && grep -qx "V EXT_NIC=from-etc" <<<"$OUT" \
        && pass "\$HAGISTACK_ETC/hagistack.env is read when there is none in ./" || fail "etc search" "rc=$RC $OUT"
    printf 'EXT_NIC=from-cwd\n' | cfg "$T/e6b/cwd/hagistack.env"
    printf 'EXT_NIC=from-etc\n' | cfg "$T/e6b/etc/hagistack.env"
    run_hs e6b 'load_env_file; resolve_config; echo "V EXT_NIC=$EXT_NIC"'
    [ "$RC" -eq 0 ] && grep -qx "V EXT_NIC=from-cwd" <<<"$OUT" \
        && pass "./hagistack.env wins over \$HAGISTACK_ETC/hagistack.env" || fail "cwd before etc" "rc=$RC $OUT"
    run_hs e6c 'load_env_file; resolve_config; echo "V EXT_NIC=[$EXT_NIC] [${CONFIG_SOURCE[EXT_NIC]}]"'
    [ "$RC" -eq 0 ] && grep -qx "V EXT_NIC=\[\] \[default\]" <<<"$OUT" && ! grep -q "config file:" <<<"$OUT" \
        && pass "no hagistack.env anywhere: nothing is read and defaults apply" || fail "no file" "rc=$RC $OUT"
fi

run_hs e7 "ENV_FILE=$(q "$T/does-not-exist.env"); load_env_file; echo LOADED"
[ "$RC" -ne 0 ] && ! grep -q LOADED <<<"$OUT" && grep -q "env file not readable" <<<"$OUT" \
    && pass "a named --env-file that does not exist is an error" || fail "missing named file" "rc=$RC $OUT"

echo
echo "result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
