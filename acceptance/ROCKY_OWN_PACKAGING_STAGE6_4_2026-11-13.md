# Hagistack's own RPM packaging — stage 6-4: release blockers and the release candidate (2026-11-13)

The implementer wrote this record. The independent audit is reported separately
below.

What was not done:
- No GCE resource was created, changed or deleted.
- Stage 6-1 was not re-run.
- No RPM was rebuilt; the set is still `6c43da…`.
- History was not rewritten.
- Nothing was pushed, tagged or released.

## Commits

| Commit | Change |
|---|---|
| `9daac74` | `RELEASE-README.md` ships with every candidate; `make-rpm-release.sh` refuses a candidate that is not exactly the standard files, or whose `SHA256SUMS` does not list and verify each; notices: owner of the OpenStack marks, not "OpenStack Powered/Compatible", upstream changes sorted by kind |
| (this record) | stage 6-4 record |

## 1. Apache-2.0 §4(b) (modified files must carry notices of the change)

**Inventory of the Neutron RPMs, checked on Rocky.** Every file the 15 binary
RPMs of `openstack-neutron` install under `site-packages/neutron/` was compared
with the upstream `neutron-28.0.2.tar.gz` inside the SRPM:

| Result | Files |
|---|---|
| identical to upstream | 2,031 |
| changed by the two backported upstream commits | 4 (`constants.py`, `mech_driver.py`, `impl_idl_ovn.py`, `maintenance.py`) |
| shebang only, rewritten by rpm's `brp-mangle-shebangs` | 11 (10 × `env python3`, 1 × `env bash`) |
| shebang only, Hagistack's `%prep` edit | 1 (`tests/fullstack/servers/metadata.py`, `env python` → `python3`) |
| any other difference | **0** |

The 858 entries without a tarball counterpart are directories.

**Classification:**

| Kind | Files | Notice today |
|---|---|---|
| 1. Upstream changes (two Neutron commits by their upstream author, Apache-2.0; changed lines identical to upstream, context adapted to 28.0.2) | 4 Neutron files | SRPM spec (`Patch0001/0002`), `third-party/neutron/NOTICE.md`, `THIRD_PARTY_NOTICES.md` |
| 2. Hagistack's own edits | Neutron `requirements.txt` and `metadata.py`; Horizon `requirements.txt` and `manage.py`; qrcode shebangs; three `doc/source/conf.py` | SRPM spec, `THIRD_PARTY_NOTICES.md` |
| 3. Changes by the RPM build tools | shebangs of executable files in every package (12 in Neutron) | `THIRD_PARTY_NOTICES.md` |
| 4. Packaging only | Hagistack's own units, sudoers, logrotate files and the like; generated files | new files (MIT), not changes to upstream files |

The upstream copyright and licence headers are untouched: the patches do not
touch any header, and no upstream file was removed. Neither the changed files
nor the binary RPMs carry a notice of the change. The binary changelog says only
"Hagistack packaging of the upstream release". The notices travel with the
release (in `THIRD_PARTY_NOTICES.md` and `third-party/`) and in the SRPMs.

**Options (Owner decision; whether option A meets §4(b) is a legal judgement):**

- **A. No rebuild.** Keep the notices in the release documents and the SRPM
  specs, as now. No further work.
- **B. Notice inside the binary RPMs** (no edit of upstream source text).
  - `genspec.py` writes `%changelog` lines that name each patch and each
    `prep_extra`/`install_extra` edit.
  - It also installs a short `HAGISTACK-CHANGES` file as `%doc` in each affected
    binary package.
  - **B1, Neutron only:** 1 SRPM, 15 binaries.
  - **B2, every package with a Hagistack edit:** Neutron, Horizon, qrcode,
    barbicanclient, keystoneauth1 and keystonemiddleware, which is 6 SRPMs and
    25 binaries. The three documentation edits change no installed file.
  - **B3:** B2, plus a changelog line about the build tool's shebang rewriting
    in all 69 SRPMs.
  - **Work for B1–B3:**
    - Change `genspec.py` and its tests.
    - Rebuild on an x86_64 builder. GCE needs the Owner's signed approval, and
      the approval key is not yet pinned.
    - This gives a new set identity. The old set `6c43da…` stays as it is.
    - Run the release on Rocky again (the 46 checks).
    - Run an install acceptance of the new set: at least `all-in-one` and a
      guest. Stage 6-1's GO applies to `6c43da…` only.
