# Hagistack's own RPM packaging — stage 6-1 live acceptance, run h6n121 (2026-11-12)

The implementer ran this acceptance. **It is not an independent audit.** Raw logs are
kept outside the repository (`<TMP_WORKSPACE>/hagistack-stage6-h6n121/`), and this
file records results only.

## Run

| Item | Value |
|---|---|
| Approval | Owner approved by chat (method A). The AI agent wrote the approval records from the Owner's chat messages; the harness did not verify the sender. Re-approved after the harness fix below. |
| Harness | `acceptance/stage6/hs6.py` at `7f84102` until 13:15 UTC, then `a772d57` (Cloud NAT IP fix) |
| Code under test | `git archive 7f84102 rocky10.2 LICENSE` (the RPM set and installer are unchanged by the harness fix) |
| RPM set | `6c43da51144ca01c413f5c7dbbc44be70b66f03df69e77b3e632c2d55b8a1313`, 195 RPMs, 69 SRPMs; not rebuilt |
| GCE | project `<GCP_PROJECT>`, zone `asia-northeast1-a`, a VPC for this run only (IAP SSH, Cloud NAT, no external IPs), image `rocky-linux-10-v20261110` (`VERSION_ID=10.2` on every node), nested KVM |
| Nodes | n1 n2-standard-8; n2, n3, n4, u1 n2-standard-4; all `pd-standard` (100/60/50/50/60 GB); u1 created after n4 was deleted |
| Times (UTC) | init 13:02:57; first creation 13:03:31; paused 13:15–13:51 for the harness fix; teardown complete 15:20:32; elapsed 2.3 h of 6 h |
| Cost | harness estimate US$3.17 at list prices, of which US$1.07 is assumed (egress, NAT data). Not the Google Cloud bill. |
| Monitoring | `watch` ran under `caffeinate -i` for the whole run; no stop was recorded |
| Cleanup | `teardown` complete; `residual` none; a direct listing showed 0 instances, disks, networks, subnets, firewall rules, routers and addresses of the run; other products' resources unchanged |

## Results per configuration

| Configuration | Result | Evidence (summary) |
|---|---|---|
| **B** controller-only (n1) | **PASS** | `--rpm-source bundle --rpm-set-sha256 6c43da…`; rc 0 in 443 s. Recorded set `6c43da…`, 102 set packages installed, 0 header-digest mismatches. No nova-compute, libvirt or qemu-kvm. Conductor and scheduler up, no hypervisor, OVN gateway chassis (`enable-chassis-as-gw`), and a guest ends in "No valid host was found". Horizon admin sign-in PASS. Re-run rc 0 with 0 restarts, reusing the recorded set. |
| **D** remote compute (n3 bundle, n4 GitHub path) | **PASS** | Both rc 0 (195 s, 191 s); "this node's RPM set is the controller's"; 69 set packages, 0 digest mismatches. No database in effect: hagistack's own check, an independent oslo.config query as the nova user (`database.connection` and `api_database.connection` None), and 0 database lines in the nova-compute journal. Hypervisors up and mapped; OVN agents alive. A guest ACTIVE on each node (31 s, 21 s), whose console shows the metadata fetch. Re-runs rc 0, 0 restarts. |
| **C** controller → local hypervisor (n1) | **PASS** | `compute-add --local` rc 0 in 128 s. Only preflight, RPM source, repositories, SELinux, packages and hypervisor phases ran; 0 controller config files changed. Role all-in-one, 3 hypervisors up. Guests on n1, n1, n3 and n4 ACTIVE; SSH with the metadata key; metadata hostname; ping n1→n1, n1→n3 and n1→n4 5/5 each, across nodes over Geneve. Re-run rc 0, 0 restarts. |
| **A** all-in-one (n2, mock GitHub path) | **PASS** | Lock from `make-rpm-release.sh` on the own set. Asset SHA-256 and size, identity `6c43da…`, repodata and `rpm -K` verified by hagistack; rc 0 in 542 s. 103 set packages, 0 digest mismatches. 2 guests ACTIVE; SSH with the metadata key; metadata hostname; ping 4/5 (first packet ARP). Horizon admin sign-in PASS. Re-run rc 0, 0 restarts. |

