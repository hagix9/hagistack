# GCE acceptance run 2, 2026-09-28 — guest boot solved

The first acceptance (`GCE_ACCEPTANCE_2026-09-28.md`) fixed nine defects and
left one open: **no guest would boot on either node**. Neutron's
`os-server-external-events` POST returned 200, the libvirt domain was created
and paused, ovn-controller claimed the logical port — and `nova-compute` still
timed out on `network-vif-plugged` after 300 s.

This run found why. It is not a Nova bug, not a message-queue bug, and not the
cell transport. **It is a systemd hardening option on `apache2.service`.**

Guest boot now works: **ACTIVE in 12–18 s on both nodes, cloud-init completes,
and two guests on different hosts ping each other over a Geneve tunnel whose
packets were captured.**

---

## 1. Environment

| | |
|---|---|
| Project / region | `sinter-508914` / `asia-northeast1` |
| node1 (all-in-one) | `hagistack-node1`, n2-standard-4, 60 GB pd-balanced, zone `-a`, `10.146.0.26` |
| node2 (compute-add) | `hagistack-node2`, n2-standard-2, 40 GB pd-balanced, zone **`-a`**, `10.146.0.29` |
| Image | `ubuntu-2604-resolute-amd64-v20260918` |
| Nested virtualisation | enabled; `/dev/kvm` present on both |
| Window | ≈ 10:48Z → 12:05Z, about **1 h 20 min** for both nodes |
| Cost | ≈ **$0.45** (n2-standard-4 ≈ 1.3 h, n2-standard-2 ≈ 0.4 h, 100 GB pd-balanced). List-price estimate, not a billing export |
| New VMs created | **2**, the agreed maximum. Both deleted; see §6 |

Unlike run 1, node2 fitted in `asia-northeast1-a`, so both nodes were in one
zone. Nothing in the result depends on that.

A clean `all-in-one` took **≈ 25 minutes** end to end, 13/13 phases, 0 skips.

---

## 2. The defect: `ProcSubset=pid` on apache2 silently disables ML2/OVN

### 2.1 What the first run misread

Run 1 recorded *"Neutron's `os-server-external-events` POST returns 200"* and
concluded Nova was ignoring the plug event. The access log was real, but it was
the wrong event. With debug logging on both sides, correlated by instance and
port id:

```
port     468a28b5-d0f2-4362-8cdb-9093670d5dc3
instance a685cb61-b7c9-4372-9b7f-c6fe16b43753
host     hagistack-node1.asia-northeast1-a.c.sinter-508914.internal

11:19:09.866  nova-api      Creating event network-changed:468a28b5… for instance a685cb61… on hagistack-node1…
11:19:09.884  nova-compute  Received event network-changed-468a28b5…              <- 18 ms later
11:19:11.152  nova-compute  Preparing to wait for external event network-vif-plugged-468a28b5…
11:24:14.589  nova-compute  Timeout waiting for ['network-vif-plugged-468a28b5…'] … timed out after 300.00 seconds
```

The only event Neutron ever sent was **`network-changed`**. `network-vif-plugged`
was never sent at all. And because `network-changed` was delivered to
nova-compute in **18 milliseconds**, the whole transport chain — RabbitMQ, the
`cell1` mapping's `transport_url`, the `compute.<host>` routing — is proven
working, not merely assumed. The cell transport was checked directly as well:

```
cell0  00000000-0000-0000-0000-000000000000  none:///
cell1  abab1162-152d-4a97-8cc0-798c23d8fe01  rabbit://USER:REDACTED@10.146.0.26:5672/   <- matches nova.conf
```

### 2.2 OVN had done its job

Watched live during a boot, every 15 s for 90 s:

```
  t+15s  NB.up=true  SB.chassis=646765fe-…  neutron.port=DOWN  ovs-iface=present
  t+30s  NB.up=true  SB.chassis=646765fe-…  neutron.port=DOWN  ovs-iface=present
  …
  t+90s  NB.up=true  SB.chassis=646765fe-…  neutron.port=DOWN  ovs-iface=present
```

