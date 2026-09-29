# Step 4 — Neutron + OVN on Ubuntu 26.04: what was measured, and what it proves

Base: branch `docs/openstack-renewal-research`, on top of `d0b9923` (step 3).

This document separates three different things, because conflating them is how
a networking layer ends up "verified" without a packet ever moving:

1. **Packaging facts** — measured in throwaway `ubuntu:26.04` containers before
   a line of the phase was written. No unit name, config path or start order in
   the shell was guessed.
2. **What the container run proves** — the API, the configuration, the schema,
   the identity registration, the OVN northbound/southbound control plane, and
   re-run behaviour.
3. **What it cannot prove** — Geneve between nodes, any path onto a physical
   LAN, systemd ordering, and instance boot. These are UNVERIFIED with reasons.

---

## 1. Packaging facts (measured, not assumed)

### 1.1 Packages taken from the Ubuntu 26.04 archive

| Package | Version measured | Role |
|---|---|---|
| `openvswitch-switch` | *(see §4 run log)* | `ovsdb-server` + `ovs-vswitchd` |
| `ovn-central` | *(see §4 run log)* | northbound/southbound DBs + `ovn-northd` |
| `ovn-host` | *(see §4 run log)* | `ovn-controller` on every hypervisor |
| `neutron-server` | `2:28.0.2-0ubuntu1` | the server code; **ships no systemd unit** |
| `neutron-plugin-ml2` | `2:28.0.2-0ubuntu1` | ML2 plugin config |
| `neutron-ovn-metadata-agent` | `2:28.0.2-0ubuntu1` | metadata for instances on OVN |
| `neutron-api` | pulled in by `neutron-server` | the Apache vhost that actually serves :9696 |

`neutron-ovn-agent` **is** obtainable (`Candidate: 2:28.0.2-0ubuntu1`, measured
with `apt-cache policy` in a clean container, and re-measured inside the
verified run as `N5f`). It is deliberately **not** installed: it is the newer
agent for OVN-managed hypervisor-side extensions, and for this single-controller
step the OVN metadata agent plus `ovn-controller` cover what is needed. The
availability is recorded so the choice stays a choice rather than an assumption.

### 1.2 The three different startup models, all in one deployment

Step 2 and 3 already met two of them. OVN adds a third:

| Service | How it starts | Consequence for the shell |
|---|---|---|
| Keystone, Placement, **Neutron API** | **no unit at all** — an Apache vhost with its own `Listen` | drive `apache2` + `a2ensite`, never invent a unit |
| Glance | its own `glance-api.service` | ordinary `systemctl start` |
| **OVN** | `ovn-central` / `ovn-host` are `Type=oneshot`, `ExecStart=/bin/true` **wrappers** | liveness must be checked on the *real* units, never on the wrapper |

Measured unit contents (`/usr/lib/systemd/system`, verbatim fields):

```
[ovn-ovsdb-server-sb]  Type=simple   ExecStart=/usr/share/ovn/scripts/ovn-ctl run_sb_ovsdb $OVN_CTL_OPTS
[ovn-northd]           Type=forking  ExecStart=/usr/share/ovn/scripts/ovn-ctl start_northd --ovn-manage-ovsdb=no --no-monitor
                       After=network.target ovn-nb-ovsdb.service ovn-sb-ovsdb.service
[ovn-controller]       Type=forking  ExecStart=/usr/share/ovn/scripts/ovn-ctl start_controller --ovn-manage-ovsdb=no --no-monitor
                       After=network.target openvswitch-switch.service
[ovn-central]          Type=oneshot  ExecStart=/bin/true   Wants=ovn-northd, ovn-ovsdb-server-sb, ovn-ovsdb-server-nb
[ovn-host]             Type=oneshot  ExecStart=/bin/true   Wants=ovn-controller
[openvswitch-switch]   Type=oneshot  ExecStart=/bin/true   Requires=ovsdb-server.service ovs-vswitchd.service
```

Two things worth recording:

* `ovn-northd` declares `After=ovn-nb-ovsdb.service ovn-sb-ovsdb.service` —
  **units by those names do not exist** in this packaging (they are
  `ovn-ovsdb-server-nb/-sb`). So the declared ordering is inert, and ordering in
  practice comes from the `ovn-central` wrapper's `Wants=` plus northd retrying.
  The shell therefore starts the DBs first, explicitly, rather than trusting the
  unit graph. Whether that is enough under a real systemd is exactly what the
  GCE acceptance item `B0a` is for.
* `--ovn-manage-ovsdb=no` in both `ovn-northd` and `ovn-controller` means those
  units will not start the databases themselves. The `ovn-ctl` entry points the
  units call are the same ones the container run uses by hand, so the container
  exercises the packaged code path rather than a hand-rolled substitute.

Start order the shell uses: `openvswitch-switch` → `ovn-ovsdb-server-nb` →
`ovn-ovsdb-server-sb` → `ovn-northd` → `ovn-controller`, then Neutron.

### 1.3 Neutron API serving

* `/etc/apache2/sites-available/neutron-api.conf` ships with its own
  `Listen 9696` and `WSGIScriptAlias / /usr/share/neutron/neutron-api.wsgi`,
  and is **enabled on install**. `neutron-server` itself installs no unit.
* Separate units, all real: `neutron-rpc-server.service` (`User=neutron`),
  `neutron-periodic-workers.service`, `neutron-ovn-metadata-agent.service`
  (`User=root`, it manipulates network namespaces).
* `neutron.conf` and `plugins/ml2/ml2_conf.ini` come from `neutron-common`,
  mode `0640 root:neutron`; the shell preserves that ownership.
* `neutron/server/__init__.py` was read: with no `OS_NEUTRON_CONFIG_FILES` set
  the WSGI app defaults to loading **both** `neutron.conf` and
  `plugins/ml2/ml2_conf.ini`. The API and the RPC server therefore cannot
  disagree about the mechanism driver, and there is no
  `/etc/neutron/plugin.ini` symlink convention in this packaging.
* Schema: `neutron-db-manage --config-file … --config-file … upgrade head`.

### 1.4 State the packages do **not** create until first start

`/etc/ovn`, `/var/lib/ovn`, `/var/log/ovn` and `/var/run/ovn` do not exist after
installation, and the northbound/southbound DBs listen on **unix sockets only**
until `set-connection` is issued. So a TCP listener is something the shell must
ask for, not something it can assume.

---

## 2. What the shell does, and the three networks kept apart

The one thing a single-LAN lab and a split mgmt/provider deployment must not
share is a single "the IP" variable. Three concerns, three settings:

| Concern | Where it lives | Value in the verified run |
|---|---|---|
| management / API plane | `MGMT_IP` — DB, RabbitMQ, authtoken, endpoints | the node's management address |
| Geneve tunnel endpoint | `external_ids:ovn-encap-ip` (+ `ovn-encap-type=geneve`) | the same address **by default**, but a separate setting |
| provider physical network | `external_ids:ovn-bridge-mappings` = `PROVIDER_PHYSNET:PROVIDER_BRIDGE`, plus `ml2_type_flat`/`ml2_type_vlan` | `physnet1:br-ex` |

`--provider-physnet` and `--provider-bridge` are new options with the full
precedence chain (command line > environment > `hagistack.env` > default) and
the same validation as the other labels.

Both `flat` **and** `vlan` are enabled on the provider physnet, and tenant
networks are `geneve`. That is what makes several LANs possible later without
re-plumbing: more provider LANs arrive as VLAN segments on the same bridge, and
tenant networks need no VLANs at all.

### 2.1 The deliberate omission: the provider bridge is empty

`phase_ovn` creates `br-ex` with `ovs-vsctl --may-exist add-br` and **attaches
no port and assigns no address**. Enslaving a NIC to the bridge and moving the
management IP onto it is disruptive — done wrong over SSH it takes the host off
the network — so this step does not do it, on any path. The run says so in
`log_warn`, `hagistack status` says so, and the test asserts it: `N4h` (no port
on the bridge), `N4i` (no address on the bridge), `N4j` (the management
interface still holds exactly the addresses it had before the run).

Until that step exists, **provider networks exist in Neutron but have no path to
a physical LAN.**

---

## 3. Re-run safety