- **Not proposed:** inserting comments into upstream `.py` files. It is the
  largest change to upstream source and adds nothing over option B.

## 2. OpenStack trademark and the Horizon logo

What OpenInfra's official pages say, read 2026-11-13. None of the pages
carries a date.

- **Policy:** `openinfra.org/legal/trademark-policy`. The old
  `openstack.org` policy URL redirects there.
- **Brand pages:** `openstack.org/brand/` and `openinfra.dev/brand/logos/`.

Findings:
- **Owner of the marks:** the OpenStack Foundation d/b/a Open Infrastructure
  Foundation. The Linux Foundation's trademark page does not cover the OpenStack
  marks.
- **The word "OpenStack" without a licence:** allowed only as nominative fair
  use, under three conditions:
  - the mark is used only as needed to refer to the project;
  - your own branding is more prominent;
  - no endorsement or affiliation is implied.
- **Confusingly similar names** are prohibited.
- **The OpenStack logo:**
  - Using it to brand a commercial product needs a signed licence.
  - The primary logo is generally limited to educational and community use.
  - Marks must be used unaltered.
- **"OpenStack Powered" and "OpenStack Compatible"** (for distributions and
  products) need a signed licence.
- **Not addressed:** redistributing OpenStack software that contains the logo
  (for example, Horizon's default images), whether unmodified or modified, and
  any specific rule for packagers.

Use in this release:
- The name appears in package names (`openstack-*`, upstream's names), summaries
  ("OpenStack Compute (Nova)") and documents, to say what the software is.
- No Hagistack name or logo imitates the marks.
- `openstack-dashboard` contains Horizon's default `logo.svg`,
  `logo-splash.svg` and favicon, unmodified. Horizon shows them in its UI.

Done here (no Owner decision needed): `THIRD_PARTY_NOTICES.md` and
`RELEASE-README.md` now name OpenInfra as the owner of the marks. They say that
the release is not an OpenStack release, is not "OpenStack Powered" or
"OpenStack Compatible", and is not affiliated or endorsed.

**Options (Owner decision; the policy gives no clear basis for keeping the logo):**

- **T1. Keep the logo as upstream ships it.** Nothing more to do. The policy
  neither allows nor forbids it explicitly.
- **T2. Replace it with a Hagistack theme.**
  - `openstack-dashboard-theme`, which is empty today, would ship a neutral
    `logo.svg`, `logo-splash.svg` and favicon. `local_settings` would select that
    theme.
  - `openstack-dashboard` would exclude upstream's logo files, so that the logo
    is not distributed at all.
  - Work:
    - Rebuild one SRPM, `python-django-horizon` (3 binaries).
    - Get a new set identity and run the release on Rocky again.
    - Check the Horizon sign-in page and pages in a live install.
- **T3. Ask OpenInfra** for written confirmation, then choose T1 or T2.

## 3. Clean-room records

The 16 Hagistack files with a similarity ratio of 0.50 or more to an RDO
packaging file were re-examined line by line.

- **The shared lines:**
  - `[Unit]`, `[Service]`, `[Install]`, `Type=simple`, `Restart=on-failure`
    and `WantedBy=multi-user.target` (12 files each);
  - the service user (`User=nova`, `User=neutron`);
  - `KillMode=process` (4);
  - logrotate keywords (`compress`, `missingok`, `weekly`, `rotate 4`,
    `copytruncate`);
  - the upstream console-script paths (`ExecStart=/usr/bin/nova-serialproxy`
    and similar);
  - `EnvironmentFile=-/etc/sysconfig/openstack-nova-novncproxy`;
  - in `neutron-dist.conf`: the two `root_helper` lines and `lock_path`.
- **No copyright notice** is in any of the RDO files concerned, so there is
  nothing to carry over.
- **Records against files:**
  - Every one of the 16 files is covered by its `AUTHORING.md`, by name or in a
    group heading (for example `openstack-nova-{conductor,…}.service`).
  - The `root_helper` lines are the installer's own: `hagistack` lines 2643–2645
    and 3236–3238, present since 2026-09-29 (`c206073`). The clean-room file came
    on 2026-11-11, which matches the record's stated source.
  - The installer's sources say why each of the other lines is there.
- **Conclusion (technical):** the shared parts are functional (syntax, service
  names, paths, settings that upstream or the installer dictate). No expression
  beyond them is shared.
- **Limit:** the records are the authors' own statements. Neither they nor
  this comparison can prove how the files were written. Whether to rely on them
  is an Owner decision.

## 4. Release candidate

| Item | Value |
|---|---|
| RPM set | `6c43da51…8b1313`, 195 RPMs, 69 SRPMs (unchanged since stage 5) |
| Binary asset | `hagistack-rpms-<TAG>-el10-x86_64.tar`, sha256 `da5471b0…1993465a`, 107,663,360 bytes |
| Standard files (11) | the binary asset; the SRPM asset; `PACKAGE_MANIFEST.tsv`; `SHA256SUMS`; `rpm-release.lock.candidate`; `LICENSE`; `THIRD_PARTY_NOTICES.md`; `RELEASE-README.md` (install steps, supported OS and architecture, known limitations); `gazpacho.manifest`; `build-env.lock`; `third-party/` |
| SRPMs | published with the RPMs, in `hagistack-srpms-<TAG>.tar` |

The binary asset's bytes do not depend on the tag. The asset is unchanged by
stage 6-4.

**Verification on Rocky Linux 10.2 aarch64.** The VM was re-created with the
Owner's approval, under the stage 6-3 conditions, and deleted afterwards.
- Tree `9daac74`: **46/46** checks.
  - These are the 41 checks of stage 6-3, re-run because the script changed.
  - New:
    - `RELEASE-README.md` is shipped identical;
    - the candidate holds exactly the 11 entries;
    - the run is refused without `RELEASE-README.md`;
    - it is refused with a stray file in the candidate (fault injected through a
      `cp` wrapper);
    - it is refused when `SHA256SUMS` does not verify (fault injected through a
      `sha256sum` wrapper).

**Not verified:**
- a run on x86_64;
- downloading from a real GitHub Release (none exists);
- the lock committed as `rpm-release.lock` (that happens after publication).

## 5. Git history

`origin/master..HEAD` holds 51 commits before this record.
- Added lines:
  - credentials: 0;
  - private keys: 0;
  - local paths: 0.
- E-mail addresses are only `example.com` and `example.invalid`.
- The SSH keys are synthetic test values.
- The IPv4 matches are version strings, documentation or example ranges, and
  Google's public IAP range.
- Binary files added: 0. `.pyc` files: 0.
- Commit messages contain no local paths and no addresses.
- The GCE project id is already on `origin/master` (Owner decision, stage 6-3).

## Independent audit

(see below)

## Owner decisions

1. §4(b): option A, B1, B2 or B3.
2. The Horizon logo: T1, T2 or T3.
3. Rely on the clean-room records.
4. Where to publish, then push, tag and release.
   - Push only this branch.
   - After publication, commit `rpm-release.lock` from
     `rpm-release.lock.candidate`.
5. The GCE project id on the branch: keep it or replace it.
6. Pin the GCE approval key. It is needed only if option B or T2 asks for a
   rebuild or acceptance run on GCE.
