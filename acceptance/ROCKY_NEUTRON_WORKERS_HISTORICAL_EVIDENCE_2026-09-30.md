# Rocky Neutron workers: historical evidence extract

Source: 2556d832d9317aa7f4b5e9d4c2c675f66b4ae63f, acceptance/WP-A_NEUTRON_WORKERS_2026-09-30.md, sections4–8 reproduced verbatim below. This is historical evidence for cb3154a, not a new test run. It includes original limitations/incidents; the later PATH-B/runtime reports close the lock-specific gaps for40472e8. Ubuntu sections are excluded. WP-A MERGE remains HOLD.

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

