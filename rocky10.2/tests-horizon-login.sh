#!/bin/bash
# Horizon acceptance: a real admin sign-in, asserted — not a 200 on a page.
#
# What this checks, and why each one is a separate assertion:
#
#   * the login page returns 200 and renders a form with a CSRF token;
#   * every hidden field is read back from that form rather than guessed.
#     Horizon's `region` is the literal string "default", not the Keystone URL,
#     and posting the URL gives "Invalid region ''" with HTTP 200 — a failure
#     that reads as success if only the status code is looked at;
#   * the POST REDIRECTS (302/303) and the redirect does NOT go back to the
#     login page. A 200 here means the form was re-rendered, which is what a
#     rejected password looks like;
#   * a sessionid cookie is issued AND has a value;
#   * each protected page is fetched WITHOUT following redirects, and must be
#     200 — a 302 means the session was not accepted. Following redirects would
#     turn exactly that failure into a 200 on the login page;
#   * each protected page must contain the username and must not contain the
#     login form.
#
# It then proves the test can fail, with two negative cases: a wrong password,
# and a protected page fetched with no session at all. A test that has never
# been seen to fail is not evidence.
#
# The administrator password is never placed in a command line. curl reads it
# from a config file written with umask 077 inside a private directory, so it
# is not visible in `ps`, in this script's own output, or to another user.
set -u

HZ_URL="${HZ_URL:-http://127.0.0.1/dashboard}"
OPENRC="${OPENRC:-/etc/hagistack/admin-openrc}"

say(){ printf '\n======== %s ========\n' "$*"; }
ok(){  printf '  PASS  %s\n' "$*"; }
no(){  printf '  FAIL  %s\n' "$*"; }

# One private directory, removed whole. The old version removed /tmp/hz.* by
# glob, which could take files this script never created.
umask 077
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hagistack-hzlogin.XXXXXXXX")" || exit 2
chmod 700 "$WORK"
trap 'rm -rf -- "$WORK"' EXIT INT TERM

[ -r "$OPENRC" ] || { echo "cannot read $OPENRC"; exit 2; }
# shellcheck disable=SC1090
. "$OPENRC"
: "${OS_USERNAME:?OS_USERNAME missing from $OPENRC}"
: "${OS_PASSWORD:?OS_PASSWORD missing from $OPENRC}"

# ---------------------------------------------------------------------------
# attempt_login <password> <jar> <tag>
#   prints the POST status and the Location header; returns 0 only if the POST
#   redirected somewhere that is not the login page and a sessionid was set.
# ---------------------------------------------------------------------------
attempt_login() {
    local pw="$1" jar="$2" tag="$3"
    local page="$WORK/$tag.login" fields="$WORK/$tag.fields"
    local cfg="$WORK/$tag.curlcfg" post="$WORK/$tag.post" hdr="$WORK/$tag.hdr"

    local code
    code="$(curl -s -c "$jar" -o "$page" -w '%{http_code}' "$HZ_URL/auth/login/")"
    [ "$code" = "200" ] || { no "$tag: login page returned $code, expected 200"; return 1; }
    grep -q 'csrfmiddlewaretoken' "$page" || { no "$tag: login page has no CSRF token"; return 1; }

    python3 - "$page" > "$fields" <<'PY'
import re, sys, html
h = open(sys.argv[1], encoding="utf-8", errors="replace").read()
for m in re.finditer(r'<input[^>]*type="hidden"[^>]*>', h):
    tag = m.group(0)
    n = re.search(r'name="([^"]*)"', tag)
    v = re.search(r'value="([^"]*)"', tag)
    if n:
        print(f"{n.group(1)}={html.unescape(v.group(1)) if v else ''}")
PY
    grep -q '^csrfmiddlewaretoken=' "$fields" || { no "$tag: no csrfmiddlewaretoken among the hidden fields"; return 1; }

    # Build a curl config file rather than a command line. umask 077 above means
    # this lands 0600 inside a 0700 directory, so the password is not in argv,
    # not in this script's output, and not readable by another user.
    : > "$cfg"
    local k v
    while IFS='=' read -r k v; do
        printf 'data-urlencode = "%s=%s"\n' "$k" "$v" >> "$cfg"
    done < "$fields"
    printf 'data-urlencode = "username=%s"\n' "$OS_USERNAME" >> "$cfg"
    printf 'data-urlencode = "password=%s"\n' "$pw"          >> "$cfg"

    code="$(curl -s --config "$cfg" -b "$jar" -c "$jar" -D "$hdr" -o "$post" \
                 -w '%{http_code}' -e "$HZ_URL/auth/login/" "$HZ_URL/auth/login/")"
    local loc
    # grep -i, not awk IGNORECASE: that is a gawk extension, and on an awk
    # without it the Location never parses, which silently disables the
    # "redirected back to the login page" check below.
    loc="$(grep -i '^location:' "$hdr" | head -1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')"
    printf '  %s: POST -> HTTP %s   Location: %s\n' "$tag" "$code" "${loc:-<none>}"

    case "$code" in
        302|303) ;;
        *) no "$tag: POST returned $code; a sign-in must redirect, and a 200 means the form came back"
           grep -oiE 'Invalid[^<]{0,60}' "$post" | head -2 | sed 's/^/        server said: /'
           return 1 ;;
    esac
    case "$loc" in
        *"/auth/login"*) no "$tag: redirected back to the login page — credentials rejected"; return 1 ;;
    esac
    grep -qE '(^|[[:space:]])sessionid[[:space:]]+[^[:space:]]+' "$jar" \
        || { no "$tag: no sessionid cookie with a value was issued"; return 1; }
    return 0
}

