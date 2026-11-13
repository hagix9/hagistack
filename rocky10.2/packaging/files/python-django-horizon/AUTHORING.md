# Authoring record: python-django-horizon packaging files

These files and `defs/python-django-horizon.toml` were written for Hagistack
from a functional specification, the upstream Horizon 25.7.3 source
(Apache-2.0), rc4's binary-package metadata (paths, modes, owners, file flags,
scriptlet kinds; no file contents: `svc-facts/horizon.txt`), the Hagistack
installer `rocky10.2/hagistack`, and public documentation (systemd.service(5),
systemd.exec(5), logrotate(8), Apache httpd and mod_wsgi documentation, Django
and django-compressor documentation). Upstream paths below are relative to the
unpacked tree `horizon-25.7.3/`.

## Statement of sources

No distribution packaging was consulted: no RDO, Fedora, CentOS, Debian or
Ubuntu packaging, no existing distribution httpd, logrotate or systemd file for
OpenStack or Horizon, and no web search for them. None of the forbidden local
paths (`hagistack-license-decision-2026-11-10/`, `hagistack-u1-*`,
`hagistack-rc*`, `hagistack-ownpkg-2026-11-11/lima`,
`hagistack-ownpkg-2026-11-11/payload`, any `*.rpm`, any `*.spec`,
`rocky10.2/spec-adapt/`, `rocky10.2/build-rpms.sh`) was opened. No network,
build, VM or git command was run. Checks run: a Python syntax parse of
`local_settings`, genspec.py on the definition, test_genspec.py, and a
file-list simulation (upstream tree + the definition's steps, compared with
the rc4 path/mode/owner list; see "Placement check" below).

## Layout (definition, install_extra)

Facts:
- `setup.cfg` `[files] packages` installs three top-level packages: `horizon`,
  `openstack_dashboard`, `openstack_auth`.
- rc4 metadata: `openstack-dashboard` holds `/usr/share/openstack-dashboard/`
  (`manage.py` 0755, `openstack_dashboard/`, `static/`), `/etc/openstack-dashboard/`
  (0750 root:apache; files 0640 root:apache, `%config(noreplace)`),
  `/var/lib/openstack-dashboard` and `/var/log/horizon` (0750 apache:apache),
  `/etc/httpd/conf.d/openstack-dashboard.conf`, `/etc/logrotate.d/openstack-dashboard`,
  `/usr/lib/systemd/system/httpd.service.d/openstack-dashboard.conf` (all 0644,
  `%config(noreplace)`). `python3-django-horizon` holds only doc and licence
  files outside site-packages. `openstack-dashboard-theme` holds NO file outside
  site-packages.
- The rc4 `openstack_dashboard/` tree equals the upstream `openstack_dashboard/`
  tree minus `conf/`, `local/local_settings.py.example` and
  `local/local_settings.d/`, with every `.po` replaced by a `.mo`, plus two
  symlinks (`local/local_settings.py` -> `../../../../../etc/openstack-dashboard/local_settings`,
  `local/local_settings.d` -> `../../../../../etc/openstack-dashboard/local_settings.d`)
  and `__pycache__/*.cpython-312.pyc` + `.opt-1.pyc` for every `.py`
  (including `local/__pycache__/local_settings.*`).
