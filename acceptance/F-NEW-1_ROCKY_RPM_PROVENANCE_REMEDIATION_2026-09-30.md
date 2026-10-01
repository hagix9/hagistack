# F-NEW-1 Rocky RPM provenance remediation

Recorded 2026-09-30. **Evidence only.** Product candidate `40472e879bf55d66fb4f3ecb719d67fb180567d6` was not touched.
Raw evidence: `/Volumes/VGX1000 SSD/Codex/tmp/hagistack-fnew1-rpm-provenance-remediation-2026-09-30/` (`SHA256SUMS` at its root).
The GCP project id, addresses, account and credentials are not recorded here. RPM headers embed the builder FQDN, which contains the project id; it is in the raw artifacts, not in this report.

**PROVENANCE REMEDIATION PATH: B — CLEAN REBUILD**

The old acceptance artifacts and the new remediation artifacts are kept apart throughout. Nothing below proves the provenance of the old RPMs.

---

## A. Preflight

| | |
|---|---|
| branch | `fix/rocky-neutron-maintenance-lock` |
| HEAD | `207795084855e0fa7e3bce7124d4f0440408cfd4` (evidence commit) |
| product candidate | `40472e879bf55d66fb4f3ecb719d67fb180567d6`, tree `dbb2b2f1ad1dc41650a278467f20653d422966bf` |
| candidate parent | `2556d832d9317aa7f4b5e9d4c2c675f66b4ae63f` (verified) |
| origin/master | `7a20dbe1ba8cde14f9e35252e1f9074387d695d6` |
| ancestry | 40472e8 and 2077950 are ancestors of HEAD; HEAD = 40472e8 + one commit |
| staged | none |
| untracked at start | `AGENTS.md` and the four F-NEW-1 investigation/feasibility/audit reports |
| `git diff 40472e8 HEAD -- . ':!acceptance'` | empty; the only difference is `acceptance/F-NEW-1_ROCKY_BACKPORT_ACCEPTANCE_2026-09-30.md` (evidence commit) |

Candidate file SHA-256 (from Git objects): `neutron.patch` `d3755588c744d756218e5b673dff1a33aa943000769c31b373ffd91d58073098`, `gazpacho.manifest` `8c22a5bdc7d4302a0084f661b9c09b68d9d47b21dc99be2b64ecb700de813538`, `build-rpms.sh` `1ad25aa87a0279358576109377a2665f12e3cd5f8d0761d8f577ef8fe4362754`, `hagistack` `082a4a8c3879fedd1b0db262cea83fa39c63d7e4edba2536959f1e58c453e170`, test `b8ae2d4997feffb8c887e59b07617bad060e2ce4aec98ce1ad6a60c7bee89793`.

## B. Audit blocker (IA-R01, quoted scope only)

The independent recheck stopped at one point: *"候補SRPMの実体・hashと完全rpmbuildログが保存証拠に見当たらず、要求された正確なRPMビルド来歴を確立できない"* — the candidate SRPM and the complete rpmbuild log are not in the preserved evidence, so Git → spec/SOURCES → SRPM → binary cannot be established. The auditor found the complete-log hash (`c3808f39…`) and the old builder path only, zero Neutron `.src.rpm` files, and 196 RPMs / 0 SRPMs inside `served-repo-fix.tar`. It stated this is neither a product defect nor fabricated evidence. Nothing else was reopened.

Checklist derived from that finding (all closed by PATH B, section G onward):

- [x] SRPM object with SHA-256
- [x] complete rpmbuild log with SHA-256
- [x] spec/SOURCES ↔ SRPM ↔ binary correspondence record
- [x] Git bytes (`40472e8`) ↔ spec/patches in the SRPM
- [x] binary RPM identities frozen before deployment
- [x] deployed packages tied to those identities

## C. Product mutation check

`PRODUCT CANDIDATE 40472e8: FROZEN`

`PRODUCT MUTATIONS DURING REMEDIATION: ZERO`

## D. Original artifact identity (OLD acceptance set, recovered from raw evidence)

Recovered from `hagistack-fnew1-rocky-fix-2026-09-30/raw/builder/repo-inventory.tsv`; all 45 full digests (15 × SHA-256, SHA256HEADER, PAYLOADDIGEST) also appear in the committed acceptance §7 table. Every row's SOURCERPM is `openstack-neutron-28.0.2-2.el10.src.rpm`.

| Item | Value |
|---|---|
| served repository | 196 files; `repodata/repomd.xml` `0f31249ae507fb5ea65d1f9558a672e5d93cf1a90518f1fccc52bdb95872d5f9`; per-file list `d9bca70c4d62ff5ef79162ad681a99a84273a957487c2abd16f9b4a59c94e2d3`; TSV inventory `c745154b881409d4bb0f0f1f29be78905e0e7099c2ac57a3a71d0c2b81c9723a`; tarball `served-repo-fix.tar` `06e94f29fab8afa21bffe956688f52eca243c9f9d9b08031c2c1d09c4cfff02b` |
| recorded rpmbuild log hash | `c3808f3954ed4957d2815dad48f0ee5331770cdb8cbf65711e621260617634d2` (file not preserved) |
| build-env.lock | `fa06a3a03788b389b5d8c102132b959073c360bc1670f29894b10f6ee2b6294d` |
| Neutron SRPM | never recorded; see E |

