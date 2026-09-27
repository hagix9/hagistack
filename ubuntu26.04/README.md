# hagistack — Ubuntu Server 26.04 LTS

A plain-Bash OpenStack deployment shell. Not OpenStack-Ansible, not
Kolla-Ansible, not Packstack, not DevStack.

## Current status: Step 5 — **this is not a finished OpenStack yet**

| | |
|---|---|
| Version | `0.5.0-step5` |
| Target OS | Ubuntu Server **26.04 LTS** only (`amd64`; `arm64` accepted but untested) |
| Target OpenStack | 2026.1 Gazpacho, from the Ubuntu 26.04 archive |

**Implemented**

- `all-in-one` skeleton, argument parsing, `--help`, `status`
- preflight: OS gate, architecture → qemu package, KVM/QEMU detection,
  memory and disk checks, full validation of the required settings,
  single-NIC warning
- secret generation into `/etc/hagistack/secrets.env` (mode `0600`)
- base packages, **MariaDB**, **RabbitMQ**, **memcached**
- **Keystone identity**: schema, fernet and credential keys, `bootstrap`,
  Apache/mod_wsgi on port 5000, and an `admin-openrc` you can authenticate with
- **Glance** image service on port 9292, and **Placement** on port 8778, both
  registered in the catalogue and answering authenticated requests
- **Neutron networking API** on port 9696 with **ML2/OVN**, and the OVS/OVN
  control plane: northbound and southbound databases, `ovn-northd`,
  `ovn-controller`, Geneve as the tenant network type, and a provider bridge
  with its physnet mapping
- **Nova**: the compute API on port 8774 and the metadata API on 8775 (both
  Apache vhosts), `nova-conductor`, `nova-scheduler`, cells v2 (`cell0` +
  `cell1`), and `nova-compute` with libvirt/KVM — wired to Keystone, Glance,
  Placement, Neutron and RabbitMQ

**Not implemented yet**

Horizon, the initial resources (flavor / image / network / router / security
group / keypair), and the whole of `compute-add`. `compute-add` exits with a
clear "not implemented" message and status 3.

So: after `all-in-one` finishes you have a database, a message queue, a cache,
identity, an image store, placement, a networking API and a compute service
with a registered hypervisor. **No guest VM has been booted or verified, the
provider bridge has no NIC and no address so provider networks reach no
physical LAN, and Geneve between nodes is untested until a second node joins.
Do not call this a finished OpenStack.**
The command prints a banner saying exactly that, and `hagistack status` lists
which phases are implemented versus pending.

### Keystone

Served by **`apache2.service`** with `libapache2-mod-wsgi-py3`. There is no
Keystone systemd unit on Ubuntu — the `keystone` package ships exactly one
file, `/etc/apache2/sites-available/keystone.conf`, which carries its own
`Listen 5000` and points at `/usr/bin/keystone-wsgi-public`, and installing it
enables the site. hagistack drives that packaged vhost rather than inventing a
unit or installing uwsgi. The evidence behind each of those statements is in
`STEP2_KEYSTONE_EVIDENCE.md`.

```sh
. /etc/hagistack/admin-openrc
openstack token issue
```

Re-running never rotates the fernet or credential keys, never rewrites the
admin credential, and never drops the schema.

### Glance and Placement

They start differently, and the difference is in the packaging rather than a
choice hagistack made:

| | Glance | Placement |
|---|---|---|
| started by | **`glance-api.service`** (its own unit) | **`apache2.service`** — a second vhost beside identity |
| port | 9292 (`bind_port` has no default, so it is set explicitly) | 8778 (from the packaged vhost) |
| DB key | `[database] connection` | **`[placement_database] connection`** |
| migration | `glance-manage db_sync` | **`placement-manage db sync`** |

```sh
. /etc/hagistack/admin-openrc
openstack image list
openstack endpoint list
```

Uploaded images survive re-runs: the image id, Glance's checksum and the bytes
on disk were all unchanged across three consecutive runs. Service users,
services and endpoints are reused, never deleted and recreated.