- rc4 `static/` (950 files) equals what `collectstatic` collects from
  `horizon/static`, `openstack_dashboard/static`,
  `openstack_dashboard/dashboards/*/static` and the default and material themes
  (`static/themes/<name>/`), minus `static/horizon/lib/` (the XStatic packages'
  files and Horizon's own `lib/jquery/jquery.bootstrap.wizard.js`), with empty
  `static/dashboard/css` and `static/dashboard/js`. The developer contrib and
  the example theme are absent: they are not enabled by default
  (`openstack_dashboard/contrib/developer/enabled/` are copied to
  `local/enabled` by hand; `defaults.py` lines 96-106 list only default and
  material in `AVAILABLE_THEMES`).
- `settings.py` lines 311-315: `STATIC_ROOT` defaults to `ROOT_PATH/../static`
  (= `/usr/share/openstack-dashboard/static`), `STATIC_URL` to `WEBROOT + 'static/'`;
  line 149 `COMPRESS_OUTPUT_DIR = 'dashboard'`; `utils/settings.py` lines
  284-297: every XStatic package is collected under `horizon/lib/<name>`.

Choices:
- `openstack_dashboard` is copied from the upstream tree (`cp -pr`) rather
  than moved from site-packages, so the content is exactly the tree the rc4
  facts were compared with; the wheel's site-packages copy is removed.
  `horizon` and `openstack_auth` stay in site-packages (`modules`).
- Modes normalised to 0755 (directories) / 0644 (files), `manage.py` 0755, as
  rc4. `manage.py` gets `#!%{python3}`, because the installer runs it directly
  (`hagistack` lines 2868-2871).
- Static tree: `manage.py collectstatic --noinput` once at build time, with a
  temporary `local/local_settings.py` that only sets a synthetic build-only
  `SECRET_KEY` (so `settings.py` lines 332-340 never write a key store; checked
  with `test ! -e`), `python3 -B` (no bytecode carrying build-root paths), then
  `static/horizon/lib` removed (XStatic files are not bundled; the
  httpd.service drop-in collects them from the installed python3-XStatic-*
  packages before httpd starts) and the empty `dashboard/css`, `dashboard/js`
  created. `test -f` checks for `static/app/_app.scss` and
  `static/themes/material/_styles.scss` stop the build if collection did not
  happen. The XStatic packages are present at build time because
  `%pyproject_buildrequires -r` installs the runtime requirements
  (`requirements.txt`).
- Bytecode outside site-packages: `%py_byte_compile` on the project directory,
  after the symlinks exist (so `local_settings` is compiled as in rc4).
- `%{_datadir}/openstack-dashboard/{manage.py,openstack_dashboard,static}` are
  listed as whole trees in `files` (raw `%files` lines), because the generator
  has no "install a tree" entry.

## Packages

- `openstack-dashboard`: everything above, plus `%license LICENSE`.
  Requires: `python3-django-horizon` (same EVR; the project imports
  `horizon`/`openstack_auth`, and their runtime requirements come from upstream
  metadata on that package), `httpd` (configuration and drop-in for it; the
  apache user and group come from it, nothing here creates them),
  `python3-mod_wsgi` (`WSGIDaemonProcess`/`WSGIScriptAlias`),
  `python3-pymemcache` (upstream `local_settings.py.example` lines 94-99 name
  `django.core.cache.backends.memcached.PyMemcacheCache`, and the installer
  configures exactly that backend, `hagistack` lines 2908-2913; upstream
  `requirements.txt` does not list pymemcache).
- `openstack-dashboard-theme`: no files, as in rc4's metadata (nothing outside
  site-packages, and site-packages holds only `horizon` and `openstack_auth`).
  The upstream themes (`openstack_dashboard/themes/{default,material,example}`
  and the collected `static/themes/{default,material}`) are listed under
  `openstack-dashboard` in rc4 and stay there; the default theme is required
  for the dashboard to work at all, so it cannot move to an optional package.
  The package keeps its name (epoch 1, same EVR) and requires
  `openstack-dashboard`.
- `python3-django-horizon`: `horizon` (including
  `horizon/static/horizon/lib/jquery/jquery.bootstrap.wizard.js`, which
  `rocky10.2/THIRD_PARTY_NOTICES.md` lines 48-52 describe; kept unchanged) and
  `openstack_auth`, `%license LICENSE`, `/usr/share/doc/python3-django-horizon/README.rst`
  (`%doc`) and `openstack-dashboard-httpd-logging.conf`.

## Licence tag: `Apache-2.0 AND MIT`