| File | NEVRA | Size | SHA-256 | SHA256HEADER | PAYLOADDIGEST |
|---|---|---|---|---|---|
| `openstack-neutron-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-1:28.0.2-2.el10.noarch` | 32650 | `2c162ce8db70f44b7d8a4d1118898cf1bfb24993b804bd78ae61acf6c9397972` | `43eac96b4de5034dd6af2fb28cbf1f029fc816052831f27685a6de876986b92d` | `4cee54070fa619d67c7698ae465fd48dbb3f1ad705d58eee1a321689b514c810` |
| `openstack-neutron-common-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-common-1:28.0.2-2.el10.noarch` | 156522 | `a89c63ee0603f6805574b07881351d708252e0b3fd77475af43f41295fb91b6a` | `cac9fb36b4cf2c967dd7984d04b34d305c2bb7e1dcd132aebe70a022e3fb4e38` | `1e33d8a74fc3e071094f91ee4a19bf8e04da07b933d42c8c4a535cfdd228c629` |
| `openstack-neutron-macvtap-agent-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-macvtap-agent-1:28.0.2-2.el10.noarch` | 12945 | `d386afa5000f2202094aac278079cbf3d466fc150296e68690e567e3a28eb331` | `b084018869a470ff191ef67ab46241b81061351e16dcd4d231e8d47642a795c8` | `3f1c92fd872b47b0929f1ef8623ac9185dd05a86f50660b91331d0e2cda78dc0` |
| `openstack-neutron-metering-agent-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-metering-agent-1:28.0.2-2.el10.noarch` | 16473 | `abb31239d6983d075c115a63167973e0a088802902c90365f094e64313866063` | `18a581ed1a5fc8c12a93779d90c87693843142eb1dce12dbae65a13152a177e9` | `62d4af8ef42786e164c38df868a281c9af11ceee4193809f6079f009b124e68a` |
| `openstack-neutron-ml2-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-ml2-1:28.0.2-2.el10.noarch` | 22579 | `fa231c48dd6132d680e25c59f4820ae47e01a21b3970131c1ad4b32ce061d2c0` | `b96f0f4b08fd6af12ab55ccc9d5c1c5d201f66f24651106906da9f2dcf64e602` | `a49af632c534fa486339097c1359e9f9b2ece279490a8210c6e9fd12c1ae3384` |
| `openstack-neutron-ml2ovn-trace-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-ml2ovn-trace-1:28.0.2-2.el10.noarch` | 11072 | `7be19c75b9c3b6ce7e223f8017098de9a0b258e591111f0f1f4057b7cf3c6750` | `8f807ff667b24c6b9b7b88d4bfbed1fd4375c5fce352185b0317efd83e4787d5` | `8ab64f3b99d52ff7efa262296a3ccba500fe28cc63bb2a3f74cc8e3ba0fa8f3e` |
| `openstack-neutron-openvswitch-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-openvswitch-1:28.0.2-2.el10.noarch` | 21384 | `e3004731a374638fd3ab9756c3d72d3e5f7fdc746f81a270973c5c26e6b1cd18` | `731148337b689a516fe62e2943c655dd6e945c18e3140acd8586860b4f7671e9` | `b54b9481a86fee5caba4c058b2a50b441d0ff1c47c973bff8d034719775d3a39` |
| `openstack-neutron-ovn-agent-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-ovn-agent-1:28.0.2-2.el10.noarch` | 19017 | `2fd33d37d7887558838bd53aa2774a572d4b3e0b92458ab6097d8bc7055eae3c` | `794b3ead84890f1d21500fdb037a3cf9d1a2d3023e76205f20a73cede7291f2f` | `a28b58950d4f0afda311a0663842aab1e56976d7d12af4c3768cb920bc47aab1` |
| `openstack-neutron-ovn-maintenance-worker-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-ovn-maintenance-worker-1:28.0.2-2.el10.noarch` | 12490 | `b3a11ca8bf31bdb83654eba180a92b8d879aad641c223644f1fe83b434dac82d` | `0dd83c773ec2326fceffd11d61a48b48ec0a7e09b9bfd144357e476cda6af017` | `94345425728e1a9038779b277828a105dea6be2a9f408eee4ca891778098969e` |
| `openstack-neutron-ovn-metadata-agent-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-ovn-metadata-agent-1:28.0.2-2.el10.noarch` | 17181 | `127c5dde5ddc00b72c02221db903e1349f7444fad71ef7ac0096e64037bd0150` | `9bad1c1aff55f47ba562cd17a31debcd0c3fb266c8f79fbc29d09fcb3f959f3b` | `157f78fde34f7ba82c7a382b3a3e2ef2713462d47dcfa6b6f93419d2409c8ace` |
| `openstack-neutron-periodic-workers-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-periodic-workers-1:28.0.2-2.el10.noarch` | 12400 | `aeb0cafa11562661e6f7cf8c03413039fc80482681acb68220c79d9a987f306b` | `ce2546dbfbc44b01ff32e97056a190b198daa8947be3bc89c5dd4e3e08366ebd` | `51ea43dff8153f4463c2e033d4811ce8bbda835b9f61de9f7930c3f7ecf8a6ab` |
| `openstack-neutron-rpc-server-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-rpc-server-1:28.0.2-2.el10.noarch` | 12049 | `6ce47f2f66e66a45894548bb535b1df88ee0c58801e9a34388d101ecb8eaec06` | `e4b9d386a8360df52c5e2d7e46d83560dd2e7653d45b711bfb437c08d9e66ca0` | `0f7b4ea5df916398c30b87cfcbc7032c2c9062db3bd009c9bcd977edca1cd644` |
| `openstack-neutron-sriov-nic-agent-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-sriov-nic-agent-1:28.0.2-2.el10.noarch` | 16282 | `968008aff843615ffbe7fa2e566489b3afad0003d5db5b061efe79587fa66941` | `c58b2e78500eb7b1adbf7eacf0dde3ec78de9d21bdaa3296ab70306aa3a4987f` | `3cf06e7ef973cae160f9274357c2a9ea00f462551e80c570b048b809c2fcc26a` |
| `python3-neutron-28.0.2-2.el10.noarch.rpm` | `python3-neutron-1:28.0.2-2.el10.noarch` | 3450576 | `8c4fa706826168bd651f8d54da48d5896f9bb6828a2cde159dfca6348b7c5c21` | `9ed28fc0f1ac9f09d93ea09c730b800f2a490fdb8a22a5e8418b7332aaf399b7` | `5accb128eccce6588bdf067ffc80fa1b9e1ef2a546b27828ea9f97dc96b18a6a` |
| `python3-neutron-tests-28.0.2-2.el10.noarch.rpm` | `python3-neutron-tests-1:28.0.2-2.el10.noarch` | 4332085 | `721a738fedfaff9b6f95ac14cf197248b4ff66dbf5905f412aa851d260e8b9fa` | `f570c946f61ba14c309bd49461b81eaa52f63b9d9a40c51cf292abea8c02fa15` | `a2c2e7b0b449db727161a9daa8f43d1c7676e4e0e0942c8cd0bf848a9d0f4a59` |


