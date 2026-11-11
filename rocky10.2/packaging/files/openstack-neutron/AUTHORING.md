# Authoring record: openstack-neutron packaging files

These files, and `../../defs/openstack-neutron.toml`, were written for
Hagistack from a functional specification, rc4's binary-package metadata
(paths, modes, owners, file flags, scriptlet kinds; no file contents:
`svc-facts/neutron.txt`), Hagistack's installer `rocky10.2/hagistack`, the
upstream sources (Apache-2.0) of Neutron 28.0.2, oslo.rootwrap 7.9.0,
oslo.privsep 3.10.1, oslo.concurrency 7.4.1, oslo.service 4.5.1 and
oslo.config 10.3.0, and public man pages (systemd.unit(5), systemd.service(5),
systemd.exec(5), sysusers.d(5), sysctl.d(5), sudoers(5), logrotate(8)).
Neutron paths below are relative to the unpacked `neutron-28.0.2/`;
installer lines refer to `rocky10.2/hagistack`.

## Statement of sources

No distribution packaging was consulted: no RDO, Fedora, CentOS, Debian or
Ubuntu packaging, no existing OpenStack `.service`, logrotate, sudoers,
sysctl, modules or `neutron-dist.conf` file from any distribution (rc4's file
contents included), and no web search for them. None of the forbidden local
paths (`hagistack-license-decision-2026-11-10/`, `hagistack-u1-*`,
`hagistack-rc*`, `hagistack-ownpkg-2026-11-11/lima`,
`hagistack-ownpkg-2026-11-11/payload`, any `*.rpm`, any `*.spec`,
`rocky10.2/spec-adapt/`, `rocky10.2/build-rpms.sh`) was opened. No network,
build, VM or git command was run. Checks run: `sh -n` on the two shell
scripts, `visudo -c -f openstack-neutron.sudoers` (parsed OK), `genspec.py`
on the definition and `test_genspec.py` (OK).

## Facts used by all units

- Console scripts: `pyproject.toml` lines 303-331 (`[project.scripts]`), the
  same list as `neutron.egg-info/entry_points.txt`.
- Configuration is read by oslo.config; when `--config-file` is given, the
  default file list is not used (`neutron/server/__init__.py` lines 30-45 and
  `neutron/common/config.py` `init()`), so every file a service needs is
  named on its command line. Later files and `--config-dir` directories
  override earlier ones (oslo.config command-line order).
- `root_helper` is registered in group `AGENT` with default `sudo`
  (`neutron/conf/agent/common.py` lines 57-84, 168-169); privsep is started
  with that root helper as prefix (`neutron/conf/agent/common.py` lines
  213-214; `oslo_privsep/priv_context.py` lines 101, 151-153, 227-237).
- oslo.rootwrap always allows `privsep-helper` in addition to the filter
  files (`oslo_rootwrap/wrapper.py` lines 191-195).
- Upstream's `lock_path` has no default except `$OSLO_LOCK_PATH`, and an
  external lock without it raises `RequiredOptError`
  (`oslo_concurrency/lockutils.py` lines 58-66, 226-229). The agents take
  external locks: `neutron/agent/linux/ipset_manager.py` lines 87-88,
  `neutron/agent/linux/iptables_manager.py` lines 309, 465-466.
- Helper processes are tracked through pid files under
  `$state_path/external/pids` (`neutron/conf/agent/common.py` lines 26-28).
- The only sd_notify in Neutron is in the Open vSwitch agent, after its first
  report to the server (`ovs_neutron_agent.py` lines 470-472); oslo.service
  notifies only when `NOTIFY_SOCKET` is set (`oslo_service/systemd.py`).
- Installer: units it enables (`NEUTRON_UNITS`, lines 121-126; compute node
  line 3240); files it writes per unit (lines 2594-2645, 3213-3239); it
  passes `neutron.conf`, `ml2_conf.ini` and `neutron_ovn_metadata_agent.ini`
  as the files whose change restarts them (line 2695); it disables
  `neutron-server` if enabled (lines 2663-2667); it runs the API under httpd
  from `neutron/wsgi/api.py` (line 2692), which reads `/etc/neutron/neutron.conf`
  and `plugins/ml2/ml2_conf.ini` (`neutron/server/__init__.py` lines 30-45).