Both phases refuse to run unless memcached is listening — a configured but dead
token cache makes every authenticated call block, so hagistack will not
configure against one. See `STEP3_GLANCE_PLACEMENT_EVIDENCE.md`.

### Neutron and OVN

A third startup model again, and again it is the packaging's choice rather than
hagistack's:

| | how it starts |
|---|---|
| Neutron **API** (:9696) | **`apache2.service`** — a third vhost beside identity and placement. `neutron-server` ships *no* systemd unit |
| Neutron RPC / workers / metadata | `neutron-rpc-server`, `neutron-periodic-workers`, `neutron-ovn-metadata-agent` — real units |
| OVN | `ovn-central` and `ovn-host` are `Type=oneshot`, `ExecStart=/bin/true` **wrappers**. The real units are `ovn-ovsdb-server-nb`, `ovn-ovsdb-server-sb`, `ovn-northd`, `ovn-controller` |

Because the wrappers always "succeed", liveness is checked on the real units —
never on `ovn-central`. Start order is `openvswitch-switch` → northbound DB →
southbound DB → `ovn-northd` → `ovn-controller` → Neutron.

Three networks are kept as three separate settings, which is what lets one
shell serve both a single-LAN lab and a split management/provider deployment:

| Concern | Setting |
|---|---|
| management / API plane | `MGMT_IP` |
| Geneve tunnel endpoint | `external_ids:ovn-encap-ip` (defaults to `MGMT_IP`, but is its own setting) |
| provider physical network | `external_ids:ovn-bridge-mappings` = `--provider-physnet`:`--provider-bridge` (default `physnet1`:`br-ex`) |

Tenant networks are **geneve**; the provider physnet has both **flat** and
**vlan** enabled, so further provider LANs can be added later as VLAN segments
on the same bridge without re-plumbing anything.

The northbound database listens on **loopback only** (`ptcp:6641:127.0.0.1`) —
only the local Neutron talks to it. The southbound database listens on the
management address (`ptcp:6642:$MGMT_IP`) because compute nodes will need it.

**The provider bridge is created empty, on purpose.** No NIC is enslaved to it
and no address is assigned. Attaching a physical NIC and moving the management
IP onto the bridge is disruptive — done wrong over SSH it takes the host off the
network — so this step does not do it. Until that happens, provider networks
exist in Neutron but have **no path to a physical LAN**. The run warns about it,
`status` repeats it, and the tests assert that the bridge has no port, no
address, and that the management interface kept exactly the addresses it had.

See `STEP4_NEUTRON_OVN_EVIDENCE.md` for the measured packaging facts behind
every unit name and config path above.

### Nova

A fourth combination of startup models, again the packaging's choice:

| | how it starts |
|---|---|
| compute **API** (:8774) | **`apache2.service`** — a fourth vhost. `nova-api` ships *no* systemd unit |
| **metadata** API (:8775) | a *separate* package, `nova-api-metadata`, with its own vhost |
| conductor / scheduler / compute | real units (`Type=simple`, `User=nova`, `ExecStart=/etc/init.d/<name> systemd-start`) |

Things that are easy to get wrong and were checked in the packages:

- **No Nova package touches the database.** `api_db sync`, `db sync`,
  `cell_v2 map_cell0` and `cell_v2 create_cell` are all hagistack's job.
- `/etc/nova/nova.conf` is stored `0644 root:root` inside the `.deb`, but
  `nova-common`'s postinst chowns `/etc/nova` to `root:nova` and chmods it
  `0640`, so that is what is actually installed. hagistack re-applies the same
  mode after writing credentials — enforcement, not a fix (the first draft of
  the evidence document claimed otherwise; the suite caught it).
- The cell0 database **must** be called `nova_cell0`: Nova derives that name
  from `[database] connection` by appending `_cell0`. Because of that,
  `map_cell0` is called with **no arguments** and no password ever appears in
  `ps`. `cell_v2 list_cells` prints passwords, so its output is matched but
  never logged.