`virsh list` → `instance-00000002  paused`; `ovs-vsctl list-ports br-int` →
`tap3108e0b3-22`. OVN bound the port and set `Logical_Switch_Port.up=true`.
**Neutron never moved the port out of `DOWN`.**

That is exactly what Neutron then reported to Nova:

```
neutron.notifiers.nova  Ignoring state change previous_port_status: DOWN
                        current_port_status: DOWN port_id 3108e0b3-…
```

and the provisioning block was never released:

```
neutron.db.provisioning_blocks  Transition to ACTIVE for port object
  3108e0b3-… will not be triggered until provisioned by entity L2.
```

### 2.3 The cause

Every neutron API worker was throwing the same exception, in the function that
dispatches OVN database events:

```
ERROR neutron.plugins.ml2.drivers.ovn.mech_driver.ovsdb.ovsdb_monitor
  File ".../ovsdb_monitor.py", line 884, in notify
  File ".../neutron/service.py", line 117, in _get_worker_count
    mem = psutil.virtual_memory()
  File ".../psutil/_pslinux.py", line 361, in virtual_memory
    with open_binary(f"{get_procfs_path()}/meminfo") as f:
FileNotFoundError: [Errno 2] No such file or directory: '/proc/meminfo'
```

`OvnIdlDistributedLock.notify()` is the single funnel for **every** northbound
OVN row event. The exception escapes it, so every event is dropped — including
`LogicalSwitchPortUpdateUpEvent`, the one that calls `set_port_status_up()`.

`/proc/meminfo` is missing because Ubuntu 26.04 ships
`/usr/lib/systemd/system/apache2.service` with:

```
line 37:  ProtectProc=invisible
line 38:  ProcSubset=pid
```

`ProcSubset=pid` hides every non-pid file in `/proc` from the unit. Measured
inside a live worker:

```
# nsenter -t <neutron wsgi pid> -m -- ls /proc/meminfo
ls: cannot access '/proc/meminfo': No such file or directory
```

Neutron's ML2/OVN driver runs **inside those Apache workers** — on Ubuntu the
networking API is an Apache vhost, not a `neutron-server` unit — so the
hardening applies to it.

The full chain, each link measured:

```
apache2.service ProcSubset=pid
  -> /proc/meminfo invisible to the neutron API workers
  -> psutil.virtual_memory() raises inside _get_worker_count()
  -> the exception escapes OvnIdlDistributedLock.notify()
  -> every northbound OVN event is dropped
  -> set_port_status_up() never runs
  -> the "L2" provisioning block is never released
  -> the Neutron port stays DOWN for ever
  -> the nova notifier sends only network-changed, never network-vif-plugged
  -> nova-compute waits out vif_plugging_timeout
  -> VirtualInterfaceCreateException, and every guest dies at 300 s
```

Nothing in Nova was wrong. Nothing in the message queue was wrong. Raising
`vif_plugging_timeout` would have made it slower to fail and no more likely to
work, which is why that was not done.

### 2.4 The fix

A systemd drop-in, written by `phase_neutron`:

```ini
# /etc/systemd/system/apache2.service.d/10-hagistack-procsubset.conf
[Service]
ProcSubset=all
```

`ProtectProc=invisible` is deliberately **left alone** — it hides other
processes' directories, which is not what breaks this, so that hardening still
applies. Only the one option that causes the failure is relaxed.

Because `ProcSubset` is a unit property, a reload does not pick it up. The
shell therefore does a full `systemctl restart apache2` **when it writes the
drop-in**, and a plain reload when it did not. Then it measures the result
rather than assuming it:

```
    ok   apache2 ProcSubset=all written (/etc/systemd/system/apache2.service.d/10-hagistack-procsubset.conf)
    ok   apache2 restarted so the ProcSubset override takes effect
    ok   apache2 workers can read /proc/meminfo (OVN port-up events will be processed)
```

On a later run, when nothing changed:

```
    ok   apache2 ProcSubset override already in place (unchanged)
    ok   apache2 workers can read /proc/meminfo (OVN port-up events will be processed)
```