## The systemd units (15 files)

Common choices:
- `Type=simple`: the programs stay in the foreground. `Type=notify` is not
  used even for the Open vSwitch agent: it notifies only after reaching the
  server, so a start would block or time out while the server is down.
- `User=neutron`, `Group=neutron`; root actions go through the root helper.
- `ExecStart` = the upstream console script, then `--config-file` for
  `/usr/share/neutron/neutron-dist.conf` (first, so everything in /etc wins),
  `/etc/neutron/neutron.conf`, the service's own file, then `--config-dir`
  `/etc/neutron/conf.d/common` and `/etc/neutron/conf.d/<unit>` where rc4 had
  that directory. A `--config-dir` that does not exist is an oslo.config
  error, so only directories owned by the same package or by
  openstack-neutron-common are named.
- `Wants=`/`After=network-online.target` (systemd.special(7)); agents that
  talk to Open vSwitch or OVN are also ordered `After=openvswitch.service`
  (and `ovn-controller.service` for the OVN agents). `After=` on a unit that
  is not installed has no effect (systemd.unit(5)).
- `Restart=on-failure`, `RestartSec=5` for the long-running services.
- `[Install] WantedBy=multi-user.target`; the packages do not enable them
  (presets); the installer enables the four it uses.
- No `--log-file`: logs go to the journal, which the installer points
  operators to (`journalctl -u`, lines 824, 842).

Per unit (file read after `neutron-dist.conf` and `neutron.conf`):
- `neutron-rpc-server`, `neutron-periodic-workers`,
  `neutron-ovn-maintenance-worker`: `/etc/neutron/plugins/ml2/ml2_conf.ini`,
  the file the installer configures and the API reads. Named directly, so
  the `/etc/neutron/plugin.ini` link the installer creates (lines 2653-2661)
  is not needed. The two workers have no conf.d directory in rc4, so only
  `conf.d/common` is read.
- `neutron-ovn-metadata-agent`: `/etc/neutron/neutron_ovn_metadata_agent.ini`
  (installer lines 2620-2645, 3213-3239).
- `neutron-dhcp-agent`: `dhcp_agent.ini`; `neutron-l3-agent`: `l3_agent.ini`;
  `neutron-metadata-agent`: `metadata_agent.ini`; `neutron-metering-agent`:
  `metering_agent.ini`; `neutron-openvswitch-agent`:
  `plugins/ml2/openvswitch_agent.ini`; `neutron-ovn-agent`:
  `plugins/ml2/ovn_agent.ini`; `neutron-sriov-nic-agent`:
  `plugins/ml2/sriov_agent.ini`. Generator config names: `etc/oslo-config-generator/`.
- `neutron-macvtap-agent`: rc4 shipped no `macvtap_agent.ini`, so no such
  file is named (a missing `--config-file` is fatal); its settings go into
  `conf.d/neutron-macvtap-agent/*.conf`.
- `neutron-netns-cleanup` (oneshot): registers interface-driver and DHCP
  options (`neutron/cmd/netns_cleanup.py` lines 61-73), so it reads
  `dhcp_agent.ini` and `l3_agent.ini`; ordered before both agents.
- `neutron-ovs-cleanup` (oneshot): registers the OVS agent options
  (`neutron/cmd/ovs_cleanup.py` lines 34-48), so it reads
  `openvswitch_agent.ini`, which belongs to another package; hence
  `ConditionPathExists=` on that file (systemd.unit(5)).
- `KillMode=process` (systemd.kill(5)) for the DHCP, L3, OVN and OVN metadata
  agents: they start dnsmasq, keepalived, neutron-keepalived-state-change,
  radvd or haproxy (rootwrap.filters lines 37-60), which must keep serving
  while the agent restarts; the agent finds them through the pid files. The
  cost: `systemctl stop` leaves them running.
