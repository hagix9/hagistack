"""Tests of s66_web.py against a small local stand-in for Horizon and the docs.

    python3 -B -m unittest test_s66_web
"""
import contextlib
import http.server
import io
import os
import sys
import tempfile
import threading
import unittest
import urllib.parse

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import s66_web  # noqa: E402

LOGO, SPLASH, FAV = b"<svg>hagistack logo</svg>", b"<svg>hagistack splash</svg>", b"ICOhagistack"
DOC = {"hagistack-doc-logo-full.svg": b"<svg>doc full</svg>", "hagistack-doc-logo-full.png": b"PNGfull",
       "hagistack-doc-logo-vert.svg": b"<svg>doc vert</svg>", "hagistack-doc-logo-vert.png": b"PNGvert",
       "hagistack-doc-favicon.ico": b"ICOdoc"}
PASSWORD = "s3cret-Example-Only"


class Site(http.server.BaseHTTPRequestHandler):
    files = {}            # path -> bytes, set per test
    protected = set()

    def log_message(self, *a):
        pass

    def send(self, code, body=b"", headers=()):
        self.send_response(code)
        for k, v in headers:
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path
        if path in self.protected and "sessionid=ok" not in (self.headers.get("Cookie") or ""):
            return self.send(302, headers=[("Location", "/dashboard/auth/login/?next=" + path)])
        if path in self.files:
            return self.send(200, self.files[path])
        self.send(404, b"not found")

    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        form = urllib.parse.parse_qs(self.rfile.read(n).decode())
        if form.get("password") == [PASSWORD] and form.get("csrfmiddlewaretoken") == ["tok"] \
                and form.get("region") == ["default"]:
            return self.send(302, headers=[("Location", "/dashboard/"), ("Set-Cookie", "sessionid=ok; Path=/")])
        self.send(200, b'<form><input type="password" name="password"></form>')


LOGIN = b'''<html><head><link rel="shortcut icon" href="/dashboard/static/dashboard/img/favicon.ico">
<link rel="stylesheet" href="/dashboard/static/dashboard/css/a.css"></head>
<body><img class="splash-logo" src="/dashboard/static/dashboard/img/logo-splash.svg">
<form method="POST" action="/dashboard/auth/login/">
<input type="hidden" name="csrfmiddlewaretoken" value="tok"><input type="hidden" name="region" value="default">
<input name="username"><input type="password" name="password"></form></body></html>'''
ADMIN = b'''<html><head><link rel="icon" href="/dashboard/static/dashboard/img/favicon.ico"></head>
<body><img src="/dashboard/static/dashboard/img/logo.svg"> admin</body></html>'''


def horizon_files(**over):
    f = {"/dashboard/auth/login/": LOGIN, "/dashboard/admin/": ADMIN, "/dashboard/admin/hypervisors/": ADMIN,
         "/dashboard/project/instances/": ADMIN,
         "/dashboard/static/dashboard/css/a.css": b"body{background:url('../img/bg.png')} .x{src:url(data:abc)}",
         "/dashboard/static/dashboard/img/bg.png": b"PNG",
         "/dashboard/static/dashboard/img/favicon.ico": FAV,
         "/dashboard/static/dashboard/img/logo.svg": LOGO,
         "/dashboard/static/dashboard/img/logo-splash.svg": SPLASH}
    f.update(over)
    return {k: v for k, v in f.items() if v is not None}


class Server:
    def __enter__(self):
        self.httpd = http.server.HTTPServer(("127.0.0.1", 0), Site)
        self.t = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.t.start()
        return "http://127.0.0.1:%d" % self.httpd.server_address[1]

    def __exit__(self, *a):
        self.httpd.shutdown()
        self.httpd.server_close()


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR"))
        d = self.tmp.name
        self.images = os.path.join(d, "img")
        self.docimg = os.path.join(d, "doc")
        os.makedirs(self.images)
        os.makedirs(self.docimg)
        for n, b in (("hagistack-logo.svg", LOGO), ("hagistack-logo-splash.svg", SPLASH),
                     ("hagistack-favicon.ico", FAV)):
            with open(os.path.join(self.images, n), "wb") as f:
                f.write(b)
        for n, b in DOC.items():
            with open(os.path.join(self.docimg, n), "wb") as f:
                f.write(b)
        self.openrc = os.path.join(d, "openrc")
        with open(self.openrc, "w") as f:
            f.write("export OS_USERNAME=admin\nexport OS_PASSWORD=%s\n" % PASSWORD)
        Site.protected = {"/dashboard/admin/", "/dashboard/admin/hypervisors/", "/dashboard/project/instances/"}

    def tearDown(self):
        self.tmp.cleanup()

    def run_web(self, *args):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = s66_web.main(list(args))
        return rc, buf.getvalue()

    def horizon(self, files):
        Site.files = files
        with Server() as url:
            return self.run_web("horizon", "--base", url + "/dashboard", "--openrc", self.openrc,
                                "--images", self.images)


