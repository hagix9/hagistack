# F-NEW-1 Rocky root fix: acceptance evidence

Recorded 2026-09-30 on Google Compute Engine. The evidence for product commit
`40472e879bf55d66fb4f3ecb719d67fb180567d6`, which carries the upstream Neutron
fix for the OVN maintenance-worker lock race (F-NEW-1) in the Rocky build.
**Ubuntu is out of scope and unchanged. Ubuntu WP-A remains on hold.**

The GCP project id, external addresses, the account and credentials are not
recorded. The compute-node credentials were piped from controller to compute
node and only their key names were checked.

---

## 1. Results

| Item | Result |
|---|---|
| Upstream commits carried | `83f1d8305651a0ab23629c88d70bfa237055158c` + `91abb5e720e1c515dbfbe9b2313fbdff92b2abbf`, together |
| ROCKY BACKPORT MATCHES MINIMAL UPSTREAM FIX | **YES**: the four patched files inside `python3-neutron-28.0.2-2` are byte-identical to 28.0.2 + the two commits |
| OPTIONAL HAS_LOCK COMMIT INCLUDED | **NO** (`c695003d` absent) |
| Neutron RPM release | 1 → **2** (`1:28.0.2-2.el10`); no other package rebuilt |
| Dependency upgrade | none |
| F-NEW-1 REGRESSION NEGATIVE CONTROL | **PASS**: unpatched 3/3 stuck, exit 1; patched 0/3, exit 0 |
| RPC WORKERS REQUEST MAINTENANCE LOCK | **NO**: 8 RPC NB sessions on the wire, 0 lock messages |
| Lock handover (two maintenance workers) | correct |
| ROCKY INSTALLED NEUTRON RPMS MATCH INVENTORY | **YES**: 104/104 (controller), 70/70 (compute) by header and payload digest |
| Rocky deployed `rocky10.2/hagistack` = candidate | yes, both nodes (`082a4a8c…`) |
| Real two-node acceptance | pass |
| Maintenance-worker starts on the patched build | 42 (install, 30 restart, 10 stop/start, 1 reboot): **0 F-NEW-1**; the 41 captured starts all got the lock on the wire |
| Hagistack rerun | exit 0; nothing changed, nothing restarted |
| UBUNTU PRODUCT CHANGES | **ZERO** |

---

## 2. Upstream patch identity

Repository `https://opendev.org/openstack/neutron`, re-fetched 2026-09-30.

| Commit | Author, date | Subject | Change-Id | Bug |
|---|---|---|---|---|
| `83f1d8305651a0ab23629c88d70bfa237055158c` | Terry Wilson, 2026-06-09 | Ensure MaintenanceWorker lock set before connect | `Iaefe1e2cc86ddd55c9053fde66353b2a333e1e98` | Related-Bug #2155155 |
| `91abb5e720e1c515dbfbe9b2313fbdff92b2abbf` | Terry Wilson, 2026-06-17 | Only set the maintenance worker lock on the worker | `I74145ef1407856b7ec75de87daa2270b452b6c70` | Closes-Bug #2156979 |

Both are on master and stable/2026.2; neither is on stable/2026.1 (no commit
with either Change-Id).

**Why both.** `83f1d830` calls `set_lock()` in
`OvsdbNbOvnIdl.from_worker()` before the connection starts. In 28.0.2 that
branch is `if worker_class in (worker.MaintenanceWorker, n_service.RpcWorker)`,
because the 2026.1 backport of "rpc/ovn: Use base OVN IDL for RPC workers" put
RPC workers there. Cherry-picked alone onto `28.0.2`, it produces
`idl_.set_lock(ovn_const.MAINTENANCE_NB_IDL_LOCK_NAME)` in that shared branch
(re-verified): the RPC workers would request the maintenance lock. `91abb5e7`
changes the call to `set_lock(worker_class.lock_name)` under
`except AttributeError`, and sets `MaintenanceWorker.lock_name` only in
`post_fork_initialize` of the real maintenance worker. `RpcWorker` has no
`lock_name`.