If the check ever fails it says so in the loudest terms the shell has, because
the alternative is discovering it 300 seconds into a build.

### 2.5 Proof, on the same host, minutes apart

| | before the drop-in | after the drop-in |
|---|---|---|
| Neutron port status | `DOWN` for ever | `ACTIVE` |
| `network-vif-plugged` sent | **never** | yes, `status: completed` |
| nova-compute | `Timeout waiting for [...]` at 300 s | `Processing event network-vif-plugged-…` |
| instance | `ERROR` after 235–300 s | **`ACTIVE` after 18 s** |

The events, after the fix, end to end:

```
neutron   Sending events: [{'server_uuid': '37f79373…', 'name': 'network-vif-plugged',
                            'status': 'completed', 'tag': '016fc9c2…'}]
nova-api  Creating event network-vif-plugged:016fc9c2… for instance 37f79373… on hagistack-node1…
compute   Received event   network-vif-plugged-016fc9c2…
compute   Processing event network-vif-plugged-016fc9c2…
```

---

## 3. Defect 2.11 from run 1, now fixed: `[database]` on a compute node

Run 1 recorded, and did not fix, a `[database] connection` left in node2's
`nova.conf`, which made `nova-compute` open a database it must never touch.

Fixed with a new `ini_comment_out`, which **comments the key out instead of
deleting it**: the value stays on the line so it can be restored, a comment
records who silenced it and why, and only the named key in the named section is
touched. `[api_database] connection` gets the same treatment.

Measured on node2, first run:

```
    ok   [database] connection commented out in nova.conf (value kept on the line)
    ok   [api_database] connection commented out in nova.conf (value kept on the line)
    ok   no active [database]/[api_database] connection: this node opens no database
    ok   nova-compute journal since start: 0 database lines (no SQL connection attempted)
```

That last line is the point: the shell reads `nova-compute`'s own journal since
the current start and counts the lines that only appear when a database is
opened (`oslo_db.sqlalchemy.engines`, `SQL connection failed`, `Timed out
waiting for response from cell`). It found **0**, where run 1 had
`SQL connection failed. 7 attempts left.` on every start.

On a second `compute-add`, the keys are already commented, nothing is rewritten,
and **0 units are restarted** — so the fix is re-runnable, not just correct once.

---

## 4. Acceptance results

### 4.1 node1 — all-in-one — **PASS**

| Item | Evidence |
|---|---|
| deploy | 13/13 phases, **0 skipped**, exit **0**, ≈ 25 min |
| units | 17/17 `active` |
| **guest boot** | `demo3` **ACTIVE after 18 s** |
| **cloud-init** | `checking http://169.254.169.254/2009-04-04/instance-id`, key injected, `=== datasource: ec2 net ===`, `demo3 login:` |
| port status | `ACTIVE` (was `DOWN` for ever before the fix) |
| ProcSubset check | `apache2 workers can read /proc/meminfo` |

### 4.2 node2 — compute-add — **PASS**

| Item | Evidence |
|---|---|
| credential delivery | exactly **5** keys, 0 database/admin keys, installed `0600 root:root` |
| deploy | exit **0** |
| `[database]` removal | commented out, **0 database lines** in the journal |
| registration | both nodes `up` in `compute service list` and `hypervisor list` |
| cells | both hosts mapped by `discover-hosts` |
| OVN chassis | 2 chassis, geneve encaps `10.146.0.26` and `10.146.0.29` |
| **guest boot on node2** | `gB` **ACTIVE after 12 s** on `hagistack-node2` |

### 4.3 Cross-node traffic — **PASS**

Two guests, one pinned to each host, then an SSH into `gA` from the OVN
metadata namespace and a ping to `gB`:

```
gA(node1)=10.10.10.209   gB(node2)=10.10.10.125

ga
    inet 10.10.10.209/24 brd 10.10.10.255 scope global dynamic noprefixroute eth0
--- ping the guest on node2 ---
8 packets transmitted, 8 received, 0% packet loss, time 7011ms
rtt min/avg/max/mdev = 1.166/1.471/2.906/0.558 ms
```

