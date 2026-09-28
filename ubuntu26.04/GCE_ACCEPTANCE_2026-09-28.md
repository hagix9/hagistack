# GCE acceptance, 2026-09-27/28 — Ubuntu 26.04 on real hardware

> **Superseded in part by `GCE_ACCEPTANCE_2026-09-28_RUN2.md`.** The two items
> this document leaves open — guest boot (§3.1) and the compute-node
> `[database]` connection (§2.11) — were both solved in run 2. Note also that
> §2.8's conclusion was **wrong**: the 200 in the Nova access log was a
> `network-changed` event, not `network-vif-plugged`, which was never sent at
> all. Run 2 §2 has the correlated logs and the actual cause (`ProcSubset=pid`
> on `apache2.service`). Everything else here stands.

The first time any of this ran outside a container. It found **ten defects**,
nine of which are fixed here. None of them could have been found in a container:
every one depends on systemd, on a package starting its own unit, on a real
hypervisor, or on two machines.

---

## 1. Environment

| | |
|---|---|
| Project / region | `sinter-508914` / `asia-northeast1` |
| node1 (all-in-one) | `hagistack-node1`, **n2-standard-4** (4 vCPU / 16 GiB), 60 GB pd-balanced, zone `-a`, `10.146.0.22` |
| node2 (compute-add) | `hagistack-node2`, **n2-standard-2** (2 vCPU / 8 GiB), 40 GB pd-balanced, zone **`-b`**, `10.146.0.23` |
| Image | `ubuntu-2604-resolute-amd64-v20260918` (family `ubuntu-2604-lts-amd64`) |
| Nested virtualisation | `--enable-nested-virtualization`; **confirmed**: `/dev/kvm` present, `kvm_intel` loaded, `vmx` in `/proc/cpuinfo`, `virsh capabilities` reports `domain type='kvm'`, and preflight resolved `virt_type=kvm` |
| Window | `21:02:05Z` → `01:08:15Z` = **4 h 06 min** (node1); node2 ≈ 25 min |
| Quota at the time | N2_CPUS 0/200, CPUS 0/100, INSTANCES 10/24, DISKS_TOTAL_GB 80/4096 |

**node2 had to go to a different zone.** `asia-northeast1-a` refused
`n2-standard-2` with *"resources available to fulfill the request. Try a
different zone"*; `-b` succeeded. Cross-zone made no difference to any result —
both are in the same VPC and subnet `10.146.0.0/20`.

**Cost.** Approximate, on-demand, asia-northeast1: n2-standard-4 ≈ $0.24/h for
4.1 h ≈ **$1.0**; n2-standard-2 ≈ $0.12/h for 0.4 h ≈ **$0.05**; 100 GB
pd-balanced for that window ≈ **$0.02**. Order **$1.1 total**. These are
estimates from list prices, not a billing export.

### 1.1 Firewall: measured, not assumed

The previous plan said "`default-allow-internal` exists, so no rule is needed".
That was checked properly this time, first by reading the rules and then by
measuring from node2.

Rules, with target and priority — the three `sinter-p8-gateway-*` rules are
**target-tagged** and cannot apply to an untagged VM:

| Rule | Priority | Source | Targets | Allows |
|---|---|---|---|---|
| `default-allow-internal` | 65534 | 10.128.0.0/9 | **none (all instances)** | tcp:0-65535, udp:0-65535, icmp |
| `default-allow-ssh` | 65534 | 0.0.0.0/0 | none | tcp:22 |
| `default-allow-icmp` | 65534 | 0.0.0.0/0 | none | icmp |
| `sinter-p8-gateway-ssh-iap` | 900 | 35.235.240.0/20 | tag `sinter-p8-gateway` | tcp:22 |
| `sinter-p8-gateway-ssh-deny-external` | 950 | 0.0.0.0/0 | tag `sinter-p8-gateway` | DENY tcp:22 |
| `sinter-p8-gateway-https` | 1000 | 0.0.0.0/0 | tag `sinter-p8-gateway` | tcp:80,443 |

Measured from node2 (`10.146.0.23`) to node1 (`10.146.0.22`), before
`compute-add` changed anything:

```
  tcp/5000   OPEN      identity
  tcp/9292   OPEN      image
  tcp/8778   OPEN      placement
  tcp/5672   OPEN      message queue
  tcp/6642   OPEN      OVN southbound
  tcp/11211  OPEN      memcached
  tcp/6641   closed    OVN northbound   <- by design: bound to 127.0.0.1
  tcp/3306   closed    MariaDB          <- by design: bound to 127.0.0.1
  icmp       OK
  udp/6081   egress not blocked
```

**No firewall rule was added, and none was needed.** The two closed ports are
closed because hagistack binds those services to loopback, not because a rule
blocks them — which is the distinction the earlier plan glossed over.

