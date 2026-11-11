# Authoring record: openstack-nova packaging files

These files and `../../defs/openstack-nova.toml` were written for Hagistack from a
functional specification, rc4's binary-package metadata facts (paths, modes,
owners, file flags, scriptlet kinds; no file contents), Hagistack's installer
`rocky10.2/hagistack`, the upstream sources (Apache-2.0) of Nova 33.0.2,
oslo.rootwrap 7.9.0, oslo.privsep 3.10.1, oslo.config 10.3.0, oslo.service 4.5.1,
oslo.messaging 17.3.0, os-vif 4.3.0, os-brick 7.0.0 and osprofiler 4.3.0, and
public documentation (systemd.service(5), systemd.exec(5), sysusers.d(5),
sudoers(5), logrotate(8), sshd(8), sshd_config(5), ssh_config(5), scp(1),
the oslo.rootwrap and oslo.privsep documentation, the libvirt documentation).
Upstream paths below are relative to the unpacked tree named in front of them;
`nova:` means `nova-33.0.2/`.

## Statement of sources

No distribution packaging was consulted: no RDO, Fedora, CentOS, Debian or
Ubuntu packaging, no existing OpenStack `.service`, logrotate, sudoers, httpd,
sysusers, rootwrap or migration-wrapper file from any distribution, and no web
search for them. None of the forbidden local paths
(`hagistack-license-decision-2026-11-10/`, `hagistack-u1-*`, `hagistack-rc*`,
`hagistack-ownpkg-2026-11-11/lima`, `hagistack-ownpkg-2026-11-11/payload`, any
`*.rpm`, any `*.spec`, `rocky10.2/spec-adapt/`, `rocky10.2/build-rpms.sh`) was
opened. No network, build, VM, cloud or git command was run. Checks run:
`genspec.py` and `test_genspec.py`; `visudo -c -f` on both sudoers files (parsed
OK); `bash -n` on the wrapper; the wrapper exercised with stubbed
`sudo`/`logger`/`realpath` in a scratch directory (accepted and refused forms);
`cold_migration.filters` loaded and matched with upstream oslo.rootwrap's own
`load_filters`/`RegExpFilter.match`; the INI files parsed with configparser.

## Binary packages (facts: svc-facts/nova.txt)

All twelve rc4 packages exist with the same names and epoch 1.

- **openstack-nova** (meta, no files, as rc4). Requires the packages of a
  complete single-host Nova with the default console: -api, -conductor,
  -scheduler, -compute, -novncproxy. VNC is the console enabled by default
  (`nova:nova/conf/vnc.py:28`); SPICE and serial consoles are disabled by
  default (`nova:nova/conf/spice.py:61`, `nova:nova/conf/serial_console.py:28`),
  so their proxies are not pulled in. -migration is not pulled in because it
  creates an SSH login account (opt-in). python3-nova-tests is not pulled in.
- **openstack-nova-api**: rc4 held only three units (`openstack-nova-api`,
  `-metadata-api`, `-os-compute-api`) that start binaries 2026.1 no longer
  builds (no `nova-api*` console scripts in `nova:pyproject.toml` `[project.scripts]`).
  They are intentionally not shipped (installer lines 27-43 and 2788-2799 serve
  both APIs through httpd from `nova/wsgi/osapi_compute.py` and
  `nova/wsgi/metadata.py` and only disables those units if present). What is
  left of the API side lives elsewhere: the WSGI modules in python3-nova and
  `api-paste.ini` in -common. The package therefore has no files and requires
  openstack-nova-common (which requires python3-nova); it still exists so the
  installer's `dnf install openstack-nova-api` (installer line 2159) works. No
  systemd scriptlets, since it has no units (rc4 had postin/preun/postun).
- **openstack-nova-common**: all rc4 paths, modes, owners and flags except the
  intended omission `/usr/share/nova/nova-dist.conf` (never read at run time).
  `prein` = sysusers. One addition: `/usr/lib/sysusers.d/openstack-nova-common.conf`.
- **openstack-nova-compute**: as rc4 plus `/usr/lib/sysusers.d/openstack-nova-compute.conf`
  and ownership of the directory `/usr/share/nova/rootwrap` (rc4 left it unowned).
