# Hagistack's own RPM packaging — stage 6 real-machine acceptance plan (stage 6-0, 2026-11-12)

Plan only. Prepared under the Owner's instruction "Hagistack：段階6-0 実機受入準備・4構成試験計画の確定".
No GCE resource was read, created, started, stopped or deleted. Nothing was rebuilt,
pushed or released. Stage 6-1 (the GCE run) starts only after the Owner approves
section 9.

**Revision R1 (2026-11-12).** The Owner decided D1–D4 as recommended, plus:
- **D5:** all five boot disks are `pd-standard`, with the sizes unchanged.
- **D6:** effective IAM is unverified. The 2026-11-11 run created and deleted the same
  kinds of resource with the same account and project. A permission error stops the
  run at once, and IAM is never changed.

The GCE lifecycle is driven by `acceptance/stage6/hs6.py` (section 5.1). A read-only
preflight on 2026-11-12 gave the observations in section 5.

## 1. What is under test

| Item | Value | Checked |
|---|---|---|
| Branch / HEAD | `feat/rocky-own-packaging` / `178820ad05b31bad440f3e98f0089fbc8d97476d` | real files |
| Installer under test | `rocky10.2/hagistack` at that HEAD (exported with `git archive`, no local change) | real files |
| RPM set | 195 RPMs, 69 SRPMs; identity `6c43da51144ca01c413f5c7dbbc44be70b66f03df69e77b3e632c2d55b8a1313` | real files (section 3) |
| Build input id | `384eee75bb32ce5e…` | recomputed from the tree |
| Stage 5 record | `acceptance/ROCKY_OWN_PACKAGING_FINAL_BUILD3_2026-11-11.md` (commits `1f34a99`, `178820a`) | real files |

The RPM set is used as it is. It is not rebuilt or changed. If it cannot be delivered
to a node as it is, the configuration is BLOCKED; a rebuild is never the fallback.

## 2. The four configurations (existing definitions)

The configurations are those of `docs/ROCKY_INSTALLER_DESIGN.md` §2 and §7, as run on
2026-11-09 for rc-level acceptance (`acceptance/ROCKY_INSTALLER_COMPLETION_ACCEPTANCE_2026-11-09.md`):

| Id | Name (design §2) | Command |
|---|---|---|
| A | all-in-one | `hagistack all-in-one` |
| B | controller-only | `hagistack controller` |
| C | controller → local hypervisor | `hagistack compute-add --local` on a B host |
| D | remote compute | `hagistack compute-add --controller-ip IP` on a new host |

Design §7: "A configuration is PASS only when it was itself run; all-in-one success
does not imply the others." Each of A–D gets its own PASS / FAIL / BLOCKED.
Design §7 also lists "two remote compute nodes"; that is decision D1 (section 9).

## 3. The RPM set on the external SSD (checked 2026-11-12, read-only)

Location: `<TMP_WORKSPACE>/hagistack-ownpkg-2026-11-11/run-final3/artifacts-384eee75bb32ce5e/out/` (167 MB).

| Check | Result |
|---|---|
| `repo/*.rpm` | 195 |
| `srpms/*.src.rpm` | 69 |
| `sha256sum -c RPM-SHA256SUMS` (in `repo/`) | 195 OK, 0 failures |
| SHA-256 of `RPM-SHA256SUMS` (set identity) | `6c43da51…1313`, equal to the stage 5 record |
| `repo/repodata/` | `repomd.xml`, primary, filelists, other |
| `build-env.lock` | present, 754 lines |
| `logs/build.ok` | `packages=69 rpms=195 srpms=69` |

rc4 (needed only for N3 and N8):
`<TMP_WORKSPACE>/hagistack-rc4-2026-11-10/release-candidate/rc4/`. The asset's SHA-256
is `25d03d26…0870`, equal to the asset pinned by `rpm-release.lock.candidate`; that lock
names set `a7c372bd…bf72`, 195 RPMs. Its `MANIFEST_SHA256` equals the
`gazpacho.manifest` at HEAD, so the HEAD installer accepts that lock.