---

## 2. Defects found on real hardware

### 2.1 memcached was serving an address it had not been configured with

`phase_memcached` rewrote `/etc/memcached.conf` and reported success. The
service was `active`. It was listening on **127.0.0.1 and ::1**.

Two independent bugs:

* `/etc/memcached.conf` is **not a dpkg conffile** (`dpkg -S` finds no owner);
  the package ships `/usr/share/memcached/memcached.conf.default` and copies it,
  and that default has **two** `-l` lines (`127.0.0.1` and `::1`). The old
  `sed -i -E 's/^-l .*/-l $MGMT_IP/'` rewrote **both**, leaving the same address
  listed twice.
* The package had already started memcached at install time. `systemctl enable
  --now` is a no-op on an active unit, so nothing restarted it and the running
  process kept its original arguments:
  `/usr/bin/memcached -m 64 -p 11211 -u memcache -l 127.0.0.1 -l ::1`

Everything downstream skipped honestly — which is the one thing that worked as
designed. Fixed by replacing every `-l` line with exactly one, restarting when
the file changes, and **verifying the cache answers on `$MGMT_IP:11211`** rather
than trusting `is-active`.

### 2.2 The same trap, for every service — the systemic one

Ubuntu starts each service's unit at install time, which is **before** hagistack
writes any configuration. Measured, with timestamps:

| unit | started by the package at | configured by hagistack after that |
|---|---|---|
| `memcached` | 21:07:11 | yes |
| `glance-api` | 21:09:43 | yes |
| `neutron-ovn-metadata-agent` | 21:10:46 | yes |
| `neutron-periodic-workers` | 21:14:18 | yes |
| `nova-scheduler` | 21:14:18 | yes |
| `nova-conductor` | 21:14:20 | yes |

`neutron.conf` still read `connection = sqlite:////var/lib/neutron/neutron.sqlite`
while `neutron-rpc-server` was `active`. A container has no systemd, so this was
invisible for five steps.

Fixed with `service_apply <unit> <config-file>...`, which restarts a unit **when
the configuration it reads is newer than the running process**. `ini_set` only
rewrites a file when the content changes, so an unchanged re-run restarts
nothing — confirmed below.

### 2.3 Probing a service the instant it restarts is a race

`systemctl restart` returns when the unit is active, seconds before the socket
listens. memcached, glance-api and the Apache vhosts each lost that race and
were reported "active but not answering". Fixed with a **bounded** `wait_for`
at each probe (60–90 s), never an unbounded loop.

### 2.4 Horizon: HTTP 500 from a stale offline compression manifest

```
OfflineGenerationError: You have offline compression enabled but key ...
is missing from offline manifest
```

`COMPRESS_OFFLINE = True` in the packaged settings, and the manifest was built
by the package's postinst **before** hagistack's `local_settings.d` snippet
existed. Step 6's rule — "regenerate only when `/var/lib/openstack-dashboard/static`
is empty" — was wrong: the directory was full, of assets built for other
settings. Fixed by rebuilding when the settings change **and** by treating a
non-200 login page as a reason to rebuild once and retry.

### 2.5 The router interface was not idempotent

Re-running `bootstrap_resources` failed with:

```
BadRequestException: 400 ... Bad router request: Cidr 10.10.10.0/24 of subnet
6c6758c5-... overlaps with cidr 10.10.10.0/24 of subnet 6c6758c5-...
```

Neutron reports "this subnet is already attached" as the subnet overlapping
**with itself**. Matching on `already exists`/`409` never fires for it, so a
correct deployment was reported as a failed phase on its second run. Fixed by
asking about state (`router_has_subnet`, via `port list --router`) instead of
parsing an error string.

### 2.6 nova-scheduler caches the cell list at startup — `NoValidHost`

Every boot failed with *"No valid host was found"* on a cloud where the
hypervisor was up, registered, and reporting a full inventory to Placement
(`VCPU 4, MEMORY_MB 15984, DISK_GB 57`, usage 0). The scheduler log said:

```
WARNING nova.scheduler.host_manager  No cells were found
INFO    nova.filters  Filter ComputeFilter returned 0 hosts
```

Timestamps settle it:

```
nova-scheduler ExecMainStartTimestamp : 21:21:31
nova_api.cell_mappings cell1 created  : 21:21:44
```

Thirteen seconds. The scheduler reads the cells once, at startup, and caches
them; creating a cell touches no file, so `service_apply` had nothing to notice.
Fixed by restarting the scheduler **when a cell is created**, and by setting
`[scheduler] discover_hosts_in_cells_interval = 300` so a later compute node is
mapped without anyone remembering to run a command.