- Horizon is Apache-2.0 (`LICENSE`, `setup.cfg` classifier).
- A grep of `horizon/`, `openstack_dashboard/`, `openstack_auth/` (`*.js`,
  `*.scss`, `*.css`, `*.py`, `*.html`) for MIT/BSD/GPL/OFL/ISC licence
  statements finds one file: `horizon/static/horizon/lib/jquery/jquery.bootstrap.wizard.js`
  (lines 15-25: "Dual licensed under the MIT and GPL licenses"). Hagistack
  distributes it under MIT (THIRD_PARTY_NOTICES.md). No other file carries a
  copyright notice without the Apache licence header.
- rc4's "ASL 2.0 and BSD" named BSD; no BSD-licensed code is left in the 25.7.3
  tree (BSD-licensed D3/Rickshaw are separate XStatic packages,
  `requirements.txt`), so BSD is not part of this tag.

## Translations

Facts: upstream ships `django.po`/`djangojs.po` under `horizon/locale` (50),
`openstack_dashboard/locale` (50) and `openstack_auth/locale` (14); no `.mo`.
rc4's `openstack_dashboard/locale/<lang>/LC_MESSAGES/` holds 50 `.mo` and no
`.po`. Django finds catalogues in each installed app's `locale/` directory.

Choice: `msgfmt` compiles every catalogue in place and the `.po` is removed
(the build stops if one fails). For site-packages the `.po` lines are deleted
from `%{pyproject_files}` and the `.mo` files are listed in `files`; the
generator's `locale_domain` (which moves catalogues to /usr/share/locale) is not
used, because Django would not find them there. `gettext` is a BuildRequires
(`bindep.txt`). The `.mo` files are not `%lang`-marked (rc4 metadata does not
show language flags either).

## local_settings

Upstream `openstack_dashboard/local/local_settings.py.example` with changes
marked `Hagistack:` (a `diff` against upstream shows only these):

1. Header comment (what the file is, where it is installed).
2. `COMPRESS_OFFLINE = True`. The installer relies on offline compression
   (`hagistack` lines 2851-2852 and its OfflineGenerationError retry, lines
   2971-2979), and `manage.py compress` refuses to run without it unless
   `--force` is given. Upstream's commented `not DEBUG` would give False with
   the example's `DEBUG = True`.
3. `WEBROOT = '/dashboard/'`, matching the packaged httpd configuration and the
   installer's `HORIZON_URL_PATH="/dashboard"` (line 2856);
   `settings.py` lines 294-315 derive LOGIN/LOGOUT/STATIC URLs from it.
4. `POLICY_FILES_PATH = '/etc/openstack-dashboard'`: `defaults.py` lines 63-89
   look for `*_policy.yaml`, `nova_policy.d/` and `default_policies/` under
   `POLICY_FILES_PATH`, by default `openstack_dashboard/conf`, which this layout
   moves to /etc (rc4 facts).
5. `LOCAL_PATH = '/var/lib/openstack-dashboard'` instead of the directory of
   the file (which, through the symlink, is under /usr). `settings.py` uses
   `LOCAL_PATH` after the import only for the fallback secret key store
   (lines 332-340); the `local_settings.conf` glob (lines 226-233) and the
   `local_settings.d/*.py` snippets (lines 263-276) use `ROOT_PATH/local` and
   are unaffected.
6. The `SECRET_KEY = secret_key.generate_or_read_from_file(...)` call is
   commented out. `horizon/utils/secret_key.py` lines 46-81: an existing key file
   is read on every import and must be 0600; a new one is created 0600 by the
   calling user. `manage.py` runs as root (httpd.service ExecStartPre, the
   installer), the WSGI processes as apache, so a root-created key file would
   make every dashboard request fail, even after the installer's later
   `SECRET_KEY = ...` assignment (`hagistack` line 2906), because the call
   still runs first. Without any SECRET_KEY, settings.py's own fallback still
   generates one in `LOCAL_PATH`.