- `neutron-openvswitch-agent`: `Wants=`/`After=neutron-destroy-patch-ports.service`;
  `ExecStartPre=-+/usr/bin/neutron-enable-bridge-firewall.sh` ("+" runs it
  with full privileges, "-" makes a failure non-fatal; systemd.service(5)),
  because the iptables-based firewall only warns when br_netfilter or the
  sysctls are missing (`neutron/agent/linux/iptables_firewall.py` lines 99-123).
- `neutron-destroy-patch-ports` (oneshot, before the OVS agent):
  `neutron/cmd/destroy_patch_ports.py` has `main()` (lines 83-90) and an
  `if __name__ == "__main__"` guard (line 93) but no console script, so the
  unit runs `/usr/bin/python3 -I -m neutron.cmd.destroy_patch_ports` with the
  OVS agent's files. The text is written as is in the Hagistack file; the
  build edits no unit or source in place, so the interpreter name cannot be
  mangled. `-I` keeps the working directory and `PYTHON*` variables out of
  the module path. The package requires `/usr/bin/python3` for it.
- Not written: `neutron-server.service` (it would name `/usr/bin/neutron-server`,
  which 2026.1 does not build; installer lines 2663-2667).
- `networking-ovn-metadata-agent.service` is a link to
  `neutron-ovn-metadata-agent.service`, as in rc4 (an alias name).

## neutron-dist.conf

Decision: ship a small defaults file and pass it first, because the installer
does not set everything the agents need:
- `[AGENT] root_helper` / `root_helper_daemon` = rootwrap through sudo. The
  installer sets them only in `neutron_ovn_metadata_agent.ini` (lines
  2622-2635, 3215-3228, with the reason: plain `sudo` is refused); the
  DHCP, L3, OVS, OVN, SR-IOV, macvtap and metering agents and the cleanup
  tools would otherwise use plain `sudo` and fail the same way.
- `[oslo_concurrency] lock_path = $state_path/lock`: the installer sets no
  lock_path for Neutron (it does for nova, line 2737); see the facts above.
  `state_path` defaults to `/var/lib/neutron` (`neutron/conf/common.py` line
  188), owned by `neutron`; fasteners creates the directory.
Not included, with reasons: `state_path` (upstream default already
`/var/lib/neutron`); `api_paste_config` (default `api-paste.ini` is found via
the config file directory, `oslo_service/wsgi.py` lines 362-364,
`_options.py` lines 67-74, and the API under httpd does not read this file
anyway); log options (journal). Mode 0640 root:neutron as in rc4. It contains
no secrets.

## openstack-neutron.sudoers

- `/usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf *`: the root helper.
- `/usr/bin/neutron-rootwrap-daemon /etc/neutron/rootwrap.conf`: the daemon
  helper is called with exactly that argument (installer lines 2634-2635), so
  no wildcard.
- `/usr/bin/privsep-helper *`: oslo.privsep's built-in prefix is plain `sudo`
  (`priv_context.py` line 101) for a process that does not set a root helper.
- The installer calls `sudo neutron-rootwrap ...` by bare name; sudo resolves
  it through `secure_path` to `/usr/bin` (sudoers(5)), matching the rules.
- `Defaults:neutron !requiretty`; runas `(root)` only; `NOPASSWD`. Not
  `%config`, as in rc4 (flags 0).
- Why the metadata agent needs this: installer comment lines 2622-2627 — it
  spawns haproxy in the ovnmeta namespace through the root helper; rootwrap
  allows it via the `ip_exec` and `haproxy` filters (rootwrap.filters lines
  38-43).

## rootwrap.conf, rootwrap.filters (upstream)

Installed from upstream: `etc/neutron/rootwrap.conf` to
`/etc/neutron/rootwrap.conf` (0644, `%config(noreplace)`), and
`etc/neutron/rootwrap.d/rootwrap.filters` to
`/usr/share/neutron/rootwrap/rootwrap.filters` (0644), as rc4 placed them.
Upstream's `filters_path` already lists `/usr/share/neutron/rootwrap` (line
7); `/etc/neutron/rootwrap.d` is not shipped (rc4 had none) and a missing
directory is skipped (`oslo_rootwrap/wrapper.py` lines 170-175).
`exec_dirs` includes `/etc/neutron/kill_scripts` (line 13), shipped empty.