## 4. How the set reaches the nodes (no rebuild)

| Node use | RPM source | Trust anchor |
|---|---|---|
| B, then C (n1) | `--rpm-source bundle --rpm-bundle <tar> --rpm-set-sha256 6c43da…` | the identity in this plan (from the stage 5 record), checked by hagistack |
| A (n2) | `--rpm-source github --rpm-lock-file <lock>` against a mock release server on n1 | the lock written by `make-rpm-release.sh` from the same set; its `RPM_SET_SHA256` must equal `6c43da…` before use |
| D (n3) | `--rpm-source bundle --rpm-bundle <tar>` made by `hagistack rpm-bundle` on n1 | the controller's identity in `compute-secrets` |
| D2 (n4, if D1 = yes) | `--rpm-source github` against the mock server | as for A |

- The bundle for n1 is a tar of `RPM-SHA256SUMS` and `repo/` from the directory in
  section 3, in the layout `rpm_unpack_tar` accepts. hagistack throws away its repodata
  and regenerates it.
- A uses the GitHub path because a fresh github all-in-one was "not verified" on
  2026-11-09, and because `make-rpm-release.sh` has not yet been run on the own set.
  Running it only writes files on n1; nothing is published (decision D2).
- Mock server locks:
  - for the own set, `make-rpm-release.sh --base-url http://<n1>:<port>` writes the lock
    with the mock URL;
  - for rc4 (u1), a copy of `rpm-release.lock.candidate` with only `BASE_URL` changed
    to the mock. Every pinned value (asset SHA-256 and size, set identity, manifest)
    stays as committed in the candidate.
- `--rpm-source build` is not used anywhere: it would rebuild.
- Transfers: the IAP copy stalled at about 60 MB in stage 5. Files go up in 16 MB parts,
  and the SHA-256 is compared before and after each transfer.

## 5. Nodes and cost

GCE, one zone, a VPC created for this run only (IAP SSH, internal traffic, Cloud NAT,
no external IPs). Stock Rocky Linux 10.2 x86_64 image. Nested virtualisation is
required, so **N2 machine types only** (E2 has no nested virtualisation).

| Node | Machine, disk | Use | Est. hours |
|---|---|---|---|
| n1 | n2-standard-8, pd-standard 100 GB | B, then C; mock release server; `make-rpm-release.sh` | 4 |
| n2 | n2-standard-4, pd-standard 60 GB | A; N4, N6, N7 checks | 3 |
| n3 | n2-standard-4, pd-standard 50 GB | D | 3 |
| n4 | n2-standard-4, pd-standard 50 GB | second remote compute (D1) | 2.5 |
| u1 | n2-standard-4, pd-standard 60 GB | N3 and N8: rc4 all-in-one, then replacement (D3); created only after n4 is deleted | 3 |

Total 320 GB. At most 20 vCPUs run at once: u1 replaces n4.

**Read-only preflight, 2026-11-12.** These values were observed once, may change, and
are checked again by `hs6.py init` immediately before the run.

| Item | Observed |
|---|---|
| Project / zone | ACTIVE / UP; Compute Engine and IAP APIs enabled; cloudresourcemanager API disabled (so IAM cannot be read) |
| Existing resources | 13 Sinter VMs (all TERMINATED) and their disks; networks `default`, `mkg-proto-vpc`, `sinter-v180-relv-net`; one Sinter router with NAT; one reserved Sinter address. No `hagistack-*` resource. All of these are protected. |
| Region quotas free | N2_CPUS 200, CPUS 100, DISKS_TOTAL_GB 4096, SSD_TOTAL_GB **170** (the reason for D5), INSTANCES 11, IN_USE_ADDRESSES 8 |
| Project quotas free | CPUS_ALL_REGIONS 32, NETWORKS 2, ROUTERS 9, FIREWALLS 91 |
| Machine types | n2-standard-8 and n2-standard-4 available in the zone |
| Image | `rocky-linux-10-v20261110` (id `4057710101549472031`, `rocky-linux-cloud`, READY, X86_64). Its description says only "10", so `VERSION_ID=10.2` is checked on each node at boot. |