On every node:
- 0 failed units and 0 Python tracebacks in the OpenStack journals.
- `novnc`, `openstack-nova-novncproxy` and `openstack-nova-migration` are not installed.
- `rpm -V` differences are limited to configuration files the installer writes, the
  dashboard's static tree, and `/var/lib/nova/tmp` mode. The static tree is rebuilt
  by its httpd drop-in by design.

## N3–N8

- **N3 (scriptlets) and N8 (same-NEVR replacement), u1:**
  - rc4 was installed as an all-in-one through the mock GitHub path (rc 0). A guest
    was booted and a local edit made to `nova.conf`.
  - A manual `dnf reinstall` replaced 101 packages from the own set only, with weak
    dependencies off (rc 0, 101 s).
  - After it, every one has the own set's header digest, so no rc4 package is left.
  - Users and groups are unchanged, the local edit was kept, and `.rpmnew` files were
    written for the edited configs. Unedited packaged configs took the own set's
    content.
  - Units: 11 active before and after.
  - The guest stayed ACTIVE, two new guests booted with SSH, metadata and ping, and
    Horizon sign-in passed. **PASS.**
  - Differences recorded:
    - two dashboard policy directories went from `root:root 755` to `root:apache 750`;
    - `/var/lib/nova/tmp` went from 750 to 755 (still present, still the `lock_path`);
    - the four API unit files the own set does not ship are gone, as known from
      stage 5;
    - hagistack's deployment record still names the rc4 set, the expected limit of a
      manual replacement.
- **N4 (units), n2 and n3:** **PASS with observations.**
  - Restart worked for every tested unit. After `kill -9`, nova-compute and glance-api
    were back within 20 s.
  - **nova-conductor and nova-scheduler took about 95 s.** Their workers outlive the
    killed main process, so systemd waits for the 90 s stop timeout before killing
    them and restarting (KillMode control-group, `Type=simple`). Recovery holds but
    is slow.
  - A clean SIGTERM is not restarted (`Restart=on-failure`).
  - glance-api runs with a soft open-files limit of 1024. Image upload and download
    round trips (3) were OK.
  - Neutron agents log to the journal; `/var/log/neutron` holds no files.