## 3. Rocky source base (unchanged pins)

| | Value |
|---|---|
| Neutron | 28.0.2, `neutron-28.0.2.tar.gz` SHA-256 `cdaf45a2100de5233e4c1cc7c01c9df2b634510a0f0436913f73f29d42d325ee` (verified by `build-rpms.sh`; `%gpgverify`: Good signature, key `0x30566c45…`) |
| distgit | `rdo-packages/neutron-distgit` `fa1f5135e66282364250f2f5630a48423f497099` (verified) |
| release before / after | 1 / **2** |
| spec | `%autosetup -n %{service}-%{upstream_version} -S git`; no `Patch` lines upstream |

## 4. Implementation (product commit `40472e8`)

| Path | Change | SHA-256 at `40472e8` |
|---|---|---|
| `rocky10.2/spec-patches/neutron.patch` | description section; spec hunk declaring `Patch0001`/`Patch0002` after the `Source` block; the two `%files` hunks unchanged (new-side line numbers shift by 6); two new-file diffs creating the patch files in the distgit tree | `d3755588c744d756218e5b673dff1a33aa943000769c31b373ffd91d58073098` |
| `rocky10.2/gazpacho.manifest` | neutron row, release column `1` → `2` (one token; line length unchanged) | `8c22a5bdc7d4302a0084f661b9c09b68d9d47b21dc99be2b64ecb700de813538` |
| `rocky10.2/tests-neutron-maintenance-lock.py` | new deterministic regression test (§9) | `b8ae2d4997feffb8c887e59b07617bad060e2ce4aec98ce1ad6a60c7bee89793` |
| `rocky10.2/README.md`, `rocky10.2/README.ja.md` | one bullet each: Neutron is the exception to "the released tarball, unchanged"; release 2; the test | `871a927d…0030`, `c17a71ac…ab43` |

Unchanged: `rocky10.2/hagistack` (`082a4a8c3879fedd1b0db262cea83fa39c63d7e4edba2536959f1e58c453e170`),
`rocky10.2/build-rpms.sh` (`1ad25aa8…2754`), all other spec patches,
everything under `ubuntu26.04/`, top-level READMEs.

The two carried patch files are `git format-patch --zero-commit --no-signature`
output of the upstream commits cherry-picked (`-x`) onto tag `28.0.2`. Each keeps
the upstream author, date, message, Change-Id and a
`(cherry picked from commit <upstream SHA>)` line:

| File (created by `neutron.patch`) | SHA-256 |
|---|---|
| `0001-Ensure-MaintenanceWorker-lock-set-before-connect.patch` | `4f981103be17689f9186776b5059c55bb33950dae47740fd52575be7849387e4` |
| `0002-Only-set-the-maintenance-worker-lock-on-the-worker.patch` | `136ce37c86bf3ac8dd7f737b23c5e2b60bdb17326cac6876852ebc4bfb96d9cf` |

Regeneration is byte-identical (`--zero-commit`). Their combined source diff
against 28.0.2 has SHA-256 `8f8c85dcf69a5a0262ac54d7f9676c22899903e06bac9ad3b8326868a294ce7d`,
the same value the feasibility research recorded.

## 5. Patch equivalence

- `neutron.patch` applied to a pristine `fa1f5135` tree (BSD `patch`
  locally, GNU `patch` on the builder, both `--dry-run` first): the created
  patch files and spec are byte-identical to the intended ones.
- The two patch files applied with `git apply` to the 28.0.2 tarball tree: the
  four resulting files are byte-identical to `28.0.2` + `83f1d830` + `91abb5e7`
  from the upstream cherry-pick.
- In the built RPM (§7): the same four files, extracted from
  `python3-neutron-28.0.2-2.el10`, have exactly these SHA-256:

