# hagistack — Ubuntu Server 26.04 LTS

A plain-Bash OpenStack deployment shell. Not OpenStack-Ansible, not
Kolla-Ansible, not Packstack, not DevStack.

## Current status — two claims, kept apart

This README, `hagistack --help`, `hagistack status` and the closing banner all
report **two different things**, and never merge them:

| | |
|---|---|
| **IMPLEMENTED** | the code exists here and runs |
| **VERIFIED** | observed working on a real machine |

| | |
|---|---|
| Version | `0.6.0-step6` |
| Target OS | Ubuntu Server **26.04 LTS** only (`amd64`; `arm64` accepted but untested) |
| Target OpenStack | 2026.1 Gazpacho, from the Ubuntu 26.04 archive |
| Implemented | **everything below.** Neither `all-in-one` nor `compute-add` has a stub left |
| **Verified on hardware** | **partly.** Two GCE VMs on 2026-09-28 — see `GCE_ACCEPTANCE_2026-09-28.md`. Most of it passed; **guest boot still fails** |

**Implemented**

- `all-in-one` and `compute-add`, plus `compute-secrets`, `discover-hosts`,
  `status`, `--help`, argument parsing and a parsed (never sourced) config file
- preflight: OS gate, architecture → qemu package, KVM/QEMU detection, memory
  and disk checks, full validation of every setting, single-NIC warning
- secret generation into `/etc/hagistack/secrets.env` (mode `0600`)
- base packages, **MariaDB**, **RabbitMQ**, **memcached**
- **Keystone identity**: schema, fernet and credential keys, `bootstrap`,
  Apache/mod_wsgi on port 5000, and an `admin-openrc` you can authenticate with
- **Glance** on 9292 and **Placement** on 8778, registered and answering
  authenticated requests
- **Neutron** on 9696 with **ML2/OVN**, and the OVS/OVN control plane
- **Nova**: compute API on 8774, metadata on 8775, conductor, scheduler,
  cells v2 (`cell0` + `cell1`), and `nova-compute` with libvirt/KVM
- **Horizon** at `http://<mgmt-ip>/horizon`
- **initial resources**: `m1.tiny`, a digest-verified cirros image, a provider
  network and a tenant network, a router joining them, ICMP and SSH rules, and
  an SSH keypair
- **`compute-add`**: a second compute node — packages, OVN chassis,
  `nova-compute` and the OVN metadata agent, with the credentials delivered
  explicitly and no database access at all

**Verified on two GCE VMs, 2026-09-28**

Nested virtualisation and `virt_type=kvm`; 17 systemd units active; authenticated
Keystone, Neutron and Nova APIs; cells v2; Placement resource providers with
inventory on both nodes; every initial resource; **a real Horizon login** (302 →
session cookie → authenticated pages rendering `admin`, not merely a 200 on the
login form); `compute-add` on a second node with credentials delivered and no
database or admin password; **two OVN chassis** and a **Geneve tunnel** between
them; and re-run safety — a second `all-in-one` exited 0 changing nothing and
restarting nothing.

That run found **ten defects**, nine fixed here. Among them: memcached serving
an address it had not been configured with, every packaged unit still running
the stock configuration because the package started it first, Horizon 500ing on
a stale offline manifest, `NoValidHost` because nova-scheduler caches the cell
list thirteen seconds before the cell exists, os_vif unable to reach the local
OVSDB, Neutron unable to tell Nova a VIF was plugged, and Keystone exhausting
its SQLAlchemy pool — which the step 4 notes had blamed on disk pressure and
which turned out to have nothing to do with disk.

**Still failing, and still honest about it**

**Guest boot.** It gets as far as: scheduled, libvirt domain created and paused,
OVN claims the port and marks it up, Neutron posts `os-server-external-events`
and Nova answers 200 — and the instance still reaches ERROR after 252 s with
`VirtualInterfaceCreateException`. Nothing downstream of that has run, so
**cloud-init is untested** and **Geneve has carried zero packets** (the tunnel
exists with the right endpoints; `tcpdump` on udp/6081 saw nothing, because
there was no guest to generate traffic). No path onto a physical LAN was
attempted; it is out of scope.

So after `all-in-one` finishes you have a host on which every OpenStack service
this project targets has been installed, configured and, as far as one machine
can check, started — and **on which nobody has ever logged in to the dashboard
or booted a virtual machine.** Both halves of that sentence are true and the
command prints both.

### Horizon