## E. Original artifact search

Locations checked (bounded, no whole-disk crawl): the original raw evidence directory, its `repo/served-repo-fix.tar` member list, the WP-A remediation directories, `~/rpmbuild`, and a `find` over `Codex/tmp` (excluding `.git` and `node_modules`) for `*.src.rpm`, `*.nosrc.rpm` and `*rpmbuild*.log`.

- `ORIGINAL SRPM: NOT RECOVERED`. There is no Neutron `.src.rpm` anywhere. The reason is structural: `build-rpms.sh` at `40472e8` runs only `rpmbuild -br` (line 328) and `rpmbuild -bb` (line 346); it never runs `-bs` or `-ba`, so the original build never emitted an SRPM. The binary RPMs' `SOURCERPM` header names a file that was never produced. The original builder VM and its disks were deleted.
- `ORIGINAL COMPLETE RPMBUILD LOG: NOT RECOVERED`. The only complete `neutron.rpmbuild.log` on disk is `hagistack-wpa-remediation-2026-09-30/raw/builder/neutron.rpmbuild.log`, SHA-256 `a55c43cb284d71045308d6836bfbcda809aa284466f34ed1915feffa852300b5`. It is a different build: it builds `openstack-neutron-28.0.2-1.el10` and has no `Patch0001`/`0001-Ensure` line. The recorded hash of the accepted build's log is `c3808f39…`, which does not match. The wrapper `build-neutron.log` is only a summary.

`ORIGINAL ARTIFACT PROVENANCE RECOVERABLE: NO`

## F. Path decision

PATH A fails on three of its own requirements: the original SRPM does not exist, no complete build log for the accepted build survives, and therefore the old binaries cannot be linked to an SRPM or a build. This is a gap in preserved evidence. Nothing shows a product inconsistency.

`PROVENANCE REMEDIATION PATH: B — CLEAN REBUILD`

---

## G. Why original provenance could not be recovered

See E. In one line: no SRPM was ever emitted (`-br`/`-bb` only), the log of the accepted build was not kept, and the builder is gone.

## H. Clean builder

| | |
|---|---|
| VM | `hgprov-builder`, n2-standard-8, 80 GB pd-balanced, `asia-northeast1-a`, label `purpose=hagistack-provenance-remediation` |
| image | `projects/rocky-linux-cloud/global/images/rocky-linux-10-v20260910` |
| OS / kernel / arch | Rocky Linux 10.2 (Red Quartz), `6.12.0-211.51.1.el10_2.x86_64`, x86_64 |
| repos | Rocky BaseOS/AppStream/CRB/Extras, EPEL 10, RDO `delorean.repo` `bdfd56e0e1c00eef294d924fa2a7651184894e1f9d5281342718b15cc28f7f2b` and `delorean-deps.repo` `cd8094d28984486b936da16c6b8973cb1fd645096cdf8b1334440b7dbf5fd8d9`; **all ten `/etc/yum.repos.d` file hashes equal the original builder's** (`builder-repofiles.sha256` of WP-A) |
| build tools | `git curl rpm-build rpmdevtools createrepo_c epel-release dnf-plugins-core tar` |
| environment record | `builder-env-before.txt` `41935ab806eb1bcc7409963b67e97bc241c7b53c1472e395ec48286b5931fbf7` (os-release, kernel, image, repos, dnf repolist, repomd hashes, tool versions); RPM list before build `builder-rpms-before-prep-build.txt` (543 packages); `build-env.lock` `458efca50780798ada1089f3c600c43ac3a12143eefa97825a602545e197c9b5` (758 packages) |
| base repository | the WP-A served repository `served-repo.tar` `5c8e82264c1ca18afa6f3352182221bee4779a49d0277649ed01dfbeaf6bbd4c`; all 196 files matched the WP-A per-file list; the 15 `neutron-28.0.2-1` RPMs were moved out (hashes in `removed-neutron-1.sha256`), leaving 181 |

## I. Candidate inputs

`git archive --prefix=hagistack/ 40472e8` regenerated locally: SHA-256 `2208303d5a2353adedaff788bc17fb9f681d0044e9b2767e10819a83f37cf3e9`, identical to the archive used in the original acceptance. Extracted on the builder (hashes checked there): `build-rpms.sh` `1ad25aa8…`, `gazpacho.manifest` `8c22a5bd…`, `neutron.patch` `d3755588…`, `hagistack` `082a4a8c…`, test `b8ae2d49…`. Pinned upstream inputs verified by the unchanged `build-rpms.sh`: distgit `fa1f5135e66282364250f2f5630a48423f497099`, `neutron-28.0.2.tar.gz` `cdaf45a2100de5233e4c1cc7c01c9df2b634510a0f0436913f73f29d42d325ee`, `%gpgverify` Good signature, key `0x30566c45…`.