- **openstack-nova-conductor, -scheduler, -novncproxy, -serialproxy,
  -spicehtml5proxy**: binary, Hagistack unit, standard systemd scriptlets; the
  novncproxy sysconfig file as rc4.
- **openstack-nova-migration**: all rc4 paths, modes, owners and flags; plus
  `/usr/lib/sysusers.d/openstack-nova-migration.conf`.
- **python3-nova**, **python3-nova-tests**: modules, tests split at
  `nova/tests`, `LICENSE` under `/usr/share/licenses/<package>/` as rc4.

## Generated files (definition `build_extra`)

- `/etc/nova/nova.conf` is `etc/nova/nova.conf.sample` produced by
  `oslo-config-generator --config-file etc/nova/nova-config-generator.conf`,
  and `/usr/share/doc/openstack-nova-common/policy.yaml.sample` by
  `oslopolicy-sample-generator --config-file etc/nova/nova-policy-generator.conf`,
  the same commands as upstream `nova:tox.ini:206-214`.
- Build-host identity: the options whose defaults are computed from the build
  host carry upstream `sample_default` placeholders, which the generator prints
  instead of the value (`oslo_config-10.3.0/oslo_config/generator.py:122-133`):
  `my_ip` -> `<host_ipv4>` (`nova:nova/conf/netconf.py:26-27`), `host` ->
  `<current_hostname>` (`netconf.py:68-69`), `console_host` ->
  `<current_hostname>` (`nova:nova/conf/compute.py:582-583`), `pybasedir` ->
  `<Path>` (`nova:nova/conf/paths.py:24-26`), `[oslo_messaging_rabbit] hostname`
  -> `node1.example.com` (`oslo_messaging-17.3.0/oslo_messaging/_drivers/impl_rabbit.py:267-269`).
  A grep of every namespace in the generator config for `gethostname()`,
  `get_my_ipv4()`, `getfqdn()` and `cpu_count()` found no other such default
  without a sample_default. No replacement is therefore needed; each
  placeholder is checked with `grep -q ... || exit 1`. In addition, the build
  stops if this build host's name, FQDN or non-loopback IPv4 appears as a value
  in either generated file, and if any expected option group (including the
  namespaces of keystonemiddleware, os-vif, os-brick, osprofiler) is missing:
  oslo-config-generator only warns when a namespace's entry point is missing.
- `python3-osprofiler` is a BuildRequires because `nova-config-generator.conf`
  names the `osprofiler` namespace while osprofiler is only an optional extra
  of nova (`nova:pyproject.toml` `[project.optional-dependencies]`).
- Catalogues: rc4 had them in -common, owned nova:nova. The definition makes
  -common the package that carries the `%find_lang` list and gives that list
  `%attr(0644, nova, nova)`, failing the build if any line was not converted.

## Upstream files installed unchanged

`etc/nova/api-paste.ini`, `etc/nova/rootwrap.conf` (filters_path
`/etc/nova/rootwrap.d,/usr/share/nova/rootwrap`, which is where rc4 put
`compute.filters`), `etc/nova/rootwrap.d/compute.filters` ->
`/usr/share/nova/rootwrap/compute.filters`, `nova/virt/interfaces.template` ->
`/usr/share/nova/interfaces.template`.

## openstack-nova-{conductor,scheduler,compute,novncproxy,serialproxy,spicehtml5proxy}.service

Facts:
- Console scripts: `nova:pyproject.toml` `[project.scripts]`.
- conductor and compute start with the eventlet backend, scheduler with native
  threading (`nova:nova/cmd/conductor.py:17`, `compute.py:19`, `scheduler.py:19`,
  `nova:nova/monkey_patch.py:89-112`); the environment variable
  `OS_NOVA_DISABLE_EVENTLET_PATCHING` switches it. Only oslo.service's eventlet
  launchers send `READY=1` (`oslo_service-4.5.1/oslo_service/backend/_eventlet/service.py:297,563`);
  the threading backend has no sd_notify. All stay in the foreground.
- The console proxies run websockify in the foreground unless `daemon` is set
  (default False, `nova:nova/conf/novnc.py:25-27`; `nova:nova/cmd/baseproxy.py:82`).
