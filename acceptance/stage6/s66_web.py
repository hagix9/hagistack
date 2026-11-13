#!/usr/bin/python3 -I
"""Stage 6-6 page checks: what a browser would load, fetched and asserted.

  s66_web.py horizon --base URL --openrc FILE --images DIR
  s66_web.py docs    --base URL --images DIR

For each page it fetches every image, stylesheet, script and icon the page
names, and every url(...) inside those stylesheets, and requires HTTP 200 for
each one on the page's own server. A resource on another host is a FAIL for
an image and a NOTE otherwise (a browser would try to load it; this check does
not). It does not render anything: a page that loads but draws wrongly is not
caught.

horizon: signs in as the administrator of the openrc file (the password is read
from the file and sent only in the POST body, never printed), then checks the
login page, two admin pages and one project page. The Hagistack logos must be
the bytes in --images (hagistack-logo.svg, -logo-splash.svg, -favicon.ico),
and the splash logo, the header logo and the favicon must each be loaded by
some checked page.

docs: checks the documentation index page. Every theme logo it loads must be
the bytes in --images (hagistack-doc-*), and each of the theme's logo and
favicon paths under _static/ must serve those bytes too. Which of them the page
itself shows depends on the theme's templates and is reported as a NOTE.

One PASS / FAIL / NOTE line per check; exit 1 if any check failed. Standard
library only.
"""
import argparse
import html.parser
import http.cookiejar
import posixpath
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

# by file name: the page may load them from the dashboard's or a theme's static
# directory, and every served file of that name must be Hagistack's
HORIZON_IMAGES = {
    "logo.svg": "hagistack-logo.svg",
    "logo-splash.svg": "hagistack-logo-splash.svg",
    "favicon.ico": "hagistack-favicon.ico",
}
DOC_IMAGES = {
    "images/logo-full.svg": "hagistack-doc-logo-full.svg",
    "images/logo-full.png": "hagistack-doc-logo-full.png",
    "images/logo-vert.svg": "hagistack-doc-logo-vert.svg",
    "images/logo-vert.png": "hagistack-doc-logo-vert.png",
    "images/openstack-logo-full.svg": "hagistack-doc-logo-full.svg",
    "images/openstack-logo-full.png": "hagistack-doc-logo-full.png",
    "images/openstack-logo-vert.svg": "hagistack-doc-logo-vert.svg",
    "images/openstack-logo-vert.png": "hagistack-doc-logo-vert.png",
    "favicon.ico": "hagistack-doc-favicon.ico",
}
IMAGE_EXT = (".svg", ".png", ".jpg", ".jpeg", ".gif", ".ico", ".webp")
TIMEOUT = 30


class Report:
    def __init__(self):
        self.failed = 0

    def line(self, kind, msg):
        print("%-5s %s" % (kind, msg))
        if kind == "FAIL":
            self.failed += 1

    def check(self, ok, msg):
        self.line("PASS" if ok else "FAIL", msg)
        return ok


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Refs(html.parser.HTMLParser):
    """The resources a browser loads for a page (not links it may follow)."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.refs = []      # (kind, url)
        self.forms = []     # (action, {hidden name: value})
        self._form = None

    def handle_starttag(self, tag, attrs):
        a = {k: (v or "") for k, v in attrs}
        if tag == "img" and a.get("src"):
            self.refs.append(("image", a["src"]))
        elif tag == "script" and a.get("src"):
            self.refs.append(("script", a["src"]))
        elif tag == "link" and a.get("href"):
            rel = a.get("rel", "").lower().split()
            if "stylesheet" in rel:
                self.refs.append(("style", a["href"]))
            elif {"icon", "apple-touch-icon", "mask-icon"} & set(rel):
                self.refs.append(("image", a["href"]))
        elif tag in ("image", "use") and (a.get("href") or a.get("xlink:href")):
            self.refs.append(("image", a.get("href") or a.get("xlink:href")))
        elif tag == "form":
            self._form = (a.get("action", ""), {})
            self.forms.append(self._form)
        elif tag == "input" and self._form is not None and a.get("type", "").lower() == "hidden" and a.get("name"):
            self._form[1][a["name"]] = a.get("value", "")

    def handle_endtag(self, tag):
        if tag == "form":
            self._form = None


CSS_URL = re.compile(r"url\(\s*(['\"]?)([^'\")]+)\1\s*\)")
CSS_IMPORT = re.compile(r"@import\s+(['\"])([^'\"]+)\1")


class Fetcher:
    def __init__(self, base, report):
        self.base = base.rstrip("/") + "/"
        self.origin = urllib.parse.urlsplit(self.base)[:2]
        self.jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.jar), NoRedirect)
        self.r = report
        self.seen = {}      # url -> (status, bytes)

    def get(self, url, data=None, headers=None):
        """(status, body, headers); a redirect is returned, not followed."""
        req = urllib.request.Request(url, data=data, headers=headers or {})
        try:
            with self.opener.open(req, timeout=TIMEOUT) as resp:
                return resp.status, resp.read(), resp.headers
        except urllib.error.HTTPError as e:
            return e.code, e.read() if e.fp else b"", e.headers
        except (urllib.error.URLError, OSError) as e:
            return 0, str(e).encode(), {}

    def own(self, url):
        return urllib.parse.urlsplit(url)[:2] == self.origin

    def assets(self, page_url, body):
        """Fetch what the page loads; returns {path: bytes} of what loaded."""
        p = Refs()
        p.feed(body.decode("utf-8", "replace"))
        loaded = {}
        todo = [(k, urllib.parse.urljoin(page_url, u)) for k, u in p.refs]
        while todo:
            kind, url = todo.pop(0)
            url = urllib.parse.urldefrag(url)[0]
            if url.startswith("data:"):
                continue
            if not self.own(url):
                is_img = kind == "image" or urllib.parse.urlsplit(url).path.lower().endswith(IMAGE_EXT)
                self.r.line("FAIL" if is_img else "NOTE",
                            "%s loads %s from another host: %s" % (page_url, kind, url))
                continue
            if url not in self.seen:
                st, data, _h = self.get(url)
                self.seen[url] = (st, data)
                if st != 200:
                    self.r.line("FAIL", "%s: %s %s returned HTTP %s" % (page_url, kind, url, st))
                if st == 200 and kind == "style":
                    css = data.decode("utf-8", "replace")
                    for m in CSS_IMPORT.finditer(css):
                        todo.append(("style", urllib.parse.urljoin(url, m.group(2))))
                    for m in CSS_URL.finditer(css):
                        u = m.group(2).strip()
                        if not u.startswith("data:"):
                            todo.append(("image" if u.split("?")[0].lower().endswith(IMAGE_EXT) else "font",
                                         urllib.parse.urljoin(url, u)))
            st, data = self.seen[url]
            if st == 200:
                loaded[urllib.parse.urlsplit(url).path] = data
        bad = sum(1 for u in self.seen if self.seen[u][0] != 200)
        self.r.line("NOTE", "%s: %d resources fetched so far, %d not HTTP 200" % (page_url, len(self.seen), bad))
        return loaded


def read_images(directory, names):
    out = {}
    for n in set(names.values()):
        with open(posixpath.join(directory, n), "rb") as f:
            out[n] = f.read()
    return out


def match_images(loaded, mapping, images, r, where):
    """Every loaded file at a mapped path must be Hagistack's; returns the mapped keys seen."""
    seen = set()
    for path, data in loaded.items():
        for key, img in mapping.items():
            if path.endswith("/" + key):
                seen.add(key)
                r.check(data == images[img], "%s: %s is Hagistack's %s" % (where, path, img))
    return seen