## Config samples (generated)

`build_extra` runs `oslo-config-generator --config-file` for each of the 11
files in `etc/oslo-config-generator/` (the loop of
`tools/generate_config_file_samples.sh`); output paths are each file's
`output_file` (line 2). `PYTHONPATH=$PWD` makes the tree's
`neutron.egg-info/entry_points.txt` (`[oslo.config.opts]`) visible.
Build-host identity: `my_ip`/`my_ipv6` default to the host's addresses with
no sample default (`neutron/conf/common.py` lines 177-184) and are replaced
by `<host_ipv4>`/`<host_ipv6>` in every generated file, then checked with
`grep -qx ... || exit 1`; `host` has `sample_default='example.domain'`
(lines 98-99), checked the same way. Every generated file is then checked to
have no other `my_ip`/`my_ipv6`/`host` value and not to contain (as a word)
the build host's names or the addresses the generator saw (from
`socket.gethostname()`, `socket.getfqdn()` and oslo.utils `netutils`, the
same functions the defaults use); generic loopback names are skipped. A hit
fails the build. Destinations, modes and flags follow rc4. The macvtap
sample is generated but not installed (rc4 did not ship it).

## openstack-neutron.logrotate

The services log to stderr (journal) unless `log_file`/`log_dir` is set;
oslo.log does not reopen files on a signal unless `watch_log_file` is set.
Choices (logrotate(8)): `copytruncate`, `weekly`, `rotate 4`, `compress`,
`delaycompress`, `missingok`, `notifempty`, `su neutron neutron` (the
directory is owned by neutron, 0750 as in rc4).

## openstack-neutron.sysusers

sysusers.d(5): `u neutron - "GECOS" /var/lib/neutron /usr/sbin/nologin`; "-"
allocates IDs dynamically (no reserved ID for neutron), and a `u` line also
creates the group of the same name. rc4 created the user in `%pre` of
openstack-neutron-common; `%sysusers_create_compat` does that here.

## neutron-enable-bridge-firewall.sh, 99-neutron-openvswitch-agent.conf, neutron-openvswitch-agent.modules

Fact: the iptables-based firewall checks `sysctl -N net.bridge` (module
loaded) and that `net.bridge.bridge-nf-call-{arp,ip,ip6}tables` are 1
(`iptables_firewall.py` lines 99-123); `neutron-sanity-check` checks the same
(`neutron/cmd/sanity/checks.py` line 315).
- The script (common package, `/usr/bin`, 0755): `modprobe -b br_netfilter`,
  then `sysctl -w` of the three keys; exit 1 on any failure.
- The sysctl.d file (`/usr/lib/sysctl.d`, 0644): the three keys = 1, each
  with a leading `-` so a missing key (module not loaded yet) is ignored
  (sysctl.d(5)).
- The `.modules` file (`/etc/sysconfig/modules/`, 0755, path as in rc4): a
  shell script that loads br_netfilter. systemd does not run these scripts,
  so the agent's unit does the real work through the script above.

## conf.d-README, ml2-README

Own text: what `conf.d/` is, the read order, and that `neutron-server` has no
program in 2026.1; and what openstack-neutron-ml2 installs. `ml2-README` is
installed under `/usr/share/doc/openstack-neutron-ml2/`, where rpm marks files
as documentation (rc4 flag 2). Both carry a "Written for Hagistack." line.

## Files that cannot carry a comment

None: every file here has a comment line or a text line naming Hagistack.

## Uncertainties

- Not built or run. The generator step, the identity check and the units
  have been reasoned from the code, not observed. If a build host's short
  name is an ordinary word that appears in a sample, the identity check fails
  closed and the build stops.
- `KillMode=process` trades restart continuity for processes left behind on
  stop.
- `neutron-destroy-patch-ports` runs as neutron and reaches OVSDB the same way
  the agent does (`[OVS] ovsdb_connection`, privsep for setting the manager).