- Installer: units `openstack-nova-conductor`, `openstack-nova-scheduler`,
  `openstack-nova-compute` (lines 127-128), enabled and started with
  `systemctl enable` + `start` (lines 834-860). For nova-compute the installer
  states that "Its unit runs /usr/bin/nova-compute with no --config-file, so
  oslo.config searches its default locations" and checks the effective
  configuration with exactly that search (lines 3105-3123).

Choices:
- `Type=simple` for all six: a `Type=notify` unit would time out whenever the
  threading backend is selected, and the scheduler and proxies never notify.
- No `--config-file`: oslo.config's default files for project nova and the
  program name (`oslo_config-10.3.0/oslo_config/cfg.py:273-316`), i.e.
  `/etc/nova/nova.conf` then `/etc/nova/<program>.conf`, plus the `.conf.d`
  directories. This keeps the installer's database-key proof exact and makes
  `/etc/nova/nova-compute.conf` effective. Consequence (documented, accepted):
  oslo.config also looks in the nova user's home (`/var/lib/nova/.nova/`,
  `/var/lib/nova/`) first.
- `User=nova`, `Group=nova`; systemd applies nova's supplementary groups from
  the user database, so the libvirt/qemu memberships apply to nova-compute.
  No `NoNewPrivileges=` or similar, because nova-compute must use sudo
  (rootwrap, privsep).
- nova-compute is ordered `After=libvirtd.service virtqemud.socket
  virtqemud.service` (ordering only, no dependency): it opens
  `qemu:///system` (`nova:nova/virt/libvirt/driver.py:1444`).
- `Wants=`/`After=network-online.target`, `Restart=on-failure`, `RestartSec=5`,
  `WantedBy=multi-user.target` (systemd.unit(5), systemd.service(5)); the
  packages do not enable units themselves (standard `%systemd_post`).
- novncproxy reads `OPTIONS` from `/etc/sysconfig/openstack-nova-novncproxy`
  (`EnvironmentFile=-`, `$OPTIONS` unquoted so an empty value adds no argument,
  systemd.service(5) "Command lines").

## openstack-nova-novncproxy.sysconfig

rc4 shipped this path as `%config(noreplace)` with comments only. Hagistack's
file has comments only and documents `OPTIONS`, which the Hagistack unit reads.

## openstack-nova-common.sysusers, openstack-nova-compute.sysusers

Facts: sysusers.d(5) `g`, `u`, `m` lines. UID/GID 162 is the ID the `setup`
package table reserves for nova (task specification). Home `/var/lib/nova`
(rc4 facts: 0755 nova:nova). The installer runs `runuser -u nova` and reads the
home from passwd (lines 2712, 3114). Shell `/usr/sbin/nologin`: nothing logs in
as nova (migration uses the nova_migration account).

Group membership (compute only, so controllers do not get libvirt/qemu groups):
- `libvirt`: nova-compute connects to `qemu:///system` as the non-root user
  nova (`driver.py:1444`; unit `User=nova`). The libvirt documentation's access
  control for the system daemon's local socket grants management access to
  members of the `libvirt` group (polkit rule shipped by libvirt).