Served by **`apache2.service`** at **`/horizon` on port 80** — and the reason is
packaging, not choice. `openstack-dashboard` ships exactly one file,
`/etc/apache2/`**`conf-available`**`/openstack-dashboard.conf`. Note `conf-`, not
`sites-`: it is a *server-wide fragment* with no `Listen` of its own, so the
dashboard rides on whatever vhost exists (the packaged default site on port 80),
and that alias is inherited by the API vhosts as well.

Settings do **not** go into `/etc/openstack-dashboard/local_settings.py`, which
is a dpkg conffile. They go into a snippet at
`…/openstack_dashboard/local/local_settings.d/_99_hagistack.py`, which
`settings.py` `exec`s *after* the conffile — so the packaged file is never
touched and dpkg never prompts.

That loader swallows exceptions, which means **a broken snippet is silent**: the
dashboard would quietly keep the packaged `127.0.0.1` defaults. So hagistack does
not trust the file it just wrote — it asks Django what the settings actually are
and compares. Two values matter and both are wrong as shipped:

| | shipped | set by hagistack |
|---|---|---|
| `OPENSTACK_KEYSTONE_URL` | `http://127.0.0.1/identity/v3` (a DevStack path) | `http://<mgmt-ip>:5000/v3` |
| `CACHES … LOCATION` | `127.0.0.1:11211` | `<mgmt-ip>:11211` |

The cache one is not cosmetic: `SESSION_ENGINE` is
`django.contrib.sessions.backends.cache`, so Horizon keeps **sessions** in
memcached, and hagistack binds memcached to the management address. A dashboard
pointed at `127.0.0.1` is one nobody can log into. The phase refuses to run at
all unless memcached is answering.

Two more things worth knowing: installing the dashboard runs `invoke-rc.d
memcached restart` in its postinst, i.e. it bounces the cache the other services
use (the run warns first, and re-checks afterwards); and `nova-novncproxy` is
**not** installed, so the console tab will not work.

`ALLOWED_HOSTS` is left as the package ships it (`['*']`). Narrowing it would
break reaching the dashboard through an address this host does not know about —
a cloud external IP, or an SSH tunnel.

What the run proves: the settings took effect, and `/horizon/auth/login/`
answers **200**. What it does not prove: that a login works. Nobody has tried.

### Initial resources

The smallest set an instance needs. Every one is show-or-create **by name**;
nothing is deleted and nothing is recreated.

| | |
|---|---|
| flavor | `m1.tiny` — 1 vCPU / 512 MiB / 1 GiB |
| image | `cirros-0.6.3-<arch>` |
| external network | `hagistack-provider` (flat, `--external`), subnet with the floating pool and **no DHCP** |
| tenant network | `hagistack-tenant` (geneve), subnet with `--dns-nameserver` |
| router | `hagistack-router` — external gateway plus an interface on the tenant subnet |
| rules | ICMP and TCP/22 on the admin project's `default` security group |
| keypair | `hagistack-key`, RSA 3072, private key `0600` in `/etc/hagistack` |

**The image is never fetched without a digest.** There is no cirros package in
the Ubuntu archive, so it comes from a URL — and `--image-url` without
`--image-sha256` is a preflight error. The default URL and digest were measured
on 2026-09-27 by downloading the file and comparing it with the publisher's
`SHA256SUMS`; the download 302-redirects, so `curl -L` is mandatory and a run
without it saves a 273-byte HTML page. The file is verified *before* Glance sees
it; a mismatch is refused and left on disk, never uploaded.

**A test image is not an initial image.** An image hagistack uploads carries a
`hagistack_sha256` property. On a re-run, an image with the right name but no
such property — a leftover from a verification run, say — is *neither* accepted
as the initial image *nor* deleted: the run stops and says to pick another
`--image-name` or remove it by hand.

### compute-add

Run it **on the new machine**, with `--controller-ip <the controller's MGMT_IP>`.
None of the provider-network settings apply.

What the node deliberately does **not** get:

| Not given | Why |
|---|---|
| any database credential | since Pike a compute node reaches the cell database only through `nova-conductor`, over RabbitMQ |
| the admin password | nothing there authenticates as admin |
| `ovn-bridge-mappings` | a mapping with no NIC behind it invites OVN to bind a provider port here and drop its traffic. Geneve tenant ports need no mapping |
| `enable-chassis-as-gw` | the controller is the gateway chassis |

**Secrets are delivered, never generated** — a node that invented its own
RabbitMQ password could not talk to anything:

```sh
# on the controller
sudo hagistack compute-secrets > compute-secrets.env     # refuses a terminal
scp compute-secrets.env node2:/tmp/
# on node2
sudo install -o root -g root -m 0600 /tmp/compute-secrets.env /etc/hagistack/secrets.env
shred -u /tmp/compute-secrets.env
sudo hagistack compute-add --controller-ip 10.146.0.10
# back on the controller
sudo hagistack discover-hosts
```