Everything in this phase is written key-by-key or guarded by a read-back:

* `ini_set` rewrites a file only when a value actually changes.
* `ovn-nbctl/sbctl set-connection` is issued only when `get-connection` differs.
* `external_ids` are compared before being set.
* `ovs-vsctl --may-exist add-br`; an existing bridge is never recreated, and its
  ports are never touched.
* `neutron-db-manage upgrade head` is idempotent by design; the table count
  before and after is reported.
* Keystone objects use `show || create` (`ks_ensure_*`) — no service user,
  service or endpoint is ever deleted and recreated.
* No `DROP DATABASE`, no deletion of keys or state, anywhere.

---

## 4. The container's own limit, diagnosed rather than tuned around

Two full container runs both aborted part-way through Keystone object
registration with `Internal Server Error (HTTP 500)`, and the shell did what it
is supposed to do with that: it stopped, said which line failed, and said
nothing had been rolled back.

The cause was measured, not guessed. At the moment of the abort:

```
sqlalchemy.exc.TimeoutError: QueuePool limit of size 5 overflow 50 reached,
                             connection timed out, timeout 30.00
```
```
Max_used_connections   56
Threads_connected      56
@@max_connections      1024          <- the server was nowhere near its limit
overlay  18771M total  18342M used   414M available   98% /
```

So this was **not** the step-3 failure (`max_connections` left at the stock
151) returning: the server had 1024 and only 56 connections existed. The
ceiling that was hit is Keystone's **client-side** SQLAlchemy pool — 5 plus 50
overflow — inside one WSGI process, with requests issued serially by the shell.
Fifty-five connections held open against a serial caller means each request was
stalling long enough to keep its connection checked out, in a container that was
**98% full with 414 MB left** while MariaDB, RabbitMQ, memcached, three WSGI
applications, `ovsdb-server`, `ovs-vswitchd`, the two OVN databases and
`ovn-northd` all ran on the same starved filesystem.

Two things follow, and they are deliberately kept apart:

* **Not a hagistack configuration defect.** The shell writes no pool settings at
  all; those numbers are Keystone's own defaults, and the same configuration
  authenticated successfully in the step 2 and step 3 containers, which started
  with several GB free rather than 1.5 GB. Nothing in `neutron.conf`,
  `ml2_conf.ini`, the metadata configuration or the OVN setup is implicated by
  this traceback.
* **A container resource limit.** It is therefore recorded as an environment
  constraint, and the checks that depend on a healthy Keystone are left
  **UNVERIFIED and sent to the GCE acceptance**, rather than re-tuning WSGI
  process counts and pool sizes until the suite turns green. A green suite
  bought that way would prove nothing about a real host.

## 5. What the container runs did prove

Environment: `ubuntu:26.04` (Ubuntu 26.04.1 LTS, amd64) under containerd/nerdctl
in a lima VM, **no systemd**, `--privileged` with `/lib/modules` mounted so the
Open vSwitch datapath module could be loaded. Every backing service was started
by hand and the method recorded:

| Service | How it was started here |
|---|---|
| MariaDB | `mariadbd-safe --bind-address=127.0.0.1 --max-connections=1024` |
| memcached | `memcached -u memcache -l <MGMT> -d` |
| RabbitMQ | `rabbitmq-server -detached` as user `rabbitmq` — **it started this time**, unlike step 1 |
| Apache (identity/placement/networking vhosts) | `apachectl -k start` |
| OVS DB | `/usr/share/openvswitch/scripts/ovs-ctl start --system-id=random --no-ovs-vswitchd --no-monitor` |
| `ovs-vswitchd` | `ovs-ctl start --system-id=random --no-monitor` |
| OVN NB/SB + northd | `/usr/share/ovn/scripts/ovn-ctl start_ovsdb` then `start_northd --ovn-manage-ovsdb=no --no-monitor` — the same entry points the packaged units call |

### 5.1 Verified: static checks, inputs, honesty of the output

* `bash -n` clean; **ShellCheck `-S warning` clean** on the whole shell. ShellCheck
  found one real defect while step 4 was being written (`SC2178`: `phase_ovn`
  shadowed the preflight `missing` array with a string); it was fixed.
