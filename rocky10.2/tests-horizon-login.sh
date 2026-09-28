#!/bin/bash
# Horizon acceptance: a real admin sign-in, not a 200 on the login page.
# Every hidden field is read back from the rendered form rather than guessed:
# Horizon's "region" is the literal string "default", not the Keystone URL, and
# guessing it produces "Invalid region ''" with a 200 that looks like success.
set -u
say(){ printf '\n======== %s ========\n' "$*"; }
H="http://127.0.0.1/dashboard"
J=$(mktemp); trap 'rm -f "$J" /tmp/hz.*' EXIT
. /etc/hagistack/admin-openrc

say "1. login page"
code=$(curl -s -c "$J" -o /tmp/hz.login -w '%{http_code}' "$H/auth/login/")
echo "GET $H/auth/login/ -> HTTP $code"
[ "$code" = "200" ] || { echo "FAIL: login page did not return 200"; exit 1; }

# every hidden input, name=value, as the server rendered it
python3 - > /tmp/hz.fields <<'PY'
import re,html
h=open("/tmp/hz.login",encoding="utf-8",errors="replace").read()
for m in re.finditer(r'<input[^>]*type="hidden"[^>]*>', h):
    tag=m.group(0)
    n=re.search(r'name="([^"]*)"',tag); v=re.search(r'value="([^"]*)"',tag)
    if n: print(f"{n.group(1)}={html.unescape(v.group(1)) if v else ''}")
PY
echo "hidden fields the form carries:"; sed 's/=.*/=<value>/' /tmp/hz.fields | sed 's/^/  /'
grep -q '^csrfmiddlewaretoken=' /tmp/hz.fields || { echo "FAIL: no CSRF token"; exit 1; }

ARGS=()
while IFS='=' read -r k v; do ARGS+=(--data-urlencode "$k=$v"); done < /tmp/hz.fields

say "2. POST the admin credentials"
code=$(curl -s -b "$J" -c "$J" -o /tmp/hz.post -w '%{http_code}' -e "$H/auth/login/" \
  "${ARGS[@]}" -d "username=$OS_USERNAME" --data-urlencode "password=$OS_PASSWORD" \
  "$H/auth/login/")
echo "POST -> HTTP $code"
if grep -oiE "Invalid[^<]{0,60}" /tmp/hz.post | head -2 | grep -q .; then
  echo "server said:"; grep -oiE "Invalid[^<]{0,60}" /tmp/hz.post | head -2 | sed 's/^/  /'
fi
grep -q 'sessionid' "$J" && echo "sessionid cookie ISSUED" || { echo "FAIL: no sessionid"; exit 1; }

say "3. fetch authenticated pages"
fail=0
for p in "/project/instances/" "/identity/" "/project/networks/" "/project/api_access/"; do
  code=$(curl -s -L -b "$J" -c "$J" -o /tmp/hz.page -w '%{http_code}' "$H$p")
  isform=$(grep -c 'id="loginBtn"' /tmp/hz.page 2>/dev/null || true)
  who=$(grep -c ">$OS_USERNAME<" /tmp/hz.page 2>/dev/null || true)
  printf '  %-26s HTTP %-4s login-form=%-3s %s-in-page=%s\n' "$p" "$code" "${isform:-0}" "$OS_USERNAME" "${who:-0}"
  [ "$code" = "200" ] || fail=1
  [ "${isform:-0}" = "0" ] || fail=1
done

say "4. verdict"
if [ "$fail" -eq 0 ]; then echo "PASS: authenticated session; pages render with no login form"; else echo "FAIL"; fi
exit $fail