| File | SHA-256 |
|---|---|
| `neutron/common/ovn/constants.py` | `9083ce4a0a00d6dd8fdbfb3f555590bcb5e5694c9df347e749651ee789dbd675` |
| `neutron/plugins/ml2/drivers/ovn/mech_driver/mech_driver.py` | `d0dda5739ceca47561a0a7b7e90f7b35610fe08ffcbc36faac16d2fc10ca9d48` |
| `neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/impl_idl_ovn.py` | `06d9c453ab6f83efa81069b5cef9beae8345867ab31cbd1e302de362cd35d9ae` |
| `neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/maintenance.py` | `d3e16686e6cb625c2464498ed780a334cba87b540e304af83cbc13f439081cb0` |

**ROCKY BACKPORT MATCHES MINIMAL UPSTREAM FIX: YES**

**c695003d exclusion.** In the built RPM, `DBInconsistenciesPeriodics.has_lock`
is still `return not self._idl.is_lock_contended`. `services/bgp/reconciler.py`
still uses `is_lock_contended`, and there is no
`fix-ovn-lock-check-is-lock-contended` release note. `c695003d` is defensive
lock-state correctness. It is not needed to remove the race, which the
research and §9 show, and it is not part of the minimal fix.

**OPTIONAL HAS_LOCK COMMIT INCLUDED: NO**

## 6. Build

| | Value |
|---|---|
| builder | `hgrf-builder`, n2-standard-8, `rocky-linux-10-v20260910`, Rocky Linux 10.2, kernel 6.12.0-211.51.1.el10_2 |
| candidate | `git archive --prefix=hagistack/ 40472e8`, SHA-256 `2208303d5a2353adedaff788bc17fb9f681d0044e9b2767e10819a83f37cf3e9`; on the builder `build-rpms.sh` `1ad25aa8…`, manifest `8c22a5bd…`, `neutron.patch` `d3755588…` |
| builder repos | BaseOS/AppStream/CRB/Extras, EPEL 10, RDO `delorean.repo` (`bdfd56e0…`) and `delorean-deps.repo` (`cd8094d2…`), byte-identical to the WP-A builder files |
| base repository | the WP-A served repository, `served-repo.tar` `5c8e8226…`, all 196 files checked against its per-file list |
| steps | 1. moved the 15 `*neutron*-28.0.2-1.el10` RPMs out of the base repository (hashes recorded); 2. `REPO_PUBLISH_DIR=/opt/hagistack-repo ./build-rpms.sh --publish`; 3. `REPO_PUBLISH_DIR=/opt/hagistack-repo ./build-rpms.sh --nocheck neutron` (README "named packages" form); 4. copied the 15 `28.0.2-2` RPMs into the repository; 5. `--publish` again; `--lock` |
| result | exit 0; `applied spec-patches/neutron.patch (5 hunk(s))`; `spec version set to 28.0.2-2`; `spec + 28 distgit source files staged`; `%prep`: `git apply` "Applied patch … cleanly" for every file of 0001 and 0002; PASS neutron (`%check` NOT run) |
| logs | build log `build-neutron.log`; rpmbuild log SHA-256 `c3808f3954ed4957d2815dad48f0ee5331770cdb8cbf65711e621260617634d2`; `build-env.lock` `fa06a3a03788b389b5d8c102132b959073c360bc1670f29894b10f6ee2b6294d` |

**F13b.** It did not arise: only neutron was built, in one pass, because its
2026.1 build dependencies were already in the base repository. Nothing about
the build process was changed. RPMs remain unsigned (`rpm -K`: digests OK), as
before.

## 7. RPM artifacts

Final served repository, frozen before any node was created: 196 files,
`repodata/repomd.xml` `0f31249ae507fb5ea65d1f9558a672e5d93cf1a90518f1fccc52bdb95872d5f9`,
per-file list `d9bca70c4d62ff5ef79162ad681a99a84273a957487c2abd16f9b4a59c94e2d3`,
full inventory (TSV) `c745154b881409d4bb0f0f1f29be78905e0e7099c2ac57a3a71d0c2b81c9723a`,
tarball `served-repo-fix.tar` `06e94f29fab8afa21bffe956688f52eca243c9f9d9b08031c2c1d09c4cfff02b`.

- **181 files** are byte-identical to the WP-A served repository.
- **15 files** are the new Neutron RPMs, all from
  `openstack-neutron-28.0.2-2.el10.src.rpm`.