* `--version` reports `hagistack 0.4.0-step4`.
* `status` names the networking layer and OVN, says the provider bridge has no
  NIC and no address, and still names what is missing; `--help` still refuses the
  phrase "working OpenStack"; and a scan of the whole shell confirms every
  mention of a "usable" cloud is a negation.
* The two new options are validated, and a rejected value never executes:
  `--provider-physnet 'physnet1;touch /tmp/N1'`, `'phys net1'`,
  `--provider-bridge 'br/ex'`, an over-long name, `'..'`, and a missing value are
  all refused, and the marker file the injection would have created does not
  exist. Command line, environment and defaults all resolve correctly for both
  options.

### 5.2 Verified: honest skipping when the services are not there

With no database and no OVS, `all-in-one` exits **4**, reports
`phase 'ovn' SKIPPED` and `phase 'neutron' SKIPPED`, writes **no** state marker
for either, never prints `COMPLETE`, and leaves no half-written networking
configuration behind.

### 5.3 Verified: the packaging assumptions the code depends on

Checked inside the run, not from documentation: every unit the shell starts
exists on disk (dumped to `n4-units.txt`); `ovn-central` and `ovn-host` really
are `Type=oneshot ExecStart=/bin/true` wrappers; `neutron-server` really ships no
unit while the `neutron-api` vhost really carries `Listen 9696` and is enabled;
and `neutron-ovn-agent` really is obtainable (`2:28.0.2-0ubuntu1`) although this
design does not use it.

### 5.4 Verified: the OVS/OVN control plane, and only the control plane

Measured in the **first** full container run, which reached both phases before it
later aborted during Glance/Placement registration (§4) — the shell's own output:

```
ok   Open vSwitch database reachable
ok   OVN northbound and southbound databases reachable
ok   OVN northbound listener set to ptcp:6641:127.0.0.1
ok   OVN southbound listener set to ptcp:6642:10.4.0.75 (reachable by future compute nodes)
ok   provider bridge br-ex created
     ports on br-ex: <none, by design>
ok   local chassis configured (ovn-remote, geneve encap on 10.4.0.75, physnet1:br-ex)
ok   chassis registered in the OVN southbound DB: 37078056-48b4-4734-bc45-33d0a6168dae
ok   networking schema created (135 tables)
```

Corroborated independently of the shell's own reporting, in the same run:

```
$ ss -ltnp | grep -E '6641|6642|9696'
LISTEN 10.4.0.75:6642   users:(("ovsdb-server",pid=12260))
LISTEN 127.0.0.1:6641   users:(("ovsdb-server",pid=12232))
LISTEN         *:9696   users:(("apache2",...))
$ ovn-sbctl show
Chassis "37078056-48b4-4734-bc45-33d0a6168dae"
    hostname: "3b274ee293c7"
    Encap geneve
        ip: "10.4.0.75"
        options: {csum="true"}
```

So, proven in a container: the OVN databases run and listen exactly where the
design says (northbound on loopback only, southbound on the management address),
`ovn-northd` runs, `ovs-vswitchd` runs, the local chassis registers itself with a
**Geneve** encapsulation pointing at the management address, the provider bridge
exists with **no port**, the management interface keeps exactly the addresses it
had, and the Neutron schema is created (135 tables).

**What this is not:** a chassis registering itself is not a tunnel between two
chassis, and a bridge mapping is not a physical LAN. Neither of those is claimed.

### 5.5 Verified directly in the running container, independently of the suite

Read out of the live container after the OVN phase completed (second run), so
this does not depend on the test harness agreeing with itself:

```
$ ovs-vsctl get open_vswitch . external_ids
{hostname="5373ed118907", ovn-bridge-mappings="physnet1:br-ex",
 ovn-cms-options=enable-chassis-as-gw, ovn-encap-ip="10.4.0.76",
 ovn-encap-type=geneve, ovn-remote="tcp:10.4.0.76:6642",
 rundir="/var/run/openvswitch", system-id="78bc4add-…"}

$ ovn-nbctl --bare --columns=target list connection   ->  ptcp:6641:127.0.0.1
$ ovn-sbctl --bare --columns=target list connection   ->  ptcp:6642:10.4.0.76
$ ovs-vsctl list-ports br-ex                         ->  (empty)
$ ip -4 -o addr show br-ex                           ->  (empty)
$ ls /var/lib/hagistack/state/
base_packages.done  database.done  ovn.done  rabbitmq.done
```