## J. Complete build transcript

Steps run on the builder, each through `stage.sh` (exact command, PATH, start/end UTC, exit status, timestamped output plus a byte-exact `.raw` copy): setup, `--publish`, **the build**, copy of the 15 RPMs + `--publish` + `--lock`, freeze.

The build command, exit 0, `2026-09-30T12:21:57Z`–`12:24:47Z`:

```
cd /home/a0000/hagistack/rocky10.2 && REPO_PUBLISH_DIR=/opt/hagistack-repo ./build-rpms.sh --nocheck neutron
```

`build-rpms.sh` sends rpmbuild's own output to a log file, so the complete rpmbuild log is a second part of the transcript:

| File | SHA-256 |
|---|---|
| `build.transcript` (timestamped) | `8f123bb8d3a77c8cf0d1785a7cad40b71840cb8a905b9550b8519e1d2ee2504a` |
| `build.raw` (byte-exact stdout+stderr) | `d3b7438e8d072fed03232cad9b2ec4f04288b693bb761f0e592e34e96e48b448` |
| `neutron.rpmbuild.log` (26,086 lines) | `fa297077675730d1958b75a0cc32c239dfb8aa5f9a9d75d9371bc9d3b9cf2790` |
| `neutron.br.log`, `neutron.builddep.log` | `2d95407f8f0506201d93b6725ec2697a85b5fb6c8557efdf54d4d43af9030ca3`, `2ee939d5b13cc71ea7ee0d77d4eec22281b0c9a86b70235bbdd8f13bd2f46752` |
| `rpmbuild-bs.log` (the SRPM step) | `0d8568bf957c84b104eb0ddcff821b29888141845f208cd0d28f9e20734e679f` |
| `shim.log` | `a94cf150a1a546b6408ef354868699acc3ee3a6e41d3380b7102ff38ebc0e137` |

What the rpmbuild log shows: `%prep` with `gpgverify` Good signature; `git apply` "Applied patch … cleanly" for the three files of `0001-…` and the two files of `0002-…` (lines 35–44); `%generate_buildrequires`; `%build`; `%install`; 15 `Wrote:` lines; exit 0. `%check` was not run (`--nocheck`, as in the original).

**How the SRPM was obtained.** The unchanged `build-rpms.sh` never emits one. A transparent `rpmbuild` wrapper (`rpmbuild-shim`, `cdd9e7ba0c637f863bb737e5364754a346035b41f0c1508bae793842027cee74`, placed first in `PATH` on the builder, outside the product tree) passes `-br` through, and on the single `-bb` it (1) hashed `SPECS/` and `SOURCES/`, (2) ran `rpmbuild -bs` on that same spec, (3) copied the SRPM aside, (4) re-hashed, then (5) ran the real `rpmbuild -bb` unchanged. `build-rpms.sh` itself was not modified.

`COMPLETE RPMBUILD TRANSCRIPT CAPTURED: YES`

## K. New SRPM

| | |
|---|---|
| file | `openstack-neutron-28.0.2-2.el10.src.rpm`, 12,424,560 bytes |
| SHA-256 | `47f8cd8e7421b064fdf4ca4f15e5854917a92e01103a38cffd1bd5998f4a012c` |
| NEVRA | `openstack-neutron-1:28.0.2-2.el10.src` (arch noarch in the header query), SHA256HEADER `2f01f4956100441f04c3bff69bf84eb0a2e98435c737465f83bb92c08212a68c`, PAYLOADDIGEST `e40bb820f745b9275389d095a83d9a0a9214563e2f55135854edce8ee80d1a17` |
| `rpm -K` | digests OK (unsigned, as before) |
| frozen | at `2026-09-30T12:23:18Z` on the builder, before `-bb` finished; copied to the Mac and re-hashed; write-protected; **no target VM existed** (`FREEZE-BEFORE-DEPLOYMENT.txt` `4fcfc1975017595c1b36ee41cdc6164caee4c23d0c822a1264d2acf1cdbf5f4a`, written 12:31:19Z with zero `hgprov-*` VMs other than the builder) |

`NEW SRPM FROZEN BEFORE DEPLOYMENT: YES`

Independent audit on the Mac (extraction with `bsdtar`, not `rpm`):

- 29 members; the Mac and builder extractions have identical hashes.
- Tarball `cdaf45a2100de5233e4c1cc7c01c9df2b634510a0f0436913f73f29d42d325ee` = manifest pin. Patch files `0001-…` `4f981103be17689f9186776b5059c55bb33950dae47740fd52575be7849387e4` and `0002-…` `136ce37c86bf3ac8dd7f737b23c5e2b60bdb17326cac6876852ebc4bfb96d9cf`, equal to the values in the committed acceptance §4 and to the patch-file bytes created by applying `git show 40472e8:…/neutron.patch` to a fresh clone of distgit `fa1f5135`.
- Spec: SRPM spec `ad1584f0be1a162d63d318f629a10d76c15e656d8a7216c543ba4f64e14dd72f` is **byte-identical** to (distgit `fa1f5135` + candidate `neutron.patch` + the four documented `build-rpms.sh` substitutions: Version `28.0.2`, Release `2%{?dist}`, `sources_gpg_sign` key, `%autosetup -n neutron-28.0.2`). Version 28.0.2, Release 2, exactly `Patch0001` and `Patch0002`, no other `Patch` line.
- Both patches apply cleanly to a pristine 28.0.2 tree.
- 24 of the other 25 members equal the distgit tree byte for byte. No `c695003d`, no `tag_request`/`a8feb94e`: the only semantic source patches are the two above.
- SRPM member hashes equal the pre-build `SPECS`/`SOURCES` hashes taken by the wrapper (`inputs-before-bs.sha256` = `inputs-after-bs.sha256`).