- No `28.0.2-1` Neutron file remains, so there was no choice of older build.

| File | NEVRA | Size | SHA-256 | SHA256HEADER | PAYLOADDIGEST |
|---|---|---|---|---|---|
| `noarch/openstack-neutron-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-1:28.0.2-2.el10.noarch` | 32650 | `2c162ce8db70f44b7d8a4d1118898cf1bfb24993b804bd78ae61acf6c9397972` | `43eac96b4de5034dd6af2fb28cbf1f029fc816052831f27685a6de876986b92d` | `4cee54070fa619d67c7698ae465fd48dbb3f1ad705d58eee1a321689b514c810` |
| `noarch/openstack-neutron-common-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-common-1:28.0.2-2.el10.noarch` | 156522 | `a89c63ee0603f6805574b07881351d708252e0b3fd77475af43f41295fb91b6a` | `cac9fb36b4cf2c967dd7984d04b34d305c2bb7e1dcd132aebe70a022e3fb4e38` | `1e33d8a74fc3e071094f91ee4a19bf8e04da07b933d42c8c4a535cfdd228c629` |
| `noarch/openstack-neutron-macvtap-agent-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-macvtap-agent-1:28.0.2-2.el10.noarch` | 12945 | `d386afa5000f2202094aac278079cbf3d466fc150296e68690e567e3a28eb331` | `b084018869a470ff191ef67ab46241b81061351e16dcd4d231e8d47642a795c8` | `3f1c92fd872b47b0929f1ef8623ac9185dd05a86f50660b91331d0e2cda78dc0` |
| `noarch/openstack-neutron-metering-agent-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-metering-agent-1:28.0.2-2.el10.noarch` | 16473 | `abb31239d6983d075c115a63167973e0a088802902c90365f094e64313866063` | `18a581ed1a5fc8c12a93779d90c87693843142eb1dce12dbae65a13152a177e9` | `62d4af8ef42786e164c38df868a281c9af11ceee4193809f6079f009b124e68a` |
| `noarch/openstack-neutron-ml2-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-ml2-1:28.0.2-2.el10.noarch` | 22579 | `fa231c48dd6132d680e25c59f4820ae47e01a21b3970131c1ad4b32ce061d2c0` | `b96f0f4b08fd6af12ab55ccc9d5c1c5d201f66f24651106906da9f2dcf64e602` | `a49af632c534fa486339097c1359e9f9b2ece279490a8210c6e9fd12c1ae3384` |
| `noarch/openstack-neutron-ml2ovn-trace-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-ml2ovn-trace-1:28.0.2-2.el10.noarch` | 11072 | `7be19c75b9c3b6ce7e223f8017098de9a0b258e591111f0f1f4057b7cf3c6750` | `8f807ff667b24c6b9b7b88d4bfbed1fd4375c5fce352185b0317efd83e4787d5` | `8ab64f3b99d52ff7efa262296a3ccba500fe28cc63bb2a3f74cc8e3ba0fa8f3e` |
| `noarch/openstack-neutron-openvswitch-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-openvswitch-1:28.0.2-2.el10.noarch` | 21384 | `e3004731a374638fd3ab9756c3d72d3e5f7fdc746f81a270973c5c26e6b1cd18` | `731148337b689a516fe62e2943c655dd6e945c18e3140acd8586860b4f7671e9` | `b54b9481a86fee5caba4c058b2a50b441d0ff1c47c973bff8d034719775d3a39` |
| `noarch/openstack-neutron-ovn-agent-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-ovn-agent-1:28.0.2-2.el10.noarch` | 19017 | `2fd33d37d7887558838bd53aa2774a572d4b3e0b92458ab6097d8bc7055eae3c` | `794b3ead84890f1d21500fdb037a3cf9d1a2d3023e76205f20a73cede7291f2f` | `a28b58950d4f0afda311a0663842aab1e56976d7d12af4c3768cb920bc47aab1` |
| `noarch/openstack-neutron-ovn-maintenance-worker-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-ovn-maintenance-worker-1:28.0.2-2.el10.noarch` | 12490 | `b3a11ca8bf31bdb83654eba180a92b8d879aad641c223644f1fe83b434dac82d` | `0dd83c773ec2326fceffd11d61a48b48ec0a7e09b9bfd144357e476cda6af017` | `94345425728e1a9038779b277828a105dea6be2a9f408eee4ca891778098969e` |
| `noarch/openstack-neutron-ovn-metadata-agent-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-ovn-metadata-agent-1:28.0.2-2.el10.noarch` | 17181 | `127c5dde5ddc00b72c02221db903e1349f7444fad71ef7ac0096e64037bd0150` | `9bad1c1aff55f47ba562cd17a31debcd0c3fb266c8f79fbc29d09fcb3f959f3b` | `157f78fde34f7ba82c7a382b3a3e2ef2713462d47dcfa6b6f93419d2409c8ace` |
| `noarch/openstack-neutron-periodic-workers-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-periodic-workers-1:28.0.2-2.el10.noarch` | 12400 | `aeb0cafa11562661e6f7cf8c03413039fc80482681acb68220c79d9a987f306b` | `ce2546dbfbc44b01ff32e97056a190b198daa8947be3bc89c5dd4e3e08366ebd` | `51ea43dff8153f4463c2e033d4811ce8bbda835b9f61de9f7930c3f7ecf8a6ab` |
| `noarch/openstack-neutron-rpc-server-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-rpc-server-1:28.0.2-2.el10.noarch` | 12049 | `6ce47f2f66e66a45894548bb535b1df88ee0c58801e9a34388d101ecb8eaec06` | `e4b9d386a8360df52c5e2d7e46d83560dd2e7653d45b711bfb437c08d9e66ca0` | `0f7b4ea5df916398c30b87cfcbc7032c2c9062db3bd009c9bcd977edca1cd644` |
| `noarch/openstack-neutron-sriov-nic-agent-28.0.2-2.el10.noarch.rpm` | `openstack-neutron-sriov-nic-agent-1:28.0.2-2.el10.noarch` | 16282 | `968008aff843615ffbe7fa2e566489b3afad0003d5db5b061efe79587fa66941` | `c58b2e78500eb7b1adbf7eacf0dde3ec78de9d21bdaa3296ab70306aa3a4987f` | `3cf06e7ef973cae160f9274357c2a9ea00f462551e80c570b048b809c2fcc26a` |
| `noarch/python3-neutron-28.0.2-2.el10.noarch.rpm` | `python3-neutron-1:28.0.2-2.el10.noarch` | 3450576 | `8c4fa706826168bd651f8d54da48d5896f9bb6828a2cde159dfca6348b7c5c21` | `9ed28fc0f1ac9f09d93ea09c730b800f2a490fdb8a22a5e8418b7332aaf399b7` | `5accb128eccce6588bdf067ffc80fa1b9e1ef2a546b27828ea9f97dc96b18a6a` |
| `noarch/python3-neutron-tests-28.0.2-2.el10.noarch.rpm` | `python3-neutron-tests-1:28.0.2-2.el10.noarch` | 4332085 | `721a738fedfaff9b6f95ac14cf197248b4ff66dbf5905f412aa851d260e8b9fa` | `f570c946f61ba14c309bd49461b81eaa52f63b9d9a40c51cf292abea8c02fa15` | `a2c2e7b0b449db727161a9daa8f43d1c7676e4e0e0942c8cd0bf848a9d0f4a59` |

