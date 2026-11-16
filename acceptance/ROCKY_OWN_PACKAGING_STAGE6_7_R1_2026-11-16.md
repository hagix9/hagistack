# Hagistack's own RPM packaging — stage 6-7-R1: full-release preparation for Rocky Linux 10.2 (2026-11-16)

Nothing was pushed, merged, tagged or released. No GCE resource was used, no RPM was rebuilt, and nothing under `ubuntu26.04/` was changed. This record supersedes the rc3 naming in stage 6-7 (`ROCKY_OWN_PACKAGING_STAGE6_7_2026-11-16.md`).

**Owner decision:**
- The release is a full release, not a pre-release.
- Name: "Hagistack for Rocky Linux 10.2 — OpenStack 2026.1".
- Tag: `rocky10.2-rpms-2026.1`.

**Status: CONDITIONAL GO.** The independent audit found 0 BLOCKER. The one open condition is the Owner's decision on the GCP project identifier (decision D1 below).

## Re-tagging without a rebuild

In `make-rpm-release.sh` the tag reaches the output in only three places:
- the names of the two tar files;
- four lines of `rpm-release.lock.candidate`: two comment lines, `RELEASE_TAG` and `ASSET_NAME`;
- `SHA256SUMS`, through those two.

The tar contents do not depend on the tag. They are made from the set directory with fixed flags and an mtime taken from `RPM-SHA256SUMS`.

A small converter applies exactly those changes to the rc3 candidate from run s66r5c. It is kept on the external workspace and is not part of the repository. It was checked twice:
- Converting rc3 to rc3 reproduces the `make-rpm-release.sh` candidate byte for byte. Both the executing agent and the auditor ran this check.
- The auditor's own conversion to the new tag is byte-identical to the prepared candidate.

| File | SHA-256 |
|---|---|
| `hagistack-rpms-rocky10.2-rpms-2026.1-el10-x86_64.tar` (195 RPMs, 107 929 600 bytes) | `565a10133cbb26b6f871f53514c7f8ebc0b3329c206a8b0ed7d2b93690ab713b` (unchanged) |
| `hagistack-srpms-rocky10.2-rpms-2026.1.tar` (69 SRPMs) | `db019350729477a7f12d4cfed5dd067e813eb0158a3f5b19d5191785708fdd25` (unchanged) |
| `rpm-release.lock.candidate` | `9ff85a2a5fffcb32ac5d1f400e25a1164d22c04af8c89a22c902c959e4c00da4` (new) |
| `SHA256SUMS` | `4bd30d36466e9ea43e7f5ea24d89c0f524edfc558fd950f18abba7728b5280df` (new) |
| `PACKAGE_MANIFEST.tsv`, `LICENSE`, `THIRD_PARTY_NOTICES.md`, `RELEASE-README.md`, `gazpacho.manifest`, `build-env.lock` | unchanged from stage 6-7 |

- The RPM set identity is still `0b61c809…`.
- Every RPM's SHA-256 still matches `RPM-SHA256SUMS` and `PACKAGE_MANIFEST.tsv`.

## Installer `github` path

**Offline run.** The installer's `github` steps were run offline against the assets:
- A local HTTP server serves the assets under `/<tag>/`, the same layout as GitHub's `releases/download/<tag>/`.
- The steps then follow `rpm_prepare_github`: the lock checks, the manifest check, a `curl -f` download, size and SHA-256, the installer's own embedded `TAR_CHECK_PY` (200 members), unpack, the `RPM-SHA256SUMS` comparison, the set identity, the installer's own `REPODATA_CHECK_PY` (195), and the RPM count.
- Two negative checks are included: a one-byte change, and another tag's path.
- Result: **14/14 PASS**, re-run by the auditor.

**Not run:** `rpm -K`, dnf, and the Rocky-only shell tests, including the changed g12b, which was reviewed statically. The download from the real GitHub Release has not been tested; the publication commands carry the check to run after publication.

## Acceptance mapping

| Area | Exact published RPMs (s66r5c) | Rebuild from the same sources (s66r5d, set `59d0086c…`) |
|---|---|---|
| All-in-one install | PASS | — |
| Controller + remote compute-add | — | PASS |
| Guests: SSH, metadata, ping | PASS | PASS, plus floating IPs and a 2 MB Geneve stream |
| Service restart and recovery | PASS | PASS (controller) |
| Compute host reboot and recovery | — | PASS |
| Installer re-run changes nothing | — | PASS (`compute-add`) |

The s66r5d builds are not byte-identical to the published set. The release notes and READMEs say so.

## Release commit (prepared as a patch, not applied)

The patch:
- commits the new lock as `rocky10.2/rpm-release.lock`;
- updates `README.md`, `README.ja.md`, `rocky10.2/README.md`, `rocky10.2/README.ja.md` and `docs/ROCKY_INSTALLER_DESIGN.md` (status, cloning from the tag, troubleshooting, the verified-run paragraph, the lock order);
- changes `rocky10.2/tests/test-rpm-source.sh` g12b so that it expects the shipped lock to pass every check up to the download.

It does not change `hagistack`, `make-rpm-release.sh`, `gazpacho.manifest`, the build, bundle and repo-url paths, or Ubuntu.

The release notes list these limitations: unsigned RPMs, SELinux permissive, no automatic firewall, live migration and three or more nodes not verified, x86_64 and Rocky Linux 10.2 only.

## Decision D1: the GCP project identifier (Owner)

The project identifier is not a secret, but AGENTS.md publication rule 5 applies to it.

**Where it is:**
- It is not in the release assets, the patch, the release notes or any commit message.
- It is already public on origin/master: two files under `ubuntu26.04/`, three occurrences.
- A push of `origin/master..HEAD` adds it through four commits, in five files and ten occurrences:
  - `acceptance/stage6/hs6.py` (the `PROJECT` constant);
  - `acceptance/stage6/test_hs6.py`;
  - `acceptance/stage6/APPROVAL.template.json`;
  - `acceptance/stage6/README.md`;
  - `acceptance/ROCKY_OWN_PACKAGING_STAGE6_LIVE_2026-11-12.md`.

**Options:**
- **A.** Publish as it is, and record the exception under rule 15 (reason, files, approval, expiry).
- **B.** Add a commit that replaces it with a placeholder. `hs6.py` would then read the project from configuration, which is a small functional change to the harness. The four earlier commits still carry it, so a push still publishes it in history.
- **C.** Rewrite the unpushed commits. No force push is needed, but rule 14 requires the Owner's approval.
- **D.** Also rewrite the published history (force push).

The executing agent does not choose. History is not rewritten without the Owner's approval.

## Independent audit (separate agent)

**Result:** 0 BLOCKER.

**Fixed after the audit:**
- the READMEs now show cloning from the tag;
- post-publication step 4 now matches its commands and checks `isPrerelease=false`;
- `--latest` was removed from the release command, so GitHub's automatic choice applies.

**Left as NON-BLOCKER:**
- the root README's "Verified" table still shows 2026-09-29;
- the lock in the tag carries the candidate comment, not the trust-anchor explanation. Changing it would break the byte comparison with the asset;
- the RELEASE-README hand check needs `--ignore-missing`; the release notes say so;
- the s66r5d chassis label is stale.

**Not verified, does not block:** `rpm -K`, dnf, the Rocky shell tests, a scan of the upstream tarballs inside the SRPMs, and the real GitHub download.