`compute-secrets` emits exactly `RABBIT_PASS`, `NOVA_SERVICE_PASS`,
`PLACEMENT_SERVICE_PASS`, `NEUTRON_SERVICE_PASS` and `METADATA_PROXY_SECRET`.

**Input checks before anything is installed.** `nova-compute` pulls libvirt and
qemu, so preflight first validates `--controller-ip` as an address that can
belong to another machine (`0.x`, `127.x`, `169.254.x`, multicast,
`255.255.255.255` and this node's own address are all refused) and then opens a
bounded TCP connection to the controller on **5000, 9292, 8778, 5672 and 6642**.
Any of them closed is a hard error naming which — and nothing has been installed
or changed at that point.

The node cannot confirm its own registration (no database, no admin credential,
by design), so it tells you to run `hagistack discover-hosts` on the controller.
It does check what it can: that its chassis has appeared in the controller's
southbound database.

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

A service that cannot be reached is not quietly skipped. The run prints
`INCOMPLETE`, names the phases it skipped, writes **no** state marker for them,
and **exits 4**. `hagistack status` lists what is missing. Only a run in which
every implemented phase actually did its work prints the completion banner and
exits 0 — and that banner still says, in red, that nothing has been verified on
real hardware.

An incomplete run is the normal outcome in a container with no systemd. It is
not a failure of the shell, and it is not a completed deployment either.

| Exit | Meaning |
|---|---|
| 0 | success |
| 1 | configuration or preflight error |
| 2 | usage error |
| 3 | unused — no subcommand is a stub any more |
| 4 | ran to the end, the deployment is incomplete (a service was unreachable) |

## Usage

```sh
cp hagistack.env.example hagistack.env   # edit it
sudo ./hagistack all-in-one              # or: --check for preflight only
./hagistack status
```

Required settings for `all-in-one`: `EXT_NIC`, `PROVIDER_CIDR`,
`PROVIDER_GATEWAY`, `FLOATING_START`, `FLOATING_END`. Everything else is
autodetected or defaulted (including `REGION_NAME`, which defaults to
`RegionOne`, and the image settings).

`compute-add` needs exactly one setting of its own, `--controller-ip`, and none
of the provider-network ones.

Then, to find out whether any of it works:

```sh
. /etc/hagistack/admin-openrc
openstack server create --flavor m1.tiny --image cirros-0.6.3-x86_64 \
    --network hagistack-tenant --key-name hagistack-key demo1
openstack server list
openstack console log show demo1
```

That has never been run successfully by anyone, which is the point of the
section below.

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
| — | A service that cannot be reached does not count as done: no state marker, `INCOMPLETE`, exit 4 |
| AppArmor disabled, libvirt opened on TCP with `auth_tcp="none"`, MariaDB bound to `0.0.0.0` | None of these. MariaDB is pinned to `127.0.0.1`, memcached to the management IP |

Re-running `all-in-one` is safe and is part of the acceptance criteria.

## What has actually been verified

**Nothing on real hardware.** Everything below was done in an Ubuntu 26.04.1 LTS
amd64 container, and a container cannot boot a guest, run systemd, or be a
second machine. Read this section as "what the container settled", not as
"what works".

### Step 6 (this build) — `tests/container-step6.sh`

**PASS 69 / FAIL 0 / UNVERIFIED 7, guest exit 0.** Deliberately light, and the
limits were decided before it ran.

Regression on the same container, all guest exit 0 and no FAIL:
`container-step5.sh` **68/0/7**, `container-audit.sh` **39/0/1**,
`container-verify.sh` **63/0/8** — each matching its baseline. Four assertions
in those older suites were re-pinned because this change removed the wording
they matched (the `STEP <n>` numbering, and `compute-add` being a stub); one
step-5 run also failed on a **full disk** rather than on anything in the shell,
and was re-run with room. Both are itemised in
`STEP6_HORIZON_RESOURCES_EVIDENCE.md` §5.3.

Settled: `bash -n`; ShellCheck `-S warning` clean on the shell and both suites;
that `status` and `--help` separate *implemented* from *verified* and state that
the second is `none`; that the stale "STEP 1" header is gone and no subcommand
advertises itself as a stub; twelve image-input validations and eight
controller-IP validations, none of which executed anything; that **every**
`CONFIG_KEYS` entry is accepted from a config file; that `IMAGE_URL=$(...)` is
refused rather than run; that the pinned cirros digest matches **the publisher's
live `SHA256SUMS`**; that `compute-add` refuses an unreachable controller, a
missing secrets file, a world-readable one and an incomplete one, **installing
nothing** in any of those cases; that `compute-secrets` emits no database or
admin credential; and a source audit — no `openstack … delete`, no `DROP`, no
`rm -rf` against a system path, no write to the dashboard's dpkg conffile, no
`[database]` connection on a compute node, no gateway chassis on a compute node.

Recorded **UNVERIFIED**, not forced into a PASS: Horizon serving and login,
guest boot, the initial resources actually being created, a second node's OVN
chassis, node-to-node Geneve, `compute-add` → Placement registration, and unit
startup under systemd.

A bug the suite found that had nothing to do with step 6: keys sitting at the
**end of a line** inside `CONFIG_KEYS` were rejected from `hagistack.env` as
"unknown key" while working fine on the command line. In the shipped step 5 that
was `FLOATING_START` — a *required* setting — and `REGION_NAME`. Fixed, with a
test that now walks every key. See `STEP6_HORIZON_RESOURCES_EVIDENCE.md` §4.

### Earlier steps

Verified in the same kind of container (no systemd): `bash -n`, ShellCheck,
`--help`, subcommand resolution, input validation, config-generation
idempotence, secret file permissions and value stability across runs, refusal of
code-execution payloads in the config file, the full precedence matrix, and the
incomplete-run reporting and exit code.

With **MariaDB started by hand** inside the container (`mariadbd-safe
--skip-networking`, recorded as such): database and user creation, login as the
`nova` user to both the `nova` and `nova_api` databases with one credential, and
survival of a planted row across three consecutive runs.

Keystone was verified with MariaDB and Apache started **by hand**
(`mariadbd-safe --bind-address=127.0.0.1`, `apachectl -k start`): 49-table
schema, fernet and credential keys, bootstrap, and `openstack token issue`
succeeding as admin, with every artefact unchanged across three consecutive runs.

For step 4 the same container (this time `--privileged`, with `/lib/modules`
mounted) started MariaDB, memcached, **RabbitMQ**, Apache, `ovsdb-server`,
`ovs-vswitchd`, the OVN northbound and southbound databases and `ovn-northd`,
all by hand and all recorded. That proved: the OVN databases listen exactly
where the design says (`ptcp:6641:127.0.0.1` and `ptcp:6642:$MGMT_IP`, confirmed
with `ss`), the local chassis registers itself in the southbound database with a
**Geneve** encap pointing at the management address, the provider bridge is
created with **no port and no address**, the management interface keeps exactly
the addresses it had, and the networking schema is created (135 tables).

Step 5 ran a light suite — **PASS 68 / FAIL 0 / UNVERIFIED 7, guest exit 0** —
covering syntax, ShellCheck, input validation, honest skipping, the Nova
packaging facts, configuration generation against the real packaged `nova.conf`
(including byte-identical re-application), the three compute databases with one
credential, and secret handling.

### Not verified anywhere, by anything

Logging in to **Horizon**; **booting a guest**; the initial resources being
created against a live control plane; the **authenticated Neutron API** and
network creation; **Nova's** cells commands executing, `nova-compute`/libvirt,
and hypervisor registration; **`compute-add`** end to end, the second node's OVN
chassis, and **Geneve between two nodes**; any **physical-LAN** provider path or
floating IP; and service startup and unit ordering **under systemd**.

Those are the GCE acceptance items — see
`../HAGISTACK_VERIFICATION_SCOPE_2026-09-26.md` §5.

About one earlier note: step 4 hit a Keystone `QueuePool limit of size 5
overflow 50 reached` at 98% disk, and the write-up leaned on the disk figure.
**Disk pressure was a correlation, not a diagnosis** — the one number actually
measured, 56 of 1024 server-side connections, says the database server was not
the limit. It was never diagnosed. `STEP6_HORIZON_RESOURCES_EVIDENCE.md` §5.2
lists the candidates that were not ruled out.

Nothing in this shell has been run on real Ubuntu 26.04 hardware or on a GCE VM.

## Rocky Linux 10.2

Not implemented, and this repository does not claim it is. The re-investigation
on 2026-09-27/28 corrected part of the earlier verdict — EL10 RPMs *do* exist,
and `dnf` resolves a 704-package OpenStack on Rocky 10.2 — but what it resolves
mixes three OpenStack cycles from stalled build queues behind content-hash URLs.
The measurements, the reasoning and a re-runnable probe are in
`../rocky10.2/README.md`.