Payload comparison with the removed `-1` builds (non-bytecode files):

- `python3-neutron`: differs **only** in the four patched files and
  `neutron-28.0.2.dist-info/pbr.json`. `pbr.json` holds the throwaway git
  commit `%autosetup -S git` creates per build (`cd85408` → `aad3dc3`).
- The `.pyc` files all differ; bytecode embeds per-build source timestamps.
- `openstack-neutron-periodic-workers` and
  `openstack-neutron-ovn-maintenance-worker`: identical payloads. Both require
  `openstack-neutron-common = 1:28.0.2-2.el10`.
- `openstack-neutron-common`: differs only in the commented default
  `#my_ip = <build host address>` in the generated sample
  `/etc/neutron/neutron.conf`. This is build-host dependent, not code.

## 8. Deployed byte identity

| Host | Role | Before install |
|---|---|---|
| `hgrf-rocky1` | all-in-one; n2-standard-4, nested KVM, 60 GB, `rocky-linux-10-v20260910` | candidate tar `2208303d…`; `rocky10.2/hagistack` `082a4a8c…`; test `b8ae2d49…`; repo tar `06e94f29…`; all 196 RPMs `sha256sum -c` against the frozen list; `repomd.xml` `0f31249a…`; 0 OpenStack packages installed |
| `hgrf-rocky2` | compute-add; n2-standard-2, nested KVM, 40 GB, same image | same values |

