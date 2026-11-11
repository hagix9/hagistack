# Authoring record: openstack-placement packaging files

These files and `../../defs/openstack-placement.toml` were written for
Hagistack from a functional specification, rc4 binary-package metadata
(paths, modes, owners, rpm file flags, scriptlet kinds; no file contents), the
upstream Placement 15.0.0 source (Apache-2.0), the upstream oslo.config 10.3.0,
oslo.policy 5.0.0 and stevedore 5.7.0 sources (Apache-2.0), Hagistack's own
installer `rocky10.2/hagistack`, Apache httpd/mod_wsgi documentation knowledge
and public man pages. Paths below are relative to the unpacked upstream tree
`openstack_placement-15.0.0/` unless another tree is named.

## Statement of sources

No distribution packaging was consulted: no RDO, Fedora, CentOS, Debian or
Ubuntu packaging, no existing OpenStack `.service`, logrotate, sysusers or
httpd file from any distribution, and no web search for them. None of the
forbidden local paths (`hagistack-license-decision-2026-11-10/`,
`hagistack-u1-*`, `hagistack-rc*`, `hagistack-ownpkg-2026-11-11/lima`,
`hagistack-ownpkg-2026-11-11/payload`, any `*.rpm`, any `*.spec` file,
`rocky10.2/spec-adapt/`, `rocky10.2/build-rpms.sh`) was opened. No network,
build, VM or git command was run. The only checks run were `genspec.py` on the
definition, `test_genspec.py` and `bash -n` on the generated `%build`/`%install`
shell text.

## 00-placement-api.conf

Facts:
- `placement/wsgi/api.py` lines 19-22 build the module-level `application` with
  `wsgi.init_application()`; that is the name mod_wsgi's `WSGIScriptAlias`
  looks for.
- Configuration: `init_application()` reads `OS_PLACEMENT_CONFIG_DIR` if set,
  otherwise oslo.config's default search for `project='placement'`
  (`placement/wsgi/__init__.py` lines 37, 56-69, 81-83), which finds
  `/etc/placement/placement.conf`. Nothing needs to be set in the vhost.
- The installer uses the shipped vhost when it contains
  `placement/wsgi/api.py` (installer lines 2471-2475) and adds a separate
  `<Directory>` grant for `$SITELIB/placement/wsgi`; otherwise it writes its
  own. Its own `write_vhost` (installer lines 927-956) uses port 8778
  (`PLACEMENT_PORT`, line 112), a daemon process with `processes=3 threads=1`
  as the service user, `WSGIApplicationGroup %{GLOBAL}`,
  `WSGIPassAuthorization On`, a `<Directory>` grant on the module's directory
  and logs under `/var/log/httpd`. This file follows that Hagistack text.
- rc4: `/etc/httpd/conf.d/00-placement-api.conf`, 0640 root:root,
  `%config(noreplace)` (facts file).

Choices:
- `Listen 8778` and `<VirtualHost *:8778>`: the port the installer registers in
  the catalog.
- `WSGIDaemonProcess placement-api ... user=placement group=placement`: the API
  runs as the placement user, which can read `/etc/placement/placement.conf`
  (0640 root:placement).
- `WSGIPassAuthorization On`: keystonemiddleware needs the `X-Auth-Token` and
  `Authorization` headers passed to the application.
- The `<Directory>` grant is in the file itself, so it works without the
  installer's extra grant (Apache otherwise answers 403 for a path outside
  DocumentRoot). The installer's grant for the same directory is harmless.
- Logs in `/var/log/httpd`: under SELinux httpd may write there, and the httpd
  package rotates that directory.
- The site-packages path is not written into the file: the placeholder
  `__PYTHON3_SITELIB__` is replaced in `%install` with `%{python3_sitelib}`, and
  the build stops if the placeholder survives, if the `WSGIScriptAlias` line
  does not name `.../placement/wsgi/api.py`, or if that module is not in the
  buildroot. (`@...@` placeholders are avoided because `test_genspec.py`
  rejects them in a spec.)

## openstack-placement.sysusers

Facts: sysusers.d(5); no fixed ID is reserved for placement in the `setup`
package table (specification), so IDs are dynamic (`-`). rc4's
`openstack-placement-common` had a `prein` scriptlet and uses group placement
for `placement.conf` and owner placement for `/var/log/placement` (facts file).

Choices: `g placement -` then `u placement -:placement`; home `/` (Placement
keeps no state on disk; rc4 had no `/var/lib/placement`); shell
`/usr/sbin/nologin`. Installed by the generator as
`/usr/lib/sysusers.d/openstack-placement-common.conf` and applied in `%pre`.

## openstack-placement.logrotate

Facts:
- By default Placement logs to stderr, which mod_wsgi sends to the vhost's
  `ErrorLog`; it writes files only when `log_file`/`log_dir` is set (oslo.log).
  `watch_log_file` defaults to false, so files are not reopened when moved.
- `/var/log/placement` is `0750 placement:root` (facts file): not group- or
  world-writable, which is what logrotate(8) checks.

Choices (logrotate(8)): `copytruncate` (no signal or httpd reload needed),
`weekly`, `rotate 4`, `compress`, `delaycompress`, `missingok`, `notifempty`;
no `su` line, for the reason above.

## Upstream files installed and generated (no Hagistack text)

- `/etc/placement/placement.conf`: generated in `%build` with
  `oslo-config-generator --config-file etc/placement/config-generator.conf`
  (namespaces placement.conf, keystonemiddleware.auth_token, oslo.log,
  oslo.middleware.cors, oslo.middleware.http_proxy_to_wsgi, oslo.policy,
  osprofiler). 0640 root:placement, `%config(noreplace)` (rc4 flags 17).
  osprofiler is not a runtime requirement of Placement (it is an optional
  import, `placement/deploy.py` line 33) but `test-requirements.txt`
  lines 21-22 list it as needed to generate its options, so it is a build
  requirement. Missing namespaces are only warned about by stevedore
  (`stevedore/named.py` lines 38, 92-96), so the build checks that every
  expected section exists. The installer sets its options in this file with
  `ini_set` (installer lines 2457-2465).
- `/usr/share/doc/openstack-placement-common/policy.yaml.sample`: generated
  with `oslopolicy-sample-generator --config-file
  etc/placement/policy-generator.conf`; the build checks that a known rule
  (`placement:resource_providers:list`, `placement/policies/resource_provider.py`
  lines 19-20) is present.

Both generated files pass through the same `hagistack_scrub` function as
Keystone's: option values equal to the build host's name or IPv4 address become
`<current_hostname>` / `<host_ipv4>`, and the build stops if any remain. Static
check: Placement's only build-tree-derived default, `pybasedir`, has
`sample_default='<Path>'` (`placement/conf/paths.py` lines 24-28), so no
replacement is expected.

## Requirements added by hand

- `openstack-placement-api` requires `httpd` and `python3-mod_wsgi`: the file
  is an httpd configuration in httpd's `conf.d` that uses mod_wsgi directives;
  without mod_wsgi httpd refuses to start. (The installer also installs both
  itself, installer lines 2154-2162.)
- Intra-package: `-api` requires `-common`, `-common` and `-tests` require
  `python3-placement`, all at `%{version}-%{release}` (rc4 had no epoch).

## Intended differences from rc4

- `/usr/share/placement/placement-dist.conf` is not shipped; the directory
  `/usr/share/placement` is kept as in rc4.
- The vhost logs to `/var/log/httpd/placement_{error,access}.log`.

## Uncertainties

- The vhost has not been run under httpd in this task (no VM); it uses only
  directives that the installer's own `write_vhost` already uses on real
  installs.