Unchanged on purpose: `DEBUG = True`, `OPENSTACK_HOST`, `OPENSTACK_KEYSTONE_URL`,
`LOGGING` (console, i.e. httpd's error log) and the rest: the installer
overrides DEBUG, hosts, keystone URL, caches and sessions in its managed block
appended at the end (`hagistack` lines 2888-2926); nothing in the layout needs
them changed.

## openstack-dashboard.httpd.conf

Facts: installer lines 2842-2844, 2856-2861: the conf.d file is active as
shipped, the dashboard is at `/dashboard` and the login page at
`/dashboard/auth/login/`. `openstack_dashboard/wsgi.py` lines 24-29 put the
parent of its real path on `sys.path`, set `DJANGO_SETTINGS_MODULE` and define
`application`. Static URL and root as above.

Choices (mod_wsgi documentation for each directive):
- `WSGIDaemonProcess openstack-dashboard user=apache group=apache` with its own
  name, distinct from the installer's per-API daemon groups (`hagistack`
  line 942 names them after the service).
- `WSGIScriptAlias ... process-group=... application-group=%{GLOBAL}` instead
  of server-level `WSGIProcessGroup`/`WSGIApplicationGroup`, which would apply
  to every WSGI application of this httpd.
- `Alias /dashboard/static` listed before the WSGI alias (mod_wsgi docs:
  more specific URL first).
- `<Directory>` grants for `wsgi.py` only and for the static tree;
  `Options None`, `AllowOverride None`.

## openstack-dashboard.httpd-dropin.conf

Facts: installer lines 874-897 (ExecStartPre steps write into
`/usr/share/openstack-dashboard/static`; the installer adds
`ReadWritePaths=/usr/share/openstack-dashboard` in
`/etc/systemd/system/httpd.service.d/`), lines 2866-2876 (the same two steps,
`collectstatic` and `compress --force`). systemd.service(5): additional
`ExecStartPre=` lines in a drop-in are appended; a `-` prefix ignores failure;
`TimeoutStartSec=` covers ExecStartPre.

Choices:
- `collectstatic --noinput` (no `--clear`: the packaged files stay in place)
  then `compress --force`, run with `/usr/bin/python3`.
- `-` prefix: httpd also serves other OpenStack APIs on a Hagistack host; a
  dashboard asset failure should not stop them.
- `TimeoutStartSec=300`: the installer notes the steps take about a minute.
- No `ReadWritePaths` here: the installer adds it (task specification). Without
  it the steps fail, httpd still starts, and the dashboard lacks the XStatic
  files and the offline manifest until the installer runs.
- No scriptlet is needed for the drop-in to take effect: the installer runs
  `systemctl daemon-reload` (line 896) and restarts/reloads httpd.

## openstack-dashboard.logrotate

Facts: rc4 ships `/var/log/horizon` (0750 apache:apache) and a logrotate file;
upstream logs to the console by default. logrotate(8): `sharedscripts`,
`postrotate`, `missingok`, `notifempty`, `delaycompress`.

Choices: weekly, 4 rotations, compressed one cycle late; `postrotate`
`systemctl reload httpd.service` because the writers are httpd processes (httpd
log files, or Python file handlers in the mod_wsgi daemons, which a graceful
reload restarts); `|| true` so a stopped httpd is not an error. No `su`: the
directory is not group- or world-writable, and running the reload as apache
would fail.

## openstack-dashboard-httpd-logging.conf

rc4 had a doc file of this name in python3-django-horizon; its content here is
Hagistack's own: an example (not loaded) of a virtual host whose ErrorLog and
CustomLog go to /var/log/horizon, which ties together the directory and the
logrotate file. It is installed with an `install` entry, so it is not flagged
`%doc` (rc4 had flag 2): the generator gives every `install` entry its own plain
`%files` line, and a relative `%doc` in the same package would collide with a
file installed into the same doc directory. README.rst is installed in
`install_extra` and listed with an absolute `%doc` line, so it keeps the flag.

## Scriptlets

rc4 had `%pretrans`, `%post` and `%preun`. None is added:
- the `local_settings.d.rpmmoved` ghost in rc4 shows a directory-to-symlink
  migration, which only matters when upgrading from an older layout;