**Cost (Tokyo list prices, read from Google's pricing pages on 2026-11-12):**
- n2-standard-8 US$0.498352/h, n2-standard-4 US$0.249176/h;
- pd-standard US$0.000071233 per GiB-hour;
- Cloud NAT US$0.0014 per VM-hour, US$0.045 per GiB processed, US$0.005 per NAT
  IP-hour;
- internet egress for Tokyo was **not verified**. The harness assumes US$0.20/GiB for
  2 GiB.

| Case | Estimate |
|---|---|
| Planned hours (15.5 node-hours) | **US$6.06** projected by `hs6.py plan`, including the egress assumption, NAT data and the NAT IP |
| All five nodes for the full 6 hours | about **US$10.3**, above the cap. This is why the guards below exist and u1 waits for n4. |

The planned US$6.06 leaves about US$1 before the US$7 threshold that blocks new
resources. If n1–n4 run well over their planned hours, u1 (N3 and N8) can be blocked
by the guard. That ends N3/N8 as BLOCKED and does not raise the limit.

- Proposed caps: **US$8 and 6 hours of wall time** from the first creation.
- The figures are estimates, not billing. GCE does not cap the bill.
- Labels on nodes: `purpose=hagistack-verify`, `temporary=true`, `run-id=<rid>`,
  `hs-node=<node>`. Labels are never the reason to delete anything.

### 5.1 The harness (`acceptance/stage6/hs6.py`)

- **Dry-run by default.** Execution needs all of the following:
  - an Owner approval file bound to the run id, project, zone, account and the
    harness's own SHA-256, with the approved operations, a budget of US$8 or less,
    6 hours or less, and at most a 24-hour validity;
  - `HS6_EXECUTE=<rid>`;
  - the gcloud account matching the approval.
- **Names.** Only names `hagistack-s6-<rid>-*` that the harness generates can be
  changed, through exact create/delete command forms.
- **Run id.** A run id is never reused: a local registry and the empty-namespace check
  at `init` enforce this.
- **Identity.** Every gcloud call carries `--account=<approved account>`.
  Impersonation and `CLOUDSDK_*` identity overrides are refused. The test hooks
  (`HS6_GCLOUD`, `HS6_NOW`) are refused with any real account.
- **Nodes.** Each node is created with:
  - no external address, no service account and no scopes;
  - `block-project-ssh-keys=TRUE`, so `gcloud compute ssh` keeps its key on the
    instance and not in the project metadata that Sinter's VMs share;
  - a GCE-side `--max-run-duration`, with `--instance-termination-action=DELETE`, so
    a node is deleted by GCE even if the operator or agent is gone. The duration is
    the smaller of its planned hours × 1.5 and the time left before the run's limit.
- **Project ssh-keys.** They are recorded at `init` and checked before and after
  every ssh/upload.
- **Test steps.** Each step's full output and exit status are kept under the state
  directory (`remote/`). The lock is not held while a step runs, so a teardown is
  never blocked.
- **Outcomes of a creation.** The API can refuse a creation outright (a permission or
  quota error), or the outcome can be unclear (a timeout or any other error).
  - A refused creation is recorded as failed.
  - An unclear outcome is recorded as **unknown** and counted as running. Teardown
    reconciles it: it adopts and deletes a resource that appeared later, or records
    the creation as failed only after it has stayed absent for 15 minutes.
- **Ledger and deletion.** A hash-chained ledger records every creation before the
  call, and then its GCE id. A deletion requires the same id and creation time in GCE.
- **Stops.** Each of these stops the run:
  - a permission, quota, timeout or unknown-state error;
  - a broken ledger;
  - an unexpected resource in the run's namespace or a new external address;
  - a failed deletion.
- **Cost and time (R2).**
  - Projected US$7 blocks new resources.
  - Accrued US$8, the run's time limit, or a node 50 % over plan stops the run **and
    starts the teardown**. The stop and the teardown's outcome are recorded
    separately; an incomplete teardown names what is left.
  - A failed monitor stops new work without tearing down.
  - The guards are also checked while an ssh/upload step runs, which is killed at a
    limit, and by `hs6.py watch` in a second terminal.
  - An approval may lower these limits, never raise them.
  - Teardown is never refused by the guards, and remains possible after the approval
    expires.
- **When the harness is not running.** GCE deletes each node at its max run duration.
  The network and NAT stay until removed.
  - An unattended run is estimated at about US$8.54, so US$8 is not guaranteed then.
  - The estimate assumes all five nodes at their longest possible duration, list
    prices, the assumed egress (2 GiB) and NAT data (3 GiB per node), and 6 hours of
    NAT IP.
  - It is an estimate, not a bound. The NAT IP charge after that is not included.
  **Required operating conditions:**
  - keep `hs6.py watch` running for the whole run;
  - finish only when `hs6.py residual` reports nothing left;
  - check `residual` at once after any interruption.

  No extra billable monitor (VM, Cloud Scheduler, Cloud Functions) is added.
- **Cost display.** Status shows these apart: the planned projection, the harness's
  accrued estimate, the assumed or unpriced items, and the fact that the real bill is
  unknown to it.
- **Order.** The harness enforces the creation order: network, then n1 before n3 and
  n4, then u1 after n4 is gone.
- Details: `acceptance/stage6/README.md`. Tests: `acceptance/stage6/test_hs6.py`
  (mock gcloud, no Google API).

## 6. Procedure per configuration

### 6.0 Common to every node

1. **Before:**
   - `hs6.py init` records the project's existing resources (read-only) as the
     protected baseline, and checks quotas and the image;
   - confirm the image is Rocky Linux 10.2 x86_64;
   - confirm `/proc/cpuinfo` has `vmx`.
2. **Node:** `hs6.py create-node <node>` creates it with nested virtualisation and no
   external IP. Set a dummy
   provider interface (`hgext0`), as in earlier runs; it is never attached to `br-ex`.
3. **Inputs:** `hs6.py upload` sends the tree archive and the RPM inputs, and compares
   the SHA-256 on the node.
4. **Install:** as listed per configuration below. Keep each run's exit code and full log.
5. **Services:** `systemctl is-active` for every unit hagistack enables, and
   `hagistack status`.
6. **Functional checks:** listed per configuration.
7. **Evidence:** collected per configuration (6.6), before anything is deleted.
8. **Cleanup:** section 8.
9. **Verdict:** PASS only when every pass criterion of that configuration holds;
   FAIL when a criterion was tested and did not hold; BLOCKED when it could not be
   tested (for example, the RPM set could not be delivered, or the cloud failed).

Checks on every node, alongside the configuration criteria:

- every installed package with a name from the set has the header of the set's RPM
  (installed `SHA256HEADER` / `SIGMD5` equals `rpm -qp` of the set's file);
- `rpm -V` of those packages shows no difference;
- `novnc` and `openstack-nova-novncproxy` are not installed (N7);
- no Python traceback in the journal of the OpenStack units since the run started
  (a traceback is examined; it is not a FAIL by itself if it is a logged, handled error).

### 6.1 B — controller-only (n1)

1. Install: `hagistack controller --rpm-source bundle --rpm-bundle <tar> --rpm-set-sha256 6c43da…`
2. Pass criteria:
   - exit 0, every phase completed;
   - the recorded set identity is `6c43da…`;
   - `openstack-nova-compute`, `libvirt` and `qemu-kvm` are not installed;
   - conductor and scheduler are up;
   - an OVN gateway chassis is present;
   - there is no hypervisor, and a guest request ends in "No valid host was found";
   - `tests-horizon-login.sh` PASS;
   - a re-run exits 0 with 0 restarts and reuses the recorded set.
3. Then on n1, for A and D:
   - `make-rpm-release.sh` on the set directory, which writes the candidate files only;
   - the mock server (`python3 -m http.server` on n1's internal address);
   - `hagistack rpm-bundle`;
   - `hagistack compute-secrets`.

### 6.2 D — remote compute (n3, and n4 if D1)

Run while n1 is still controller-only.

1. Install:
   - n3: `hagistack compute-add --controller-ip <n1> --rpm-source bundle --rpm-bundle <n1 bundle>`;
   - n4: `--rpm-source github --rpm-lock-file <lock>`.
2. Pass criteria:
   - exit 0;
   - "this node's RPM set is the controller's";
   - nova-compute has no database in effect (hagistack's check, and an independent
     oslo.config query as the nova user);
   - the hypervisor is up and OVN agents are alive;
   - a guest boots ACTIVE on the node;
   - SSH to the guest works with the metadata-injected key, and the metadata
     instance-id is fetched on the first try;
   - a re-run exits 0 with 0 restarts.

### 6.3 C — controller → local hypervisor (n1)

1. Install: `hagistack compute-add --local`.
2. Pass criteria:
   - exit 0;
   - no controller phase runs, and the controller configuration files are not
     modified (mtimes earlier than the run);
   - the hypervisor is up and mapped, and the role becomes all-in-one;
   - 2 guests ACTIVE, SSH with the metadata key, guest→guest ping;
   - with D: guests on n1 and n3 (and n4) ping each other across nodes over Geneve;
   - a re-run exits 0 with 0 restarts.

### 6.4 A — all-in-one (n2)

1. Before the install: the lock from `make-rpm-release.sh` must name `RPM_SET_SHA256=6c43da…`
   and `RPM_COUNT=195`. If it does not, A is BLOCKED and the Owner decides (no fallback).
2. Install: `hagistack all-in-one --rpm-source github --rpm-lock-file <lock>` on a
   fresh node (nothing installed beforehand).
3. Pass criteria:
   - asset SHA-256 and size, set identity, repodata and `rpm -K` are checked by hagistack;
   - every phase completed;
   - 2 guests ACTIVE, SSH with the metadata key, metadata hostname, guest→guest ping;
   - `tests-horizon-login.sh` PASS;
   - a re-run exits 0 with 0 restarts.
4. Then the N4, N6 and N7 checks (section 7) on n2.

### 6.5 Stop conditions (every configuration)

Stop the affected configuration and collect evidence. Do not retry automatically.

- The RPM set fails hagistack's verification, or an identity differs from `6c43da…`
  (BLOCKED).
- An install exits non-zero.
  - Collect evidence and classify the cause (package, installer, cloud) first.
  - A re-run is allowed only when hagistack's own re-run contract applies, at most once,
    and only if it costs no new resource.
  - A second failure ends the configuration as FAIL.
- A package from the set is replaced by one from another repository.
- Any cap is reached: US$8, 6 hours, or a node running beyond its planned hours by more
  than 50 %.
- Unexpected billable resources appear, or a resource outside this run would be touched.
- Any new resource, larger machine or additional node needs the Owner's approval first.

### 6.6 Evidence

Kept under `<TMP_WORKSPACE>/hagistack-stage6-<date>/` on the external SSD, and screened
before anything is quoted.

Per node:

- install and re-run logs with exit codes;
- `hagistack status`;
- the deployment record (secrets removed);
- `rpm -qa`, the header-digest comparison and `rpm -V`;
- `systemctl show` of every OpenStack unit;
- the journal of the OpenStack units;
- guest check output;
- for D, the oslo.config query.

GCE:

- the state before the run;
- the create and delete logs;
- a final residual check.

The acceptance record goes into `acceptance/` with results only, because the raw logs
contain cloud-internal host names.

## 7. N3–N8

### N3 — scriptlet differences (15 packages)

- Packages: `openstack-dashboard`, `openstack-glance`, `openstack-keystone`,
  `openstack-neutron`, `-neutron-common`, `-neutron-macvtap-agent`,
  `-neutron-metering-agent`, `-neutron-openvswitch`, `-neutron-rpc-server`,
  `-neutron-sriov-nic-agent`, `openstack-nova-api`, `-nova-common`, `-nova-compute`,
  `-nova-migration` and `openstack-placement-common`.
  - Recomputed from the stage 5 audit's header dumps: 15 packages whose
    PREIN / POSTIN / PREUN / POSTUN / PRETRANS differ from rc4.
- Fresh installs: covered by A–D.
- Replacement from rc4 on u1:
  - `dnf reinstall` runs the **new** package's `%pre` and `%post` and the **old** (rc4)
    package's `%preun` and `%postun`;
  - so both sets of scriptlets act on a running all-in-one.
- Pass criteria on u1, comparing before and after:
  - users and groups (uid, gid, shell, membership): unchanged, or changed only as the
    new sysusers files state, with the difference recorded;
  - config files: local edits kept, a `.rpmnew` file where a default changed;
  - ownership and modes under `/etc/<service>`, `/var/lib/<service>` and `/var/log/<service>`
    are what `rpm -V` expects;
  - units: still enabled and active after the transaction;
  - the guest stays ACTIVE, and a new guest boots;
  - `tests-horizon-login.sh` PASS.

### N4 — unit differences (on n2; n3 for nova-compute)

- glance: `LimitNOFILE`, `LimitNPROC` and `PrivateTmp` removed.
  - Record the effective limits (`systemctl show`).
  - Upload and download 3 images.
  - The service works, and the effective limits are recorded.
- nova: `Type=notify` → `simple`, `Restart=always` → `on-failure`, and
  `LIBGUESTFS_ATTACH_METHOD` removed.
  - For conductor, scheduler and compute:
    - `systemctl restart` → active, and the service up again in `openstack compute service list`;
    - `kill -9` of MainPID → systemd restarts it within `RestartSec`;
    - `systemctl kill -s TERM` → the result is recorded.
  - With `on-failure`, a clean exit is not restarted, unlike rc4's `always`. That
    difference is recorded, and it is a FAIL only if a required behaviour (start,
    restart, recovery after a crash) does not hold.
  - A guest boots after the restarts.
- neutron: `--log-file` removed.
  - Find where each agent's log goes now (file or journal).
  - Pass: each agent's log is readable at a defined place.
- OVN metadata agent reads `neutron.conf`: covered by the metadata checks in A and D.
- RPC server reads `ml2_conf.ini`: the server starts and port binding works (covered by
  guest boot).
- Rule: a different unit file is not a FAIL. FAIL only when start, restart, recovery
  or the functional checks do not hold.

### N5 — migration

- Live migration is **not** a criterion, and is not attempted.
- Pass:
  - the installer does not install `openstack-nova-migration` (on every node);
  - its package metadata and wrapper allow only the commands of cold migration
    (static, from the set's RPM).
- An actual cold migration between n1 and n3 is optional (decision D4). The installer
  does not configure migration, so it needs manual setup. Without D4 it is recorded as
  "not tested", not as a pass.

### N6 — the 13 rebuild differences

- The 12 doc packages and the cinder man page.
- Check on every node whether any of the 13 packages is installed by the installer.
- Pass:
  - none of them is needed at run time;
  - the stage 5 differences are confined to `/usr/share/doc` and `/usr/share/man`
    (already recorded).
- The cause (environment-dependent Sphinx output) stays a presumption and is not
  stated as fact.

### N7 — weak dependencies

- Every installer run already uses `--setopt=install_weak_deps=False`
  (`rocky10.2/hagistack` line 2176). A–D therefore run under the installer's
  condition, unlike the stage 5 fresh-install test.
- Pass:
  - A–D pass;
  - `novnc` is not installed;
  - the list of installed packages is recorded and compared with the stage 5
    fresh-install list (weak dependencies on), and the difference is explained.

### N8 — same NEVR replacement (u1)

1. Install rc4 on u1: `hagistack all-in-one --rpm-source github --rpm-lock-file <rc4 lock>`.
   - Use the rc4 asset from section 3, through the mock server.
   - Boot a guest and make one local config edit.
2. hagistack does not switch the set of a deployed cloud:
   - `rpm_guard_consistency` stops with "Switching the package set of a running cloud
     is an upgrade, and hagistack does not do upgrades implicitly";
   - so the replacement is the **manual** procedure under test.
3. Procedure:
   - add the own set as a local repository with `priority=1`;
   - `dnf reinstall` every installed package whose name is in the set, from that
     repository only, with `--setopt=install_weak_deps=False`.
4. Pass criteria:
   - after the transaction, every installed package with a name from the set has the
     own set's header digest, so no rc4 package is left;
   - `rpm -V` is clean except the edited files;
   - plus the N3 criteria.
5. Record: hagistack's deployment record on u1 still names the rc4 set afterwards.
   - That is the expected limit of a manual replacement, not a FAIL.
   - rc4 was never published, so no real deployment has it.

## 8. Cleanup

- After the last configuration, or at any stop:
  - collect evidence;
  - `hs6.py teardown` deletes, in this order, the nodes (with their boot disks), the
    NAT, the router, the firewall rules, the subnet and the network;
    - each deletion checks the ledger entry and the GCE id;
    - a node that cannot be deleted stops it before the network;
  - `hs6.py residual` lists every resource named `hagistack-s6-<rid>-*`. It must show
    none.
- Resources that existed before the run are not touched.
- If a deletion fails, report at once which resource still runs and why. No further
  test is run while billable resources of this run are unaccounted for.
- Local temporary data stays under `<TMP_WORKSPACE>`. It is removed after the record is
  committed, except evidence the Owner wants kept.

## 9. Owner approval (needed before stage 6-1)

Decided on 2026-11-12: D1–D4 as recommended, D5 (pd-standard) and D6 (IAM as above).
Still needed before any GCE change: the approval file of `hs6.py` (section 5.1),
written by the Owner for a fresh run id.


1. **GCE operations:** the project, zone and account to use, and permission to create,
   run and delete the resources in section 5. The account and project were **not**
   checked in stage 6-0, and no GCE call was made.
2. **Budget:** caps of US$8 and 6 hours.
3. **Decisions** (recommended option first):
   - **D1:** include n4, the second remote compute node on the GitHub path, as design
     §7 lists "two remote compute nodes" (recommended), or run D with n3 only.
   - **D2:** A through the GitHub path with a candidate from `make-rpm-release.sh` on n1
     (recommended; writes files on n1 only, publishes nothing), or A through
     `--rpm-source bundle`.
   - **D3:** N3 and N8 on a separate node u1, so A stays a fresh install (recommended),
     or on n2 after A.
   - **D4:** do not attempt an actual cold migration, and record N5 statically
     (recommended), or set up and attempt one between n1 and n3.
4. Any re-run that costs a new resource, any larger machine or additional node, and
   exceeding a cap: each needs the Owner's approval at the time.

## 10. Not verified in stage 6-0

- Effective IAM permissions (D6). The cloudresourcemanager API is disabled and is not
  enabled for this.
- Organisation policies that could forbid nested virtualisation.
- The Tokyo internet egress price (assumed).
- That the quotas and the image observed on 2026-11-12 are unchanged at run time;
  `hs6.py init` checks them again.
- That `--rpm-source bundle --rpm-set-sha256` works for the `controller` role. The code
  path is shared with `rpm-prepare`, but on 2026-11-09 bundle was run only on remote
  compute nodes. B is BLOCKED if it does not work, and the Owner decides.
- That `make-rpm-release.sh` accepts the own set. It has not been run on it. Under D2,
  A is BLOCKED if it fails.
- That `novnc` can be installed from the RDO dependency repository (not needed by any
  criterion).