class Horizon(Base):
    def test_a_good_site_passes_and_the_password_is_not_printed(self):
        rc, out = self.horizon(horizon_files())
        self.assertEqual(rc, 0, out)
        self.assertIn("PASS  a checked page loads logo.svg", out)
        self.assertIn("PASS  a checked page loads logo-splash.svg", out)
        self.assertNotIn(PASSWORD, out)

    def test_the_upstream_logo_fails(self):
        rc, out = self.horizon(horizon_files(**{"/dashboard/static/dashboard/img/logo.svg": b"<svg>OpenStack</svg>"}))
        self.assertEqual(rc, 1, out)
        self.assertIn("FAIL", out)

    def test_a_missing_image_fails(self):
        rc, out = self.horizon(horizon_files(**{"/dashboard/static/dashboard/img/bg.png": None}))
        self.assertEqual(rc, 1, out)
        self.assertIn("bg.png returned HTTP 404", out)

    def test_an_image_from_another_host_fails(self):
        page = ADMIN.replace(b"</body>", b'<img src="https://cdn.example.com/x.png"></body>')
        rc, out = self.horizon(horizon_files(**{"/dashboard/admin/": page}))
        self.assertEqual(rc, 1, out)
        self.assertIn("from another host", out)

    def test_a_script_from_another_host_is_a_note(self):
        page = ADMIN.replace(b"</body>", b'<script src="https://cdn.example.com/x.js"></script></body>')
        rc, out = self.horizon(horizon_files(**{"/dashboard/admin/": page}))
        self.assertEqual(rc, 0, out)
        self.assertIn("NOTE", out)

    def test_a_wrong_password_fails(self):
        with open(self.openrc, "w") as f:
            f.write("export OS_USERNAME=admin\nexport OS_PASSWORD='wrong'\n")
        rc, out = self.horizon(horizon_files())
        self.assertEqual(rc, 1, out)
        self.assertIn("FAIL  admin sign-in", out)

    def test_a_page_that_does_not_load_the_header_logo_fails(self):
        page = ADMIN.replace(b'<img src="/dashboard/static/dashboard/img/logo.svg">', b"")
        rc, out = self.horizon(horizon_files(**{"/dashboard/admin/": page, "/dashboard/admin/hypervisors/": page,
                                                "/dashboard/project/instances/": page}))
        self.assertEqual(rc, 1, out)
        self.assertIn("FAIL  a checked page loads logo.svg", out)

    def test_a_protected_page_without_session_fails(self):
        Site.files = horizon_files()
        # the sign-in "succeeds" but the session is never accepted
        orig = Site.do_POST
        Site.do_POST = lambda self: self.send(302, headers=[("Location", "/dashboard/")])
        try:
            with Server() as url:
                rc, out = self.run_web("horizon", "--base", url + "/dashboard", "--openrc", self.openrc,
                                       "--images", self.images)
        finally:
            Site.do_POST = orig
        self.assertEqual(rc, 1, out)
        self.assertIn("not the login form (302)", out)


class Docs(Base):
    def docs_files(self, **over):
        f = {"/index.html": b'<link rel="stylesheet" href="_static/css/t.css"><img src="_static/images/logo-full.svg">',
             "/_static/css/t.css": b".h{background:url(../images/logo-vert.png)}"}
        for key, img in s66_web.DOC_IMAGES.items():
            f["/_static/" + key] = DOC[img]
        f.update(over)
        return {k: v for k, v in f.items() if v is not None}

    def docs(self, files):
        Site.files = files
        Site.protected = set()
        with Server() as url:
            return self.run_web("docs", "--base", url, "--images", self.docimg)

    def test_good_docs_pass(self):
        rc, out = self.docs(self.docs_files())
        self.assertEqual(rc, 0, out)
        self.assertIn("images/logo-full.svg", out)

    def test_an_upstream_theme_logo_fails_even_when_not_shown(self):
        rc, out = self.docs(self.docs_files(**{"/_static/images/openstack-logo-vert.svg": b"<svg>OpenStack</svg>"}))
        self.assertEqual(rc, 1, out)

    def test_a_missing_page_image_fails(self):
        rc, out = self.docs(self.docs_files(**{"/index.html": b'<img src="_static/images/nothere.png">'}))
        self.assertEqual(rc, 1, out)
        self.assertIn("HTTP 404", out)


if __name__ == "__main__":
    unittest.main()