**One recorded exception.** `neutron-destroy-patch-ports.service` in the SRPM differs from distgit: `ExecStart=/usr/bin/python333` instead of `/usr/bin/python`. The spec's `%prep` runs `sed -i 's/\/usr\/bin\/python/\/usr\/bin\/python3/'` on that file in `SOURCES/` in place, and the unchanged `build-rpms.sh` runs `%prep` three times through `rpmbuild -br` before `-bb`. The SRPM was made after the third pass (`python333`); the `-bb` pass made it `python3333` (`inputs-after-bb.sha256` differs from `inputs-before-bs.sha256` in that one line only). All three builds carry the same `python3333` in `openstack-neutron-openvswitch` (checked in the old `-1`, the old `-2` and the new `-2`). This is a build-process side effect, not a candidate change, and it does not touch the maintenance-lock path. It means the SRPM is not the pristine distgit tree, and rebuilding from it would give `python33333`. Recorded, not fixed (F13b family).

`NEW SRPM MATCHES CANDIDATE INPUTS: YES` (with the exception above)

## L. New binary RPM inventory (NEW set)

All 15: Epoch 1, Version 28.0.2, Release 2.el10, noarch, SOURCERPM `openstack-neutron-28.0.2-2.el10.src.rpm`, `rpm -K` digests OK, frozen on the Mac before any target VM. Header values from `rpm -qp` on the builder; the same header and payload digests were re-read by `rpm -qa` on two other hosts (section O).

| File | NEVRA | Size | SHA-256 | SHA256HEADER | PAYLOADDIGEST |
|---|---|---|---|---|---|
| `openstack-neutron-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-1:28.0.2-2.el10.noarch` | 32659 | `e5761d6a6b4998140b521aa9ea1b570e6ee5c04ca1a1ff0e832222e6846581d3` | `8b2353bd9a435c8462dba9f585c59b4784527cce638caad12b85c2e1f4df2c8a` | `00a8bbe5e8066d28103bae667e77c18b05ec6de3ca3ac77fc467a006af264989` |
| `openstack-neutron-common-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-common-1:28.0.2-2.el10.noarch` | 156655 | `83472f0e8a73f1d8b811518a01f5d69fc1332ff64fc077a12bfaf992aa7bcc93` | `e4b2213e12493d0fa22b65f2110832dda7559626701435d19b92af7b3431dd6e` | `1bb44f09d212b58f6617dfa9c161f8b33ef63159a21e012b32f1f4669672a73c` |
| `openstack-neutron-macvtap-agent-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-macvtap-agent-1:28.0.2-2.el10.noarch` | 12955 | `5a6d567cace934d819b19b6d6d2585092d1fc1e8658ed9b6946b0ec1157d500a` | `7def88870d8afaba62de91a0e142e4a46fd07b71ff103dec762fbcb6de58c1c1` | `d489e81de288e10e8c0d5d90b71635e52bdbab3a99aded1ffe4293e3e4666374` |
| `openstack-neutron-metering-agent-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-metering-agent-1:28.0.2-2.el10.noarch` | 16476 | `f11b5b01bb772d93c97ec18f35eb344ea48ecdda9aff9f0dd60bdbb5c56a3a1d` | `5060645129aefa1cdd2e5d67ba9dea367468f3f5b30a04a76f5049ea80324742` | `f86c0a87d2c39c45d36a3b01c0d0cfe1f4f5913092eec4abd710491b19f04810` |
| `openstack-neutron-ml2-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-ml2-1:28.0.2-2.el10.noarch` | 22584 | `282c938f9f503ed33bb9ce2c3b7d2979d09229111af3049ec1251869e32385d5` | `71f9fb4fcc7ce73971e7840cba695f85b4b609678a1230f408ce9e28b88eb4ea` | `303421595af5e239020eecb624bd05d6ce631508cab04e9f1cddd049de184b9b` |
| `openstack-neutron-ml2ovn-trace-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-ml2ovn-trace-1:28.0.2-2.el10.noarch` | 11075 | `344bbeaec6f3bb8f5f18e61848608f502f32f8b1747072e0a8e981028b297d07` | `ca08985cfc3397d698402a2268a1d15a0dbb7fd5558d0d71f0b1dd009b050a9b` | `597ee3f96485302ee8b163fc7bb172900cd8b793478755c8655383cb0bf97125` |
| `openstack-neutron-openvswitch-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-openvswitch-1:28.0.2-2.el10.noarch` | 21394 | `db193750395c8c47d1e87ba3f431e448353e34c620b00c835dd2566144a97898` | `a3e4d8306fface0cafe484ecebf7e3d2ff1e5d7bb5f49d26736fedda554491ef` | `64ba24954131d8b65763042aca8ce38a24e6fc426d70b34bed8a9dbe3ac9256d` |
| `openstack-neutron-ovn-agent-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-ovn-agent-1:28.0.2-2.el10.noarch` | 19030 | `1284fada0975f88f7ebefcf6b7a765d1825697c2a5501c31c9c848cce7b26a5e` | `74d51627f56724c470e85cc5a9dcf5a3eada375b873bdfe08045d7820b539dd8` | `c09c6f68fcb82129240ee25d2c69d6d8dfa844037968935c0eb8c0b5ed96acc9` |
| `openstack-neutron-ovn-maintenance-worker-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-ovn-maintenance-worker-1:28.0.2-2.el10.noarch` | 12499 | `e0012bdd042228118289e2426577bac456d99efa0b7cd37af894c2553140e4ac` | `838756770805abcf16cd9167f6f9b0b57024028845bfdbf1df71e66ca1dde332` | `e5fb1d8e78162008be2b5fca239d2dd1dd7e0f2e0dc374b816eb7190bee8110f` |
| `openstack-neutron-ovn-metadata-agent-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-ovn-metadata-agent-1:28.0.2-2.el10.noarch` | 17193 | `e6df9ba5ade1eb9c94aec4ec93bdbc7737e047dbe760f1d721f7b952ce226aff` | `9f05afab9e5186a524b4968ac3bd4d64b319df326f0baf93e72edb5503ce7225` | `9ffc921fd6e9c773e2aac0ddd80db10b40b3e9225bb7e4ae165f2a8685a5764b` |
| `openstack-neutron-periodic-workers-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-periodic-workers-1:28.0.2-2.el10.noarch` | 12404 | `691b4f97460fe366823e97d72b45bd846cb2a783c327f067f8c0d4771aee9f24` | `1b82bd5609168057af122ba306f6222125b41d8f39062704370a6ad7efd56081` | `5ae699ede67f401d77f82813aaa9f521ae229921fcd287ae113b0cd4c801e61f` |
| `openstack-neutron-rpc-server-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-rpc-server-1:28.0.2-2.el10.noarch` | 12055 | `08cd4918bf94d500761d95e5ce27f215456255fc22cb0ebfaed902148c0e4f01` | `763138e2002a42269318abef68f40b1e9a49bb73baaffbd5fe24632a44fb908d` | `3ec401bb526583e119e821466848d71f18b4f680ff8f7e7217cc3b4a87939cdb` |
| `openstack-neutron-sriov-nic-agent-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-sriov-nic-agent-1:28.0.2-2.el10.noarch` | 16291 | `589142edad6fc34b93597810406c5d3f52ba65c360e2a694f073eca573ea6c81` | `9df96131aa6ac2057977fbb5ce0b6fe4e2da32447dafd35d34d9074871bcdfe6` | `a5da44d67cf4b1957355cde12240a918d89ab8ee70317ba1b768d9f649d6d0e0` |
| `python3-neutron-28.0.2-2.el10.noarch.rpm` | `python3-neutron-1:28.0.2-2.el10.noarch` | 3450580 | `1afd65940e98a29c2fb7c74b6daaa2a54185c9a80a1de7362e63c04228a94307` | `b06a3b71f3b8a85a2cb6913df42881b6ea2a12be9d7faf8d76b444139658bace` | `7b8d4ee0b653f076e54058113a12247689524221c5210a7f7fdeb1fcc80e00e9` |
| `python3-neutron-tests-28.0.2-2.el10.noarch.rpm` | `python3-neutron-tests-1:28.0.2-2.el10.noarch` | 4331861 | `d2edd6da8722f5ae6dd4c186bb7d93b31ba7ec10f9c5a0ded87bf2ef23485aaa` | `3d2059e33188a2d0107c5584a27e8c9d0105fa96e6ecb302bef4dc9391497750` | `c3d713004ae7c8fcf888124bff7852624469663cdb1ec5c25fda30d80d528c69` |


