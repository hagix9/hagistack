# Authoring record: openstack-keystone packaging files

These files and `../../defs/openstack-keystone.toml` were written for Hagistack
from a functional specification, rc4 binary-package metadata (paths, modes,
owners, rpm file flags, scriptlet kinds; no file contents), the upstream
Keystone 29.1.0 source (Apache-2.0), the upstream oslo.config 10.3.0,
oslo.messaging 17.3.0 and stevedore 5.7.0 sources (Apache-2.0), Hagistack's own
installer `rocky10.2/hagistack`, and public man pages. Paths below are relative
to the unpacked upstream tree `keystone-29.1.0/` unless another tree is named.

## Statement of sources

No distribution packaging was consulted: no RDO, Fedora, CentOS, Debian or
Ubuntu packaging, no existing OpenStack `.service`, logrotate, sysusers,
tmpfiles or httpd file from any distribution, and no web search for them. None
of the forbidden local paths (`hagistack-license-decision-2026-11-10/`,
`hagistack-u1-*`, `hagistack-rc*`, `hagistack-ownpkg-2026-11-11/lima`,
`hagistack-ownpkg-2026-11-11/payload`, any `*.rpm`, any `*.spec` file,
`rocky10.2/spec-adapt/`, `rocky10.2/build-rpms.sh`) was opened. No network,
build, VM or git command was run. The only checks run were `genspec.py` on the
definition, `test_genspec.py`, `bash -n` on the generated `%build`/`%install`
shell text, `sh -n` on `openstack-keystone-sample-data`, and a local run of the
`hagistack_scrub` shell function on two hand-made test files.

## openstack-keystone.sysusers

Facts: sysusers.d(5) syntax `g name GID` and `u name UID:GROUP "GECOS" home
shell`. The ID 163 is the one reserved for keystone in the Fedora/EL `setup`
package's uidgid table, as stated in the specification. rc4's
`/var/lib/keystone` is `0755 keystone:keystone` (facts file).

Choices: group line first so the user line can name it; home `/var/lib/keystone`
(the package's state directory); shell `/usr/sbin/nologin` (a service account
never logs in). GECOS text written for this file. Installed by the generator as
`/usr/lib/sysusers.d/openstack-keystone.conf` and applied in `%pre` with
`%sysusers_create_compat` (rc4 also had a `prein` scriptlet).

## openstack-keystone.tmpfiles

Facts:
- rc4 listed `/var/log/keystone/keystone.log` as `%ghost`, `0660 root:keystone`,
  and had a `postin` scriptlet (facts file). The observable result to keep: the
  file exists with that owner and mode after installation.
- tmpfiles.d(5): type `f` creates a file with the given mode, user and group if
  it does not exist yet, and leaves an existing file alone.

Choices: one `f` line, applied in `%post` by the standard systemd-rpm-macros
`%tmpfiles_create`, and applied again at boot by systemd-tmpfiles-setup, so the
file is recreated if an operator deletes it. The definition still lists the
file as `%ghost %attr(0660, root, keystone)` so that `rpm -qf` names the
package and the file goes away on erase, like rc4. Mode 0660 with group keystone
lets both the httpd mod_wsgi daemon (user keystone, from the installer's
`write_vhost keystone ... keystone`, installer line 2364) and `keystone-manage`
run as root write the same file.

## openstack-keystone.logrotate

Facts:
- Keystone logs through oslo.log; with `log_file` set it uses a plain file and
  `watch_log_file` defaults to false (oslo.log `_options.py`), so the file is
  not reopened when moved. Keystone runs inside httpd/mod_wsgi (installer
  line 2364) and as short `keystone-manage` runs.
- `/var/log/keystone` is `0750 keystone:keystone` (facts file): not group- or
  world-writable, which is what logrotate(8) checks before refusing a directory.

Choices (logrotate(8)): `copytruncate`, so no signal or httpd reload is needed
and the file keeps its owner and mode (`root:keystone 0660`); `weekly`,
`rotate 4`, `compress`, `delaycompress`, `missingok`, `notifempty`. No `su`
line: the directory is not group/world writable, and rotating as root lets
logrotate truncate the root-owned file.