`rocky10.2/hagistack` in `40472e8` = `082a4a8c…`: **equal on both nodes**
before any run, and on rocky1 again before the rerun.

Installed identity, matching every package whose `from_repo` is
`hagistack-gazpacho` to its RPM file by (SHA256HEADER, PAYLOADDIGEST):

| Node | Installed from the repo | Match | Mismatch |
|---|---|---|---|
| hgrf-rocky1 | 104 | 104 | 0 |
| hgrf-rocky2 | 70 | 70 | 0 |

| Installed (rocky1) | File SHA-256 |
|---|---|
| `openstack-neutron-ovn-maintenance-worker-1:28.0.2-2.el10.noarch` | `b3a11ca8bf31bdb83654eba180a92b8d879aad641c223644f1fe83b434dac82d` |
| `openstack-neutron-periodic-workers-1:28.0.2-2.el10.noarch` | `aeb0cafa11562661e6f7cf8c03413039fc80482681acb68220c79d9a987f306b` |
| `openstack-neutron-common-1:28.0.2-2.el10.noarch` | `a89c63ee0603f6805574b07881351d708252e0b3fd77475af43f41295fb91b6a` |
| `python3-neutron-1:28.0.2-2.el10.noarch` | `8c4fa706826168bd651f8d54da48d5896f9bb6828a2cde159dfca6348b7c5c21` |
| `openstack-neutron-1:28.0.2-2.el10.noarch` | `2c162ce8db70f44b7d8a4d1118898cf1bfb24993b804bd78ae61acf6c9397972` |

`rpm -V python3-neutron openstack-neutron-ovn-maintenance-worker openstack-neutron-periodic-workers`:
clean. All 8 installed `openstack-neutron*`/`python3-neutron` packages are
`28.0.2-2.el10`.

**ROCKY INSTALLED NEUTRON RPMS MATCH INVENTORY: YES**

## 9. Deterministic regression and negative control

`rocky10.2/tests-neutron-maintenance-lock.py` (`b8ae2d49…`) was run on
hgrf-rocky1 from the deployed candidate tree.

How the test works:

- It starts its own ovsdb-server with the OVN NB schema on a free 127.0.0.1
  port. The deployment's NB and its real lock are never touched.
- It drives `OvsdbNbOvnIdl.from_worker()` and the real
  `DBInconsistenciesPeriodics`.
- It forces the race window open with a 0.02 s sleep between sending the lock
  request and recording its id.
- It checks three starts, an RPC worker, and handover between two maintenance
  workers.

| Run | Result |
|---|---|
| PATCHED: installed `python3-neutron-28.0.2-2` | starts 1–3: `idl.has_lock=True`, not stuck, NB write ok; RpcWorker `lock_name=None has_lock=False`; handover A owner / B contended (`neutron has_lock=False`) → after A stops B owner. **RESULT: PASS, exit 0** |
| NEGATIVE CONTROL: unpatched 28.0.2 source (`--neutron-path`, tarball `cdaf45a2…`) | starts 1–3: `idl.has_lock=False is_lock_contended=False neutron has_lock=True`, **stuck**, NB write failed (`OVSDB Error`, NOT_LOCKED); handover broken. **RESULT: FAIL, exit 1** |

