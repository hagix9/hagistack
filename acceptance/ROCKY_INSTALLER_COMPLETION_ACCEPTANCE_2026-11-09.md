# Rocky 10.2 installer completion — acceptance record, 2026-11-09

Scope: `rocky10.2/hagistack` 0.2.0-rocky (uncommitted working tree on top of
`8225c50`): RPM sources (`github`, `build`, `bundle`, `repo-url`) and the four
configurations (all-in-one, controller, `compute-add --local`, remote
`compute-add`). Design: [docs/ROCKY_INSTALLER_DESIGN.md](../docs/ROCKY_INSTALLER_DESIGN.md).

This is the implementer's own acceptance run. **It is not an independent
audit.** Raw logs are kept outside the repository (they contain cloud-internal
host names); this file records results only.

## Environment

| | |
|---|---|
| Cloud | Google Compute Engine, one zone, a dedicated VPC created for this run (IAP SSH only, internal traffic, Cloud NAT egress, no external IPs) |
| Image | stock `rocky-linux-10` (`/etc/os-release`: Rocky Linux 10.2 "Red Quartz"), kernel 6.12.0-211.67.1.el10_2.x86_64 |
| Virtualisation | nested, `virt_type=kvm` on every node |
| n1 | n2-standard-8, 100 GB: source build, then `controller`, then `compute-add --local` |
| n2 | n2-standard-4, 60 GB: `all-in-one --repo-url` (legacy path); also ran the unit tests and ShellCheck |
| n3 | n2-standard-4, 50 GB: remote `compute-add` with `--rpm-source bundle` |
| n4 | n2-standard-4, 50 GB: remote `compute-add` with `--rpm-source github` against a mock release server |
| SELinux | switched to permissive by hagistack (unchanged scope) |
| Provider NIC | a dummy interface (`hgext0`), as in earlier acceptance; never attached to `br-ex` |

The mock "GitHub" was `python3 -m http.server` on n1's internal address serving
the release candidate made by `make-rpm-release.sh`, with a lock pointing at it
(`--rpm-lock-file`). No real GitHub Release exists.

All VMs and network resources were created for this run and deleted afterwards.

## RPM results

| Item | Result | Evidence |
|---|---|---|
| Source build through hagistack (`rpm-prepare --rpm-source build`) | **PASS**: container build, pass 1 66 PASS / 3 FAIL (neutron, nova, horizon: build order), pass 2 3 PASS; 195 RPMs + 69 SRPMs; set verified; about 35 min on n2-standard-8 | run log, `pass1/2.results`, container log |
| BUILDHOST in published headers | **PASS**: 195/195 `hagistack-builder` | `make-rpm-release.sh` check |
| RDO builder repo files | digests identical to the 2026-09-30 build | `builder-repo-files.sha256` |
| Build cache reuse (same inputs) | **PASS**: 3.8 s, "not rebuilt" | run log |
| Source build → automatic install (`controller --rpm-source build`) | **PASS** | n1 log |
| Release candidate (`make-rpm-release.sh`) | **PASS**: asset 115,916,800 B, every binary has its SRPM, SHA256SUMS consistent after transfer | candidate dir |
| GitHub path, real install (n4, mock server) | **PASS**: asset SHA-256/size, set identity, repodata, `rpm -K`, then compute-add | n4 log |
| Bundle path, real install (n3) | **PASS**: bundle repodata discarded and regenerated, identity matched controller | n3 log |
| `--repo-url` compatibility, real install (n2 all-in-one) | **PASS** | n2 log |
| Multi-node identity check | **PASS**: n3 and n4 both "this node's RPM set is the controller's" | logs |
| Checksum mismatch, size mismatch, set-identity mismatch, 404, network failure, incomplete set, repodata omitting an RPM, altered repodata, unsafe tar member, unpublished lock, manifest mismatch, lock metacharacters/unknown key, corrupted cache, wrong bundle, re-run reuse, role guard, consistency guard | **PASS**: `rocky10.2/tests/test-rpm-source.sh` 56/56 on Rocky 10.2 | unit log |

## OpenStack results

| Configuration | Result |
|---|---|
| **Controller-only** (n1) | **PASS**: every phase completed; `openstack-nova-compute`, `libvirt`, `qemu-kvm` not installed; conductor/scheduler up; OVN gateway chassis present; no hypervisor; a guest request ends in "No valid host was found" (expected) |
| Controller re-run | **PASS**: exit 0, 0 restarts, recorded RPM set reused |
| Remote compute-add on the controller | **PASS (refused as designed)** |
| **Controller → `compute-add --local`** (n1) | **PASS**: no controller phase run; controller config files' mtimes all earlier than the run; hypervisor up and mapped; role becomes all-in-one; 2 guests ACTIVE (29 s / 21 s), SSH with metadata-injected key, guest→guest ping 4/5 (first ARP) |
| `compute-add --local` re-run | **PASS**: exit 0, 0 restarts |
| **All-in-one** (n2, `--repo-url`) | **PASS**: 2 guests ACTIVE (32 s / 21 s), SSH via metadata key, metadata hostname, guest→guest ping 4/5 |
| All-in-one re-run | **PASS**: exit 0, 0 restarts |
| **Remote compute** n3 (bundle) and n4 (github) | **PASS**: both up; nova-compute opens no database (0 lines) |
| **Two remote compute nodes + local** | **PASS**: hypervisors n1, n3, n4 up; guests ACTIVE on each (~21 s); guest on n1 pings guests on n3 and n4, 5/5 each (cross-node over Geneve) |
| Metadata on a remote node | **PASS**: guest on n4 fetched instance-id from 169.254.169.254 on the first try |
| Remote compute re-run | n3: **FAIL then fixed** — first re-run stopped with "--rpm-source bundle needs --rpm-bundle FILE" (defect: a recorded bundle source still demanded the file). Fixed, unit-tested, re-run exit 0 / 0 restarts. n4: exit 0 / 0 restarts |
| Horizon admin sign-in on the controller host (`tests-horizon-login.sh`) | **PASS** |

## Static checks

- `bash -n` on all shell scripts: PASS.
- ShellCheck 0.10.0, severity warning: `hagistack` 9 warnings, all 9 present at
  `8225c50` (baseline 9; none new); `build-in-container.sh`,
  `make-rpm-release.sh`: 0; test script: 0 after fixes.
- `spec-adapt` unit tests: 61/61 PASS after the cliff rule moved to `DISABLED_RULES`.

## Not verified

- A real GitHub Release download (none exists; mock server only).
- A fully fresh `--rpm-source github` **all-in-one** (github was exercised as a
  real install on a compute node; the all-in-one used `--repo-url`).
- `%check` of any RPM (built `--nocheck`).
- SELinux enforcing, physical LAN, floating IP reachability from outside, live
  migration, hosts with an active firewall (unchanged limitations).
- Upgrading a host deployed by hagistack 0.1.0 (no deployment record).
- n2 was not pristine when all-in-one ran: `rpm-build`, `createrepo_c`, EPEL and
  ShellCheck had been installed for the unit tests beforehand.

Approximate GCE cost of the run: about US$3–4 (estimate from machine hours,
not from billing data).