## openstack-keystone-sample-data

Facts: upstream `tools/sample_data.sh` is a bash script that bootstraps sample
projects and users with python-openstackclient (lines 41-45 check for
`openstack`; lines 47-60 read `ADMIN_PASSWORD`, `SERVICE_PASSWORD`,
`KEYSTONE_CONF` and others from the environment). The package installs it as
`/usr/share/keystone/sample_data.sh`, 0755 (facts file). rc4 also had
`/usr/bin/openstack-keystone-sample-data`, 0755.

Choices: a three-line POSIX sh wrapper that `exec`s the installed script with
all arguments; the environment passes through unchanged. The script itself
does not need its own path except for a git-checkout fallback (line 59-66),
which is harmless here.

## Upstream files installed (no Hagistack text)

- `/etc/keystone/keystone.conf`: generated in `%build` by
  `oslo-config-generator --config-file config-generator/keystone.conf`
  (upstream generator config; namespaces keystone, oslo.cache, oslo.log,
  oslo.messaging, oslo.policy, oslo.db, oslo.middleware, osprofiler). All of
  their libraries are runtime requirements in `requirements.txt`, so
  `%pyproject_buildrequires -r` installs them. stevedore's
  `NamedExtensionManager` only warns about a missing name
  (`stevedore/named.py` lines 38, 92-96, used by `oslo_config/generator.py`
  lines 505-511), so the build checks that the expected sections exist and
  stops otherwise. Mode 0640 root:keystone, `%config(noreplace)` (rc4 flags 17).
  The installer creates this file only when it is missing and then sets
  options in it with `ini_set` (installer lines 2322-2336), so a full sample
  with every option commented out works with it.
- `/etc/keystone/logging.conf`: upstream `etc/logging.conf.sample`.
- `/etc/keystone/sso_callback_template.html`: upstream
  `etc/sso_callback_template.html`; Keystone's default
  `[federation] sso_callback_template` is this path
  (`keystone/conf/federation.py` lines 93-95). Owner keystone:keystone 0640
  as in rc4. The wheel's own copy under `/usr/etc/keystone`
  (`pyproject.toml` lines 179-181, data-files) is removed after install.
- `/usr/share/keystone/uwsgi-keystone.conf`: upstream `httpd/uwsgi-keystone.conf`.
- `/usr/share/keystone/sample_data.sh`: upstream `tools/sample_data.sh`.

## Build-host identity in generated files

The `hagistack_scrub` shell function in the definition's `build_extra` runs on
every generated file. It replaces an option value that equals the build host's
name (`uname -n`, skipped when it is `localhost`) with `<current_hostname>`
and one that equals a non-loopback IPv4 address of the build host (from
`getent ahostsv4` and the source address of an unconnected UDP route lookup)
with `<host_ipv4>`. It then stops the build if any option line still contains
the name or any line contains such an address. Static check of the sources: the
only option in these namespaces whose default comes from the host is
oslo.messaging's `[oslo_messaging_rabbit] hostname`, and it has
`sample_default='node1.example.com'` (`oslo_messaging/_drivers/impl_rabbit.py`
lines 268-269), so no replacement is expected; the check is a safety net.

## Intended differences from rc4

- `/usr/share/keystone/keystone-dist.conf` is not shipped: nothing reads it at
  run time and the installer writes `/etc/keystone/keystone.conf` itself.
- `/usr/lib/tmpfiles.d/openstack-keystone.conf` is new; it creates the log
  file in place of rc4's own `%post` script.

## Uncertainties

- `%tmpfiles_create` does nothing when `systemd-tmpfiles` is missing (for
  example in a container without systemd); the log file is then created at
  the next boot, or by Keystone when it opens it. The generator cannot express
  `Requires(post): systemd`; on Rocky 10.2 systemd is always installed.
- `sample_data.sh` needs `python3-openstackclient` at run time; this is not a
  package requirement (the script checks and says so, lines 41-45).
