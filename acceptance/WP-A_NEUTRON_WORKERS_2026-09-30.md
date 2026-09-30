# WP-A acceptance evidence: Neutron workers (candidate `cb3154a`)

Recorded 2026-09-30 on Google Compute Engine. This file is the durable record
for the two evidence gaps the independent WP-A audit left open:

- **WP-A-01**: artifact-level provenance of the Rocky RPMs used in acceptance,
  above all the two Neutron worker packages.
- **WP-A-02**: proof that the product bytes deployed and tested on real Linux
  are exactly candidate `cb3154a`.

It adds no product change. Every value below was observed during this run;
nothing is carried over from the original implementation report. Where the
earlier audit is relied on instead of a new observation, the text says so.

Redactions: the GCP project id is written `<project>` and the login user
`<user>`. External IP addresses, the account and the credentials are not
recorded. Secret files were never printed; the compute-node credentials were
piped from controller to compute node and only their key names were checked.

---

## 1. Results

| Item | Result |
|---|---|
| Candidate | `cb3154a361f343b940fffaa6bdbc0f5a7aad234e`, tree `a3e16307dfe5bff1500cf9b7056ac8ff304d8a76`, parent `7a20dbe1ba8cde14f9e35252e1f9074387d695d6` |
| ROCKY DEPLOYED HAGISTACK MATCHES CANDIDATE | **YES** (2/2 nodes, checked before any run and again after) |
| UBUNTU DEPLOYED HAGISTACK MATCHES CANDIDATE | **YES** (3/3 nodes that ran the candidate) |
| Rocky worker RPMs identified by file SHA-256, NEVRA, header and payload digest | yes (§4, §5) |
| Installed Rocky packages tied to the inventoried files | 104/104 on the controller, 70/70 on the compute node, 0 mismatches (§7.1) |
| Rocky fresh two-node acceptance | pass (§7) |
| Rocky converged re-run | exit 0, nothing changed, nothing restarted (§8) |
| Ubuntu fresh two-node acceptance | pass (§10) |
| Ubuntu converged re-run | exit 0, no Neutron change (§11) |
| Ubuntu existing-host convergence on GCE | package transition correct on a real `7a20dbe` host and on a recreated old state (§12) |
| **New finding F-NEW-1** | after existing-host convergence (2 of 5 cases), the Ubuntu maintenance worker ran without its OVSDB lock and every northbound-writing maintenance task failed until an external lock request; not seen on fresh installs or on Rocky (§13) |

---

## 2. Canonical candidate bytes

Computed from the Git objects (`git show cb3154a:<path> | shasum -a 256`), not
from a working tree.

| Path | Git blob | SHA-256 |
|---|---|---|
| `ubuntu26.04/hagistack` | `274fa065f1ab69fa4f8a8b70f2d1e5910543c4d6` | `81c4e62685a92f3264051890b518c3dcc3be0710483fe9d86acc83f4b0ed6559` |
| `rocky10.2/hagistack` | `1450b21f5b73c8ef2308768c32e1f1986f11d85c` | `082a4a8c3879fedd1b0db262cea83fa39c63d7e4edba2536959f1e58c453e170` |
| `ubuntu26.04/tests/container-step4.sh` | `5253c12d0fb774824e4823766abc7aa94d4b5f3f` | `c66f88bb832cbd216131f8d342f9c9d48782a377c21f13fe2cefc74b22fb66c3` |
| `README.md` | `91a45775a2afa4e036d443e7209c18aa583db7eb` | `cda0ed3d0bf15fd447132d072380d9e56aad76b3fa6e78b79b2b801f9258648e` |
| `README.ja.md` | `31391db0e7c61bb1c0102f9a66e4bb060cf41fb6` | `92375c0997b764e397e6c6848c263b50284e6faa77d0b930178c4be82480e458` |
| `rocky10.2/build-rpms.sh` | `cd1f2f54dce70038a6a4af35110329ef3b7fdc9c` | `1ad25aa87a0279358576109377a2665f12e3cd5f8d0761d8f577ef8fe4362754` |
| `rocky10.2/gazpacho.manifest` | `c858f2923345687e2adf4dd95756111eaf7473de` | `e4c08c17d90f121db28fabd3293560ca63044d7af5dc068f4ec87848b040ae8c` |
| `rocky10.2/spec-patches/neutron.patch` | `5715811ebde67df6298696564b038837ce718e67` | `c067419a6c5187031646cd9c381a00b9c8b624d4ebfb8df50771e2f9efb2bc35` |
| `rocky10.2/spec-patches/cliff.patch` | `6094ae2508e9d12c8150c340a92e95d4f85e56f6` | `4f83247b4486783cb6e6df26fc1377863f71af3139d1e60024d6c4ba223799ad` |

For comparison, the parent's installers: `ubuntu26.04/hagistack`
`d2d35ad978970c3c9cf47710fbd08cdc2a6d21bdddd634657513490fecffc3bf`,
`rocky10.2/hagistack`
`d8135b2f7c9b9fdb3b85c70772ac63eae7f8a462401af59ef837ef7c455c4445`.

**Transport.** Every host received the same archive,
`git archive --format=tar --prefix=hagistack/ cb3154a`, SHA-256
`042226db74317f1e955763e9687643e345fa89e8dd8ad9d707bd9749ee9e7e17`. That value
was re-computed on each host after the copy. The installer was then hashed
**in place on the host**, in the directory it was run from, before it was run
(§6, §9).

---

## 3. Environment

All in `asia-northeast1-a`. Every instance was created for this remediation
and carries the label `task=hagistack-wpa-remediation`.

| Host | Role | Machine | Disk | Image | OS observed |
|---|---|---|---|---|---|
| `hgwpa-builder` | Rocky RPM builder | n2-standard-8 | 100 GB | `rocky-linux-10-v20260910` | Rocky Linux 10.2 (Red Quartz), kernel 6.12.0-211.51.1.el10_2 |
| `hgwpa-rocky1` | Rocky all-in-one | n2-standard-4, nested virt | 60 GB | `rocky-linux-10-v20260910` | Rocky Linux 10.2 |
| `hgwpa-rocky2` | Rocky compute-add | n2-standard-2, nested virt | 40 GB | `rocky-linux-10-v20260910` | Rocky Linux 10.2 |
| `hgwpa-ubu1` | Ubuntu all-in-one | n2-standard-4, nested virt | 60 GB | `ubuntu-2604-resolute-amd64-v20260918` | Ubuntu 26.04.1 LTS, kernel 7.0.0-1011-gcp |
| `hgwpa-ubu2` | Ubuntu compute-add | n2-standard-2, nested virt | 40 GB | `ubuntu-2604-resolute-amd64-v20260918` | Ubuntu 26.04.1 LTS |
| `hgwpa-ubu3` | Ubuntu real `7a20dbe` → `cb3154a` host | n2-standard-4, nested virt | 60 GB | `ubuntu-2604-resolute-amd64-v20260918` | Ubuntu 26.04.1 LTS |

`/dev/kvm` was present on every node; `virt_type=kvm`. The provider NIC was a
`dummy` interface `hgext0` on each all-in-one host (§14).

Long runs were started as transient **system** units (`systemd-run`), not in
an ssh session. The reason is incident H-1 (§14).

---

## 4. Rocky: build and source provenance

### 4.1 How the repository was built

The documented process: `rocky10.2/build-rpms.sh` from the candidate archive
(hash verified on the builder), on a disposable Rocky 10.2 x86_64 VM, with the
builder repositories the README names.

| Builder input | Value |
|---|---|
| Rocky repos | BaseOS, AppStream, CRB (enabled with `dnf config-manager --set-enabled crb`), Extras |
| EPEL 10 | `dnf install epel-release` |
| RDO files | `https://trunk.rdoproject.org/centos10-master/current/delorean.repo` (SHA-256 `bdfd56e0e1c00eef294d924fa2a7651184894e1f9d5281342718b15cc28f7f2b`) and `https://trunk.rdoproject.org/centos10-master/delorean-deps.repo` (`cd8094d28984486b936da16c6b8973cb1fd645096cdf8b1334440b7dbf5fd8d9`) |
| Tools | `git curl rpm-build rpmdevtools createrepo_c dnf-plugins-core` |
| Build-environment lock after the build | `build-env.lock`, 1079 package lines, SHA-256 `43c7ef89f8bbfd074e13e08f479979d9a6736bb3585c5e321e7c0442b72ad52a` |

The RDO files are **mutable** (`current/`, `deps/latest`). Their contents on
the day are pinned by the hashes above and by the lock, not by a URL. This is
recorded, not fixed (build reproducibility is F13b).

**The build took two passes, and a single documented pass does not produce the
repository.** Recorded as found:

| Pass | Command | Result | Log SHA-256 |
|---|---|---|---|
| 1 | `./build-rpms.sh --nocheck` | 67 PASS, 4 FAIL. **neutron, nova, horizon**: `rpmbuild` exit 11, *Failed build dependencies* (`python3dist(neutron-lib) >= 3.24`, `os-ken >= 4.1.1`, `oslo-config >= 10.2` and others). The manifest builds the services **before** the 2026.1 libraries they need, so on a clean builder those libraries do not exist yet. **requestsexceptions**: `%prep` exit 1, `gpgverify` failed: the tarball's signature is from key `421E6472811F9A81`, not the key the manifest pins (`0x01527a34…`) | `77806c9b4ac23c306630810b53010fd07d4b08d1337c797a96319fb07dc92c53` |
| 2 | `./build-rpms.sh --nocheck neutron nova horizon` (the README's named-package form) | 3 PASS; `publish_repo` and `write_lock` ran | `f0d984d5365da0edc506eeba865cf3157bc2352293a977117278d3f95b2c4e22` |

No manual step, source edit or unpinned input was used. The only operator
choice was re-running the documented script for the three packages that
failed on build order. requestsexceptions was not re-attempted and is **not in
the repository**; on the Rocky nodes `python3-requestsexceptions-1.4.0-29.el10_2`
(the same upstream 1.4.0) was installed from EPEL. Both are F13b-class issues
and are not fixed here.

### 4.2 Neutron source provenance

| Input | Value | Verified how |
|---|---|---|
| distgit | `https://github.com/rdo-packages/neutron-distgit` | — |
| distgit commit (manifest pin) | `fa1f5135e66282364250f2f5630a48423f497099` | `build-rpms.sh` compares `git rev-parse HEAD` with the pin; re-checked after the build: HEAD equal, `git status --porcelain` empty. Commit date 2025-06-18, subject "Add python3-babel build requires for compile catalog" |
| pin comes from | the candidate's `rocky10.2/gazpacho.manifest` (SHA-256 above) | the manifest was hashed on the builder before the build |
| spec as shipped in the distgit | `openstack-neutron.spec` SHA-256 `9869639694d3402720652a22c0488009091786b4954abf1e6e5eab017ab4b114` | — |
| local spec patch | `rocky10.2/spec-patches/neutron.patch` SHA-256 `c067419a6c5187031646cd9c381a00b9c8b624d4ebfb8df50771e2f9efb2bc35`; 2 hunks, drops `%{_bindir}/neutron-api` and `%{_bindir}/neutron-server` from `%files` | applied with `--dry-run` first by the script |
| spec as built | SHA-256 `fea3a6f6782a39f31ca29dac151339eae6d3044a49d73d2cf10048a1e4f83752`; `Version: 28.0.2`, `Release: 1%{?dist}`, `Epoch: 1` | the script's `XXX` substitution from the manifest |
| source tarball | `neutron-28.0.2.tar.gz`, SHA-256 `cdaf45a2100de5233e4c1cc7c01c9df2b634510a0f0436913f73f29d42d325ee` | equal to the manifest pin; the script refuses a mismatch |
| detached signature | `neutron-28.0.2.tar.gz.asc`, SHA-256 `4eb45cfd3ee89bf415895c7697cccb49da1a6c0d44ab561d48afcc6525b8981f` | `%gpgverify` in `%prep`: `gpgv: Good signature from "OpenStack Infra (2026.2/Hibiscus Cycle) <infra-root@openstack.org>"` |
| signing key | `0x30566c450e41d7c91e442dfb231f942f608ddeff.txt`, SHA-256 `0f7901e358e78067604188563264589ee3a53f2369379a9b6310ab698af10fc9` | equal to the manifest's `KEY` line |
| `%check` | **not run** (`--nocheck`), as documented | — |
| libraries neutron was built against | `python3-neutron-lib-0:3.24.0-1.el10`, `python3-os-ken-0:4.1.2-1.el10`, `python3-oslo-service-0:4.5.1-1.el10`, `python3-ovsdbapp-0:2.16.1-1.el10`, all self-built in pass 1 | `build-env.lock` |
| rpmbuild log | SHA-256 `a55c43cb284d71045308d6836bfbcda809aa284466f34ed1915feffa852300b5` | — |

`fa1f5135…` is therefore not assumed from the earlier audit: it is the pin in
the candidate's own manifest, and the build verified the checkout against it.

---

## 5. Rocky: the RPM artifacts

### 5.1 Repository identity

| Object | Value |
|---|---|
| Built repository (`~/rpmbuild/RPMS`) | 197 RPM files, all `noarch`, from 70 source RPMs (60 distgit rows + 10 PyPI rows of the manifest; requestsexceptions missing). `repodata/repomd.xml` SHA-256 `576f57d1fa0d99c5d04c16c37a31f3f5be9f48d15eee5a7545a6edbbc1cca460` |
| **Served repository** (what the nodes installed from) | the built repository **minus one file**, `python3-cliff-4.13.3-1.el10.noarch.rpm` (§5.3), re-indexed with `createrepo_c`. 196 RPM files. `repomd.xml` SHA-256 `e7ac8e88716a343ea34895c297197256fd08d00fdcea699f49fe848c6012e328`. Per-file list SHA-256 `cf5b464a411cfb104a3db86d2d37db1b76538b4657fd01b3294300b4286473eb`. Tarball `served-repo.tar` SHA-256 `5c8e82264c1ca18afa6f3352182221bee4779a49d0277649ed01dfbeaf6bbd4c` |
| Served vs built | `diff` of the two per-file SHA-256 lists: exactly one line, the cliff file |
| Location type | a local directory on each node, `file:///opt/hagistack-repo` (the README's first form). Copied builder → operator workstation → node with `gcloud compute scp`. Not served over a network |
| Pre-install verification on **each** Rocky node | tarball SHA-256 equal; **all 196 files** passed `sha256sum -c` against the builder's per-file list; `repomd.xml` equal; `rpm -qa` showed 0 OpenStack or neutron packages installed |

The complete inventory (file, NEVRA, size, SHA-256) is Appendix A. It was
generated on the builder **before** any node existed.

### 5.2 Neutron RPMs (source RPM `openstack-neutron-28.0.2-1.el10.src.rpm`)

All built on `hgwpa-builder` at 2026-09-30 06:06:52 UTC (pass 2).

| File | NEVRA | Size | SHA-256 (file) | SHA256HEADER | PAYLOADDIGEST |
|---|---|---|---|---|---|
| `noarch/openstack-neutron-28.0.2-1.el10.noarch.rpm` | `openstack-neutron-1:28.0.2-1.el10.noarch` | 32655 | `acfaddd2f7d00d1205bb9432b9470a2910a7836916053071af94ef81ec0fd57a` | `04b9e8dee85c824bf0f103eb0259ca77a9edc8f4ebfb89bbe6f41aa184f98cca` | `b841b407a1256b1f9c77cd9475a9a9b7dd3c5ea9fd7cde08c9b4fa22c107dfb0` |
| `noarch/openstack-neutron-common-28.0.2-1.el10.noarch.rpm` | `openstack-neutron-common-1:28.0.2-1.el10.noarch` | 156672 | `d93f8ac74e286870274ebbbb54c8d459e49542bc3c4df6e23f7510331d9dab0c` | `2c9def8a7faa02d3b576db28e8ff67eab68f37f755c58b0285d8e586f321ecc0` | `b41f70f9dcac6626f855daedcd6b564c20732ec9d9ef54f03030018ac8dba500` |
| `noarch/openstack-neutron-macvtap-agent-28.0.2-1.el10.noarch.rpm` | `openstack-neutron-macvtap-agent-1:28.0.2-1.el10.noarch` | 12951 | `1f94738167783151d1bc89b71c0c357cfbdf83c2374c6770336b7659b26b0787` | `42e281e58f76ad73bca44533825f3706ec25a6be7ac9751e0ba16b994de83984` | `7d21436556b2bf42e0c703391ca2c07a17a9ede5dfa52ca93bf903522f1128b2` |
| `noarch/openstack-neutron-metering-agent-28.0.2-1.el10.noarch.rpm` | `openstack-neutron-metering-agent-1:28.0.2-1.el10.noarch` | 16476 | `0a201a31c5243c52c29e1cb02407e25aadef00387040971e04636845907a6e85` | `e0bd431d6a556b37b50a28bcc23414669cd2c35b88692dc0729f6da2851f559e` | `14fffb2b203e477f28f88c4562380b51ba9e0073295b07690ecec600430b31ef` |
| `noarch/openstack-neutron-ml2-28.0.2-1.el10.noarch.rpm` | `openstack-neutron-ml2-1:28.0.2-1.el10.noarch` | 22582 | `5c0c88bef425f69a85f55ed242ae74a063e86b200abc2282fb13f6237a07a961` | `b3a59868ff1275c1fae2cdcd2db9d4005822821c6468aeceb642672c2cbe092a` | `08f65ae8b37837764a375743bd996157ebad39fd2b5e439340aa4a806020d2e8` |
| `noarch/openstack-neutron-ml2ovn-trace-28.0.2-1.el10.noarch.rpm` | `openstack-neutron-ml2ovn-trace-1:28.0.2-1.el10.noarch` | 11077 | `d7699921cae632bfe76e5e4240f102622055245e47da6edc1661fc964ba7de34` | `8a5868187408f5960745bfc9ffe2724faca1530838dca311738abc927072ea81` | `01ac413de106ed648602bce756afc344672ff1f509b233064274c62f67efa431` |
| `noarch/openstack-neutron-openvswitch-28.0.2-1.el10.noarch.rpm` | `openstack-neutron-openvswitch-1:28.0.2-1.el10.noarch` | 21390 | `f35d2005aef7f7e1967381a1c7cc1c811594393361663893268b5b70a28b7544` | `eeafade209ba419734390e13c25f953367c89cc77da0161156850b157fbfcbe1` | `23ce26aeb3b9ca1b9aeae5abbc408ee6f84f3500cbbb31dd2e84a4d17d792f6d` |
| `noarch/openstack-neutron-ovn-agent-28.0.2-1.el10.noarch.rpm` | `openstack-neutron-ovn-agent-1:28.0.2-1.el10.noarch` | 19027 | `04c5be21e353653c9824ba957e5cd44569f68c61614948023df728f3ec3b17ed` | `200687ef89da64bc81cd65abf305ca7067974f8157c90c942a3a78a606ff4936` | `184424d5483c23f1133fe7005db74167be205c099afcd2c9cd58cadcdff8e7b9` |
| `noarch/openstack-neutron-ovn-maintenance-worker-28.0.2-1.el10.noarch.rpm` | `openstack-neutron-ovn-maintenance-worker-1:28.0.2-1.el10.noarch` | 12496 | `e016f2a9662c739cd90d010b613c15ca0dd35a4b0c8dd2eddb746a83a47d3953` | `904b5f6d1c12c021d5f65a5bc3f5dc16a382d9ed71be83177f6ae3efa7f9e833` | `5fb7f54dfb9238c28130bd24274e35115397662521208ba30d192f8e2f546ef6` |
| `noarch/openstack-neutron-ovn-metadata-agent-28.0.2-1.el10.noarch.rpm` | `openstack-neutron-ovn-metadata-agent-1:28.0.2-1.el10.noarch` | 17190 | `57da8e9ad3671d2ef87627ed6b536117f3b2a7229da610417ef2ccc7b5d11447` | `7424f8b86915423cdbb39e219837bcce6b1c15681aac0f8f0a3d4a0122d0f10f` | `2cd9343500e74cf09c6e3abf3f30def4f9bdc49f3d9b1e7f6bb8cc8fce974f61` |
| `noarch/openstack-neutron-periodic-workers-28.0.2-1.el10.noarch.rpm` | `openstack-neutron-periodic-workers-1:28.0.2-1.el10.noarch` | 12404 | `43db8a965e285d2c2eccb1246d70141cae2e3c221dde5c6b878f5fd997e7e46b` | `ccf8afb459c5c48daf8e58c2e19e5ab9c6b78d5bd1ccbd261d083af4ea7170cb` | `270ef5f26af41cee6b0795b01eb9c3d5294edd2865b56e885e0a01a5c161d1d8` |
| `noarch/openstack-neutron-rpc-server-28.0.2-1.el10.noarch.rpm` | `openstack-neutron-rpc-server-1:28.0.2-1.el10.noarch` | 12058 | `3b0ff58884e34d6722f82c01e8f2002d84c8e22d09c5531d035cba8a96b15fc7` | `b1141796cbab4bea45becfb97e2f8324051075252cdb8407f035871076ffee6c` | `5cb6b098d465e8a70e7e21d99c0ab82215a56d1cdd173c81fe57501faa8f8300` |
| `noarch/openstack-neutron-sriov-nic-agent-28.0.2-1.el10.noarch.rpm` | `openstack-neutron-sriov-nic-agent-1:28.0.2-1.el10.noarch` | 16287 | `38c584fc7ef9b9673f59af8c5535c231e3f960af82a521366671bbe075046642` | `16d73be4e7c9126173e4722b0c95eb4cd0512b65c57277b78d8fca911f8a4226` | `3fc3753f2c873c7a972f5d5583b729d6b5e798a5b76d43bb0150fa4f41e13fbc` |
| `noarch/python3-neutron-28.0.2-1.el10.noarch.rpm` | `python3-neutron-1:28.0.2-1.el10.noarch` | 3451656 | `5306c4c3b98867ff85cd7631a98384ef38b812b1250975670eff1af28fa28b02` | `afbc1137d49ba770b8764cfe67372ca36c08c7468c020123f15277e7e6ac0d3e` | `da0d9c0f2609fe483898825c5d8c132bbf9b6b87e39b22870b88b53232d7aea9` |
| `noarch/python3-neutron-tests-28.0.2-1.el10.noarch.rpm` | `python3-neutron-tests-1:28.0.2-1.el10.noarch` | 4331633 | `5de654ab7e523f8931fa165f9a1173ba92970a09da925986a09bf509034bed6d` | `fc5b9ebaffd8c549ff60baa79431078a650b0e19ba2001e0eeb72e141b10dfba` | `1e7db0af66f28bedc04c2001bc638b8ec7640508ce7305a686a8e146bc39192a` |

The two worker packages, read out of the files on the builder:

| | `openstack-neutron-periodic-workers` | `openstack-neutron-ovn-maintenance-worker` |
|---|---|---|
| NEVRA | `openstack-neutron-periodic-workers-1:28.0.2-1.el10.noarch` | `openstack-neutron-ovn-maintenance-worker-1:28.0.2-1.el10.noarch` |
| File SHA-256 | `43db8a965e285d2c2eccb1246d70141cae2e3c221dde5c6b878f5fd997e7e46b` | `e016f2a9662c739cd90d010b613c15ca0dd35a4b0c8dd2eddb746a83a47d3953` |
| Files | `/usr/bin/neutron-periodic-workers`, `/usr/lib/systemd/system/neutron-periodic-workers.service`, license | `/usr/bin/neutron-ovn-maintenance-worker`, `/usr/lib/systemd/system/neutron-ovn-maintenance-worker.service`, license |
| Requires | `openstack-neutron-common = 1:28.0.2-1.el10`, `/usr/bin/python3`, `/bin/sh` | same |
| Scriptlets | `%post`: `systemd-update-helper install-system-units` on first install (applies the systemd preset); Hagistack enables and starts the unit | same |
| Unit | `Type=notify`, `User=neutron`, `ExecStart=/usr/bin/neutron-periodic-workers … --config-file /etc/neutron/plugin.ini … --log-file /var/log/neutron/periodic-workers.log`, `Restart=on-failure` | same shape, `/usr/bin/neutron-ovn-maintenance-worker`, `--log-file /var/log/neutron/ovn-maintenance-worker.log` |
| Entry point | `from neutron.cmd.server import main_periodic` | `from neutron.cmd.server import main_ovn_maintenance` |
| Code that runs | `python3-neutron` (`entry_points.txt`: `neutron-periodic-workers = neutron.cmd.server:main_periodic`) | `python3-neutron` (`neutron-ovn-maintenance-worker = neutron.cmd.server:main_ovn_maintenance`; module `neutron/server/ovn_maintenance.py`) |

Packaging observation: `openstack-neutron` also lists
`/usr/bin/neutron-periodic-workers` and `/usr/bin/neutron-ovn-maintenance-worker`,
so those two paths are owned by two packages each. RPM accepts this for
identical files, and installation succeeded. Not changed here.

### 5.3 The cliff incident, recorded

The self-built `python3-cliff-0:4.13.3-1.el10.noarch`
(`python3-cliff-4.13.3-1.el10.noarch.rpm`, SHA-256
`14c3f725d0b53796b4c0dc2e873fee50991f8d2acce599c794631ce5df24f06e`) is
**incomplete**. It contains 15 of the 23 `cliff/*.py` modules in the 4.13.3
sdist, and **the whole `cliff/formatters/` package is missing**. cliff's
output formatters (`-f value`, `-f json`, …) live there, and Hagistack drives
the `openstack` CLI with them; this build was never installed, so the failure
itself was not exercised. The task brief records that the original run also
met an incomplete self-built cliff; this run found the concrete defect.

What was done, and nothing else:

- That one file was left out of the served repository (§5.1). No other
  package was added, removed or replaced.
- With the name no longer offered by the priority-1 repository, `python3-cliff`
  resolved from **EPEL**, which Hagistack enables itself.

| | Value |
|---|---|
| Package used | `python3-cliff-0:4.13.3-1.el10_2.noarch` |
| Source | EPEL 10 (`from_repo=epel` on both Rocky nodes); **external**, not Hagistack-built |
| Source RPM / build host | `python-cliff-4.13.3-1.el10_2.src.rpm`, a Fedora build VM |
| File SHA-256 (downloaded on the builder) | `82446216f126b1f678a1ce5e38ca3cc0da767239df57c4dde522705f81951bc8` |
| SHA256HEADER / PAYLOADDIGEST | `ee157a61368e8cb1a86a7b49f711d8e10eb2a11ee3b4343816f31a5854d3fae3` / `f2b8bd93ad79bc911fa391177eb8ff0fd4bc5d5e876657fdc0f654495ee14fa8`, **identical** to the package installed on both nodes |
| Signature | RSA/SHA256, key id `33d98517e37ed158` (EPEL 10); `rpm -K`: digests signatures OK |
| Content | 45 `.py` files including all 8 `cliff/formatters/*.py` |

Why it cannot alter the two worker RPMs:

- neither worker RPM, `openstack-neutron`, `openstack-neutron-common` nor
  `python3-neutron` has a cliff requirement (`rpm -qpR`: 0 matches);
- no file in `python3-neutron` imports cliff (`grep` of the unpacked payload:
  0 files);
- cliff arrives only through the client libraries: `python3-neutronclient`,
  `python3-designateclient`, `python3-barbicanclient`, `python3-osc-lib`;
- the worker RPM **files** are byte-identical to the inventory whatever cliff
  is installed (§7.1).

The empty `python3-cliff-tests-4.13.3-1.el10` stayed in the served repository.
It requires the removed build and is installed on neither node.

Other packages outside the self-built repository, from `dnf repoquery
--installed`: `python3-openstackclient-9.0.0-6.el10_2` (EPEL; the manifest
does not build it), `python3-requestsexceptions-1.4.0-29.el10_2` (EPEL; §4.1) and `openstack-network-scripts{,-openvswitch3.5}-10.11.1-8.el10s`
(RDO deps; not an OpenStack deliverable). None of them is a Neutron worker
input.

---

## 6. Rocky: deployed byte identity

Measured on each host, on the file that was then executed:

| Host | When | `rocky10.2/hagistack` SHA-256 | Equal to canonical |
|---|---|---|---|
| hgwpa-rocky1 | 06:17:55Z, before any run | `082a4a8c3879fedd1b0db262cea83fa39c63d7e4edba2536959f1e58c453e170` | yes |
| hgwpa-rocky2 | 06:17:58Z, before any run | `082a4a8c3879fedd1b0db262cea83fa39c63d7e4edba2536959f1e58c453e170` | yes |
| hgwpa-rocky1, hgwpa-rocky2 | after the acceptance and the re-run | same value | yes |

**ROCKY DEPLOYED HAGISTACK MATCHES CANDIDATE: YES**

Invocation (options only; see observation O-1 for why no config file):

```
all-in-one  --env-file /dev/null --repo-url file:///opt/hagistack-repo --ext-nic hgext0 \
            --provider-cidr 172.24.4.0/24 --provider-gateway 172.24.4.1 \
            --floating-start 172.24.4.100 --floating-end 172.24.4.200
compute-add --env-file /dev/null --controller-ip <rocky1 mgmt ip> --repo-url file:///opt/hagistack-repo
```

---

## 7. Rocky: fresh two-node acceptance

`all-in-one` on rocky1: exit **0**, 06:19:22Z → 06:29:35Z, every phase.
`compute-add` on rocky2: exit **0**. `discover-hosts` mapped rocky2.

### 7.1 Installed package identity

On each node, every installed package whose `from_repo` is
`hagistack-gazpacho` was matched to the RPM **file** in `/opt/hagistack-repo`
(already `sha256sum`-verified against Appendix A) by the pair
(SHA256HEADER, PAYLOADDIGEST):

| Node | Installed from hagistack-gazpacho | Match | Mismatch |
|---|---|---|---|
| rocky1 | 104 | 104 | 0 |
| rocky2 | 70 | 70 | 0 |

| Installed (rocky1) | Tied to file | File SHA-256 |
|---|---|---|
| `openstack-neutron-periodic-workers-1:28.0.2-1.el10.noarch` | `noarch/openstack-neutron-periodic-workers-28.0.2-1.el10.noarch.rpm` | `43db8a965e285d2c2eccb1246d70141cae2e3c221dde5c6b878f5fd997e7e46b` |
| `openstack-neutron-ovn-maintenance-worker-1:28.0.2-1.el10.noarch` | `noarch/openstack-neutron-ovn-maintenance-worker-28.0.2-1.el10.noarch.rpm` | `e016f2a9662c739cd90d010b613c15ca0dd35a4b0c8dd2eddb746a83a47d3953` |
| `openstack-neutron-common-1:28.0.2-1.el10.noarch` | `noarch/openstack-neutron-common-28.0.2-1.el10.noarch.rpm` | `d93f8ac74e286870274ebbbb54c8d459e49542bc3c4df6e23f7510331d9dab0c` |
| `python3-neutron-1:28.0.2-1.el10.noarch` | `noarch/python3-neutron-28.0.2-1.el10.noarch.rpm` | `5306c4c3b98867ff85cd7631a98384ef38b812b1250975670eff1af28fa28b02` |
| `openstack-neutron-1:28.0.2-1.el10.noarch` | `noarch/openstack-neutron-28.0.2-1.el10.noarch.rpm` | `acfaddd2f7d00d1205bb9432b9470a2910a7836916053071af94ef81ec0fd57a` |

`rpm -V` on the two workers and `python3-neutron`: no file differs from the
package. rocky2 carries `python3-neutron` and `openstack-neutron-common` with
the same file ties, and no API-side worker (expected on a compute node).

### 7.2 Units, processes, logs

| Unit (rocky1) | Enabled | Active | Since (UTC) | NRestarts |
|---|---|---|---|---|
| neutron-rpc-server | enabled | active | 06:24:15 | 0 |
| **neutron-periodic-workers** | **enabled** | **active** | 06:24:18 | 0 |
| **neutron-ovn-maintenance-worker** | **enabled** | **active** | 06:24:20 | 0 |
| neutron-ovn-metadata-agent | enabled | active | 06:24:20 | 0 |

Processes: `neutron-periodic-workers: master process` with four `Periodic
worker` children (`AgentSchedulerDbMixin` ×2, `DbQuotaNoLockDriver`,
`L3_NAT_dbonly_mixin`); `neutron-ovn-maintenance-worker: master process` with
one `maintenance worker` child; all `User=neutron`.

Startup, `/var/log/neutron/ovn-maintenance-worker.log`:

```
06:24:19.430 13060 INFO neutron.server.ovn_maintenance OVN maintenance process starting...
06:24:40.649 13065 INFO ...mech_driver Maintenance task thread has started
06:24:40.650 13065 INFO ...mech_driver MaintenanceWorker process has finished the post initialization
06:24:40.860 onward  OVN maintenance task check_* finished ...
```

`/var/log/neutron/periodic-workers.log`: `Periodic workers process starting...`
at 06:24:17.058.

ERROR / Traceback counts, measured after acceptance and again after the re-run:

| Log | ERROR | Traceback |
|---|---|---|
| rpc-server.log | 0 | 0 |
| periodic-workers.log | 0 | 0 |
| ovn-maintenance-worker.log | 0 | 0 |
| neutron-ovn-metadata-agent.log | 0 | 0 |

### 7.3 Status, API, agents

- `hagistack status` lists `neutron-periodic-workers active` and
  `neutron-ovn-maintenance-worker active` beside the other units.
- Neutron endpoint from the catalogue: unauthenticated `GET /` → **200**;
  `GET /v2.0/networks` with a token → **200**; `hagistack-provider` and
  `hagistack-tenant` exist.
- Agents: OVN Controller Gateway agent (rocky1), OVN Metadata agent (rocky1),
  OVN Controller agent (rocky2), OVN Metadata agent (rocky2), all
  alive/up.
- nova-compute up on rocky1 and rocky2; both hypervisors `up`.

### 7.4 Guests, metadata, overlay

| Guest | Host | Status | Seconds to ACTIVE |
|---|---|---|---|
| wpa-g1 | rocky1 | ACTIVE | 16 |
| wpa-g2 | rocky2 | ACTIVE | 18 |

CirrOS console, both guests: `checking http://169.254.169.254/2009-04-04/instance-id`
→ `successful after 1/20 tries`, then the `login:` prompt. (`failed to get
…/user-data` is expected: no user-data was given.) CirrOS runs its own init,
not the cloud-init package; "cloud-init completes" means this metadata fetch
and boot to login.

Cross-node ping, run **inside wpa-g1** (ssh from the tenant network's
`ovnmeta-` namespace on rocky1) to wpa-g2 on rocky2:
**30 transmitted, 30 received, 0 % loss**, rtt avg 0.679 ms.

Capture on rocky1's NIC (`ens4`, an altname of `eth0`), `udp port 6081`, during
the ping: **64 Geneve packets**; decoded inner packets: **30** ICMP echo
requests g1 → g2 and **30** echo replies g2 → g1.

---

## 8. Rocky: converged re-run

A second `all-in-one` on rocky1 with the same options: exit **0**.
Snapshots taken before and after differ **only in their own timestamp line**:

- all Neutron, Nova, glance, httpd and OVN units: same `ActiveEnterTimestamp`
  and `MainPID` (the workers stayed at 06:24:18 / 06:24:20);
- the worker, common, `python3-neutron`, `openstack-neutron` and cliff
  packages: same NEVRA, SHA256HEADER and INSTALLTIME, so nothing was
  reinstalled;
- `dnf history` transaction count unchanged;
- `neutron.conf`, `ml2_conf.ini`, `neutron_ovn_metadata_agent.ini`,
  `plugin.ini`: same SHA-256; 0 duplicate keys in `neutron.conf`.

Run log: 0 `restart` lines, 0 skipped phases. Neutron ERROR/Traceback still
0 in all four logs. The API still answered with a token after the re-run.

---

## 9. Ubuntu: deployed byte identity

| Host | When | `ubuntu26.04/hagistack` SHA-256 | Equal to canonical |
|---|---|---|---|
| hgwpa-ubu1 | 06:12:04Z, before its first run | `81c4e62685a92f3264051890b518c3dcc3be0710483fe9d86acc83f4b0ed6559` | yes |
| hgwpa-ubu2 | 05:37:06Z, before its first run; again before `compute-add` | same | yes |
| hgwpa-ubu3 | before the parent run; again before the candidate run | same (the parent copy there was `d2d35ad9…`, equal to `7a20dbe`) | yes |

**UBUNTU DEPLOYED HAGISTACK MATCHES CANDIDATE: YES**

Config file used on the all-in-one hosts (placeholders only, no secrets):
`EXT_NIC=hgext0`, `PROVIDER_CIDR=172.24.4.0/24`, `PROVIDER_GATEWAY=172.24.4.1`,
`FLOATING_START=172.24.4.100`, `FLOATING_END=172.24.4.200`.

---

## 10. Ubuntu: fresh two-node acceptance

`all-in-one` on ubu1: exit **0**, 06:12:04Z → 06:27:43Z. `compute-add` on
ubu2: exit **0**, 06:29:07Z → 06:32:21Z. `discover-hosts` mapped ubu2.

### 10.1 Packages

The fresh run's single Neutron transaction:
`apt-get install -y -qq neutron-api neutron-rpc-server neutron-periodic-workers neutron-ovn-maintenance-worker neutron-plugin-ml2 neutron-ovn-metadata-agent`.
The transitional `neutron-server` was **not** installed.

| Package | State |
|---|---|
| neutron-server | not installed |
| neutron-api, neutron-rpc-server, neutron-periodic-workers, **neutron-ovn-maintenance-worker**, neutron-plugin-ml2, neutron-ovn-metadata-agent | installed `2:28.0.2-0ubuntu1`, **manual** |
| neutron-common, python3-neutron | installed `2:28.0.2-0ubuntu1`, automatic |
| `apt-get -s autoremove` | 0 to remove |

The `.deb` files cached on ubu1 were compared with the archive index
(`resolute-updates`, `amd64v3` `Packages`, read with `apt-cache show` on ubu2,
same image and mirror): cached-file SHA-256 equals the index `SHA256` for each
of the five below.

| `.deb` | SHA-256 |
|---|---|
| neutron-ovn-maintenance-worker_2:28.0.2-0ubuntu1_all | `e3612dea95581f931e56c510741298ab2ec70460921b6f1f0e1f2616489c9778` (universe) |
| neutron-periodic-workers_2:28.0.2-0ubuntu1_all | `75aa34897762d371b2b83f9fc3d9f5dc3ef7b013b31e040343ea52f0deaa69c1` |
| neutron-api_2:28.0.2-0ubuntu1_all | `7534ac7233903fbdee6141ad0f944afb0b2c3352c31b9765ffaac92a8a82368d` |
| neutron-rpc-server_2:28.0.2-0ubuntu1_all | `ad362ef0a82112cb5afe2ab6e42ceb8c984bec130216e69c15fcfb54da882888` |
| python3-neutron_2:28.0.2-0ubuntu1_all | `01f53def7720bcebdee6c066672425d57034f7e7a6510b49034d462052d0d408` |

### 10.2 Units, processes, logs

| Unit (ubu1) | Enabled | Active | Since (UTC) | NRestarts |
|---|---|---|---|---|
| neutron-rpc-server | enabled | active | 06:18:21 | 7 |
| neutron-periodic-workers | enabled | active | 06:18:19 | 8 |
| **neutron-ovn-maintenance-worker** | **enabled** | **active** | 06:18:19 | 6 |
| neutron-ovn-metadata-agent | enabled | active | 06:19:00 | 0 |

Processes: `neutron-ovn-maintenance-worker: master process` (pid 15306) with a
`maintenance worker` child; `neutron-periodic-workers` with four periodic
children; `neutron-rpc-server` with two rpc workers and an rpc reports worker;
the metadata agent as root.

Startup of the running maintenance worker:

```
06:18:20.934 15306 INFO neutron.server.ovn_maintenance OVN maintenance process starting...
06:18:42.730 15370 INFO ...mech_driver Maintenance task thread has started
06:18:42.730 15370 INFO ...mech_driver MaintenanceWorker process has finished the post initialization
06:18:42.782 15370 INFO ...maintenance OVN maintenance task check_baremetal_ports_dhcp_options finished ...
```

**ERROR counts are non-zero and were investigated.** Whole-file counts at
acceptance: maintenance worker 1153 ERROR / 12 Traceback, periodic workers
1339 / 14, rpc-server 1338 / 14, metadata agent 7 / 0, neutron-api 1 / 0.

- Workers: every ERROR predates the final start. The packages start their
  units at install time, before Hagistack writes `neutron.conf`, so they run on
  the stock sqlite configuration and crash with
  `DBNonExistentTable: (sqlite3.OperationalError) no such table: ml2_geneve_allocations`
  until Hagistack configures and restarts them. That is the NRestarts count
  above. The last such ERROR was at 06:18:18.364; the running processes
  started at 06:18:19–21. **ERROR lines from the running process trees: 0**
  for all three. rpc-server and periodic-workers behave identically, so this is
  the existing package-starts-before-config pattern, not new with the candidate.
- Metadata agent: 7 × `Unable to open stream to tcp:127.0.0.1:6642`
  (stock config) up to 06:19:00, when it was configured and restarted.
- neutron-api: one `ovsdbapp … attempting to write bad value to column
  tag_request` at 06:27:02 during initial-resource creation. The same line is
  on hgwpa-ubu3 at 07:15:32, created by the **parent** `7a20dbe` before the
  candidate ever ran there, so it is pre-existing and not WP-A.

The unit files shipped by Ubuntu also log `Failed to parse TimeoutStopSec=` /
`TimeoutStartSec=` at every daemon-reload (a packaging warning; recorded only).

### 10.3 Status, API, agents

- `hagistack status`: `neutron pkg 2:28.0.2-0ubuntu1`, API "apache2 + mod_wsgi
  on :9696 (from neutron-api; no API unit)", other units
  `neutron-rpc-server neutron-periodic-workers neutron-ovn-maintenance-worker neutron-ovn-metadata-agent`,
  each listed `active`. (It also prints `all-in-one: INCOMPLETE — missing:
  preflight`; see O-3.)
- Neutron endpoint: unauthenticated `GET /` → **200**; `GET /v2.0/networks`
  with a token → **200**.
- Agents: OVN Controller Gateway agent and OVN Metadata agent on ubu1, OVN
  Controller agent and OVN Metadata agent on ubu2, all alive/up.
- nova-compute up on both; both hypervisors `up`.

### 10.4 Guests, metadata, overlay

| Guest | Host | Status | Seconds to ACTIVE |
|---|---|---|---|
| wpa-g1 | ubu1 | ACTIVE | 20 |
| wpa-g2 | ubu2 | ACTIVE | 19 |

Both consoles: `successful after 1/20 tries` for the instance-id, then
`login:`. Ping inside wpa-g1 to wpa-g2: **30/30, 0 % loss**, rtt avg 0.761 ms.
Capture on ubu1 `ens4`, `udp port 6081`: **65 Geneve packets**, **30** inner
echo requests g1 → g2, **30** inner echo replies.

---

## 11. Ubuntu: converged re-run

A second `all-in-one` on ubu1: exit **0**. Before/after snapshots:

- the four Neutron units: same `ActiveEnterTimestamp` and `MainPID`;
- Neutron packages, manual/auto marks, apt transaction count, `neutron-api`
  dpkg file-list mtime: unchanged;
- `neutron.conf`, `ml2_conf.ini`, `neutron_ovn_metadata_agent.ini`: same SHA-256;
  0 duplicate keys.

**Not quiet elsewhere:** `nova-conductor` and `nova-scheduler` were restarted
once ("its configuration is newer than the running process"). `nova.conf` was
last written at 06:25:03 by the first run's `nova_compute` phase, after
conductor (06:22) and scheduler (06:23) had started. This is Nova phase
ordering, not attributable to WP-A (the candidate touches no Nova code); see
O-4. A later run on the same host (§12.1, run 4) restarted nothing.

---

## 12. Ubuntu: existing-host convergence on GCE

The audit established the transition in a container (N12). This run repeated
it on real GCE hosts, in two forms.

### 12.1 Recreated old state (hgwpa-ubu1, the audit's N12 method)

Old state made from the converged host with
`apt-get install neutron-server` and
`apt-mark auto neutron-api neutron-rpc-server neutron-periodic-workers`.
apt's own record:

```
Commandline: apt-get install -y -qq neutron-server
Install: neutron-server:amd64 (2:28.0.2-0ubuntu1)
Remove: neutron-ovn-maintenance-worker:amd64 (2:28.0.2-0ubuntu1)
```

This differs from a host that never had the worker in one way: the
maintenance worker's conffiles stay behind (`deinstall ok config-files`).

The candidate run (run 3): exit **0**, log `installing:
neutron-ovn-maintenance-worker (replacing the transitional neutron-server)`, and
exactly one apt transaction:

```
Commandline: apt-get install -y -qq neutron-api neutron-rpc-server neutron-periodic-workers neutron-ovn-maintenance-worker neutron-plugin-ml2 neutron-ovn-metadata-agent
Install: neutron-ovn-maintenance-worker:amd64 (2:28.0.2-0ubuntu1)
Remove: neutron-server:amd64 (2:28.0.2-0ubuntu1)
```

After it: neutron-server not installed; the six real packages installed and
**manual**; `apt-get -s autoremove` 0 to remove; `neutron-api` dpkg file-list
mtime unchanged (not reinstalled); rpc-server, periodic-workers and the
metadata agent kept their PIDs; the Neutron configuration was "already
correct (unchanged)". The maintenance worker was started by its own package
at 06:46:55 and Hagistack found it "already running with the current
configuration".

A further run (run 4): exit **0**, snapshot unchanged, **0** restart lines,
no apt transaction.

### 12.2 A real `7a20dbe` host (hgwpa-ubu3)

`all-in-one` with the parent's installer (`d2d35ad9…`): exit **0**. The
resulting old state, observed rather than recreated:

- `neutron-server` installed and manual; `neutron-api`, `-rpc-server`,
  `-periodic-workers` installed and **automatic**;
- no maintenance worker package or unit;
- the maintenance OVSDB lock `ovn_db_inconsistencies_periodics` **free**
  (an `ovsdb-client lock` probe got `{"locked":true}`).

Then `all-in-one` with the candidate: exit **0**, one apt transaction:

```
Commandline: apt-get install -y -qq neutron-api neutron-rpc-server neutron-periodic-workers neutron-ovn-maintenance-worker neutron-plugin-ml2 neutron-ovn-metadata-agent
Install: neutron-ovn-maintenance-worker:amd64 (2:28.0.2-0ubuntu1)
Remove: neutron-server:amd64 (2:28.0.2-0ubuntu1)
```

Before/after snapshot: neutron-server gone; the six real packages manual;
`neutron-api` file-list mtime unchanged; rpc-server, periodic-workers and the
metadata agent kept their PIDs; the maintenance worker new, enabled and active;
`apt-get -s autoremove` 0 to remove. nova-conductor/-scheduler restarted once,
as in §11.

**Package convergence: as the candidate claims, on a real parent-built host.**
Worker health after convergence: see §13.

---

## 13. F-NEW-1: after convergence the Ubuntu maintenance worker can run without its lock

**Observed.** In 2 of 5 convergences, the maintenance worker started by apt
during the candidate run never obtained its OVSDB lock. Every maintenance task
that writes to the northbound database then failed on each cycle:

```
ERROR ovsdbapp.backend.ovs_idl.transaction OVSDB Error: The transaction failed because
  the IDL has been configured to require a database lock but didn't get it yet or has
  already lost it
ERROR ...ovsdb.maintenance OVN maintenance task check_fdb_aging_settings failed after 0.1…
```

| Host / case | Worker started | Stuck? | Size |
|---|---|---|---|
| ubu1, recreated old state (run 3) | 06:46:55, by apt | **yes** | 46 375 ERROR / 1 670 Traceback by 06:56 |
| ubu3, real `7a20dbe` host | 07:17:59, by apt | **yes** | 33 961 ERROR; 357 tasks failed, 18 finished |
| ubu1, recreated old state (experiment A) | 07:31:25, by apt | no | 0 ERROR; lock-guarded tasks finished |
| ubu1, recreated old state (trial T1) | 07:40:57, by apt | no | 0 ERROR; 26 tasks finished, 0 failed over a 15-minute watch with no probe |
| ubu3, recreated old state (trial T1) | 07:40:46, by apt | no | 0 ERROR; 26 tasks finished, 0 failed over a 15-minute watch with no probe |
| ubu1 fresh install | by Hagistack after configuration | no | 0 ERROR from the running process |
| rocky1 fresh install | by Hagistack | no | 0 ERROR |
| ubu1, `systemctl restart` of the worker (experiment A) | by systemd | no | 0 ERROR |

**What it is and is not.**

- The lock (`ovn_db_inconsistencies_periodics`) is requested only by
  `DBInconsistenciesPeriodics`, which runs only in the maintenance worker
  (checked in the installed Neutron source).
- While stuck, an `ovsdb-client lock` probe got `{"locked":false}`: the server
  considered the lock held. On ubu1 the NB server had exactly as many sessions
  (7) as there were client processes (4 Apache WSGI, 2 rpc, 1 maintenance), so
  no dead session was involved.
- **Both stuck workers recovered at the exact moment a diagnostic
  `ovsdb-client lock` probe connected** (ubu1: last ERROR 06:57:34.281, probe
  at 06:57:34; ubu3: last ERROR 07:24:17.826, probe at 07:24:17). The service
  restarts done afterwards on ubu1 and ubu3 therefore changed nothing; an
  earlier reading that an rpc-server worker held the lock was a confound and
  is withdrawn.
- How long a stuck worker stays stuck without such a probe is **not known**.
  The two cases ran 10 and 6 minutes without recovering.

**Scope for WP-A.**

- Rate observed: 2 of 5 worker starts by apt during convergence; 0 of 3 starts
  by Hagistack or systemd after configuration (both fresh installs and one
  restart). Five and three are small samples.
- It did not appear on any fresh install, on Rocky, or when Hagistack itself
  (re)started the worker after configuration.
- While ubu1 was stuck, the other Neutron units kept their PIDs and the
  Hagistack run in that window (run 4) verified the networking API
  (`openstack network list succeeded`). Guest boot and the overlay were **not**
  re-tested during a stuck window.
- The parent runs no maintenance worker at all (F02), so this is not a loss
  of something `7a20dbe` did. It is a defect in the newly added function, seen
  only on the existing-host path.
- Whether the cause is in Hagistack (the worker is left as apt started it)
  or upstream (the IDL losing a lock grant) was **not** established, and
  nothing was changed. It is recorded for the re-audit to weigh.

---

## 14. Operational actions and incidents

All are validation-environment actions, not product behaviour.

| # | Action | Where | Why |
|---|---|---|---|
| A-1 | `ip link add hgext0 type dummy` as the provider NIC | rocky1, ubu1, ubu3 | a single-NIC GCE VM has no spare NIC; Hagistack requires the named NIC to exist and does not attach it |
| A-2 | firewalld ports opened exactly as the Rocky README lists: controller TCP 5000, 9292, 8778, 5672, 6642, 11211 and UDP 6081; compute UDP 6081 | rocky1, rocky2 | firewalld was **active** on the stock image, as the README's prerequisite requires handling. Its default zone was **`trusted`** (accepts everything), so the added ports changed no filtering. Ubuntu: ufw inactive, firewalld inactive; nothing done |
| A-3 | `dnf install tcpdump` (tcpdump-4.99.4-10.el10) | rocky1 | capture tool for the Geneve check |
| A-4 | cliff file left out of the served repository | builder | §5.3 |
| A-5 | build pass 2 for neutron, nova, horizon | builder | §4.1 |
| A-6 | diagnostic restarts: `neutron-rpc-server` (ubu1, 06:58:22), `neutron-periodic-workers`, `apache2`, `neutron-rpc-server` (ubu3, 07:24:45–07:27:19), `neutron-ovn-maintenance-worker` (ubu1, 07:36:45); `ovsdb-client lock` probes | ubu1, ubu3 | §13, after the acceptance evidence of §10–12 had been captured |
| A-7 | old-state recreation (`apt-get install neutron-server`, `apt-mark auto …`) | ubu1 (×3), ubu3 (×1, trial) | §12.1, §13 |

**Incident H-1 (harness).** The first ubu1 (instance 1) run was launched with
`setsid nohup` over a non-interactive ssh session. At 05:38:25Z a package
operation triggered `systemctl daemon-reexec` and a systemd-logind restart;
logind then failed to re-register the already-closed session
(`Failed to start session scope session-9.scope: File exists`) and systemd
SIGTERMed the scope at 05:38:37Z, during the memcached phase. No Neutron
package had been installed. That VM was deleted and recreated; every later
long run used `systemd-run`. All Ubuntu evidence above is from the recreated
ubu1.

The Keystone database connection leak was not reproduced deliberately and
was not observed.

---

## 15. Observations deferred (not fixed)

| # | Observation |
|---|---|
| O-1 | Rocky: `load_env_file` references `CONFIG_KEYS_FLAT`, which is never defined (candidate line 362, parent line 358); any non-empty config file aborts with `unbound variable`. And `ENV_FILE` defaults to `./hagistack.env`, so with no file the script stops with `env file not readable`. Only `--env-file /dev/null` plus options works. Pre-existing |
| O-2 | Build (F13b): one pass of `build-rpms.sh` cannot build neutron, nova or horizon on a clean builder (manifest order); requestsexceptions' pinned signing key does not match its tarball; the self-built python3-cliff lacks `cliff/formatters`; builder repos are mutable URLs |
| O-3 | Ubuntu `status` always reports `all-in-one: INCOMPLETE — missing: preflight`; no `preflight` marker is ever written in `7a20dbe` or `cb3154a` |
| O-4 | Ubuntu: the first `all-in-one` rewrites `nova.conf` after starting nova-conductor/-scheduler, so the second run restarts them once |
| O-5 | Ubuntu packages start units before configuration (§10.2); the maintenance worker package does the same |
| O-6 | Ubuntu unit files: `Failed to parse TimeoutStopSec=` / `TimeoutStartSec=` |
| O-7 | Rocky: `openstack-neutron` and the two worker packages own the same `/usr/bin` paths |
| O-8 | neutron-api: `attempting to write bad value to column tag_request`, also on the parent |
| O-9 | F-NEW-1 (§13) |

---

## 16. What is and is not in Git

Kept outside the repository, on the operator's workstation: raw command
output, build logs, per-node snapshots, the served repository tarball and
the EPEL cliff RPM. The hashes of the ones this record relies on are quoted
above. No log is committed. The raw material contains internal addresses,
host names with the project id and a login name. The collection scripts never
printed a secret value (credentials were sourced or piped, and only key names
were checked); the Hagistack run logs are not committed either way.

---

## Appendix A. Complete RPM inventory of the built repository

Generated on `hgwpa-builder` before any node was created. Columns: SHA-256 of
the file, size in bytes, NEVRA, path under the repository. The served
repository is this list **minus** `noarch/python3-cliff-4.13.3-1.el10.noarch.rpm`.

```
b385defafc7c321b290816f61f59b2705b3fbd6897dcf16dbffa53b845820d94  13641483 openstack-dashboard-1:25.7.3-1.el10.noarch noarch/openstack-dashboard-25.7.3-1.el10.noarch.rpm
28cd1485567c5abd4dd7eec2251434929db1b3eb3ac8eb53241f35a523f61641      6441 openstack-dashboard-theme-1:25.7.3-1.el10.noarch noarch/openstack-dashboard-theme-25.7.3-1.el10.noarch.rpm
16058a4881e83d333ee381961986c30001af84246c14698f2a37b470cb89aebb     80233 openstack-glance-1:32.0.0-1.el10.noarch noarch/openstack-glance-32.0.0-1.el10.noarch.rpm
f72267f3d830b24bbd92146905a1b83c07f3368e99f0ba99c86681ce727e6211   2511439 openstack-glance-doc-1:32.0.0-1.el10.noarch noarch/openstack-glance-doc-32.0.0-1.el10.noarch.rpm
4387816e51a78f0fe1853d0ca5e174990299807e4899447cecd7e1bbef5b9ac2     46097 openstack-keystone-1:29.1.0-1.el10.noarch noarch/openstack-keystone-29.1.0-1.el10.noarch.rpm
acfaddd2f7d00d1205bb9432b9470a2910a7836916053071af94ef81ec0fd57a     32655 openstack-neutron-1:28.0.2-1.el10.noarch noarch/openstack-neutron-28.0.2-1.el10.noarch.rpm
d93f8ac74e286870274ebbbb54c8d459e49542bc3c4df6e23f7510331d9dab0c    156672 openstack-neutron-common-1:28.0.2-1.el10.noarch noarch/openstack-neutron-common-28.0.2-1.el10.noarch.rpm
1f94738167783151d1bc89b71c0c357cfbdf83c2374c6770336b7659b26b0787     12951 openstack-neutron-macvtap-agent-1:28.0.2-1.el10.noarch noarch/openstack-neutron-macvtap-agent-28.0.2-1.el10.noarch.rpm
0a201a31c5243c52c29e1cb02407e25aadef00387040971e04636845907a6e85     16476 openstack-neutron-metering-agent-1:28.0.2-1.el10.noarch noarch/openstack-neutron-metering-agent-28.0.2-1.el10.noarch.rpm
5c0c88bef425f69a85f55ed242ae74a063e86b200abc2282fb13f6237a07a961     22582 openstack-neutron-ml2-1:28.0.2-1.el10.noarch noarch/openstack-neutron-ml2-28.0.2-1.el10.noarch.rpm
d7699921cae632bfe76e5e4240f102622055245e47da6edc1661fc964ba7de34     11077 openstack-neutron-ml2ovn-trace-1:28.0.2-1.el10.noarch noarch/openstack-neutron-ml2ovn-trace-28.0.2-1.el10.noarch.rpm
f35d2005aef7f7e1967381a1c7cc1c811594393361663893268b5b70a28b7544     21390 openstack-neutron-openvswitch-1:28.0.2-1.el10.noarch noarch/openstack-neutron-openvswitch-28.0.2-1.el10.noarch.rpm
04c5be21e353653c9824ba957e5cd44569f68c61614948023df728f3ec3b17ed     19027 openstack-neutron-ovn-agent-1:28.0.2-1.el10.noarch noarch/openstack-neutron-ovn-agent-28.0.2-1.el10.noarch.rpm
e016f2a9662c739cd90d010b613c15ca0dd35a4b0c8dd2eddb746a83a47d3953     12496 openstack-neutron-ovn-maintenance-worker-1:28.0.2-1.el10.noarch noarch/openstack-neutron-ovn-maintenance-worker-28.0.2-1.el10.noarch.rpm
57da8e9ad3671d2ef87627ed6b536117f3b2a7229da610417ef2ccc7b5d11447     17190 openstack-neutron-ovn-metadata-agent-1:28.0.2-1.el10.noarch noarch/openstack-neutron-ovn-metadata-agent-28.0.2-1.el10.noarch.rpm
43db8a965e285d2c2eccb1246d70141cae2e3c221dde5c6b878f5fd997e7e46b     12404 openstack-neutron-periodic-workers-1:28.0.2-1.el10.noarch noarch/openstack-neutron-periodic-workers-28.0.2-1.el10.noarch.rpm
3b0ff58884e34d6722f82c01e8f2002d84c8e22d09c5531d035cba8a96b15fc7     12058 openstack-neutron-rpc-server-1:28.0.2-1.el10.noarch noarch/openstack-neutron-rpc-server-28.0.2-1.el10.noarch.rpm
38c584fc7ef9b9673f59af8c5535c231e3f960af82a521366671bbe075046642     16287 openstack-neutron-sriov-nic-agent-1:28.0.2-1.el10.noarch noarch/openstack-neutron-sriov-nic-agent-28.0.2-1.el10.noarch.rpm
b6108b6c668311c561c4d716ef5d40e5ac91991fe3f63fdd1e715a0ba7bc4d53      7041 openstack-nova-1:33.0.2-1.el10.noarch noarch/openstack-nova-33.0.2-1.el10.noarch.rpm
d5193c3dfd92965c1a452bd23ad9a2c9a7cdf06489266749a477ff858344d3f0      9025 openstack-nova-api-1:33.0.2-1.el10.noarch noarch/openstack-nova-api-33.0.2-1.el10.noarch.rpm
2342f9c566dc02ceabbe35b83fb98adfa2517ace207b92fe5078bd8512c99e8c    248933 openstack-nova-common-1:33.0.2-1.el10.noarch noarch/openstack-nova-common-33.0.2-1.el10.noarch.rpm
1c517525c3365fc8343ce03b614e52a12e72082595621fce96f5c7da08b9948b     17207 openstack-nova-compute-1:33.0.2-1.el10.noarch noarch/openstack-nova-compute-33.0.2-1.el10.noarch.rpm
5c2fc3d71147b8a146064f61cb2502a6cb429959636f16e94b28bf2eabf5e89d      8927 openstack-nova-conductor-1:33.0.2-1.el10.noarch noarch/openstack-nova-conductor-33.0.2-1.el10.noarch.rpm
06cf34dfcc922337985cc7e86c5a8cd5326572edd8bc948e4a70c6a5c70d2290     11069 openstack-nova-migration-1:33.0.2-1.el10.noarch noarch/openstack-nova-migration-33.0.2-1.el10.noarch.rpm
2455050a2ee726d8a538ef369d2eb541245d24b052a0fd9f0b281056bc877d95      9333 openstack-nova-novncproxy-1:33.0.2-1.el10.noarch noarch/openstack-nova-novncproxy-33.0.2-1.el10.noarch.rpm
d782b45bbe2e6d498b06e36ecbd735a53f6c1b0611d923acf65d95426fb81de2      8934 openstack-nova-scheduler-1:33.0.2-1.el10.noarch noarch/openstack-nova-scheduler-33.0.2-1.el10.noarch.rpm
2aeab467983f53f444fbc8a645c55d34cf8e4309d73b77957074dca6082f2a67      8946 openstack-nova-serialproxy-1:33.0.2-1.el10.noarch noarch/openstack-nova-serialproxy-33.0.2-1.el10.noarch.rpm
adb7ae124a6757195d42409675c24b8c8a646dea1b84ec78614a908652e14af9      8995 openstack-nova-spicehtml5proxy-1:33.0.2-1.el10.noarch noarch/openstack-nova-spicehtml5proxy-33.0.2-1.el10.noarch.rpm
53b783110bb309087ba9454a9ca157c0e98fe861d1e9e99a9bf6a8cb345e8baf     11352 openstack-placement-api-0:15.0.0-1.el10.noarch noarch/openstack-placement-api-15.0.0-1.el10.noarch.rpm
4d0d784faed2c66479350b2a06514e42de7f056dc4791b89a46847f89bd5f49f     24104 openstack-placement-common-0:15.0.0-1.el10.noarch noarch/openstack-placement-common-15.0.0-1.el10.noarch.rpm
f27953ed5bdc988d8af733cd9d474733c9aec9ce9839359e45b1223479e27878   1164912 python-automaton-doc-0:3.3.0-1.el10.noarch noarch/python-automaton-doc-3.3.0-1.el10.noarch.rpm
727a307cfc43a477164914bc1a5166372b69ed2ba099e4900d82c7559be24b10   1172444 python-barbicanclient-doc-0:7.3.0-1.el10.noarch noarch/python-barbicanclient-doc-7.3.0-1.el10.noarch.rpm
a42265f158e87c835a73dceba9ca54f4a46c7e5a80c8c778630ddd529bf7de43   1158169 python-cinderclient-doc-0:9.9.0-1.el10.noarch noarch/python-cinderclient-doc-9.9.0-1.el10.noarch.rpm
5bfe3200eb3b719534905804ef31d703a0474661f0cc7ea543a94a6294909e65   1126101 python-cursive-doc-0:0.2.3-1.el10.noarch noarch/python-cursive-doc-0.2.3-1.el10.noarch.rpm
a32c2e838599fb0d3f1633636874ee621978509cecbb51683685e0890f809a0b   1136553 python-debtcollector-doc-0:3.0.0-1.el10.noarch noarch/python-debtcollector-doc-3.0.0-1.el10.noarch.rpm
a68d086d498d8d500f7ac5a9fbbff76dc56978005118c97083e01844d4fb60cb   1243564 python-designateclient-doc-0:6.4.0-1.el10.noarch noarch/python-designateclient-doc-6.4.0-1.el10.noarch.rpm
c8555f1c57a92b361990d3ce69f64764e910aee9ed0a3a4e75941dda51f012b6   1147743 python-futurist-doc-0:3.2.1-1.el10.noarch noarch/python-futurist-doc-3.2.1-1.el10.noarch.rpm
00623d703eb5663e76a2196ac3af54bff77f9a1da6b0141490b771e4385fe4e1   1213655 python-glanceclient-doc-1:4.11.0-1.el10.noarch noarch/python-glanceclient-doc-4.11.0-1.el10.noarch.rpm
c264a19e3bfba66ef17fac9eb9f696bed97c553a7e8cb2086c1603bc8edc6585   1286914 python-keystoneauth1-doc-0:5.13.1-1.el10.noarch noarch/python-keystoneauth1-doc-5.13.1-1.el10.noarch.rpm
10684616d0551aa0b9187aca000e3887154d2c75088d7de453b80e7e8aac41c4   1257880 python-keystoneclient-doc-1:5.8.0-1.el10.noarch noarch/python-keystoneclient-doc-5.8.0-1.el10.noarch.rpm
6736b05464ec832e3e12804ce8333763ef241c6d5045f872daea9267745f0116   1209358 python-keystonemiddleware-doc-0:12.0.0-1.el10.noarch noarch/python-keystonemiddleware-doc-12.0.0-1.el10.noarch.rpm
9ddbf5bd76f6ddbe57769de8a58c4ffe826700e15c3fd3543437c62b6a2953da   1125867 python-microversion-parse-doc-0:2.1.0-1.el10.noarch noarch/python-microversion-parse-doc-2.1.0-1.el10.noarch.rpm
7549c62ca37ba8f26f90df604ea4efe49d0fd61b728e7338aa3c97a424c39c87   1485187 python-neutron-lib-doc-0:3.24.0-1.el10.noarch noarch/python-neutron-lib-doc-3.24.0-1.el10.noarch.rpm
8cac26fd3c04d5715060708a8d1cff90111fb93378faf048d813d6b1215d199a   1146879 python-neutronclient-doc-0:11.8.0-1.el10.noarch noarch/python-neutronclient-doc-11.8.0-1.el10.noarch.rpm
eb2ecece4f24975e78b32db123595b12baf66bda4462962a80f16b5ebd1426c0   1260067 python-novaclient-doc-1:18.12.0-1.el10.noarch noarch/python-novaclient-doc-18.12.0-1.el10.noarch.rpm
f8d1f38dc3782402cb3ef24917c4d4c936d3236bfafd96977f9f966d1178ac70   1144378 python-os-client-config-doc-0:2.3.0-1.el10.noarch noarch/python-os-client-config-doc-2.3.0-1.el10.noarch.rpm
350d0de36300b0669cac037b70720f6b31bd3ce86902e2ed51958b5dd7938a15   1363054 python-os-ken-doc-0:4.1.2-1.el10.noarch noarch/python-os-ken-doc-4.1.2-1.el10.noarch.rpm
f64cac61cd10e7cbbcbc66cda77548171fa12f7ed5fa6057c91fd9620d419832   1127853 python-os-resource-classes-doc-0:1.1.0-1.el10.noarch noarch/python-os-resource-classes-doc-1.1.0-1.el10.noarch.rpm
9d2b1f9bcab51bf4a8b33026e9a8e163de10b7c87653154e35d46b7ef1107cd2   1134603 python-os-service-types-doc-0:1.8.2-1.el10.noarch noarch/python-os-service-types-doc-1.8.2-1.el10.noarch.rpm
634a7c9eecc3fc39c1cce6a08e4ecfb155c9fd554ba4e0368a1b2196e15ad8ff   1138914 python-os-traits-doc-0:3.6.0-1.el10.noarch noarch/python-os-traits-doc-3.6.0-1.el10.noarch.rpm
c824394eefc8843f239a82db1e271b09c5c83df65b48bcb9e14da875a0e5969c   1147628 python-os-vif-doc-0:4.3.0-1.el10.noarch noarch/python-os-vif-doc-4.3.0-1.el10.noarch.rpm
3c99b25d772deaafd4859fe62c2d06a75dafcdc80c4b586601f8590b64333ccb   1169484 python-osc-lib-doc-0:4.4.0-1.el10.noarch noarch/python-osc-lib-doc-4.4.0-1.el10.noarch.rpm
83ef2642dcee8df19d1012abfff7927d9f6af8c2355499385a6413456f07ce0c   1492256 python-oslo-cache-doc-0:4.1.1-1.el10.noarch noarch/python-oslo-cache-doc-4.1.1-1.el10.noarch.rpm
567087358e92e7db10b1a12d0853340b796264090cb4cd3d753ccd0d591f0ed6     16319 python-oslo-cache-lang-0:4.1.1-1.el10.noarch noarch/python-oslo-cache-lang-4.1.1-1.el10.noarch.rpm
11bca5e576117080a5ad40b2bff51d1d23b47a25cd01b9c8cfd30957b425eef9   1154993 python-oslo-concurrency-doc-0:7.4.1-1.el10.noarch noarch/python-oslo-concurrency-doc-7.4.1-1.el10.noarch.rpm
11f4db19a0946e06803b293b50bea1a21918247100bce98ada0b8568b796d0f3     13438 python-oslo-concurrency-lang-0:7.4.1-1.el10.noarch noarch/python-oslo-concurrency-lang-7.4.1-1.el10.noarch.rpm
e06c5b4f67693c4040f384e33b5e6ac3204ed54287ffa8ba1c51a14a2ab43d6c   1215797 python-oslo-config-doc-2:10.3.0-1.el10.noarch noarch/python-oslo-config-doc-10.3.0-1.el10.noarch.rpm
36878e7938cdcb4aefbc7b5180876d63900f7f2edbdfaada0f59ba84e45ce69b   1146454 python-oslo-context-doc-0:6.3.0-1.el10.noarch noarch/python-oslo-context-doc-6.3.0-1.el10.noarch.rpm
3009b3f5f203f0afb12e93ca3b2cd4d6f920026dfcdcf50c18e7a2898d76f0c0   1187176 python-oslo-db-doc-0:18.0.0-1.el10.noarch noarch/python-oslo-db-doc-18.0.0-1.el10.noarch.rpm
c76130bdf0055b39f6f361f5725f1b91569af7014800fb4b0cdccf9afa62f6cf     12118 python-oslo-db-lang-0:18.0.0-1.el10.noarch noarch/python-oslo-db-lang-18.0.0-1.el10.noarch.rpm
f4396de32a8cebf24526231a22f43210f51a5aa85dd1e5a0a9911cdeedce5c21   1145659 python-oslo-i18n-doc-0:6.7.2-1.el10.noarch noarch/python-oslo-i18n-doc-6.7.2-1.el10.noarch.rpm
4354c6fff4af905c4cc9739212fef28495d8b5ea5bf1ed8f1cd78f5258902b84     13900 python-oslo-i18n-lang-0:6.7.2-1.el10.noarch noarch/python-oslo-i18n-lang-6.7.2-1.el10.noarch.rpm
4d2e4636c1b027f6df0f9d50ba9849ef24ad4110067eadbd30525586411ab2d3   1145158 python-oslo-limit-doc-0:2.10.0-1.el10.noarch noarch/python-oslo-limit-doc-2.10.0-1.el10.noarch.rpm
69912e1590effa53795cfde955c73dc97a690c724c7eb00eab5d593151f892b1   1175682 python-oslo-log-doc-0:8.1.1-1.el10.noarch noarch/python-oslo-log-doc-8.1.1-1.el10.noarch.rpm
9d11b242c1da0dc363635dcef6bf0091220b0205b62a05d17e68b2488a971eca     12746 python-oslo-log-lang-0:8.1.1-1.el10.noarch noarch/python-oslo-log-lang-8.1.1-1.el10.noarch.rpm
fc050379ada62766e2221ca5b44cf3ad5c9ef805d3a07e9e2d3bbec4346cad9a   1347771 python-oslo-messaging-doc-0:17.3.0-1.el10.noarch noarch/python-oslo-messaging-doc-17.3.0-1.el10.noarch.rpm
d093e9609f49a91a12b2f1008e010b4c9067dc230791a920fb9de3527015d7e9   1135753 python-oslo-metrics-doc-0:0.15.1-1.el10.noarch noarch/python-oslo-metrics-doc-0.15.1-1.el10.noarch.rpm
d504dd5e22c662651ae9ecbd610a18538f5be88a890e309a246206d85b809cf7   1150587 python-oslo-middleware-doc-0:8.0.0-1.el10.noarch noarch/python-oslo-middleware-doc-8.0.0-1.el10.noarch.rpm
ccf3c63658a5a3cb3cc0bf2d1ba4c67d376fa7faf3b6779c1f2ecf5d88aa6d36     11121 python-oslo-middleware-lang-0:8.0.0-1.el10.noarch noarch/python-oslo-middleware-lang-8.0.0-1.el10.noarch.rpm
c65a7501dca5e3a185c694ecb4bf121691e491ba28ae71388fa621761a524983   1187129 python-oslo-policy-doc-0:5.0.0-1.el10.noarch noarch/python-oslo-policy-doc-5.0.0-1.el10.noarch.rpm
6b4aba092b39e13ecb5f3cde0cd70977b3085f64bd7359855328d1a2efa0cd7c     12118 python-oslo-policy-lang-0:5.0.0-1.el10.noarch noarch/python-oslo-policy-lang-5.0.0-1.el10.noarch.rpm
9d504125ba897c79eb3ae3d985a2c1c4aff687d268dfa14932ba65d45cddd15b   1147343 python-oslo-privsep-doc-0:3.10.1-1.el10.noarch noarch/python-oslo-privsep-doc-3.10.1-1.el10.noarch.rpm
2b01c5a955821c1e2d5603694e82c7bf84655ffab056a722ec24d28ddf489289     12138 python-oslo-privsep-lang-0:3.10.1-1.el10.noarch noarch/python-oslo-privsep-lang-3.10.1-1.el10.noarch.rpm
b3c296fdbae4a27c5f30572f418760e751d92d77a67cd4125a5e3678887422dd   1164344 python-oslo-reports-doc-0:3.7.0-1.el10.noarch noarch/python-oslo-reports-doc-3.7.0-1.el10.noarch.rpm
55fc0b8edf112d713a0c6320f4a641ce82a2dc16accb0ad7bc5cac0fe263c1e8   1137705 python-oslo-rootwrap-doc-0:7.9.0-1.el10.noarch noarch/python-oslo-rootwrap-doc-7.9.0-1.el10.noarch.rpm
3f09096b6eace7dcec6fe411b182777d7f2113abfa2b1a54e086685ba838d169   1135770 python-oslo-serialization-doc-0:5.9.1-1.el10.noarch noarch/python-oslo-serialization-doc-5.9.1-1.el10.noarch.rpm
05fa7e167fb53042dbc917a36e607d63f4789138b4f9dcd0917719869114fa7b   1155731 python-oslo-service-doc-0:4.5.1-1.el10.noarch noarch/python-oslo-service-doc-4.5.1-1.el10.noarch.rpm
c04dacd873115533029fd2f7d75f1ead372676ff745d5b04486b7f58fedd4a92   1132103 python-oslo-upgradecheck-doc-0:2.7.1-1.el10.noarch noarch/python-oslo-upgradecheck-doc-2.7.1-1.el10.noarch.rpm
27635ea2329a326531e16ffc50d5934391831ff8df03bd1f9dd6f04966cd42e6   1169365 python-oslo-utils-doc-0:10.0.1-1.el10.noarch noarch/python-oslo-utils-doc-10.0.1-1.el10.noarch.rpm
9770ac5b7087dcbb43875649409dd7d8b54f3f4086eed7ee75b0572169274c90     13384 python-oslo-utils-lang-0:10.0.1-1.el10.noarch noarch/python-oslo-utils-lang-10.0.1-1.el10.noarch.rpm
a639a7bdd075f3e82cafba29390c62596fbffdae5c256dfa57b183cce70ca62c   1225140 python-oslo-versionedobjects-doc-0:3.9.0-1.el10.noarch noarch/python-oslo-versionedobjects-doc-3.9.0-1.el10.noarch.rpm
f9615022b8303fc7d1e754372c53172cc11dc8dd06d73f6f1ae10347d9b73535     12016 python-oslo-versionedobjects-lang-0:3.9.0-1.el10.noarch noarch/python-oslo-versionedobjects-lang-3.9.0-1.el10.noarch.rpm
a6777ea4eb84a9ef0ffe92ff47836f53026113f4901a05a44d96a3ea9d7a8d09   1190510 python-osprofiler-doc-0:4.3.0-1.el10.noarch noarch/python-osprofiler-doc-4.3.0-1.el10.noarch.rpm
16f1e6785abf24727f6fce4413fbb70a6a161fb39c6e65183ca25dd8e9fc68c1   1133288 python-ovsdbapp-doc-0:2.16.1-1.el10.noarch noarch/python-ovsdbapp-doc-2.16.1-1.el10.noarch.rpm
cadc947c9615588d27d42705bf38f64f4b894fac9f0a81cbef0554decbe30100     14789 python-pycadf-common-0:4.0.1-1.el10.noarch noarch/python-pycadf-common-4.0.1-1.el10.noarch.rpm
5a5a55cef1b4f26df79f83c7fed0ceff5d728c530af5c7378294bfa2f71f30cc   2113882 python-taskflow-doc-0:6.2.0-1.el10.noarch noarch/python-taskflow-doc-6.2.0-1.el10.noarch.rpm
4d7aecb90da575cd6a4e397f1ffc9ce985bc0ea37cbae6be65bcbd665fc99ea0     49800 python3-automaton-0:3.3.0-1.el10.noarch noarch/python3-automaton-3.3.0-1.el10.noarch.rpm
fb9c241efa531850a6559fe6e1f33e5a80e6ab978c733183e526453981bf05ae    170181 python3-barbicanclient-0:7.3.0-1.el10.noarch noarch/python3-barbicanclient-7.3.0-1.el10.noarch.rpm
ca487adbca896b706040545597c3e1dc7e53a31eb8b9d11c5db3b7d617cab852    164949 python3-castellan-0:5.6.0-1.el10.noarch noarch/python3-castellan-5.6.0-1.el10.noarch.rpm
52483061dc66fe0c77f07590f45ba1f14deb93496e0aa87b67f4097458f23633    280318 python3-cinderclient-0:9.9.0-1.el10.noarch noarch/python3-cinderclient-9.9.0-1.el10.noarch.rpm
14c3f725d0b53796b4c0dc2e873fee50991f8d2acce599c794631ce5df24f06e    106581 python3-cliff-0:4.13.3-1.el10.noarch noarch/python3-cliff-4.13.3-1.el10.noarch.rpm
46efa04cc208ef01d421ef38fb4a3a2932cd444011fe662a470e82bd7ece55c6      6469 python3-cliff-tests-0:4.13.3-1.el10.noarch noarch/python3-cliff-tests-4.13.3-1.el10.noarch.rpm
00c0b04af61a36ba84457942808e81aba74b1611e7c09954d4d192a61a48252c     65258 python3-cursive-0:0.2.3-1.el10.noarch noarch/python3-cursive-0.2.3-1.el10.noarch.rpm
57443b9fc515eb00ca8396f777c6e85dd4b37eeb7ed149ad0d6fabca2a59a9f6     36532 python3-debtcollector-0:3.0.0-1.el10.noarch noarch/python3-debtcollector-3.0.0-1.el10.noarch.rpm
bfaf5fdabbf766697984eec69843953c68f83a14a6a5fadda29f6c1b7ac3ccb7    120664 python3-designateclient-0:6.4.0-1.el10.noarch noarch/python3-designateclient-6.4.0-1.el10.noarch.rpm
0ba2ca64321bb8feca23a85001d7fef4e0ef1bdd060a4df309681ac7153e1d0e     48515 python3-designateclient-tests-0:6.4.0-1.el10.noarch noarch/python3-designateclient-tests-6.4.0-1.el10.noarch.rpm
84aa8fae9fe80abe5f23eb3170ca30aad4251593b382f5bd1d0e2d530c6f603a    919655 python3-django-horizon-1:25.7.3-1.el10.noarch noarch/python3-django-horizon-25.7.3-1.el10.noarch.rpm
5b7788bb120916c6ff7a574c658e65dc19181f4b5fa39cb0bb4ef2c04917e795     86914 python3-futurist-0:3.2.1-1.el10.noarch noarch/python3-futurist-3.2.1-1.el10.noarch.rpm
b767ed234412fb5ed5caeff58553dc01045e93dbae90a0e8cdf57cfd1fe92575    888872 python3-glance-1:32.0.0-1.el10.noarch noarch/python3-glance-32.0.0-1.el10.noarch.rpm
553768f21dc859eacd50a33e20f11a872fe45f3b80ca4536ac57121152f141d9    453796 python3-glance-store-0:5.4.1-1.el10.noarch noarch/python3-glance-store-5.4.1-1.el10.noarch.rpm
053a976475e2a04757727e2567075a2d2cc1529fa61c01b3ae959b78536bde09      7441 python3-glance-store+cinder-0:5.4.1-1.el10.noarch noarch/python3-glance-store+cinder-5.4.1-1.el10.noarch.rpm
331ea43c4ab5665360ade7d9f11d90a5476c3c486e393bdade031637aee91fc9      7313 python3-glance-store+swift-0:5.4.1-1.el10.noarch noarch/python3-glance-store+swift-5.4.1-1.el10.noarch.rpm
ecd14fcde30b5781d95a45f3e7c2636260fa486c311e57bac2b335b3dd6f7428   1089109 python3-glance-tests-1:32.0.0-1.el10.noarch noarch/python3-glance-tests-32.0.0-1.el10.noarch.rpm
3efd2f0e5c68a77e3b5a207f7bde2d2dfe52dd04227c25f0eeb483120b922b96    194632 python3-glanceclient-1:4.11.0-1.el10.noarch noarch/python3-glanceclient-4.11.0-1.el10.noarch.rpm
5aea0e2c1973935cace80f9e674240748e1f3e9f8d0757f4bad5fb034404c886   1140301 python3-keystone-1:29.1.0-1.el10.noarch noarch/python3-keystone-29.1.0-1.el10.noarch.rpm
9b315dca93c489b54dbebd522dbaa2f6018ae6a2233ebefd51faeba85e3e1c06   1295137 python3-keystone-tests-1:29.1.0-1.el10.noarch noarch/python3-keystone-tests-29.1.0-1.el10.noarch.rpm
ca60a650d18cc9402a7f16fce4c9a267da94027bc2e28b78be71862414dfc567      7317 python3-keystone+ldap-1:29.1.0-1.el10.noarch noarch/python3-keystone+ldap-29.1.0-1.el10.noarch.rpm
980529abc8a84906e7f7d1fca1b69a307521de164f3e77965231f4db2a2bc9c5    570142 python3-keystoneauth1-0:5.13.1-1.el10.noarch noarch/python3-keystoneauth1-5.13.1-1.el10.noarch.rpm
5ad3375a270607f9821c7baeeec80d33113c971f071bc8ca243e3c186702c549    289647 python3-keystoneclient-1:5.8.0-1.el10.noarch noarch/python3-keystoneclient-5.8.0-1.el10.noarch.rpm
b8bc70d957e34b24cec5e140aecea03558572b5f190eb9689c024b37806129e8    355939 python3-keystoneclient-tests-1:5.8.0-1.el10.noarch noarch/python3-keystoneclient-tests-5.8.0-1.el10.noarch.rpm
4a1e4f54ca53ce8306e25c330b6ab51226643111b7caa5d2cdf1d8b25d65aea7    125400 python3-keystonemiddleware-0:12.0.0-1.el10.noarch noarch/python3-keystonemiddleware-12.0.0-1.el10.noarch.rpm
974c23f8be8b4d4f1afe2c6346cbea8469b146a73ad83f0c757b53ed4ee6d938     37343 python3-microversion-parse-0:2.1.0-1.el10.noarch noarch/python3-microversion-parse-2.1.0-1.el10.noarch.rpm
5306c4c3b98867ff85cd7631a98384ef38b812b1250975670eff1af28fa28b02   3451656 python3-neutron-1:28.0.2-1.el10.noarch noarch/python3-neutron-28.0.2-1.el10.noarch.rpm
0b0aacaa9d2a78a9228e145f636b53e31265cf9a335bcd25e598c88f21431cbc    501091 python3-neutron-lib-0:3.24.0-1.el10.noarch noarch/python3-neutron-lib-3.24.0-1.el10.noarch.rpm
7e31f4c99b8f3d32e327edff69d959a24dd5315251925d9826d7b4bf5a35eed6    342450 python3-neutron-lib-tests-0:3.24.0-1.el10.noarch noarch/python3-neutron-lib-tests-3.24.0-1.el10.noarch.rpm
5de654ab7e523f8931fa165f9a1173ba92970a09da925986a09bf509034bed6d   4331633 python3-neutron-tests-1:28.0.2-1.el10.noarch noarch/python3-neutron-tests-28.0.2-1.el10.noarch.rpm
bb70fa14d3fe179f48585ff9b733341973d91f66f7a8e1f64b13b9eabfb3bd25    354202 python3-neutronclient-0:11.8.0-1.el10.noarch noarch/python3-neutronclient-11.8.0-1.el10.noarch.rpm
0796ca51e2148e6d8011a8e4a51d1306a779587ef6d799ef7dafb40b847000df    154949 python3-neutronclient-tests-0:11.8.0-1.el10.noarch noarch/python3-neutronclient-tests-11.8.0-1.el10.noarch.rpm
31de0c1a9c8f357894a21f20f57cd489520d52a5d49a33c297785da899e36126   3774927 python3-nova-1:33.0.2-1.el10.noarch noarch/python3-nova-33.0.2-1.el10.noarch.rpm
5003a59da6f0e84e1efb73330d2d83d2bcf7da2b3a505488596be97014364411   6157326 python3-nova-tests-1:33.0.2-1.el10.noarch noarch/python3-nova-tests-33.0.2-1.el10.noarch.rpm
41b12bd64f88564d6f4577711d7ad22c393d669b354fddeab4cc2d2cb6473a47    280868 python3-novaclient-1:18.12.0-1.el10.noarch noarch/python3-novaclient-18.12.0-1.el10.noarch.rpm
055930e5b1226fe3998142f8bba69efe8a8d087671d77863bfbeaafac78f2016   1118630 python3-openstacksdk-0:4.10.0-1.el10.noarch noarch/python3-openstacksdk-4.10.0-1.el10.noarch.rpm
c475c04f9502c8d176c57f85388901acc8cdece522b740668c5ea45a7c4e0618   1487477 python3-openstacksdk-tests-0:4.10.0-1.el10.noarch noarch/python3-openstacksdk-tests-4.10.0-1.el10.noarch.rpm
4f6625803823010c56a52d92c58a9280fdf53f76cb537cacfdc263f127915faa   1419600 python3-os-brick-0:7.0.0-1.el10.noarch noarch/python3-os-brick-7.0.0-1.el10.noarch.rpm
5aaaa3b13fceaac4f7baa28f86c08b484f10b40a1e8f19143658d17ff0ca5832     61321 python3-os-client-config-0:2.3.0-1.el10.noarch noarch/python3-os-client-config-2.3.0-1.el10.noarch.rpm
a0453656a3763ac8780c687df810d69046cab1be13018d1820f53b04deeb9d20   2507350 python3-os-ken-0:4.1.2-1.el10.noarch noarch/python3-os-ken-4.1.2-1.el10.noarch.rpm
21b453319227556706687c9e579f8fcbf4aeda51a5ff4fd7340b7bc734ec2cfe     17834 python3-os-resource-classes-0:1.1.0-1.el10.noarch noarch/python3-os-resource-classes-1.1.0-1.el10.noarch.rpm
e7ac786b5915576fb3c7d94820aa41166d4f3a52f21adf39c65c89b4b3344f1f     11733 python3-os-resource-classes-tests-0:1.1.0-1.el10.noarch noarch/python3-os-resource-classes-tests-1.1.0-1.el10.noarch.rpm
e93dfe591106614ce61a139896d7b8bb84e47dae3c7a14d2fd82dbb37decddc4     43929 python3-os-service-types-0:1.8.2-1.el10.noarch noarch/python3-os-service-types-1.8.2-1.el10.noarch.rpm
2a869067e53c8340165652ea11b52c44b5b625783559ebef1f93809b1e5fa841     53666 python3-os-traits-0:3.6.0-1.el10.noarch noarch/python3-os-traits-3.6.0-1.el10.noarch.rpm
bbf84c16017523abb9cbaf59c6e9c61b85fc63020985d3dfbc367d37181e9bda     14489 python3-os-traits-tests-0:3.6.0-1.el10.noarch noarch/python3-os-traits-tests-3.6.0-1.el10.noarch.rpm
54a897b17b3913b61629b86c47057126288e7dbcf5840ecc577bb9f638e69599    123816 python3-os-vif-0:4.3.0-1.el10.noarch noarch/python3-os-vif-4.3.0-1.el10.noarch.rpm
72c1ccde06c74981a21e6844f91a74176e1ff1ed782a58499dd2c2e52d5829b9    113316 python3-os-vif-tests-0:4.3.0-1.el10.noarch noarch/python3-os-vif-tests-4.3.0-1.el10.noarch.rpm
bab039e2d61f8c5813f507c824dfbea82e5d6a4f89123404c590a75073d4baac    117676 python3-osc-lib-0:4.4.0-1.el10.noarch noarch/python3-osc-lib-4.4.0-1.el10.noarch.rpm
757db394cacde72d2d10cce58140bc62775e0b9b44cc2927bb335ee6e2c73920     87922 python3-osc-lib-tests-0:4.4.0-1.el10.noarch noarch/python3-osc-lib-tests-4.4.0-1.el10.noarch.rpm
a820ab2817f410e952438c60e31410d923547c70fccf6c4197bfa45a1f34cf55     59847 python3-oslo-cache-0:4.1.1-1.el10.noarch noarch/python3-oslo-cache-4.1.1-1.el10.noarch.rpm
cd6733af28f66304c0d188bdcfefdd2dd60c5f762b992982499f9d7f75255f0a     45586 python3-oslo-cache-tests-0:4.1.1-1.el10.noarch noarch/python3-oslo-cache-tests-4.1.1-1.el10.noarch.rpm
077f9f23b64f7dfc2e84f41a45195b1c7a07a8938f4c46316ef7aaddc5ce0a9f      7417 python3-oslo-cache+dogpile-0:4.1.1-1.el10.noarch noarch/python3-oslo-cache+dogpile-4.1.1-1.el10.noarch.rpm
80b57be6796a6b3dfc6f27a3ede3e1c1c4bbb434484f48d79bd8783eb3e2296c      7281 python3-oslo-cache+etcd3gw-0:4.1.1-1.el10.noarch noarch/python3-oslo-cache+etcd3gw-4.1.1-1.el10.noarch.rpm
fc404829d8833d422e55278124aa9dbeecb9b14c468f593219e30f7aa003844f     54348 python3-oslo-concurrency-0:7.4.1-1.el10.noarch noarch/python3-oslo-concurrency-7.4.1-1.el10.noarch.rpm
e2d5dd1c0f1badac498419ff87ca6c817d86d440634af56ffc7273c9d62d8c9e     46449 python3-oslo-concurrency-tests-0:7.4.1-1.el10.noarch noarch/python3-oslo-concurrency-tests-7.4.1-1.el10.noarch.rpm
0d1c4a493ef56d5e990cde20b792a79a68503cf55cf75102c8570e334ed5867e    291919 python3-oslo-config-2:10.3.0-1.el10.noarch noarch/python3-oslo-config-10.3.0-1.el10.noarch.rpm
5731b83c716d3baa453d8e3e452285ca74edb75ae829a119f1f7d4581c42aebd     29328 python3-oslo-context-0:6.3.0-1.el10.noarch noarch/python3-oslo-context-6.3.0-1.el10.noarch.rpm
4e88eba856159cdd7a1cf370400fc6e0c876b3cc28a52290532b2d6fc3a142f4     26007 python3-oslo-context-tests-0:6.3.0-1.el10.noarch noarch/python3-oslo-context-tests-6.3.0-1.el10.noarch.rpm
c19a5753e0184e66ad103dd8908dcf2526580f25f72a7a26822ecff862f76f36    159659 python3-oslo-db-0:18.0.0-1.el10.noarch noarch/python3-oslo-db-18.0.0-1.el10.noarch.rpm
612a6def61b9fdd5ca7ae3fe55cfd652a27eec8546eb08d7ac3f4cc10fbfa3bd    161072 python3-oslo-db-tests-0:18.0.0-1.el10.noarch noarch/python3-oslo-db-tests-18.0.0-1.el10.noarch.rpm
9a337d1c9a3f633c52813f0fa9781ab3109f2ff09b6af6d0f105f8a63ef71bba      7221 python3-oslo-db+mysql-0:18.0.0-1.el10.noarch noarch/python3-oslo-db+mysql-18.0.0-1.el10.noarch.rpm
0d53609996a5ae8ca84d4ffc7e1d856bc38089b7448666541396d6491443fd8f     71175 python3-oslo-i18n-0:6.7.2-1.el10.noarch noarch/python3-oslo-i18n-6.7.2-1.el10.noarch.rpm
4bdd56c8008950d68d8b6d47d641f75adf98a164806c24aa1daef2ea2ae4218d     55767 python3-oslo-limit-0:2.10.0-1.el10.noarch noarch/python3-oslo-limit-2.10.0-1.el10.noarch.rpm
e58a5b0c73dbcb0436bbc7350fef243704fe5da247da516cdd1fd236795a450c     86161 python3-oslo-log-0:8.1.1-1.el10.noarch noarch/python3-oslo-log-8.1.1-1.el10.noarch.rpm
3ad30422755d5e0803a57ae030b4c1a2479af95032a830667a0e4b126cd89d14     76633 python3-oslo-log-tests-0:8.1.1-1.el10.noarch noarch/python3-oslo-log-tests-8.1.1-1.el10.noarch.rpm
69da108704a60caabd96f5e0267126b127d54fc836862afe25ea8d4638d98ac8    221242 python3-oslo-messaging-0:17.3.0-1.el10.noarch noarch/python3-oslo-messaging-17.3.0-1.el10.noarch.rpm
af618420a03fdd1b915378f6e52d6e1f30d9ebea717d890832e137b7403b9b90    173999 python3-oslo-messaging-tests-0:17.3.0-1.el10.noarch noarch/python3-oslo-messaging-tests-17.3.0-1.el10.noarch.rpm
042f7a05659a0c23f34a66bed124b3b4354a8b45a6b3541f38d62f50a7deb84d     28229 python3-oslo-metrics-0:0.15.1-1.el10.noarch noarch/python3-oslo-metrics-0.15.1-1.el10.noarch.rpm
e6521ada17d2447bddfe26dd94005ccef1a45664bd673841ce586cd5fb7ca02e     11935 python3-oslo-metrics-tests-0:0.15.1-1.el10.noarch noarch/python3-oslo-metrics-tests-0.15.1-1.el10.noarch.rpm
6dd811f182ac875c174706f843327ee6d1a4fd4bae210daa1dea008102ba42c7     72282 python3-oslo-middleware-0:8.0.0-1.el10.noarch noarch/python3-oslo-middleware-8.0.0-1.el10.noarch.rpm
eb8db19847d33d531aa73b67d36d4529c29efcc125f0842f9be72bd38be357d4     48537 python3-oslo-middleware-tests-0:8.0.0-1.el10.noarch noarch/python3-oslo-middleware-tests-8.0.0-1.el10.noarch.rpm
06892a1a98f54e5c99f94aedc4fc0bbdad3bc840e166a75449998ca341c20894    102020 python3-oslo-policy-0:5.0.0-1.el10.noarch noarch/python3-oslo-policy-5.0.0-1.el10.noarch.rpm
fc180d95ea1e4a929b3b1e66edbbfd192b828e09457520593fa256e058bc8568     96417 python3-oslo-policy-tests-0:5.0.0-1.el10.noarch noarch/python3-oslo-policy-tests-5.0.0-1.el10.noarch.rpm
0374c9dc446b60b3e34c0a11e5cb6e81a565525f1e2c094b7789ce9050c3f84e     57142 python3-oslo-privsep-0:3.10.1-1.el10.noarch noarch/python3-oslo-privsep-3.10.1-1.el10.noarch.rpm
ef66ed246933aa0a4c71a0a3910929afb75d69a325464f00529bcebe809aa730     34379 python3-oslo-privsep-tests-0:3.10.1-1.el10.noarch noarch/python3-oslo-privsep-tests-3.10.1-1.el10.noarch.rpm
eb960a1e39d61ea429940bba6073d2f6bba8ca844de5da426c6c98050cc26ad5     66752 python3-oslo-reports-0:3.7.0-1.el10.noarch noarch/python3-oslo-reports-3.7.0-1.el10.noarch.rpm
d3f9b64925e643c62b6e9a41029a302d64af4aa80a8195c41908ad64bc2dbc67     29554 python3-oslo-reports-tests-0:3.7.0-1.el10.noarch noarch/python3-oslo-reports-tests-3.7.0-1.el10.noarch.rpm
1f293eed0789ad8515638d09deb96e4adc018198eb99334a441ea0d9b2b48a3e     60113 python3-oslo-rootwrap-0:7.9.0-1.el10.noarch noarch/python3-oslo-rootwrap-7.9.0-1.el10.noarch.rpm
95dc6982467de3fe39257156ea958d35cb2a47a9826301dcc74ec005e2bef5b8     39779 python3-oslo-rootwrap-tests-0:7.9.0-1.el10.noarch noarch/python3-oslo-rootwrap-tests-7.9.0-1.el10.noarch.rpm
c3e9227fa4d701e3d2001a8a6b38f1d509aad73d70d0a6a5fd124d0f9a7944e2     41805 python3-oslo-serialization-0:5.9.1-1.el10.noarch noarch/python3-oslo-serialization-5.9.1-1.el10.noarch.rpm
df54adddcda99c72b2c27bee53b6c0deaef62caf3e5cd0e234c14786b11c3506     25331 python3-oslo-serialization-tests-0:5.9.1-1.el10.noarch noarch/python3-oslo-serialization-tests-5.9.1-1.el10.noarch.rpm
d2f723cfd3872a6674b3ee6b4b8a71c6c7c59264f3efccd72dc62f7d4d1322be    120428 python3-oslo-service-0:4.5.1-1.el10.noarch noarch/python3-oslo-service-4.5.1-1.el10.noarch.rpm
6f96a03609d905fc9c62ae46b5ed72221af27c0ad91ed705731171c38790acc9     99729 python3-oslo-service-tests-0:4.5.1-1.el10.noarch noarch/python3-oslo-service-tests-4.5.1-1.el10.noarch.rpm
9f89eabfc764746121110dfc103599c90b1808fdc21f5f5559b25095c6c0219c      7361 python3-oslo-service+threading-0:4.5.1-1.el10.noarch noarch/python3-oslo-service+threading-4.5.1-1.el10.noarch.rpm
9a1e0cfcdbc36476eeac96aea2b6e1eaf6cbd81fa00f42993a187db79f3a9a08     31330 python3-oslo-upgradecheck-0:2.7.1-1.el10.noarch noarch/python3-oslo-upgradecheck-2.7.1-1.el10.noarch.rpm
5b1e6972bc7ebbde288bd3c7f5d0faf7afb2255c9135c73652f70b3c7bce26d5    144638 python3-oslo-utils-0:10.0.1-1.el10.noarch noarch/python3-oslo-utils-10.0.1-1.el10.noarch.rpm
f4974008be5037a256265f2d276f02529570d4a87c152aeb91fe17200853ec8e    130551 python3-oslo-utils-tests-0:10.0.1-1.el10.noarch noarch/python3-oslo-utils-tests-10.0.1-1.el10.noarch.rpm
19948139463d8bdd1e27ad480213e7ac5451bd347ea8062d9931a483ea327f9f    102855 python3-oslo-versionedobjects-0:3.9.0-1.el10.noarch noarch/python3-oslo-versionedobjects-3.9.0-1.el10.noarch.rpm
df4f57405fea501106d4e0d018f59a7a5350c4aac20fd983087f900b6f366571    104524 python3-oslo-versionedobjects-tests-0:3.9.0-1.el10.noarch noarch/python3-oslo-versionedobjects-tests-3.9.0-1.el10.noarch.rpm
de2085a4fc2acba1694e849e02843907228cc67973b0fbd7afa92a56eb8ba0da    169611 python3-osprofiler-0:4.3.0-1.el10.noarch noarch/python3-osprofiler-4.3.0-1.el10.noarch.rpm
879b1cfaa68e824e8d76f06c67c4d8062003a51162094a042cd6464a3ba0c855    192330 python3-ovsdbapp-0:2.16.1-1.el10.noarch noarch/python3-ovsdbapp-2.16.1-1.el10.noarch.rpm
b5cdbf13fb2eeff69e25b87e11e0d4be139b3ebd469a3996eb7f282c8a4e42ab    153986 python3-ovsdbapp-tests-0:2.16.1-1.el10.noarch noarch/python3-ovsdbapp-tests-2.16.1-1.el10.noarch.rpm
ee82b1161aeb10379a97c232d1318db2ea394ce2c602b4a95d79b7da6a56cca3    327197 python3-placement-0:15.0.0-1.el10.noarch noarch/python3-placement-15.0.0-1.el10.noarch.rpm
37437583567e9c6e56b9bcfc2adf41dd327a830a1df16ef6cb2093cb9e314b8c    306563 python3-placement-tests-0:15.0.0-1.el10.noarch noarch/python3-placement-tests-15.0.0-1.el10.noarch.rpm
5ff54d78c39b32f2567d602bdcffefde94b96bfb3e8fb51920ccf31e6bf6a0b9     65428 python3-pycadf-0:4.0.1-1.el10.noarch noarch/python3-pycadf-4.0.1-1.el10.noarch.rpm
60c7528c4dfbc9a65fd316ae265dda34abfcd42405c00be49b09caae2dcac7d2    115505 python3-qrcode-0:8.2-1.el10.noarch noarch/python3-qrcode-8.2-1.el10.noarch.rpm
b919e67525480c38bfd762e413c1d707767dcbf409c196ab3910dc555fafcdd1     89303 python3-stevedore-0:5.7.0-1.el10.noarch noarch/python3-stevedore-5.7.0-1.el10.noarch.rpm
cdbb598deb4c0eb2c9b9362b5e26db4b1925f1c595cc1229de7c39be017f0419    834305 python3-taskflow-0:6.2.0-1.el10.noarch noarch/python3-taskflow-6.2.0-1.el10.noarch.rpm
d319aa1113dfe35b9e771b808e84eacc2460d2f9990a9df470046c9798e1126d    136967 python3-tooz-0:8.1.0-1.el10.noarch noarch/python3-tooz-8.1.0-1.el10.noarch.rpm
16c346f9141c0f903c0a3925a715b8bbe9dbfa1495f42f83f7eed8a4b1a7ef00      7193 python3-tooz+etcd3gw-0:8.1.0-1.el10.noarch noarch/python3-tooz+etcd3gw-8.1.0-1.el10.noarch.rpm
cc33edf04b8c1e5ff603e5d7df644e6abc33860c36338e3d8e884363f56f1ab6      7173 python3-tooz+redis-0:8.1.0-1.el10.noarch noarch/python3-tooz+redis-8.1.0-1.el10.noarch.rpm
fd793acc901ec7d457326082e4632e092f0eb5ff67d99e590203310b4fcf2695    180392 python3-wsme-0:0.12.1-1.el10.noarch noarch/python3-wsme-0.12.1-1.el10.noarch.rpm
bd713cb60e15139061be37145b3bd65f4bc02a047741134b9f0ee24636048558     12741 python3-XStatic-0:1.0.3-1.el10.noarch noarch/python3-XStatic-1.0.3-1.el10.noarch.rpm
739b5fe06ec85de50c9e588c3a51da5fda537c79084dc8e77835264b33869451    388794 python3-XStatic-Angular-0:1.8.2.3-1.el10.noarch noarch/python3-XStatic-Angular-1.8.2.3-1.el10.noarch.rpm
dc40dd41c30856e35d08e0e3792d5d0d49d4049d9697dc61fd6d18dc1fa1ccb3   1861985 python3-XStatic-Font-Awesome-0:6.2.1.2-1.el10.noarch noarch/python3-XStatic-Font-Awesome-6.2.1.2-1.el10.noarch.rpm
1935740f30d38227b778fa9f0387315554c3772844916d712d323798d00d260c    169351 python3-XStatic-jQuery-0:3.7.1.1-1.el10.noarch noarch/python3-XStatic-jQuery-3.7.1.1-1.el10.noarch.rpm
8f47c109db75bb1c4cfc509c1506c4be8624262a5971bbb648ed01b2caf194e7     22800 python3-XStatic-JQuery-Migrate-0:3.3.2.2-1.el10.noarch noarch/python3-XStatic-JQuery-Migrate-3.3.2.2-1.el10.noarch.rpm
eab2817e07ba29067a0b93f1095aa3583c37e0feda61ae0d1f106b76b72eff64     15958 python3-XStatic-JQuery-quicksearch-0:2.0.3.3-1.el10.noarch noarch/python3-XStatic-JQuery-quicksearch-2.0.3.3-1.el10.noarch.rpm
5dc21b8ea5b647ae81366ec5810fbcedc5fbe0d4469836b48f5988578115153c     27848 python3-XStatic-JQuery-TableSorter-0:2.14.5.3-1.el10.noarch noarch/python3-XStatic-JQuery-TableSorter-2.14.5.3-1.el10.noarch.rpm
ce3362a04d214f7a4e2b73d0a2ecfb41a6561c417fca0c8b6436df07e48a0894    558767 python3-XStatic-jquery-ui-0:1.13.0.2-1.el10.noarch noarch/python3-XStatic-jquery-ui-1.13.0.2-1.el10.noarch.rpm
9583e0032c0892d774954e38cc6454b5fd28a05f041984a10615b27c49ed80c9     42876 python3-XStatic-term-js-0:0.0.7.1-1.el10.noarch noarch/python3-XStatic-term-js-0.0.7.1-1.el10.noarch.rpm
```