- `qemu`: libvirt's QEMU driver runs guests as user/group `qemu` and, with
  dynamic ownership, hands disk images to that user/group while a guest runs
  (libvirt documentation for qemu.conf `user`, `group`, `dynamic_ownership`;
  Nova notes libvirt's chown in `driver.py:5073-5087`). nova-compute inspects
  those images unprivileged (`nova:nova/virt/images.py:48`
  `unprivileged_qemu_img_info`).
- Ordering: `m` lines implicitly create a missing group (sysusers.d(5)), which
  would give `qemu`/`libvirt` a dynamic GID. -compute therefore requires
  `libvirt` and `qemu-kvm` (the names the installer installs, lines 2165-2170),
  so their own scriptlets create the groups first in a normal transaction.

## openstack-nova-migration.sysusers

`u nova_migration -`: dynamic IDs (no reserved ID), primary group of the same
name (used by `authorized_keys`, rc4 facts root:nova_migration 0640). Shell
`/bin/sh`: sshd runs a forced command through the account's login shell, so a
nologin shell would make every migration login fail (sshd(8)). Home
`/etc/nova/migration` (root-owned, 0755): nova_migration cannot write it, so no
`~/.ssh`, rc or profile files can be planted.

## nova.sudoers

Facts: Nova's root helper is `sudo nova-rootwrap <rootwrap_config>`
(`nova:nova/utils.py:144-149`), `rootwrap_config` defaults to
`/etc/nova/rootwrap.conf`, and nova-compute hands it to oslo.privsep
(`nova:nova/cmd/compute.py:49`), which then starts
`<root helper> privsep-helper ...` (`oslo_privsep-3.10.1/oslo_privsep/priv_context.py:101,227-245`);
oslo.rootwrap always allows privsep-helper (`oslo_rootwrap-7.9.0/oslo_rootwrap/wrapper.py:191-195`).
The installer writes no rootwrap or privsep settings for Nova, so these
defaults are what runs; it sets `lock_path = /var/lib/nova/tmp` (line 2737),
which -common ships (0755 nova:nova as rc4; the installer may tighten it to
0750). Choices (sudoers(5)): exactly the two commands of the specification,
`NOPASSWD`, runas root, `!requiretty`.

## openstack-nova.logrotate

Facts: oslo.log `watch_log_file` defaults to false, and SIGHUP restarts the
oslo.service services, so a signal is no safe way to reopen logs; by default
Nova logs to stderr (journal) unless `log_dir`/`log_file` is set. Choices
(logrotate(8)): `/var/log/nova/*.log`, `copytruncate`, weekly, 4 rotations,
`compress`, `delaycompress`, `missingok`, `notifempty`, `su nova nova` because
`/var/log/nova` is owned by nova (rc4 facts 0750 nova:root).

## nova-release

`nova:nova/version.py:45-62` looks the file up with `cfg.CONF.find_file("release")`
(so `/etc/nova/release`) and reads `vendor`, `product`, `package`, `support`
from `[Nova]`. The vendor/product strings appear in guests' SMBIOS data
(`driver.py:6221-6222`). Hagistack's file sets vendor `Hagistack` and product
`OpenStack Nova`; no `package` key (a static file cannot carry the release).
Mode 0644, not %config, as rc4.

## nova-compute.conf

rc4 shipped `/etc/nova/nova-compute.conf` (0640 root:nova, noreplace); upstream
has no such file. Hagistack's file has comments and an empty `[DEFAULT]`: it is
read after nova.conf by nova-compute (oslo.config default files) and so is the
place for compute-only overrides. It sets nothing; the installer's database
check reads it too (lines 3142-3167).

## openstack-nova-migration (wrapper, ssh config, sudoers, rootwrap, placeholders)

### What Nova runs over SSH (facts)

- `nova:nova/utils.py:152-156` `ssh_execute`: `ssh -o BatchMode=yes <dest> <cmd...>`,
  run by nova-compute as user nova, with no remote user in the command.
- With `[libvirt] remote_filesystem_transport = ssh` (default,
  `nova:nova/conf/libvirt.py:1386`) the remote filesystem driver is
  `SshDriver` (`nova:nova/virt/libvirt/volume/remotefs.py:172-197`):
  `touch <p>`, `rm <p>`, `mkdir -p <p>`, `rm -rf <p>`, and local
  `scp [-C] -r <src> <dst>` where one side is `host:path`.
- Callers (`nova:nova/virt/libvirt/driver.py`): `_is_path_shared_with`
  (12606-12626) touches and removes `<instances>/<uuid>/<uuid4 hex>.tmp`;
  `migrate_disk_and_power_off` (12666-12676, 12715-12745) creates
  `<instances>/<uuid>`, copies each disk and `disk.info` to
  `<instances>/<uuid>/<name>`, and on failure removes `<instances>/<uuid>`
  (`_cleanup_remote_migration`, 12547-12557); vTPM state is copied as the
  directory `swtpm` into `<instances>/<uuid>` (`nova:nova/virt/libvirt/utils.py:752-773`,
  whose comment at 757-758 states that only `<instance_path>` is writable on the
  destination). Images missing from Glance are fetched back from the source
  host with `copy_image(receive=True)`: kernel/ramdisk in the instance
  directory (`driver.py:11795`) and cached images in the image cache
  (`driver.py:12089`; `_base` by default, `nova:nova/conf/imagecache.py:51-52`).
  `instances_path` defaults to `$state_path/instances`
  (`nova:nova/conf/compute.py:602-603`); the installer sets `state_path` to
  `/var/lib/nova` (line 2736). `get_instance_path` is `instances_path/<uuid>`
  (`utils.py:522-536`).
- Legacy scp runs `scp -r -t <path>` (receive) or `scp -r -f <path>` (send) on
  the remote side; `-C` only affects the local ssh. scp(1): since OpenSSH 9.0
  scp uses the SFTP protocol by default; `-O` selects the legacy protocol.
  Nova does not pass `-O`.

### Design

- `/var/lib/nova/.ssh/config` (0600 nova:nova, not %config, as rc4): `User
  nova_migration`, `IdentityFile /etc/nova/migration/identity`,
  `IdentitiesOnly`, no password/keyboard-interactive, no forwarding, and
  `StrictHostKeyChecking yes` with `/var/lib/nova/.ssh/known_hosts`
  (ssh_config(5)). Host keys must be distributed by the operator; nova's
  `BatchMode=yes` cannot answer a prompt anyway.
- `nova-migration-wrapper` (forced command, `/usr/bin`, 0755): reads
  `SSH_ORIGINAL_COMMAND` (sshd(8)), refuses empty commands, more than 4096
  characters, any character outside `A-Za-z0-9 ./_-`, and the SFTP subsystem;
  splits on spaces and accepts exactly these forms, with `<uuid>` a lowercase
  UUID, `<name>` one path component not starting with `.` or `-`, and every
  path also checked with `realpath` to resolve to itself below the resolved
  instances directory (no symlink escape, no `..`):
  `touch|rm <instances>/<uuid>/<32 hex>.tmp`, `mkdir -p <instances>/<uuid>`,
  `rm -rf <instances>/<uuid>`, `scp -r -t <instances>/<uuid>[/<name>]`,
  `scp -r -f <instances>/<uuid>/<name>`, `scp -r -f <instances>/_base/<name>`.
  It logs accepted and refused commands to authpriv with a sanitised copy of
  the request and runs the command as
  `sudo -n /usr/bin/nova-rootwrap /etc/nova/migration/rootwrap.conf runuser -u nova -- /usr/bin/<cmd> ...`.
- Why rootwrap plus runuser: oslo.rootwrap's `run_as` only calls `setuid`
  (`oslo_rootwrap-7.9.0/oslo_rootwrap/filters.py:84-87`), leaving gid 0;
  `runuser -u nova` (util-linux) switches user, group and supplementary groups,
  so copied files are owned nova:nova as nova itself would create them.
  rootwrap passes stdin/stdout through (`oslo_rootwrap/cmd.py` `run_one_command`),
  which scp's protocol needs.
- `cold_migration.filters` (0640 root:root, noreplace, as rc4): one
  `RegExpFilter` per accepted form; `RegExpFilter` requires the exact argument
  count and anchors every pattern (`filters.py:102-120`); path patterns end in
  `\Z` because `re.match(pattern + '$')` would accept a trailing newline
  (checked with upstream rootwrap's matcher).
- `nova-migration-rootwrap.conf` (0640 root:root, noreplace): only that filter
  directory, `exec_dirs=/usr/sbin,/usr/bin`, syslog on (authpriv, INFO) so
  every rootwrap decision is logged.
- `nova_migration.sudoers` (0440, noreplace): only
  `/usr/bin/nova-rootwrap /etc/nova/migration/rootwrap.conf runuser -u nova -- *`.
  oslo.rootwrap always adds an unrestricted privsep-helper filter
  (`wrapper.py:191-195`) that runs as root; requiring `runuser -u nova --` as
  the first arguments keeps that filter unreachable for nova_migration.
- `nova-migration-identity` (0600 nova:nova, noreplace) and
  `nova-migration-authorized_keys` (0640 root:nova_migration, noreplace):
  comment-only placeholders (no key). The authorized_keys comments show the
  `command="/usr/bin/nova-migration-wrapper",restrict` key option and an sshd
  `Match User nova_migration` block with `AuthorizedKeysFile` and
  `ForceCommand`; the package does not change sshd's configuration (rc4 had no
  sshd file either). The identity placeholder is not a valid key, so ssh fails
  until it is replaced; it contains only comment text.

### Not supported, and why (uncertainties)

1. **SFTP-mode scp (Rocky 10's default) is refused.** On OpenSSH 9.x, Nova's
   `scp -C -r` asks for the `sftp` subsystem instead of running `scp -t/-f`.
   sftp-server cannot be limited to a directory without a chroot, and sshd's
   ChrootDirectory needs root-owned path components, which
   `/var/lib/nova/instances` (nova-owned) is not; an SFTP session as nova could
   read and write every nova-owned file, including `/var/lib/nova/nova.conf`,
   which oslo.config would prefer over `/etc/nova/nova.conf`. The wrapper
   therefore refuses it, and **on Rocky 10 the disk-copy step of resize/cold
   migration between hosts will fail** until a decision is made (for example a
   Nova change to pass `scp -O`, or an accepted, documented relaxation). How
   sshd presents a subsystem request to a forced command (the configured
   subsystem command, e.g. `/usr/libexec/openssh/sftp-server`, or
   `internal-sftp`, in `SSH_ORIGINAL_COMMAND`) is taken from OpenSSH
   behaviour as documented/known, not verified here; the wrapper refuses it
   either way, because it matches no accepted form.
2. **Legacy scp argument forms** (`scp -r -t <path>` / `scp -r -f <path>`) are
   what OpenSSH's scp sends for nova's arguments; `-v`, `-p`, `-d` variants are
   refused. Not verified on a host.
3. **Live migration over `qemu+ssh`** is refused: the remote command is built
   by libvirt (its ssh transport helper), not by Nova, and is not derivable from
   the upstream sources available here. Nova's default live-migration URI for
   kvm/qemu is `qemu+tcp://` (`nova:nova/conf/libvirt.py` `live_migration_uri`
   help), which does not use SSH. Peer-to-peer migration is also started by the
   source libvirt daemon (root), not by nova, so `/var/lib/nova/.ssh/config`
   would not apply to it.
4. **`remote_filesystem_transport = rsync`** is refused: `RsyncDriver` writes
   relative to the remote `/` (`remotefs.py:291-308`), which cannot be limited
   to the instances directory, and rsync's `--server` arguments are
   rsync-internal.
5. Non-default `instances_path` or `[image_cache] subdirectory_name` are not
   followed: the wrapper and filters use `/var/lib/nova/instances` and `_base`.
6. `runuser` is looked up in `/usr/sbin` and `/usr/bin` (its location on
   Rocky 10 is not verified here); `touch`, `rm`, `mkdir`, `scp` are named as
   `/usr/bin/...`.
7. SELinux: whether sshd may run `/usr/bin/nova-migration-wrapper` for
   nova_migration and write into `/var/lib/nova/instances` under enforcing
   policy is not verified.

## Requires added by hand (definition comments carry the reasons)

common: `sudo` (root helper). compute: `python3-libvirt`
(`nova:nova/virt/libvirt/host.py:68`), `libvirt`, `qemu-kvm` (installer names),
`qemu-img` (`nova:nova/privsep/qemu.py:112,242`), `openssh-clients` and `lsscsi`
(`nova:bindep.txt`). novncproxy: Recommends `novnc` (`nova:nova/cmd/novncproxy.py:40`,
`baseproxy.py:65`); spicehtml5proxy: Recommends `spice-html5` (`nova/conf/novnc.py`
`web` default, `baseproxy.py:65`) — weak because `--web` can point elsewhere
and the package names on Rocky 10 are not verified. migration:
`openssh-server`, `openssh-clients`, `sudo`, `util-linux`.

## Files that cannot carry comments

None: every file has `#` comments (the identity and authorized_keys
placeholders consist of comments only).

## Other uncertainties

- `%sysusers_create_compat` handling of `m` lines, and whether rpm's own
  sysusers dependency generator on Rocky 10 turns `m nova libvirt` /
  `m nova qemu` into `group(...)` requirements that libvirt/qemu provide, is
  not verified (needs a build and install).
- `/var/run/nova` is packaged as rc4 did; `/run` is a tmpfs, so the directory
  is gone after a reboot. Nova's defaults do not use it.
- The catalogue owner nova:nova follows rc4; root ownership would be the usual
  choice.