## M. RPM source-content verification

For the four patched files, SHA-256 is identical in all four places: the tarball + the SRPM's two patches (applied on the Mac), the file inside the new `python3-neutron` RPM (extracted with `bsdtar`), the upstream cherry-pick pair (`83f1d830` + `91abb5e7` on `28.0.2`, from the original evidence worktree; its commits carry the `(cherry picked from …)` lines), and the original evidence's `expected-patched-files.sha256`:

| File | SHA-256 |
|---|---|
| `neutron/common/ovn/constants.py` | `9083ce4a0a00d6dd8fdbfb3f555590bcb5e5694c9df347e749651ee789dbd675` |
| `neutron/plugins/ml2/drivers/ovn/mech_driver/mech_driver.py` | `d0dda5739ceca47561a0a7b7e90f7b35610fe08ffcbc36faac16d2fc10ca9d48` |
| `neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/impl_idl_ovn.py` | `06d9c453ab6f83efa81069b5cef9beae8345867ab31cbd1e302de362cd35d9ae` |
| `neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/maintenance.py` | `d3e16686e6cb625c2464498ed780a334cba87b540e304af83cbc13f439081cb0` |

(These equal the values of the old build, because they are source files; that is the expected result, not a link between the two RPM sets.)

Across every `.py` under `neutron/` that also exists in the tarball, the RPM differs from tarball + patches in exactly two files, each by its removed `#!/usr/bin/env python3` first line (`cmd/destroy_patch_ports.py`, `cmd/ovn/migration_mtu.py`), plus the absent `hacking/checks.py`. All three are the distgit `%prep`.

RPC-worker behavior in the RPM bytes: `impl_idl_ovn.py:249` `idl_.set_lock(worker_class.lock_name)` under `except AttributeError`; `mech_driver.py:431` sets `lock_name` only on `MaintenanceWorker`. `c695003d` is absent: `has_lock` is still `return not self._idl.is_lock_contended`, and no `fix-ovn-lock-check-is-lock-contended` release note is in the payload.

`NEW RPM PATCHED FILES MATCH UPSTREAM PAIR: YES`

## N. Frozen validation repository