The state markers are the honest part: `ovn.done` is there because the OVN phase
really finished; there is **no** `keystone.done`, `glance.done`,
`placement.done` or `neutron.done`, because those phases did not, and the shell
refused to mark them.

Secret hygiene, checked in the same container against all 13 generated secrets:

```
secret value found anywhere under /out (all run logs and artefacts) : none
secret value found in any process argument list                     : none
/etc/hagistack/secrets.env mode                                     : 600
```

## 6. UNVERIFIED — sent to the GCE acceptance, not called passed

| Item | Why it is not verified here | Where it goes |
|---|---|---|
| Authenticated Neutron API (`GET /v2.0/networks`, `openstack network list`) | blocked by the container's Keystone HTTP 500 (§4), which is a resource limit of this container | GCE node1 |
| Networking service/endpoint registration in Keystone | same abort — the run stopped inside identity registration | GCE node1 |
| Creating a network and a subnet, and the resulting OVN logical switch | depends on the two above; with no networking in the catalogue the client falls back to the compute network commands, so it was not attempted rather than reported as a failure | GCE node1 |
| Neutron configuration content and its stability across re-runs | the files are written only after the Keystone gate, which the container never got past on the second run | GCE node1 |
| Startup and ordering of `ovn-ovsdb-server-nb/-sb`, `ovn-northd`, `ovn-controller`, `neutron-rpc-server`, `neutron-periodic-workers`, `neutron-ovn-metadata-agent` **under systemd** | there is no systemd in a container; the unit files were read and dumped, but nothing started them as managed services | GCE B0a/B0b |
| Geneve tunnelling between two chassis | one chassis cannot prove a tunnel | GCE node1+node2 (compute-add) |
| Provider network on a physical L2 LAN, and a real floating IP | not reproducible in a container or on a GCE VPC | class C — physical LAN only |
| Instance boot, port binding to a chassis | Nova and Horizon are not implemented yet | after step 5/6 |
| Enslaving a NIC to `br-ex`, moving the management IP | deliberately **not performed** in this step, on any path | a later, explicitly disruptive step |

## 7. Step 1–3 regression scope for this change

Step 4 changed shared surface — the version string, the stage banner, the
`status` output, the usage text and one helper (`phase_ovn` no longer shadows the
preflight `missing` array). The regression run for this change is therefore
scoped to **static checks and configuration generation**, not to re-running the
integration suites:

* `bash -n` and ShellCheck on the whole shell (inside the step 4 suite).
* The step 1 audit suite: option precedence, config-file parsing, secret
  handling, incomplete-run reporting and exit codes, and the
  configuration-generation idempotence checks.
* The step 1 verify suite: surface, subcommand resolution, validation matrix,
  destructive-pattern scans with their positive controls.

The step 1 database suite and the step 2/3 integration suites are **not** re-run
for this change: their evidence stands in `STEP1_CONTAINER_VERIFICATION.md`,
`STEP1_AUDIT_FIXES.md`, `STEP2_KEYSTONE_EVIDENCE.md` and
`STEP3_GLANCE_PLACEMENT_EVIDENCE.md`, and the container that would host them is
the same starved one described in §4. One brittle assertion in the step 3 suite
was corrected as part of this change: it pinned the literal sentence
`Neutron/OVN, Nova and Horizon are NOT installed`, which step 4 legitimately
shortens. It now asserts the property instead — that `status` still names a
missing service and still says no instance can be booted.

## 8. How the suite classifies a blocked check (added after the runs above)

The first run produced a table with ~50 FAILs that all meant one thing: a
backing service had died, so the phase never wrote anything, so every assertion
about what it should have written failed. That is misleading, and the fix is in
the test, not in the product:

* After the first real run the suite now decides **once** whether the neutron
  phase actually configured anything (`N4a2`), and if not, it records the reason
  the shell gave and names the backing service that went away.