# ---------------------------------------------------------------------------
# check_pages <jar>  — protected pages, WITHOUT following redirects
# ---------------------------------------------------------------------------
check_pages() {
    local jar="$1" bad=0 p code body isform who
    for p in "/project/instances/" "/identity/" "/project/networks/" "/project/api_access/"; do
        body="$WORK/page$(echo "$p" | tr -c 'a-zA-Z0-9' '_')"
        code="$(curl -s -b "$jar" -c "$jar" -o "$body" -w '%{http_code}' "$HZ_URL$p")"
        isform="$(grep -c 'csrfmiddlewaretoken' "$body" 2>/dev/null || true)"
        grep -q 'id="loginBtn"\|name="region"' "$body" 2>/dev/null && isform=login || isform=no
        who="$(grep -c -- "$OS_USERNAME" "$body" 2>/dev/null || true)"
        printf '  %-24s HTTP %-4s login-form=%-6s %s-in-page=%s\n' \
               "$p" "$code" "$isform" "$OS_USERNAME" "${who:-0}"
        [ "$code" = "200" ]  || { no "$p returned $code; a 302 here means the session was not accepted"; bad=1; }
        [ "$isform" = "no" ] || { no "$p rendered the login form"; bad=1; }
        [ "${who:-0}" -gt 0 ] || { no "$p does not mention '$OS_USERNAME'"; bad=1; }
    done
    return $bad
}

rc=0

say "1. positive: sign in as $OS_USERNAME"
JAR="$WORK/jar.good"
if attempt_login "$OS_PASSWORD" "$JAR" "good"; then
    ok "POST redirected away from the login page and a sessionid was issued"
    if check_pages "$JAR"; then
        ok "every protected page returned 200, rendered no login form, and showed '$OS_USERNAME'"
    else
        rc=1
    fi
else
    rc=1
fi

say "2. negative: a wrong password must FAIL"
JAR="$WORK/jar.bad"
if attempt_login "definitely-not-the-password-$$" "$JAR" "bad"; then
    no "a wrong password was accepted — this test cannot detect a broken login"
    rc=1
else
    ok "rejected, as it must be"
fi

say "3. negative: a protected page with no session must not render"
EMPTY="$WORK/jar.empty"; : > "$EMPTY"
code="$(curl -s -b "$EMPTY" -o "$WORK/anon" -w '%{http_code}' "$HZ_URL/project/instances/")"
loc_ok=0
case "$code" in 302|303) loc_ok=1 ;; esac
if [ "$loc_ok" = "1" ]; then
    ok "unauthenticated request redirected (HTTP $code) instead of rendering the page"
else
    no "unauthenticated request returned $code; expected a redirect to the login page"
    rc=1
fi

say "verdict"
if [ "$rc" -eq 0 ]; then
    echo "PASS: admin sign-in verified, and both negative cases failed as they should"
else
    echo "FAIL: see the lines marked FAIL above"
fi
exit "$rc"