| | |
|---|---|
| files | 196 RPMs; bundle `hagistack-repo-prov.tar` `54cdb9bcf1fc2057d4bfb5036ca8bf5cc27db08125ea09c2f21e83cdc325c13e` (sorted, owner 0, fixed mtime) |
| `repodata/repomd.xml` | `cd0990867f8100b0205667a9d2f828f736a3dc64fb5de38391dcfa3562ee240a` |
| repodata | `primary` `3e2543e81225f9ccf6c72b8d5436aa1503d247a4fbffdc919bdb5c7af7c556f6`, `filelists` `4c986a0f5236a3d16d2f64c4c2e585ac9f84621c1eb34076fac829c68680dc54`, `other` `7b0717385f316e21006027b65de6f24de00d8436a94096d0abbe47bfa6907893` |
| per-file list | `repo-files.sha256` `49e2a05a646ba306bfe89123dad54d9ed9e8dfc0842c04f67425c3e52fd3cab2`; TSV inventory `repo-inventory.tsv` `99246837ee139c569d86cd1a512b8b34d541330f5679f364556f6cedf78fb0ae` |
| composition | 181 files byte-identical to the WP-A served repository; the 15 `-1` Neutron RPMs absent; the 15 new `-2` RPMs present and equal to the frozen set |
| cliff | not changed. The base is the WP-A repository, which omits the defective self-built `python3-cliff-4.13.3-1.el10` (only `python3-cliff-tests` is in the repo); `python3-cliff-4.13.3-1.el10_2` came from EPEL on both nodes (`from_repo=epel`) |

`NEW VALIDATION REPOSITORY FROZEN: YES`

`NEW RPM INVENTORY FROZEN BEFORE DEPLOYMENT: YES`

## O. Deployed identity

| Host | Role | Before any run |
|---|---|---|
| `hgprov-rocky1` | all-in-one; n2-standard-4, nested KVM, 60 GB, same image | candidate tar `2208303d…`; `rocky10.2/hagistack` `082a4a8c…`; test `b8ae2d49…`; bundle `54cdb9bc…`; 196/196 RPMs `sha256sum -c` OK against the frozen list; `repomd.xml` `cd099086…`; 0 OpenStack packages installed |
| `hgprov-rocky2` | compute-add; n2-standard-2, nested KVM, 40 GB, same image | same values |

`rocky10.2/hagistack` = `082a4a8c3879fedd1b0db262cea83fa39c63d7e4edba2536959f1e58c453e170` = Git object `40472e8:rocky10.2/hagistack`, on both nodes before the run, and again on rocky1 before the rerun and at the end.

Installed packages whose `dnf from_repo` is `hagistack-gazpacho`, matched to the **frozen inventory by NEVRA with equal SHA256HEADER and PAYLOADDIGEST**:

| Node | Installed from the repo | Match | Mismatch / missing |
|---|---|---|---|
| hgprov-rocky1 (after install, and again at the end) | 104 | 104 | 0 |
| hgprov-rocky2 | 70 | 70 | 0 |

Installed Neutron packages on rocky1 (8): `openstack-neutron`, `-common`, `-ml2`, `-ovn-maintenance-worker`, `-ovn-metadata-agent`, `-periodic-workers`, `-rpc-server`, `python3-neutron`, each `1:28.0.2-2.el10`, each tied to a row of the new inventory (file SHA-256 shown by `ident.py`). `rpm -V` shows only Hagistack's own edits to `%config` files (`neutron.conf`, `neutron_ovn_metadata_agent.ini`); no shipped file differs.

`NEW DEPLOYED HAGISTACK MATCHES 40472e8: YES`

`NEW DEPLOYED NEUTRON RPMS MATCH NEW INVENTORY: YES`

## P. Focused runtime validation (`hgprov-rocky1` / `hgprov-rocky2`)

| # | Check | Result |
|---|---|---|
| 1 | deterministic regression, patched (`python3-neutron-28.0.2-2` installed) | 3/3 starts `idl.has_lock=True`, not stuck, NB write ok; RpcWorker `lock_name=None has_lock=False`; handover correct. **PASS, exit 0** |
| 2 | negative control, unpatched 28.0.2 source (tarball `cdaf45a2…`) | 3/3 stuck, NB write fails with OVSDB NOT_LOCKED; handover broken. **FAIL, exit 1** (the test detects the defect) |
| 3 | RPC workers request the maintenance lock | **NO.** 8 RPC-worker NB sessions (2 at install, 3 × `systemctl restart neutron-rpc-server`): 0 lock messages |
| 4 | lock handover, two maintenance workers | correct (test output above) |
| 5 | exact new RPMs on real Rocky | section O |
| 6 | both worker units | enabled and active, NRestarts 0 |
| 7 | NOT_LOCKED | **0** in the whole maintenance log |
| 8 | lock-guarded task | 23 tasks finished, 0 failed, 3 guarded tasks finished after install |
| 9 | Neutron API | `GET /` 200, `GET /v2.0/networks` with token 200 (after install, at the end) |
| 10 | agents | OVN Controller Gateway + Metadata on rocky1, OVN Controller + Metadata on rocky2, all alive; both nova-compute up |
| 11–12 | guests | `wpa-g1` on rocky1 ACTIVE in 19 s, `wpa-g2` on rocky2 ACTIVE in 17 s |
| 13 | metadata | both consoles `successful after 1/20 tries`, then `login:` |
| 14 | cross-node ping | inside g1 to g2, 30/30, 0 % loss |
| 15 | Geneve | capture on the controller NIC: 64 packets, 30 inner echo requests, 30 inner echo replies |
| 16 | rerun | section R |
| 17 | repeated starts | section Q |

Both nodes: install exit 0 (all-in-one 12:34:22Z–12:46:04Z; compute-add exit 0, `discover-hosts` mapped rocky2). Error counts after install: ERROR 0 / Traceback 0 in all four Neutron logs.

Observed after the reboot, not caused by the lock: `rpc-server.log` shows 6 `impl_rabbit` "Connection refused (retrying …)" lines at 13:20:46–48. rpc-server started before RabbitMQ was up and retried until it connected; 0 tracebacks. Also `wpa-g1` was `SHUTOFF` after the reboot (no guest resume) — not investigated, not related to F-NEW-1.