- `[api] auth_strategy` does not exist in Nova 33, and `[glance] api_servers`
  has been deprecated since 21.0.0 — neither is written.
- `/etc/init.d/nova-compute` adds `--config-file=/etc/nova/nova-compute.conf`,
  so the virtualisation type goes there, not into `nova.conf`.

`--virt-type` (or `/dev/kvm` detection in preflight) selects `kvm` or `qemu`;
under `qemu` the run says plainly that guests are 10–50× slower and sets
`[libvirt] cpu_mode = none`.

`phase_nova_compute` checks that the Nova control plane completed **before**
installing anything, because `nova-compute` pulls libvirt and qemu.

See `STEP5_NOVA_EVIDENCE.md`.

### Completion is not assumed

A base service that cannot be reached is not quietly skipped. The run reports
`STEP 1 INCOMPLETE`, names the phases it skipped, writes **no** state marker for
them, and **exits 4**. `hagistack status` says `base layer: INCOMPLETE` and lists
what is missing. Only a run in which every implemented phase actually did its
work prints `STEP 1 COMPLETE (BASE LAYER)` and exits 0.

This is the normal outcome in a container with no systemd, and it is not a
failure of the shell — but it is not a completed step 1 either.

| Exit | Meaning |
|---|---|
| 0 | success |
| 1 | configuration or preflight error |
| 2 | usage error |
| 3 | subcommand not implemented yet |
| 4 | ran to the end, the layer is incomplete (a service was unreachable) |

## Usage

```sh
cp hagistack.env.example hagistack.env   # edit it
sudo ./hagistack all-in-one              # or: --check for preflight only
./hagistack status
```

Required settings: `EXT_NIC`, `PROVIDER_CIDR`, `PROVIDER_GATEWAY`,
`FLOATING_START`, `FLOATING_END`. Everything else is autodetected or defaulted
(including `REGION_NAME`, which defaults to `RegionOne`).

### Configuration

Precedence is **command line > environment > `./hagistack.env` > default**, and
it applies to *every* option, including `--tenant-cidr`, `--dns-server` and
`--virt-type`. `--check` prints the resolved value and its source for each key:

```
==> resolved configuration
    EXT_NIC            eth0                   [command line]
    TENANT_CIDR        10.1.1.0/24            [environment]
    DNS_SERVER         172.24.4.1             [default]
```

Giving a key an empty value on any tier is an error rather than a silent
fall-through, so "explicitly blank" is never mistaken for "not supplied".
Repeating a flag is allowed; the last occurrence wins.

**The config file is parsed, never executed.** Only blank lines, `#` comments
and `KEY=VALUE` are accepted; `KEY` must be a known setting and `VALUE` may
contain only letters, digits and `. _ - : / @ + =`. Unknown keys, duplicate
keys, malformed lines and values containing shell metacharacters are refused,
and a rejected value is never echoed back in the error. Use
`--env-file /dev/null` to ignore all config files.

## Safety properties

These are the failures of the 2013-era shells in this repository, and the
rules that replace them:

| Old behaviour | Now |
|---|---|
| `MYSQL_PASS=nova`, `ADMIN_PASSWORD=secrete` committed to Git | No password in the source. Generated per host into `/etc/hagistack/secrets.env` (`0600`), git-ignored, and **reused unchanged** on re-runs |
| an unconditional database drop on every run | **No `DROP DATABASE` anywhere.** An existing database is detected and left untouched. There is no flag to bypass this |
| `cat … \| tee -a /etc/sysctl.conf` duplicating on every run | `ini_set` edits key-by-key and rewrites the file only when the content actually changes |
| `rm -rf /var/log/nova/*` | Nothing is deleted |
| No `set -e`; ran to completion after failures | `set -Eeuo pipefail` plus an `ERR` trap that reports the failing line. `-E` matters: without it the trap is not inherited by functions, so it never fires |
| Config file `source`d, making every value executable | The file is **parsed**. `KEY=$(command)` and backquoted values are refused, not run |
| — | A service that cannot be reached does not count as done: no state marker, `STEP 1 INCOMPLETE`, exit 4 |
| AppArmor disabled, libvirt opened on TCP with `auth_tcp="none"`, MariaDB bound to `0.0.0.0` | None of these. MariaDB is pinned to `127.0.0.1`, memcached to the management IP |

