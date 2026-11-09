# Rocky 10.2 — final x86_64 acceptance of 68da671 (two remaining items)

Scope: the two items the independent re-audit left unverified on x86_64:
(A) the remote-compute effective-configuration database check, and (B) a full
RPM build under the hardened pass control with `build.ok` and image-digest
verification. Everything else rests on the earlier records
([completion](ROCKY_INSTALLER_COMPLETION_ACCEPTANCE_2026-11-09.md),
[remediation](ROCKY_AUDIT_FINDINGS_REMEDIATION_2026-11-09.md)), which are
unchanged. Implementer's run, not an independent audit.

Code under test: `git archive 68da6714a5d1255c245242a5fde54208d8f16649`
(no local modification).

## Environment

Google Compute Engine, one zone, a VPC created for this run only (IAP SSH,
internal traffic, Cloud NAT egress, no external IPs). Stock `rocky-linux-10`
image (Rocky Linux 10.2, x86_64), nested KVM.

| Node | Machine | Role |
|---|---|---|
| n1 | n2-standard-8, pd-standard 100 GB | test B build; then `controller --rpm-source build` |
| n2 | n2-standard-4, pd-standard 50 GB | remote `compute-add --rpm-source bundle` |

All VMs, disks, firewall rules, router, NAT, subnet and network created for
this run were deleted afterwards and their absence was checked.
Run time ≈ 70 min (VMs 13:32–14:40 UTC). Estimated cost ≈ US$1 (list prices
× time; actual billing not obtained).

## Test B — full source build on x86_64: PASS

| Check | Result |
|---|---|
| Command | `hagistack rpm-prepare --rpm-source build` (exit 0, ≈46 min on pd-standard) |
| Build image | `quay.io/rockylinux/rockylinux:10.2@sha256:827d37bc128288ccf160ee318bb3cb92d591164cb217e92f8bc61e3982ae1834`; post-pull RepoDigests check passed (pinned digest present) |
| Build identity | `8f122e25ffda0967…` (includes the image digest) |
| Pass 1 | 66 PASS, 3 FAIL (neutron, nova, horizon: `rpmbuild exit 11`, build dependencies) |
| Pass 2 | neutron, nova, horizon PASS |
| Manifest coverage | 69 expected, 69 with a PASS, none missing |
| `logs/build.ok` | `packages=69 rpms=195 srpms=69`; newer than every other build output (repomd.xml 20 ms earlier); hagistack's `RPM-SHA256SUMS` and marker written after it |
| Counts (measured) | 195 RPMs, 69 SRPMs |
| Integrity | `sha256sum -c RPM-SHA256SUMS` 195/195; `rpm -K` 0 failures; every binary's SRPM present, no unreferenced SRPM; BUILDHOST `hagistack-builder` 195/195; repodata declares 195 and its 195 NEVRAs equal the RPM headers (dnf repoquery) |
| Set identity | `c3379764d4954fe3404a10517fb46a2f433cea15cf17ad4653e9e80c6994b457` |
| Same-input re-run | exit 0 in 4 s, "not rebuilt", no container started |

The identity differs from the 2026-11-09 completion build (`e62cb797…`): this
is a new build (rpmbuild embeds build times), not a reproducibility claim.
`%check` was not run (unchanged: not verified).

## Test A — remote compute database check on x86_64: PASS

Normal path:

- controller on n1 from the test-B set (re-verified, not rebuilt); every phase completed;
- n2 `compute-add --rpm-source bundle`: set identity equal to the controller's;
  `no database connection in effect for nova-compute (checked in nova.conf and
  with oslo.config)`; nova-compute running; journal 0 database lines; every phase completed;
- independent oslo.config query as the nova user: `database.connection`,
  `database.slave_connection`, `api_database.connection`,
  `api_database.slave_connection` all unset (files read: `/etc/nova/nova.conf`,
  `/etc/nova/nova-compute.conf`);
- n2 hypervisor `up`, OVN agents alive; a guest booted ACTIVE on n2 (the
  controller has no hypervisor) and fetched its instance-id from the metadata
  service on the first try.

Abnormal path (representative case, VM-local): `[api_database] connection`
added to `/etc/nova/nova-compute.conf` (a file hagistack does not write, so
only the effective check can see it), then `compute-add` re-run:

| Expected | Observed |
|---|---|
| hagistack fails | exit 1: "nova-compute would still open a database: api_database.connection is set" |
| nova-compute not started or restarted | nova-compute phase not reached; MainPID, ExecMainStartTimestamp, NRestarts=0 and journal line count unchanged |
| no database connection attempted | nftables counter on tcp/3306 output: 0 packets |
| setting can be reverted | file restored (SHA-256 equal to before); re-run exit 0, every phase completed, nothing restarted; the guest stayed ACTIVE throughout |

## Verdict

Both remaining items PASS on x86_64. Together with the earlier records, the
Rocky 10.2 implementation and acceptance scope is complete pending the
independent audit's own conclusion. RPM publication remains NO-GO
(licence items U-1, U-2 unresolved, C-3 open); Ubuntu and Sinter untouched.

## Correction (2026-11-10): the dnf NEVRA lines in the test-B log

The test-B table above says the repodata's "195 NEVRAs equal the RPM headers
(dnf repoquery)". The final audit found that the saved raw log
(`testB-verification.log`, lines 55–64) does not show that literally: it shows
`dnf sees 390 packages; files: 195`, `NEVRA in repodata == NEVRA in RPM
headers: NO (390 entries)` and `unique NEVRA from dnf: 196; identical: NO`.
That log is kept unchanged. The cause, now established by reproduction rather
than inference:

- **Measurement defect in the verification command, not in the artifacts.**
  dnf 4.20 terminates every `--qf` record with its own newline; the command
  added another `\n`, so each package produced its line plus an empty line:
  390 = 195 + 195 empty lines (the per-repo breakdown in the log shows
  "195 hsv" and "195" with an empty field), and 196 unique = 195 + one empty
  line. The log's diff against the RPM headers shows exactly one difference,
  an added empty line (`0a1` / `> `).
- Re-running the identical commands with the same dnf 4.20.0 on the retained
  release-candidate set reproduces the log byte-for-byte in pattern (390,
  "195"/"195 hsv", 196, `0a1`/`> `); `--qf` without the trailing `\n` gives
  195 lines and no empty line. Only the given repository was enabled; no
  installed package (`@System`) appeared.
- Independent comparison on that retained set, without dnf (RPM headers via
  `rpm -qp` vs the primary metadata parsed directly, NEVRA as
  `NAME-EPOCH:VERSION-RELEASE.ARCH` with explicit epoch): 195 RPM files, 195
  header NEVRAs, primary declares and lists 195, no duplicates, nothing only on
  either side, identical. The corrected dnf command is identical too.

Scope of that confirmation: the RPMs and repodata of the test-B set
(`c3379764…`) were not retained when the VMs were deleted, so they cannot be
re-compared now. For that set the evidence is the run-time log: the same
390/196 signature, whose only difference from the header list was the empty
line, and hagistack's own verification at run time (every file matches
`RPM-SHA256SUMS`; every primary entry's file exists with its checksum; no RPM
missing from primary; declared count 195; `rpm -K` clean). The independent
re-comparison was performed on the retained set `e62cb797…`, built from the
same inputs by the same procedure, which is also the release candidate.

hagistack's verification checks files and checksums (listing, identity,
repomd and primary checksums, coverage, `rpm -K`); it does not compare
primary's NEVRA text with the headers. No code change was made for this
correction.