and the tunnel carrying it, captured on the physical NIC:

```
11:55:18.012107 IP 10.146.0.26.17578 > 10.146.0.29.6081: Geneve, Flags [C], vni 0x2,
    options [8 bytes]: IP 10.10.10.209 > 10.10.10.125: ICMP echo request, id 12988, seq 1, length 64
11:55:18.014102 IP 10.146.0.29.15493 > 10.146.0.26.6081: Geneve, Flags [C], vni 0x2,
    options [8 bytes]: IP 10.10.10.125 > 10.10.10.209: ICMP echo reply,   id 12988, seq 1, length 64
…
total geneve packets captured: 17
17 packets captured, 0 packets dropped by kernel
```

```
br-int geneve port: ovn-0f81c5-0
  options: {csum="true", key=flow, local_ip="10.146.0.26", remote_ip="10.146.0.29"}
```

Run 1 could only report *"the tunnel exists and carries 0 packets"*. This is the
tunnel carrying real guest traffic, with the inner IP headers visible inside the
outer Geneve header.

### 4.4 Re-run safety — **PASS**

`all-in-one`, run three times in a row on a live cloud **with two guests
running**:

| run | exit | "already/unchanged/untouched" | real skips | units restarted | guests |
|---|---|---|---|---|---|
| 2 | 0 | 91 | 0 | 3 | both still `ACTIVE` |
| 3 | 0 | **94** | 0 | **0** | both still `ACTIVE` |

Run 2 restarted three units honestly: `neutron.conf` and `nova.conf` had been
hand-edited just before it (removing the diagnostic `debug = true`), so
`service_apply` correctly saw configuration newer than the running processes.
Run 3, with nothing changed at all, restarted **nothing** — which is the claim
the shell makes.

`compute-add`, run twice on node2: exit 0, 8 "already/unchanged" lines, **0**
units restarted, and the `[database]` comment-out left exactly as it was.

No initial resource was recreated: the flavor, image, both networks, the router,
the keypair and the security-group rules were the same objects afterwards, and
both guests kept running throughout.

### 4.5 Still not verified

* **Any physical-LAN path.** `br-ex` has no NIC attached on GCE, so
  `hagistack-provider` and its floating IPs were never routed off the host.
  Tenant networking, metadata and east-west traffic are proven; north-south to a
  real LAN is not.
* **Live migration, volumes (Cinder), more than two nodes.** Not attempted.

---

## 5. Changes to the shell

| Change | Why |
|---|---|
| `apache_allow_proc_subset()` + `apache_sees_meminfo()` | §2. Writes the `ProcSubset=all` drop-in, forces a full restart when it changes, and **measures** that the workers can read `/proc/meminfo` |
| `ini_comment_out()` | §3. Stops a key taking effect without deleting it — the one case where "never delete" is the wrong rule |
| `phase_compute_nova` | comments out `[database]`/`[api_database] connection` and proves from the journal that no SQL connection is attempted |
| `HAGISTACK_STAGE`, `VERIFIED_ON_HARDWARE`, `UNVERIFIED_ITEMS` | now say guest boot and cross-node traffic passed, and name what is still unproven |

---

## 6. Cleanup

```
gcloud compute instances delete hagistack-node1 --zone=asia-northeast1-a --delete-disks=all
gcloud compute instances delete hagistack-node2 --zone=asia-northeast1-a --delete-disks=all
```

Verified afterwards by listing, not by assumption:

* instances: **no `hagistack-*`** (only the pre-existing Sinter VMs)
* disks: **no `hagistack-*`**
* addresses: only `sinter-p8-gateway-ip`, which was already there
* firewall rules: the **same six**, byte for byte, as at the start
* snapshots: only the pre-existing scheduled ones

**Nothing from this work is still being billed.**

**One observation, not an action of ours.** `mikagami-validation` and `rocky98`
were `TERMINATED` when this session began and are `RUNNING` now. The only
instances this session created or deleted were `hagistack-node1` and
`hagistack-node2`. Something else operates those VMs; they were left alone.
