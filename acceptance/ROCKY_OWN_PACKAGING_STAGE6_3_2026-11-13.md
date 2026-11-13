# Hagistack's own RPM packaging — stage 6-3: release generation on Rocky, redistribution conditions (2026-11-13)

The implementer wrote this record. The independent audit, run by a separate agent,
is reported in its own section below. No GCE resource was created, changed or
deleted. Stage 6-1 was not re-run.

## Commits

| Commit | Change |
|---|---|
| `e6cfda3` | `THIRD_PARTY_NOTICES.md`: the changes made to the upstream sources, trademarks, and rc4's metadata as the source of names and paths |
| `3a0bb8c` | this record (first version); stage 6-2 record updated to the rewritten commit ids |
| `9b5aad0` | release guards and notice fixes from the independent audit (H-1, M-1, M-2, L-1–L-3); `release_check.py` |
| (this update) | audit results and the re-run on Rocky |

## Git history (Owner approved the rewrite)

- **The `.pyc`.** Stage 6-2's first commit added
  `acceptance/stage6/__pycache__/hs6.cpython-313.pyc` (128,734 bytes). It is the
  compiled `hs6.py` and the absolute path of the local checkout. It holds no user
  name and no credential. The volume part of that path, without the project
  directory, is already on `origin/master` (7 times). The file had already been
  removed from the tree.
- **The rewrite.** The six commits after `e4e4eb0` were replayed without that
  file. Each replayed commit has the same change (`git patch-id`), author, author
  date and message as the original, and the final tree is identical.

  | Before | After |
  |---|---|
  | `656d43d` | `8e5578a` |
  | `782b508` | `8ff77e2` |
  | `af3eab3` | `947276e` |
  | `4d33980` | `2556398` |
  | `afefcbf` | `0499a6d` |
  | `38807d5` | `e6cfda3` |

  The branch was never pushed, so a normal push suffices and no force push is
  needed. The old commits stay in the local reflog only.
- **Outgoing history.** These are the commits in `origin/master..HEAD` (45 when scanned, before this
  record) that a
  push of this branch would publish.
  - Added lines, screened by pattern class:
    - credentials: 0;
    - private keys: 0;
    - local paths (`/Users/…`, `/Volumes/…`): 0.
  - E-mail addresses are only `example.com` and `example.invalid`.
  - The two SSH public keys are synthetic test values and match no local key.
  - The IPv4 matches are version strings, documentation ranges, the tenant
    example and Google's public IAP range.
  - Binary files added: 0. `.pyc` files reachable from `HEAD`: 0.
- **Already public.** The GCE project id and the commit author address are
  already on `origin/master`.
- **Not part of a branch push.** A local tool ref under `refs/codex/` reaches
  other `.pyc` files. A branch push does not publish it; `git push --all` or
  `--mirror` would.

## Release generation on Rocky Linux (Owner approved a local VM)

Environment:

| Item | Value |
|---|---|
| VM | disposable Lima VM (vz, 2 CPU, 2 GiB), no host directory mounted |
| Image | Rocky Linux 10.2 GenericCloud **aarch64** (`sha256:457c8375…a5751aa0f5`, the digest pinned in Lima's template; checked after download) |
| Tools | `rpm` 4.19.1.1, GNU tar 1.35, Python 3.12.13 |
| Inputs | `git archive` of the tree at `e6cfda3` (`LICENSE`, `rocky10.2/`), and the set `6c43da…` (195 RPMs, 69 SRPMs) |
| Not x86_64 | the script only reads RPM headers and writes archives, which does not depend on the architecture |

The first copy of the set was made with macOS tar, which adds AppleDouble files
(`._*.rpm`). The script refused it ("the RPMs do not match RPM-SHA256SUMS"). The
set was then copied without them.

Result: **28/28 checks passed** (`vmtest.sh`) with the guards of stage 6-2.
After the audit fixes (`9b5aad0`): **40/40** (see "Independent audit").

| Checked | Result |
|---|---|
| Normal run | rc 0; asset `da5471b0…1993465a` (107,663,360 bytes), SRPM asset `7c35106a…9513010e` |
| Asset contents | 195 RPMs, `RPM-SHA256SUMS`, `repodata/`; every RPM matches its sum; set identity `6c43da…` |
| SRPM asset | exactly 69 `.src.rpm`, nothing else |
| `SHA256SUMS` | verifies; the lock candidate's asset sha256 and size, set identity, count 195 and manifest sha256 all match |
| Shipped files | `LICENSE`, `THIRD_PARTY_NOTICES.md`, `third-party/` and `build-env.lock` are identical to their sources |
| Manifest | 195 rows; the sha256 column equals `RPM-SHA256SUMS` |
| `HAGISTACK-LICENSE` | extracted from each of the 69 SRPMs; each is identical to `LICENSE` |
| Determinism | a second run gives a byte-identical output directory |
| Refused (12 cases) | no `LICENSE`, no `THIRD_PARTY_NOTICES.md`, no `third-party/`, no `gazpacho.manifest`; an SRPM missing; an extra SRPM; a symlink in `srpms/`; a directory in `srpms/`; an SRPM without `HAGISTACK-LICENSE` (fault injected: a wrapper hides that file from `rpm -qpl` for one SRPM); one RPM byte changed; one RPM removed; `--out` not empty. Each one stops with its own message, and no asset or lock is written. |

One check of the test script failed on its first run with the final tree. The
cause was `tar | grep -q` under `pipefail` (SIGPIPE), so the fault was in the test
and not in the release. That run produced the same asset bytes as the run before
it. The check was rewritten and the whole suite was re-run: 28/28.

## Licence and redistribution audit

These were read with `rpm` on Rocky from the set itself, unless noted.

**A. RDO-derived files.**
- Exact matches: 2 (the Neutron patches, stage 5 evidence).
- Near matches: 70 of Hagistack's own files were compared, line by line, with
  191 RDO packaging files from the 2026-10-05 snapshot. The snapshot has no
  Glance directory, so the Glance files were compared with the other projects.
  - 16 files have a similarity ratio of 0.50 or more; the highest is 0.70 (Nova
    proxy units).
  - The shared lines are systemd and logrotate keywords and values, commands
    named by upstream console scripts, and paths.
  - At most 3 shared lines per file are 40 characters or longer.
- Diffs of the five closest pairs show different descriptions, ordering,
  options and hardening.
- The names, paths, modes and the `conf.d` layout follow rc4, which came from
  RDO; they were taken from rc4's package metadata, as each `AUTHORING.md` says.
- The authoring records are the authors' own statements and could not be
  verified independently.

**B. Apache-2.0 (Neutron).**
- The two patches were compared with the upstream commits
  `83f1d830…` and `91abb5e7…` (GitHub mirror): the changed lines are identical.
  They carry the author, `Signed-off-by` and `Change-Id`.
- The SRPM holds both patches, the upstream tarball with its signature, and
  `HAGISTACK-LICENSE`.
- The binary RPMs install Neutron's `LICENSE` and `AUTHORS`.
- No upstream `NOTICE` file exists, so §4(d) does not apply.
- **Open:** under §4(b), modified files must carry a notice of the change. The
  binary changelog says only "Hagistack packaging of the upstream release", and
  the changed `.py` files carry no notice.
  - The changes are listed in the SRPM spec, in `third-party/neutron/NOTICE.md`
    and, now, in `THIRD_PARTY_NOTICES.md` (with the other edits to upstream
    files). These documents ship with the release, not inside the binary RPM.
  - Adding the notice to the RPMs needs a rebuild.

**C. CC-BY-4.0 / OFL-1.1 (Font Awesome 6.2.1).**
- The RPM installs Font Awesome's own `LICENSE.txt`.
- The CSS keeps its attribution header ("Font Awesome Free 6.2.1 by
  @fontawesome", the licence URL, and the Fonticons copyright).
- The definition changes no file (no `prep_extra`), so the fonts are shipped
  unmodified.
- term.js keeps its MIT header.

**D. Trademarks.**
- `openstack-dashboard` installs Horizon's OpenStack logo (`logo.svg`,
  `logo-splash.svg`) and its favicon, as upstream ships them.
- Font Awesome contains brand icons.
- The repository holds no image files.
- No RPM description names Rocky Linux; Vendor and Packager are unset; URLs point
  to opendev.org or pypi.org.
- `THIRD_PARTY_NOTICES.md` now has a trademark section: no affiliation, and the
  marks are shipped as upstream ships them.

**E. Source offer.** Every binary RPM has its SRPM, and every SRPM has a binary
(refusal tested). Since `9b5aad0`, the check also requires each binary's
`SOURCEPKGID` to equal its SRPM's header digest (`SIGMD5`); all 195 match. The SRPM
asset is published next to the binary asset, as `THIRD_PARTY_NOTICES.md`
describes. No licence tag names the GPL or another copyleft licence. Whether any
source obligation applies is a legal judgement; this record does not make it.

## Independent audit

**First audit** (separate agent, of `3a0bb8c`):
- It confirmed the candidate's contents independently: the asset and lock, 195
  RPMs byte-identical, 69 SRPMs, `SOURCEPKGID` = `SIGMD5` for all 195,
  `HAGISTACK-LICENSE` = `LICENSE`, the Neutron patches, Font Awesome identical to
  its sdist (2,107 files), and the rewritten history.
- Verdict: **release generation NO-GO**. Findings:
  - **HIGH H-1.** `repo/` went into the asset whole, but only its top-level
    `*.rpm` were checked. Extra files, a subdirectory with an unlisted RPM, or an
    `--out` inside the set were published with rc 0, as an asset the installer's
    member check refuses (reproduced).
  - **MEDIUM M-1.** Binaries were matched to SRPMs by file name only, so a
    swapped SRPM passed (reproduced). `HAGISTACK-LICENSE` was checked by name only.
  - **MEDIUM M-2.** The list of changes to upstream files was incomplete: it
    missed Horizon's `manage.py` shebang and rpm's `brp-mangle-shebangs`, and it
    said "Patch lines and %prep".
  - **LOW.**
    - L-1: a relative `--out` gave a misleading refusal.
    - L-2: `build-env.lock` was optional; `third-party/` was not checked against
      its pins; uncommitted files could be shipped.
    - L-3: the RDO-comparison sentence in the notices.
    - L-4: record details (commit count; the stage 6-2 decision on running on
      Rocky; the copyleft sentence).
    - L-5: the GCE project id is in more files on the branch. It is already on
      `origin/master`, so it is an Owner decision under the AGENTS.md hygiene rule.

**Fixes** (`9b5aad0`, and this update for L-4):
- `make-rpm-release.sh` with the new `release_check.py`:
  - `repo/` must hold exactly the listed RPMs and `repodata/`.
  - `repodata/` must hold exactly `repomd.xml` and the files it names, with their
    sha256. The primary metadata must list exactly the listed RPMs, each with its
    sha256.
  - The written assets are checked member by member, and the asset is put
    through the installer's own `TAR_CHECK_PY`, read from `hagistack`.
  - `SOURCEPKGID` = `SIGMD5` for each binary.
  - `HAGISTACK-LICENSE` must equal `LICENSE` byte for byte (read with `rpm2cpio`).
  - `--set-dir`/`--out` are resolved, and `--out` inside the set is refused.
  - `build-env.lock` is required.
  - `third-party/` must be exactly the expected files, with the pinned ones
    unaltered, and `third-party/neutron/LICENSE` must be the canonical
    Apache-2.0 text.
  - In a git work tree, uncommitted shipped files are refused.
- The notices add the `manage.py` shebang, rpm's shebang rewriting (checked:
  `neutron/cmd/destroy_patch_ports.py` is `#!/usr/bin/env python3` upstream and
  `#!/usr/bin/python3` in the RPM) and the generated files. The RDO sentence now
  says what was compared (all 24,877 files of the 264 packages, stage 5).