The test fails on the vulnerable code and passes on the fixed code.

**F-NEW-1 REGRESSION NEGATIVE CONTROL: PASS**

## 10. RPC-worker safety and lock timing (real deployment)

A passive `tcpdump -i lo tcp port 6641` ran from before installation, with an
`ss` sampler mapping NB client ports to PIDs.

- **Only one kind of session ever sent `lock`: the maintenance worker's.**
  First start: session opened 10:40:59.324402, `lock id=2` at 10:40:59.325244
  (0.84 ms later, before the initial dump), `{"locked": true}` at
  10:40:59.325500. The unpatched worker asked about 20 s after connecting,
  from another thread.
- RPC workers: the original pair plus three `systemctl restart
  neutron-rpc-server` gave 8 RPC-worker NB sessions (PIDs 14567, 14570, 42316,
  42320, 42481, 42485, 42658, 42662): **0 lock messages**. rpc-server active,
  `rpc-server.log` ERROR 0, maintenance worker NOT_LOCKED 0, agents alive.

**RPC WORKERS REQUEST MAINTENANCE LOCK: NO**

Lock handover between two maintenance workers is shown in §9: one owner, the
second contended and not running guarded tasks, handover on owner exit,
no nudge.

## 11. Real Rocky acceptance

`all-in-one` (hgrf-rocky1): exit 0, 10:34:56Z → 10:46:44Z, every phase.
`compute-add` (hgrf-rocky2): exit 0. `discover-hosts` mapped rocky2.

| Unit (rocky1) | Enabled | Active | NRestarts |
|---|---|---|---|
| neutron-rpc-server | enabled | active | 0 |
| **neutron-periodic-workers** | enabled | active | 0 |
| **neutron-ovn-maintenance-worker** | enabled | active | 0 |
| neutron-ovn-metadata-agent | enabled | active | 0 |

- **Processes:** a maintenance-worker master plus one `maintenance worker`
  child; a periodic-workers master plus four `Periodic worker` children.
- **Maintenance log:** `OVN maintenance process starting...` 10:40:57.878,
  `Maintenance task thread has started` and `…finished the post
  initialization` 10:41:19.442.
- **Error counts:** ERROR 0 / Traceback 0 in all four Neutron logs.
  **NOT_LOCKED 0.** 24 tasks finished, 0 failed.
- **`hagistack status`:** both workers `active`.
- **API:** `GET /` 200 and `GET /v2.0/networks` with a token 200. Agents:
  OVN Controller Gateway + Metadata on rocky1, OVN Controller + Metadata on
  rocky2, all alive. nova-compute up on both nodes; both hypervisors up.
- **Guests:** `wpa-g1` on rocky1 ACTIVE in 21 s, `wpa-g2` on rocky2 ACTIVE in
  20 s.
- **Metadata:** both consoles show `successful after 1/20 tries` for the
  instance-id, then `login:`.
- **Ping:** inside g1 to g2 across nodes, 30/30, 0 % loss.
- **Geneve:** capture on the controller NIC: 64 packets; 30 inner echo
  requests and 30 inner echo replies.
- **Ports:** 4 ACTIVE (two guests, router interface, router gateway); 2 DOWN
  are `network:distributed` (OVN metadata localports, always DOWN).

## 12. Start / restart trials

Each start was classified by the F-NEW-1 signature: `NOT_LOCKED` lines from
the new PID tree, failed tasks, and whether a lock-guarded task
(`check_fdb_aging_settings`, `update_ha_failover`, `set_fip_distributed_flag`)
finished. No trial used any lock probe.

| Path | Starts | Active | NOT_LOCKED > 0 | Failed tasks > 0 | Guarded task finished | Wire |
|---|---|---|---|---|---|---|
| Hagistack install (first start) | 1 | 1 | 0 | 0 | yes | lock granted 0.84 ms after connect |
| `systemctl restart` | 30 | 30 | 0 | 0 | 30/30 | 30/30 granted |
| `systemctl stop` → `start` | 10 | 10 | 0 | 0 | 10/10 | 10/10 granted |
| reboot (systemd at boot, no Hagistack) | 1 | 1 | 0 | 0 | yes (3 guarded tasks) | not captured (transient capture does not survive reboot) |