## Q. Repeated starts

Only the maintenance worker's starts are counted. **32 starts, 0 F-NEW-1.**

| Path | Starts | Active | NOT_LOCKED > 0 | Failed tasks | Guarded task finished |
|---|---|---|---|---|---|
| Hagistack install (first start) | 1 | 1 | 0 | 0 | yes |
| `systemctl restart` | 20 | 20 | 0 | 0 | 20/20 |
| `systemctl stop` → `start` | 10 | 10 | 0 | 0 | 10/10 |
| reboot (systemd at boot, no Hagistack) | 1 | 1 | 0 | 0 | yes (3 guarded tasks) |

Wire evidence over the first 31 (passive `tcpdump -Z root -i lo tcp port 6641` plus a passive `ss` sampler; `wire-all.tsv`): 106 NB sessions in total; 31 maintenance-worker sessions each sent **exactly one** `lock` request, 0.67–0.93 ms after connecting, all granted; no other session sent any lock message. The reboot start was not captured (the transient capture does not survive a reboot); it is judged from its log tree. No `ovsdb-client lock`, waiter or nudge was used.

Limits: this detects an obvious regression. It is not a probability claim, and the old 42-start campaign is corroboration only for the old bytes. The first capture unit failed at 12:34:22Z (tcpdump could not chown its savefile) and was restarted at about 12:35Z with `-Z root`, while packages were still installing and before any Neutron service existed.

## R. Idempotency

Second `all-in-one` with the same options and the same `hagistack` (`082a4a8c…`): exit **0**, 0 restart lines, 0 skipped phases. The before and after snapshots (`snap.sh`) are identical apart from their timestamp line: unit `ActiveEnterTimestamp`/`MainPID` for all 11 units, Neutron package NEVRA, SHA256HEADER and INSTALLTIME (no reinstall), dnf transaction count (6), and the hashes of `neutron.conf`, `ml2_conf.ini`, `neutron_ovn_metadata_agent.ini` and `plugin.ini`. API 200 and all agents alive afterwards.

`NEW ARTIFACT RERUN IDEMPOTENCY: PASS`

## S. Chain

| Arrow | Evidence |
|---|---|
| `40472e8` Git objects → candidate bytes | `git archive` `2208303d…` reproduces the original archive; file hashes in section I |
| candidate bytes + pinned distgit → spec and patches | SRPM spec byte-identical to the independently derived expected spec; patch files equal |
| → complete build transcript | `build.transcript`, `build.raw`, `neutron.rpmbuild.log`, `shim.log` |
| → frozen SRPM | `47f8cd8e7421b064fdf4ca4f15e5854917a92e01103a38cffd1bd5998f4a012c`; SPECS/SOURCES hashes before and after `-bs` identical |
| SRPM → frozen 15 binary RPMs | built from the same staged tree in the same run; `SOURCERPM` header names the SRPM; the only tree difference after `-bb` is the documented `%prep` sed on one service file; four patched files equal upstream pair |
| → frozen repository | 196 files, repomd `cd099086…`, 15 new = frozen set |
| → deployed package identity | 104/104 and 70/70 by SHA256HEADER + PAYLOADDIGEST on hosts other than the builder |
| → runtime validation | sections P–R |

Not claimed: that the binary RPMs were mechanically derived from the frozen SRPM file itself (the SRPM was produced by `-bs` from the identical staged tree immediately before `-bb`, not by rebuilding from it), and no reproducible build. Only one build was made. `pbr.json` and the commented `my_ip` default in the generated `neutron.conf` remain build-variable, as in the old evidence; F13b stays deferred. The new RPMs differ from the old ones in every SHA-256 (0 of 15 equal), as expected.

`NEW ARTIFACT PROVENANCE CHAIN: COMPLETE`

---

## T. Deferred items

`F13b: DEFERRED`

`CLIFF: UNCHANGED / DEFERRED`

`O-A: DEFERRED`

`TAG_REQUEST FINDING: DEFERRED`

`UBUNTU F-NEW-1: UNFIXED / HOLD`

## U. Cloud cleanup

Baseline before creation: 11 instances (all TERMINATED), 11 disks, 94 snapshots (md5 recorded), 6 firewall rules, 1 address. Created: `hgprov-builder` (deleted 12:31Z after everything was copied and re-hashed), `hgprov-rocky1`, `hgprov-rocky2` (deleted 13:25Z, `--delete-disks=all`). Final check: 0 `hgprov-*` instances, 0 `hgprov-*` disks, snapshots, firewall rules and addresses identical to the baseline. Remediation created no snapshot, firewall rule or address.

Unrelated external change, not touched and not owned: `mikagami-validation` and `sinter-rc111-hv1` were TERMINATED in my baseline and RUNNING at the final check.

## V. Git / mutation final check

- `40472e8` and `2077950` unchanged; HEAD still `207795084855e0fa7e3bce7124d4f0440408cfd4`.
- No product, Ubuntu, `build-rpms.sh`, manifest, patch, test or README change; nothing staged; no commit, push, PR, tag or release.
- The old acceptance report, the independent audit report and the old raw evidence directory were not modified.
- This report is untracked and unstaged.

`RPM PROVENANCE REMEDIATION PRODUCT MUTATIONS: ZERO`

## W. Recheck readiness

`RPM PROVENANCE EVIDENCE: READY FOR INDEPENDENT RECHECK`

This is not an audit PASS. WP-A remains on hold.

ROCKY F-NEW-1 ROOT FIX: AWAITING INDEPENDENT RECHECK
UBUNTU WP-A STATUS: HOLD
WP-A MERGE: HOLD
HAGISTACK ROCKY RPM PROVENANCE REMEDIATION: COMPLETE