**Re-run on Rocky** (same VM, tree `9b5aad0`): **40/40**.
- The 16 earlier checks pass, and the asset is unchanged (`da5471b0…`).
- 23 refusals pass: the 12 earlier ones plus these 11:
  - an extra file in `repo/`;
  - a subdirectory in `repo/`;
  - `--out` inside the set;
  - an extra file in `repodata/`;
  - a swapped SRPM;
  - `HAGISTACK-LICENSE` altered;
  - no `build-env.lock`;
  - an extra file in `third-party/`;
  - a pinned patch altered;
  - the Neutron licence text altered;
  - uncommitted shipped files in a git work tree (tested with a stub `git`).

  The earlier "SRPM without `HAGISTACK-LICENSE`" case now injects its fault
  through a `rpm2cpio` wrapper, because the check now reads the payload; the old
  `rpm -qpl` injection no longer reached the check (it passed with rc 0, as
  expected). The "altered" case also uses a `rpm2cpio` wrapper.
- A run with a relative `--set-dir`/`--out` and a clean (stub) git work tree gives
  output identical to the first run.

**Re-audit:** (below)

## Owner decisions and legal points

1. §4(b) for Neutron. Two options:
   - accept that the notice is in the shipped documents and the SRPM;
   - rebuild with a changelog entry, or with a notice installed in the binary RPMs.
2. The OpenStack logo in Horizon: whether to ship Horizon's default images as
   upstream ships them, under the OpenInfra trademark policy, or to replace them
   (a rebuild).
3. Accept the clean-room records (`files/*/AUTHORING.md`) as the authors'
   statements, and the rc4-compatible names and paths as functional facts.
4. Whether the SRPMs are attached to the release (they are generated and checked).
5. Approval key for GCE (stage 6-2): still unpinned. It is not needed for release
   generation.
6. The GCE project id is in the acceptance harness and its records on this branch
   (already public on `origin/master`). Keep it, or replace it with a placeholder
   before the push (AGENTS.md hygiene rule 5).
7. Push only this branch (`git push origin feat/rocky-own-packaging`). A local
   tool ref under `refs/codex/` reaches other `.pyc` files, so `--all` or
   `--mirror` must not be used.