def openrc_value(path, key):
    with open(path) as f:
        for line in f:
            m = re.match(r"\s*(?:export\s+)?%s=(.*)$" % key, line.rstrip("\n"))
            if m:
                v = m.group(1).strip()
                if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
                    v = v[1:-1]
                return v
    raise SystemExit("FAIL  %s has no %s" % (path, key))


def horizon(a, r):
    f = Fetcher(a.base, r)
    images = read_images(a.images, HORIZON_IMAGES)
    seen = set()
    login = f.base + "auth/login/"
    st, body, _h = f.get(login)
    if not r.check(st == 200, "login page %s returns HTTP 200 (%s)" % (login, st)):
        return
    seen |= match_images(f.assets(login, body), HORIZON_IMAGES, images, r, "login page")
    p = Refs()
    p.feed(body.decode("utf-8", "replace"))
    form = next((fm for fm in p.forms if "csrfmiddlewaretoken" in fm[1]), None)
    if not r.check(form is not None, "login page has a form with a CSRF token"):
        return
    fields = dict(form[1])
    fields["username"] = openrc_value(a.openrc, "OS_USERNAME")
    fields["password"] = openrc_value(a.openrc, "OS_PASSWORD")
    st, _b, h = f.get(login, urllib.parse.urlencode(fields).encode(),
                      {"Referer": login, "Content-Type": "application/x-www-form-urlencoded"})
    loc = (h.get("Location") if h else "") or ""
    if not r.check(st in (302, 303) and "/auth/login" not in loc,
                   "admin sign-in redirects away from the login page (HTTP %s)" % st):
        return
    for page in ("admin/", "admin/hypervisors/", "project/instances/"):
        url = f.base + page
        st, body, _h = f.get(url)
        text = body.decode("utf-8", "replace")
        if not r.check(st == 200 and 'name="password"' not in text,
                       "%s returns HTTP 200 with a session, not the login form (%s)" % (url, st)):
            continue
        seen |= match_images(f.assets(url, body), HORIZON_IMAGES, images, r, page)
    for key in HORIZON_IMAGES:
        r.check(key in seen, "a checked page loads %s" % key)


def docs(a, r):
    f = Fetcher(a.base, r)
    mapping = {"_static/" + k: v for k, v in DOC_IMAGES.items()}
    images = read_images(a.images, DOC_IMAGES)
    url = f.base + "index.html"
    st, body, _h = f.get(url)
    if not r.check(st == 200, "documentation index %s returns HTTP 200 (%s)" % (url, st)):
        return
    seen = match_images(f.assets(url, body), mapping, images, r, "documentation index")
    r.line("NOTE", "theme images the index loads: %s" % (", ".join(sorted(seen)) or "none"))
    # the theme's logo files themselves, whether or not this page shows one
    for key, img in sorted(mapping.items()):
        st, data, _h = f.get(f.base + key)
        r.check(st == 200 and data == images[img], "%s%s is Hagistack's %s (HTTP %s)" % (f.base, key, img, st))


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("what", choices=["horizon", "docs"])
    ap.add_argument("--base", required=True)
    ap.add_argument("--images", required=True)
    ap.add_argument("--openrc")
    a = ap.parse_args(argv)
    if a.what == "horizon" and not a.openrc:
        ap.error("horizon needs --openrc")
    r = Report()
    (horizon if a.what == "horizon" else docs)(a, r)
    print("%d check(s) failed" % r.failed)
    return 1 if r.failed else 0


if __name__ == "__main__":
    sys.exit(main())