Re-running `all-in-one` is safe and is part of the acceptance criteria.

## What has actually been verified

Verified in an **Ubuntu 26.04.1 LTS amd64 container** (no systemd): `bash -n`,
ShellCheck, `--help`, subcommand resolution, the `compute-add`
not-implemented path, input validation, config-generation idempotence,
secret file permissions and value stability across runs, refusal of
code-execution payloads in the config file, the full precedence matrix, and the
incomplete-run reporting and exit code.

With **MariaDB started by hand** inside the container (`mariadbd-safe
--skip-networking`, recorded as such): database and user creation, login as the
`nova` user to both the `nova` and `nova_api` databases with one credential, and
survival of a planted row across three consecutive runs.

Keystone specifically was verified in that container with MariaDB and Apache
started **by hand** (`mariadbd-safe --bind-address=127.0.0.1`,
`apachectl -k start` — both recorded as such): 49-table schema, fernet and
credential keys, bootstrap, and `openstack token issue` succeeding as admin,
with every artefact unchanged across three consecutive runs.

For step 4 the same container (this time `--privileged`, with `/lib/modules`
mounted) started MariaDB, memcached, **RabbitMQ** — which did come up this time,
unlike in step 1 — Apache, `ovsdb-server`, `ovs-vswitchd`, the OVN northbound
and southbound databases and `ovn-northd`, all by hand and all recorded. What
that proved: the OVN databases listen exactly where the design says
(`ptcp:6641:127.0.0.1` and `ptcp:6642:$MGMT_IP`, confirmed with `ss`), the local
chassis registers itself in the southbound database with a **Geneve** encap
pointing at the management address, the provider bridge is created with **no
port and no address**, the management interface keeps exactly the addresses it
had, and the networking schema is created (135 tables).

Regression on the step 4 build, narrowed to what that change touched: the step 1
audit suite **39/0/1** and the step 1 verify suite **63/0/8**, both guest exit 0,
**no FAIL** (the UNVERIFIED entries are tooling the leaner container lacked, not
behaviour that changed — see `STEP4_NEUTRON_OVN_EVIDENCE.md` §10).

Step 5 was verified with a deliberately light suite — **PASS 68 / FAIL 0 /
UNVERIFIED 7, guest exit 0** — covering syntax, ShellCheck, the new input
validation, honest skipping, the Nova packaging facts, configuration generation
against the real packaged `nova.conf` (including byte-identical re-application),
the three compute databases with one credential, and secret handling. It does
**not** bring the control plane up: see `STEP5_NOVA_EVIDENCE.md` §3 for why, and
§4 for what that leaves unverified.

**Not verified anywhere yet**: the **compute API** (:8774), the cells commands
actually executing, **nova-compute/libvirt**, hypervisor registration and
**booting a guest VM** — none of which a container can settle; service startup
*under systemd* and unit ordering;
the **authenticated Neutron API**, networking service/endpoint registration and
network creation — the container hit its own limit here, a Keystone
`QueuePool limit of size 5 overflow 50 reached` at 98% disk with the database
server idle at 56 of 1024 connections, which is an environment constraint and
not a setting this shell writes (the diagnosis is in
`STEP4_NEUTRON_OVN_EVIDENCE.md` §4); **Geneve tunnelling between two nodes**; any
**physical-LAN** provider path or floating IP; Nova resource-provider
registration; and instance boot. Those are GCE acceptance items — see
`../HAGISTACK_VERIFICATION_SCOPE_2026-09-26.md` §5.

Nothing in this shell has been run on real Ubuntu 26.04 hardware or on a
GCE VM.