- the SECRET_KEY is written by the installer (and settings.py has its own
  fallback), and the static assets are rebuilt by the drop-in and the
  installer, so a fresh install needs nothing at install time;
- the apache user and group come from httpd.

## Files that carry no comment

All five files carry a `Hagistack` comment (`local_settings` is Python, the
others use `#`).

## Placement check

A script built the expected path list from the upstream tree and the
definition's steps (with the collectstatic result predicted from the finder
rules above) and compared it with rc4's 5428 paths: all paths, modes and
owners agree except
- `openstack_dashboard/local/local_settings.d.rpmmoved` (rc4 `%ghost`, upgrade
  artefact) is not produced;
- additional owned directories: `/etc/openstack-dashboard/default_policies`,
  `/etc/openstack-dashboard/nova_policy.d` (0750 root:apache, rc4 left them
  unowned) and six `openstack_dashboard/locale/<lang>` directory pairs (brx,
  kok, mai, mni, zh_Hans, zh_Hant) whose `.mo` files rc4 listed without their
  directories.

## Hagistack's dashboard images (stage 6-5, 2026-11-13)

Owner decision T2: the dashboard shows Hagistack's own logo instead of the
OpenStack logo. The images were drawn for Hagistack and were not copied or
traced from any existing logo.
- **Generator.** The images come from `../../branding/make-branding.py`, which
  draws them from rectangles, stroked paths and circles. It uses no font, no
  bitmap and no external file, and `../../branding/test_branding.py` checks that
  its output is the same every time.
- **Mark.** Two pillars with three layers between them: an "H" built as a stack.
  The colours are blue `#3E6FE0` and amber `#F0A830`. It avoids the OpenStack
  logo's red rounded square, the OpenInfra marks and Rocky Linux's green.
- **Wordmark.** "hagistack", in lowercase geometric strokes drawn in the
  generator.
- **Designs considered:**
  - (A) the stacked "H" (chosen: it reads at 16 px and draws with rectangles
    only);
  - (B) chevrons in a hexagon (rejected: hexagons are common in other
    projects' logos, and it does not read at 16 px);
  - (C) a monogram in a rounded square (rejected: a rounded square is close to
    the OpenStack logo's outline).
- **Where they go.** Upstream images that show the OpenStack logo are replaced
  in the source tree in `%prep` (definition `replace_files`). That covers the
  theme lookup (`themable_asset` falls back to `dashboard/img`), the references
  that bypass it (`404.html`, `500.html`, the material theme's splash) and the
  material theme's inline header logo. A theme override alone would have left
  those references showing upstream's images.
  - The `dashboard/img` images: `logo.svg` and `logo-splash.svg` (from
    `hagistack-logo.svg` and `hagistack-logo-splash.svg`), `favicon.ico`,
    `apple-touch-icon.png`, and `safari-pinned-tab.svg` (a one-colour mask).
  - The material theme's `templates/material/openstack-one-color.svg` and
    `-alt.svg`, from `hagistack-material-brand.svg`. That file has no XML
    declaration and no fixed width or height, because `_brand.html` includes it
    inline and the theme's CSS sets only its height.
  - `templates/material/openstack-one-color-alt.svg.old`, an unused leftover
    holding the OpenStack wordmark, is removed in `%prep` (found by the
    independent audit).
- **Sizes**, from upstream's CSS:
  - the header logo is shown 40 px high (`.navbar-brand img`);
  - the splash logo at most 65 % of the login panel (material: 215 px wide);
  - the favicon has entries of 16, 32 and 48 px, and the touch icon is 180 px
    (`_stylesheets.html`).
- **`local_settings`.** `SITE_BRANDING = 'Hagistack Dashboard'` makes the page
  title and the logo's alternative text match the logo. Upstream's default is
  `'OpenStack Dashboard'`.
- **Not changed.** CSS class names (such as `openstack-logo`), package names and
  the text that names the software (Horizon, OpenStack services) are functional
  or descriptive, not branding.
