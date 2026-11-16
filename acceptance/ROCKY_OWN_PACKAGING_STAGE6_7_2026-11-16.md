# Hagistack's own RPM packaging — stage 6-7: release decision for Rocky Linux 10.2 (2026-11-16)

Nothing was pushed, tagged or released in this stage. No GCE resource was used, and no RPM was rebuilt.

**Decision: CONDITIONAL GO.** The publication target is fixed and verified, and no concrete licence or integrity problem was found. Two kinds of item remain:
- Owner decisions: the GCP project identifier in the outgoing history, and the reuse of the tag name.
- One check that can only be done after publication: the real `github` download.

## Publication target

The candidate is the one `make-rpm-release.sh` wrote on the build node in GCE run s66r5c. It was downloaded and is kept on the external workspace, outside the repository.

| File | SHA-256 | Bytes |
|---|---|---|
| `hagistack-rpms-rocky10.2-rpms-2026.1-rc3-el10-x86_64.tar` | `565a10133cbb26b6f871f53514c7f8ebc0b3329c206a8b0ed7d2b93690ab713b` | 107 929 600 |
| `hagistack-srpms-rocky10.2-rpms-2026.1-rc3.tar` | `db019350729477a7f12d4cfed5dd067e813eb0158a3f5b19d5191785708fdd25` | 52 889 600 |
| `PACKAGE_MANIFEST.tsv` | `f49fe50bd263c5ddb3c411c6fc347da7c2a7ffddb4d03cffea47b4776bc483e6` | 42 661 |
| `SHA256SUMS` | `dcaa31bab8720bdc319220ed7e0b437aaa1dc04d93ad64883f1a2f87efdbdf0f` | 2 005 |
| `rpm-release.lock.candidate` | `f678fc8e4ed6b20a34c7363381734c3919f0f9c822448c62c7afdd03bf63dfd2` | 870 |
| `LICENSE` | `5951d9cffa2a56b473eba70517285c1452ada3bde2efd6f654bc35743ae9c057` | 1 071 |
| `THIRD_PARTY_NOTICES.md` | `d44e85cd1ba50aab896dc09a71b498176e9f912f1559d994aaee00862f75679f` | 18 122 |
| `RELEASE-README.md` | `5633d38b8bc28349242bd7c1ade0600a9b6822ff7893146d792ad5d51a4c4398` | 4 117 |
| `gazpacho.manifest` | `b8d52d0f1a07b917c63b751f460b335711cb025a2ed2c96f101fb35158719fd0` | 30 599 |
| `build-env.lock` | `909bf548a6ae4499e4b82d8d39fb0e38bc67af9a89312e1b78b549ae6d2ec284` | 30 001 |

- The RPM set identity is `0b61c809ad2e90d5ab07502ae0732aaf61475278b032585cc98d9418c1f62000`: 195 binary RPMs, all noarch, and 69 source RPMs.
- `SHA256SUMS` also lists the ten files under `third-party/`. They are byte-identical to `rocky10.2/third-party/` at HEAD and are not uploaded as separate assets.
- The proposed tag is `rocky10.2-rpms-2026.1-rc3`. This name is the one the candidate's lock and asset names carry. Another name would need `make-rpm-release.sh` to be run again on a Rocky host. That repackages the files only and does not rebuild them, but it would give a new asset hash.

## Checks (executing agent)

- **Integrity:**
  - `SHA256SUMS` verifies.
  - The lock pins the asset's sha256 and size, the set identity, and the RPM count. Its manifest hash equals `gazpacho.manifest` at HEAD.
  - All 195 RPMs match `RPM-SHA256SUMS` and the manifest.
  - Every binary's source RPM is present, and there are no extra source RPMs.
- **What was tested on which bytes:**
  - s66r5c installed and accepted this exact set (all-in-one).
  - s66r5d (controller + compute) ran on a rebuild, set `59d0086c…`.
    - The inputs were the same: `rocky10.2/` and `LICENSE` did not change between `be1599a` and `4afa1e9`, and the build-input id is the same.
    - The 195 file names and the source RPM mapping are the same.
    - The builds are not byte-identical. The READMEs and the release notes say so.
- **Licences:**
  - The `License:` tags are Apache-2.0, MIT, BSD-3-Clause (qrcode), and CC-BY-4.0 / OFL-1.1 (Font Awesome).
  - None of the upstream archives in the 69 source RPMs has a NOTICE file, so Apache-2.0 §4(d) does not apply.
  - The licence texts, `HAGISTACK-LICENSE` and `HAGISTACK-CHANGES` are present in the packages that were spot-checked.
  - `make-rpm-release.sh` ran its notice, branding and source-correspondence checks on this set in s66r5c and they passed.
  - No licence term forbidding redistribution was found.
- **Ubuntu:**
  - `origin/master..HEAD` changes nothing under `ubuntu26.04/`.
  - The RPMs contain no Hagistack Ubuntu feature; the matches are upstream documentation and an icon.
  - The Ubuntu maintenance-lock issue is not a condition of this release.

## Prepared, not applied

A release commit, kept as a patch on the external workspace, is ready. It does the following:
- commits the candidate lock as `rocky10.2/rpm-release.lock`;
- updates the READMEs (status, quick start, troubleshooting, and a verified-environment paragraph) and `docs/ROCKY_INSTALLER_DESIGN.md`;
- changes `tests/test-rpm-source.sh` g12b. The old test expected the shipped lock to be unpublished. The new one points the shipped lock at a local server without the asset and expects it to pass every check before the download.

The release notes and the publication commands are prepared as well.

## Independent audit (separate agent, read-only)

The audit found **0 BLOCKER**. Its findings, by category:

- **Real files checked:** integrity; the bytes behind each acceptance run; licences; Ubuntu separation; the patch.
- **Tests run:** `test_release_check.py` on macOS, OK (1 skipped).
- **Not verified, does not block:** g12b. The test runs only on Rocky; it was reviewed statically.
- **NON-BLOCKER, fixed in the patch:** stale "not published" statements, and the lock order in the design document.
- **NON-BLOCKER, fixed in the release notes:**
  - `RELEASE-README.md`'s hand check (`sha256sum -c SHA256SUMS`) fails without `third-party/`. The notes say to use `--ignore-missing`.
  - The notes now say that the `github` path was never exercised with this asset.
- **NON-BLOCKER, Owner decision:**
  - The outgoing history adds a real cloud project identifier (`acceptance/stage6/`, several files). It is already public on origin/master in `ubuntu26.04/`, but AGENTS.md rule 5 applies to it.
  - The tag name `rocky10.2-rpms-2026.1-rc3` is also the name of an earlier, unpublished rc3 candidate (`ROCKY_RC3_BUILD_ACCEPTANCE_2026-11-10.md`) with a different hash.
- **After publication:** download the asset from the release and compare its sha256. The installer's `github` path with this asset has not been run.