On the wire, over the 40 restart and stop/start trials:

- each maintenance session sent **exactly one** `lock` request, with no
  duplicate write;
- the request came **0.60–0.88 ms** after the session connected;
- all 40 were granted;
- no other session sent any lock message.

In the investigation's trials, the unpatched build failed 4 starts in 66, and
every affected start showed a duplicate write.

42 patched starts with 0 occurrences detect an obvious regression. They are
not a statistical proof that the probability is zero.

## 13. Idempotency

A second `all-in-one` on rocky1 with the same options: exit **0**, 0 restart
lines, 0 skipped phases. The before/after snapshots differ **only in their own
timestamp line**:

- unit `ActiveEnterTimestamp` and `MainPID` for Neutron, Nova, glance, httpd
  and OVN units;
- worker and Neutron package NEVRA, SHA256HEADER and INSTALLTIME (no
  reinstall);
- the dnf transaction count;
- the hashes of `neutron.conf`, `ml2_conf.ini`, `neutron_ovn_metadata_agent.ini`
  and `plugin.ini`.

The API answered afterwards: networks listed, token issued.

## 14. Ubuntu scope and deferred findings

`git diff 2556d832 40472e87 -- ubuntu26.04 README.md README.ja.md`: 0 bytes.
`ubuntu26.04/hagistack` is still `81c4e62685a92f3264051890b518c3dcc3be0710483fe9d86acc83f4b0ed6559`.
No Ubuntu package was built, no repository was added, and no workaround was
added. No document claims the Ubuntu defect is fixed.

**UBUNTU PRODUCT CHANGES: ZERO**

- **O-A: DEFERRED.** Ubuntu restart-decision timing is unchanged, and the
  WP-A evidence wording was not corrected here.
- **TAG_REQUEST FINDING: DEFERRED.** `a8feb94e` was not imported.
- **F13b: unchanged.** No build-process change. The single-pass neutron build
  was possible only because its dependencies were already in the base
  repository.
- **cliff: unchanged.** The served repository is the WP-A one, which omits the
  defective self-built `python3-cliff-4.13.3-1.el10`. `python3-cliff` resolves
  from EPEL (`python3-cliff-4.13.3-1.el10_2`, `from_repo=epel`) exactly as in
  WP-A. The Neutron worker code does not use cliff.

## 15. Operational actions

| Action | Where | Why |
|---|---|---|
| base repository = WP-A served repository; old neutron `-1` RPMs moved out | builder | add only the rebuilt neutron (README's `REPO_PUBLISH_DIR` form) |
| firewalld: README-listed ports (controller TCP 5000, 9292, 8778, 5672, 6642, 11211, UDP 6081; compute UDP 6081); zone `trusted` | rocky1, rocky2 | documented prerequisite; no filtering effect |
| `ip link add hgext0 type dummy` | rocky1 | provider NIC on a single-NIC VM |
| `dnf install tcpdump` (4.99.4-10.el10) | rocky1 | wire capture |
| passive `tcpdump -i lo tcp port 6641` and `ss` sampler | rocky1 | lock/RPC evidence |
| `--env-file /dev/null` + CLI options | both | pre-existing config-file defect (WP-A O-1) |
| 3 × `systemctl restart neutron-rpc-server` | rocky1 | RPC-worker lock safety |
| 30 × restart, 10 × stop/start of the maintenance worker; 1 reboot | rocky1 | start trials |
| regression test on a private ovsdb-server | rocky1 | §9 |

---

## Appendix: the Neutron RPMs removed from the base repository

The 15 `28.0.2-1.el10` files (WP-A inventory) were moved out before the
build. Their hashes are in the WP-A evidence (`acceptance/WP-A_NEUTRON_WORKERS_2026-09-30.md`,
Appendix A) and in the raw `removed-neutron-1.sha256`.