- **N5 (migration):**
  - `openstack-nova-migration` is not installed anywhere.
  - Its wrapper (static, from the set's RPM) allows only the ssh/scp commands of cold
    migration and resize, and refuses libvirt's `qemu+ssh` tunnel used by live
    migration.
  - No migration was attempted (D4). **PASS (static).**
- **N6 (rebuild differences):** no `-doc` package is installed on any node.
  `python3-cinderclient` is installed as a runtime dependency; its man page was the
  differing file. **PASS.**
- **N7 (weak dependencies):**
  - Every install ran with `install_weak_deps=False` and every configuration passed.
  - `novnc` is absent everywhere.
  - Set packages installed: 103 (A), 102 (B), 69 (D).
  - Stage 5's fresh install (weak dependencies on) recorded 104, but its per-package
    list was not kept, so the one-package difference is not identified. **PASS,
    difference not itemised.**

## Findings

1. **Installer defect (FAIL-level, pre-existing).** Any `hagistack.env` aborts the
   installer with `CONFIG_KEYS_FLAT: unbound variable` (`rocky10.2/hagistack:365`).
   - The variable has never been defined since the first commit `84b50d6`.
   - Earlier acceptance runs used command-line options and did not see it. This run
     used command-line options after the first attempt failed in 0 s.
   - Not caused by the own packaging.
   - Fixed after the run in `e65204d`: `rocky10.2/hagistack` now defines
     `CONFIG_KEYS_FLAT` as the Ubuntu installer does, and
     `rocky10.2/tests/test-env-file.sh` covers the file reader. Verified on a real
     machine in run h6r4env (below): **closed**.
2. **Harness defect, fixed in `a772d57`.** Cloud NAT allocates its external IP
   (`nat-auto-ip-*`) only when a node first sends traffic out. The harness treated it
   as an unexpected address and refused new nodes. Now only an address whose every
   user is the run's own router (exact selfLink) is accepted, and residual lists it.
   - Tests: 115 on Python 3.9 and 3.13. Independent audit: GO.
   - Owner re-approved the new harness SHA-256.
3. **Test-procedure defect, fixed during the run.** macOS `tar` added AppleDouble
   `._*` files to the uploaded set archive. `make-rpm-release.sh` correctly refused
   the directory, and the files were removed on the node. The set and its identity
   were unaffected.
4. **Observation for the unit definitions (N4).** nova-conductor and nova-scheduler
   recover from a crash of their main process only after the 90 s stop timeout.
5. **First run of `make-rpm-release.sh` on the own set:** rc 0. The candidate lock
   names `6c43da…` and 195 RPMs. It was used for A and n4; nothing was published.

## Not verified

- The Google Cloud bill (the harness estimate is not billing).
- SELinux enforcing, a physical provider network and floating-IP reachability from
  outside, live migration, `%check` (unchanged scope).
- Which package makes stage 5's 104 differ from A's 103 (N7).

## Run h6r4env (2026-11-12): config-file install after the fix

Stage 6-1-R4. The implementer ran it; **it is not an independent audit.** Raw logs are
in `<TMP_WORKSPACE>/hagistack-stage6-h6r4env/`.

| Item | Value |
|---|---|
| Local verification before the run | `test-env-file.sh` 18/18 on a locally built bash 5.3; with the `CONFIG_KEYS_FLAT` line removed, 14 fail with `unbound variable`. Independent audit (a separate agent): GO, 0 BLOCKER/HIGH/MEDIUM; LOW-1 (no check of `mktemp`) fixed in `b20c1fb`, LOW-2 accepted, LOW-3 (`HAGISTACK_ETC` comes from the environment, pre-existing) out of scope. |
| Approval | Owner approved by chat (method A); the AI agent wrote the approval record; the sender was not verified. Operations `init`, `network`, `n2`, `ssh`, `upload`, `teardown`, `residual`; US$8; 6 h. |
| Harness | `hs6.py` `35e5610…` (unchanged) |
| Code under test | `git archive b20c1fb rocky10.2 LICENSE`; RPM set `6c43da…`, not rebuilt |
| GCE | `<GCP_PROJECT>` / `asia-northeast1-a`; a VPC for this run only; n2 only (n2-standard-4, `pd-standard` 60 GB) |
| Times (UTC) | init 18:01:34; network 18:02:00; n2 created 18:03:40; n2 deleted 18:42:28; teardown complete 18:43:20; elapsed 0.69 h |
| Cost | harness estimate US$0.70 at list prices, of which US$0.54 is assumed. Not the bill. |
| Cleanup | `teardown` complete; `residual` none; a direct listing showed 0 resources of the run. `watch` ended by itself; no stop recorded. |

Result: **PASS.**
- `hagistack.env` held every setting (9 keys, quotes included, `TENANT_CIDR=10.20.30.0/24`
  not the default, `RPM_SOURCE=bundle` with its path and the expected set); the installer
  ran as `hagistack all-in-one` with no options.
- `--check`: rc 0, `config file: ./hagistack.env (parsed, not executed)`, every one of
  the 9 values shown with source `[config file]`.
- Install rc 0 in 551 s, 0 `unbound variable` lines. Recorded role all-in-one, source
  bundle, set `6c43da…`; 103 set packages, 0 header-digest mismatches; `rpm -V` 1088 lines,
  as in configuration A.
- Keystone token OK; 15 endpoints in `RegionOne`; nova-scheduler, conductor and compute
  up; 1 hypervisor up; 2 Neutron agents alive; CirrOS image active; Placement (its API
  queried directly) 1 provider with VCPU 4, MEMORY_MB 15727, DISK_GB 59.
- The tenant subnet is `10.20.30.0/24`, so the file's value was applied.
- 0 failed units (11 active), 0 tracebacks, 0 `ERROR` lines in the nova, neutron, glance,
  keystone and placement logs. The journal's 2 error-priority lines are from boot (smbus,
  chrony), not OpenStack.
- Two guests ACTIVE (25 s, 22 s) on `10.20.30.x`; SSH with the metadata key; metadata
  hostname; ping 3/5. A second pair of guests, booted after the re-run, gave ping 4/5
  (as A in h6n121). Horizon admin sign-in PASS.
- Re-run rc 0 in 192 s, 0 restarts, the file read again, 0 `unbound variable` lines.
- During the run another product created `mkg-f5r23-*` resources (3 VMs and a network)
  in the project. The harness did not touch them. The one `nat-auto-ip-*` address left
  in the project belongs to Sinter's `sinter-v180-relv-router`, not to this run.

Not verified: the Google Cloud bill; the bash 5.3 source's signature (gpg not available;
the tarball's SHA-256 matched both the GNU download and the Homebrew formula).