* The configuration-content (`N6*`), schema (`N7*`), API (`N8*`) and
  configuration-retention (`N9a-c,e,n-p`) checks then record **UNVERIFIED with
  that reason** instead of FAIL. A missing file is never "unchanged" and never
  "wrong" — it is not measured.
* `N4a0` reports whether the run reached a terminal state at all, and how many
  attempts it took; `N4a1` asserts the MariaDB `max_connections` that step 3
  needed. Those two exist so that the *next* environment failure is legible
  immediately instead of after fifty red lines.

This matters for the GCE acceptance as much as for the container: on a real host
the same distinction is what separates "hagistack wrote the wrong thing" from
"the service was not up".

## 9. The collected result table

The second container run was **stopped deliberately** during the re-run section,
after 32 minutes of its own 5400-second limit, once it was clear that the
remaining work was retry loops against a Keystone that keeps dying in this
container. What it had recorded by then:

```
PASS 63    FAIL 30    UNVERIFIED 6      (n4-results-partial.tsv)
```

Where those 30 FAILs are, and what they mean:

| Block | Count | What the check wanted | Why it failed |
|---|---|---|---|
| `N6*` | 22 | the content of `neutron.conf`, `ml2_conf.ini`, the metadata agent ini | **nothing was written**: the neutron phase stopped at its Keystone gate, so there was no configuration to inspect |
| `N7*` | 3 | the 135-table networking schema and its alembic head | the schema step is after that same gate |
| `N8*` | 5 | catalogue entry, endpoints, authenticated API, unauthenticated refusal | Keystone was returning HTTP 500 (§4), and networking was never registered |

**Every one of the 30 is inside the blocked set. There is no FAIL outside it** —
nothing failed in the static checks, the input validation, the skip-honesty
checks, the packaging assertions, or the OVS/OVN control plane. Those FAIL lines
are what the pre-classification suite produced; the rule described in §8 now
records them as UNVERIFIED-with-reason, which is what they are.

Run-by-run, from the shell's own output:

| Run | Outcome | What it did |
|---|---|---|
| run 0 | exit 4, 1 attempt | created the databases, installed every package, bootstrapped Keystone; skipped the service-dependent phases (no systemd, Apache not yet started by hand) |
| run 1 | exit 4, **2 attempts** | attempt 1 aborted on the Keystone `QueuePool` error; attempt 2 resumed and **completed the OVN phase** (`ovn.done`), then skipped Keystone/Glance/Placement/Neutron because Apache and memcached had died in the meantime |

That run 1 attempt 2 resumed and finished the OVN phase after attempt 1 aborted
is itself the re-run-safety property being exercised: nothing was rolled back,
nothing was duplicated, and the phase that had not been marked done completed on
the next attempt.

## 10. Step 1–3 regression for this change (narrowed, as agreed)

Re-run on the step 4 build, in a fresh Ubuntu 26.04 container:

| Suite | Result | Guest exit |
|---|---|---|
| step 1 audit (option precedence, config-file parsing, secret handling, `gen_secret`, incomplete-run reporting, config-generation idempotence) | **PASS 39 / FAIL 0 / UNVERIFIED 1** | 0 |
| step 1 verify (surface, subcommand resolution, validation matrix, destructive-pattern scans) | **PASS 63 / FAIL 0 / UNVERIFIED 8** | 0 |

**No FAIL in either suite.** Three checks are UNVERIFIED here that were green in
the step 3 session, and all three are tooling this leaner container did not have
rather than behaviour that changed:

| Check | Why UNVERIFIED now |
|---|---|
| `5.4-openssl-path` | `openssl` not installed in this container |
| `A2-shellcheck` | `shellcheck` not installed in this container — but ShellCheck ran clean on the same build inside the step 4 suite (`N0b`), which is the stronger form of the same check |
| `F2b-scan-positive-control` | the 2013 legacy sample was not mounted, so the positive control for the destructive-pattern scan could not be armed |

The step 1 database suite and the step 2/3 integration suites were **not** re-run
for this change, by agreement: this change touches the version string, the stage
banner, `status`, the usage text and one helper rename, and the integration
evidence for those steps stands in their own documents.