### 2.7 os_vif could not reach the local Open vSwitch database

With scheduling fixed, the build reached the compute node and died there:

```
ERROR os_vif Exception: Could not retrieve schema from tcp:127.0.0.1:6640
```

os_vif's default is `tcp:127.0.0.1:6640`; Ubuntu's `ovsdb-server` listens on
**no TCP port at all**. Pointing it at the unix socket instead gave:

```
ERROR ovsdbapp Unable to open stream to unix:/var/run/openvswitch/db.sock
```

because that socket is `srwxr-x--- root root` and nova runs as `nova`. Fixed by
having the OVN phase ask ovsdb-server for a **loopback-only** manager
(`ptcp:6640:127.0.0.1`, which lives in the OVSDB and survives a restart) and
pointing `[os_vif_ovs] ovsdb_connection` at it. Nothing becomes reachable off
the host. After this a libvirt domain was created and paused, as it should be.

### 2.8 Neutron could not tell Nova the VIF was plugged

```
nova.exception.VirtualInterfaceCreateException: Virtual Interface creation failed
```

after 252 s — `vif_plugging_timeout`. The packaged `neutron.conf` ships an
**empty `[nova]` section**, comments only, so Neutron had no credentials to POST
`os-server-external-events` to the compute API. Fixed by writing that
keystoneauth block. Verified afterwards in the Nova API access log:

```
"POST /v2.1/os-server-external-events HTTP/1.1" 200
```

### 2.9 Keystone exhausted its database pool — and it was never a disk problem

Every API answered 500 or 503 after roughly forty minutes of use, recovering
only after `systemctl restart apache2`. The cause:

```
sqlalchemy.exc.TimeoutError: QueuePool limit of size 5 overflow 50 reached,
connection timed out, timeout 30.00
```

on `POST /v3/auth/tokens`. Because every other service validates its tokens
against Keystone, one wedged Keystone presented as "Neutron is broken", then
"Nova is broken".

**The step 4 write-up blamed disk pressure. That was wrong.** When this was
reproduced the host had **53 GB free**, MariaDB was at **338 of 1024**
connections with `Max_used_connections 344` and `Aborted_connects 0`. The server
had room; the **per-process pool** did not — oslo.db defaults to
`max_pool_size=5, max_overflow=50`. Fixed by sizing the pool explicitly
(`max_pool_size=25, max_overflow=50, pool_timeout=30`) for Keystone, Glance,
Placement, Neutron and both Nova databases.

### 2.10 `compute-secrets` wrote a diagnostic into the credentials file

`compute-add` on node2 died with:

```
/dev/fd/63: line 1: syntax error near unexpected token `('
```

The first line of the delivered file was:

```
    config file: ./hagistack.env (parsed, not executed)
```

`log_info` writes to stdout, and `compute-secrets` **is** stdout. Fixed twice
over: that command's diagnostics now go to stderr, and
`phase_compute_secrets` **validates the file before sourcing it** — this shell
refuses to execute a config file for exactly this reason, and a credentials file
deserves the same treatment.

### 2.11 Found, not fixed: a compute node keeps a `[database]` connection

node2's `nova.conf` carries a `[database]` connection that hagistack warns about
but does not remove, so `nova-compute` there logs:

```
WARNING oslo_db.sqlalchemy.engines SQL connection failed. 7 attempts left.
WARNING nova.context Timed out waiting for response from cell 00000000-...
```

It is harmless in the sense that registration still succeeded, but a compute
node must not attempt database access at all. Removing configuration conflicts
with this shell's "never delete" rule and needs a deliberate `ini_unset` that
comments the key out audibly. **Not done. Recorded as open.**

> **Done in run 2.** `ini_comment_out` comments the key out, keeps its value on
> the line, and the shell then reads nova-compute's journal and reports
> `0 database lines (no SQL connection attempted)`. See
> `GCE_ACCEPTANCE_2026-09-28_RUN2.md` §3.

---

## 3. Acceptance results

### 3.1 node1 — all-in-one

**PASS**

| Item | Evidence |
|---|---|
| nested virtualisation | `/dev/kvm` present, `kvm_intel` loaded, `vmx` present, `virsh capabilities` → `domain type='kvm'`, preflight → `virt_type=kvm` |
| systemd units (17) | all `active`: mariadb, rabbitmq-server, memcached, apache2, glance-api, ovn-ovsdb-server-nb/sb, ovn-northd, ovn-controller, neutron-rpc-server, neutron-periodic-workers, neutron-ovn-metadata-agent, nova-conductor, nova-scheduler, nova-compute, libvirtd, openvswitch-switch |
| authenticated identity | `openstack token issue` succeeded |
| catalogue | glance, keystone, neutron, nova, placement |
| authenticated Neutron | `openstack network list`; agents: 1 OVN Controller Gateway, 1 OVN Metadata |
| authenticated Nova | `openstack compute service list` → scheduler/conductor/compute all `up` |
| cells v2 | `cell0` + `cell1` present, host mapped into `cell1` |
| Placement resource provider | inventory `VCPU 4, MEMORY_MB 15984, DISK_GB 57`, usage 0, read over the Placement REST API with a token |
| initial resources | `m1.tiny`; image `active` at **21692416 bytes**, matching the pinned source exactly; `hagistack-provider` + `hagistack-tenant`; router with **2** interfaces; `hagistack-key`; 2 security-group rules |
| **Horizon real login** | POST → **302**, `sessionid` cookie issued, and `/horizon/project/instances/`, `/horizon/identity/`, `/horizon/project/networks/` each returned **200 with no login form and `admin` rendered in the page**. Not a 200 on the login page — an authenticated session. |
| **re-run safety** | a second `all-in-one` exited **0** with **93** "already/unchanged/left untouched" lines, **0 phases skipped and 0 units restarted** |

**FAIL**

| Item | Where it stops |
|---|---|
| **guest boot** | Scheduling works (2.6), the libvirt domain is created and paused (2.7), ovn-controller claims the logical port and sets it `up` in the southbound database, and Neutron's `os-server-external-events` POST returns 200 (2.8) — and the instance still reaches ERROR after **252 s** with `VirtualInterfaceCreateException`. **SOLVED in run 2**: the 200 was a `network-changed` event; `network-vif-plugged` was never sent, because `ProcSubset=pid` on `apache2.service` hides `/proc/meminfo` and every OVN event is dropped inside Neutron's `notify()`. Guest boot now reaches ACTIVE in 18 s. |
| **cloud-init / metadata** | not reached — no guest ever ran. **SOLVED in run 2**: cloud-init completes, key injected, `login:` reached. |

### 3.2 node2 — compute-add

`compute-add` ran to completion. **8 / 8 PASS**, measured from the controller:

| Item | Evidence |
|---|---|
| credential delivery | `compute-secrets` emitted **exactly 5** keys — `RABBIT_PASS NOVA_SERVICE_PASS PLACEMENT_SERVICE_PASS NEUTRON_SERVICE_PASS METADATA_PROXY_SECRET` — and **0** database or admin keys. Installed `0600 root:root`. |
| preflight | all five controller ports probed reachable before anything was installed |
| compute service | both nodes `up` in `openstack compute service list` |
| hypervisors | both listed |
| cells | **2** hosts mapped |
| **Placement registration** | node2 has its own resource provider with inventory `VCPU=2 MEMORY_MB=7933 DISK_GB=37` |
| **OVN chassis** | **2** chassis in the southbound DB, node2's named `hagistack-node2...` |
| **Geneve endpoint** | encaps `10.146.0.22 geneve` and `10.146.0.23 geneve` |
| **Geneve tunnel** | `ovn-12f94c-0`, `type=geneve`, `options={local_ip="10.146.0.22", remote_ip="10.146.0.23", csum="true", key=flow}` |
| re-run safety | a second `compute-add` exited **0**, 7 "already/unchanged" lines |

**Not verified**

* **Geneve carrying traffic.** The tunnel exists with the right endpoints, and
  `tcpdump -ni ens4 'udp port 6081'` captured **0 packets** over 12 s with the
  interface counters at `rx_packets=0 tx_packets=0`. There was nothing to carry:
  guest boot failed, so no tenant traffic existed. A configured tunnel is not a
  used tunnel and is not reported as one.
  **Verified in run 2**: 17 Geneve packets captured carrying guest ICMP between
  the two nodes, 8/8 ping replies, 0% loss.
* **Guest boot on node2** — blocked by the same defect as node1.
  **Verified in run 2**: ACTIVE in 12 s on node2.

---

## 4. Cleanup

```
gcloud compute instances delete hagistack-node1 --zone=asia-northeast1-a --delete-disks=all
gcloud compute instances delete hagistack-node2 --zone=asia-northeast1-b --delete-disks=all
```

Verified afterwards: **no** `hagistack-*` instance, **no** `hagistack-*` disk,
**no** snapshot, **no** reserved address, and the firewall rule list is byte for
byte the six rules it started with. Nothing was added and nothing is being
billed for this work.

**One observation, not an action of ours.** `mikagami-validation` was
`TERMINATED` when this session began and is `RUNNING` now. Its own metadata
records `lastStopTimestamp 00:23:19Z` and `lastStartTimestamp 01:04:35Z`. The
only instances this session created or deleted were `hagistack-node1` and
`hagistack-node2`; something else operates that VM. It was left alone.
