# Hagistack's own RPM packaging — third full build after the R-2 fix (2026-11-11)

This is the one full build the Owner approved with the R-2 fix
("Hagistack：R-2修正・独自RPM最終ビルド"). The implementer self-tested it.
**No independent audit was done.**

Nothing was pushed or released. Stage 6 (real-machine acceptance) was not started.
No further full build was started after this one.

## Result: PASS — 195 RPMs and 69 SRPMs from one production build

- Tree: HEAD `b46fe31` (the R-2 fix), exported as an archive and built by
  `hagistack rpm-prepare --rpm-source build`. Build input id `384eee75bb32ce5e…`.
- `rpm-prepare` returned 0. All 69 definitions passed in one run (pass 1 only).
  - Rounds 1 to 5 tried 69, 45, 34, 18 and 8 definitions and built 24, 11, 16, 10
    and 8.
  - %check was not run, as in every earlier build of this pipeline.
- 195 x86_64-set RPMs and 69 SRPMs were collected. RPM set identity
  `6c43da51144ca01c413f5c7dbbc44be70b66f03df69e77b3e632c2d55b8a1313`.
- The RPMs were not assembled from several commits or runs.

## R-2 fix (commit `b46fe31`)

- `packaging/own-excludes.py` adds the 195 names to every section of every
  repository file except `hagistack-own.repo`:
  - RDO, EPEL, Rocky and any other repository, enabled or not;
  - an existing `exclude=` / `excludepkgs=` is kept and extended;
  - a repeated run gives the same file (each written line records the original).
- A failed rewrite, or a repository defined in `dnf.conf`, stops the build.
- `build-own.sh` applies the exclusion before the first build and again before every
  dependency install, so a repository file added later is covered too.
- `build-own.sh` asks DNF itself which repositories still offer one of the names.
  It does this before the first build and at the end, and an offer from any
  repository but `hagistack-own`, or a failed query, stops the build.
- Before the first build, a package with one of the names that is already
  installed from elsewhere stops the build.
- A waiting definition is retried only after a new RPM of this build exists. This
  also covers a dependency on our libraries that comes in indirectly, for example
  through EPEL's cliff. Rounds still stop when a round builds nothing.

## Checks before GCE and before the build

- Local: `test-build-own.sh` 33/33, `test_genspec.py` 20 OK, 69/69 specs generated.
- On the VM in the pinned builder image: every suite passed (93, 54, 13, 33 checks
  and 71 unit tests).
- Real DNF in the pinned image with the builder's repositories:
  - before the exclusion, the enabled repositories offered our names 241 times,
    including 47 from EPEL and 1 from AppStream;
  - after it, 0 times, with all repositories enabled too;
  - unrelated packages, such as PyMySQL, cliff and requests, stayed available;
  - existing excludes were kept.

## Required results

| # | Requirement | Result | Basis |
|---|---|---|---|
| 1 | 69 SRPMs from one build input | 69 | real files |
| 2 | 195 x86_64 RPMs | 195 | real files |
| 3 | all 69 definitions succeed | 69 PASS, 0 fail | test run |
| 4 | own names from RDO at build time | 0 | DNF transaction logs |
| 5 | own names from EPEL | 0 | DNF transaction logs |
| 6 | own names from any other external repository | 0 | DNF transaction logs |
| 7 | origin of own RPMs confirmed | yes | transaction repo and EVR, lock vs built EVR |
| 8 | upstream signature and SHA-256 | 59 Good signature; 69/69 SHA-256 | build logs, SRPM contents |
| 9 | no build-host data | 0 hits | header and payload scan |
| 10 | SHA256SUMS and build environment saved | yes | real files |

### Origin of every package with one of our names

- Classified by the repository DNF installed it from and by its EVR, not by name.
- All 69 dependency-install transactions held 458 install rows. 75 of them have one
  of our names, and all 75 came from `hagistack-own`.
  - 0 came from RDO, EPEL, Rocky or any other repository.
- All 75 have the EVR of the RPM this build made. The first comparison reported 4
  mismatches; they came from a scripting error that dropped the epoch on one side.
  With the epoch kept on both sides, all 4 are equal.
- `build-env.lock` lists 79 packages with our names, and all 79 equal the EVR.arch of
  this build's RPM.
- The build log has these lines:
  - "195 package names excluded from every other repository (RDO, EPEL, Rocky, ...)
    before the first build"
  - "no package with one of our names is installed from elsewhere before the first
    build"
  - "every installed package with one of our names came from this build"
  - No line reports an offer from another repository at the end.
- At build time, 93 of the 754 environment packages came from RDO repositories
  (run 1: 128). None of them has one of our names; examples are cliff, reno and
  swiftclient.

### Sources

- 59 OpenStack-origin definitions: `gpgverify` reported Good signature with the key
  pinned in `gazpacho.manifest`.
- 10 PyPI-origin definitions (XStatic and qrcode) have no upstream signature. They
  are verified by the pinned SHA-256 only.
- The build stops if a pinned SHA-256 does not match. The tarball inside each of the
  69 SRPMs was also extracted and matched its definition's SHA-256: 69/69.

## Comparison with rc4 (all 195 RPMs)

- Names and EVRs: 195/195 equal; nothing is missing or extra.
- Metadata differences: files 102, requires 57, obsoletes 8, provides 6,
  recommends 3, scripts 3, conflicts 0.
- Against run 1's comparison (all classified in
  `ROCKY_OWN_PACKAGING_FINAL_BUILD_2026-11-11.md`), 4680 of 4681 comparison files
  are byte-identical. That keeps run 1's classification for all of them.
- The one changed file is `python-taskflow-doc`'s file list. 19 generated pages are
  missing: source views of optional backends and three inheritance diagrams.
  - Sphinx could not import those backends (etcd, redis, zookeeper, sqlalchemy,
    worker-based engine) in the build environment.
  - Class A: documentation only.

### Classification

- **C (lost function or blocked installation):** none.
- **B (functional effect not verified):**
  - **B-1:** `openstack-nova-novncproxy` has `novnc` as Recommends, where rc4 had
    Requires. This is unchanged and still awaits the Owner's decision.
- **B-2 of run 1 is resolved.** The generated sample configurations now follow
  this build's own oslo libraries.
  - `nova.conf`, `keystone.conf` and `placement.conf` no longer list oslo.log's
    removed `watch_log_file`, and they gain oslo.db 18's `synchronous_reader`.
  - `glance-api.conf`, `glance-cache.conf` and `glance-scrubber.conf` still mention
    `watch_log_file`. They are byte-identical to the upstream glance 32.0.0 tarball.
- **A:** everything else, as in run 1:
  - user and group provides from sysusers;
  - obsoletes of python2 and networking-ovn names, which rc4 inherited;
  - Recommends for dnsmasq, haproxy and keepalived, and for spice-html5;
  - scriptlet differences in dashboard, nova-api and neutron-rpc-server;
  - documentation file lists;
  - the taskflow-doc pages above.

### Focus items (in the new metadata, and installed)

- **PyMySQL:** `python3-oslo-db+mysql` requires `python3.12dist(pymysql) >= 0.7.6`,
  and it imports after a fresh install.
- **Neutron external tools:** conntrack-tools, dibbler-client, dnsmasq,
  dnsmasq-utils, haproxy, iproute-tc, ipset, iptables, keepalived, openvswitch,
  radvd and sudo.
- **Nova:** libvirt and its daemon drivers, python3-libvirt, qemu-img, qemu-kvm
  and qemu-kvm-core, qemu-kvm-block-rbd, virtio-vga, xorriso and openssh-clients.
- **os-brick:** cryptsetup, device-mapper-multipath, iscsi-initiator-utils,
  lsscsi, nvme-cli and sg3_utils.
- **`-tests` packages:** all 31 carry a versioned (`=`) Requires on their base package.
- **Old-name Provides:** no rc4 Provides is missing.
- **Extras and `-lang`:** 19 of them, all present with rc4's EVR.

## Licences (195 RPMs and 69 SRPMs)

- **RDO packaging files:** the payload scan of all 264 packages (24877 files) found
  2 files identical to an RDO packaging file and 0 mentions of RDO.
  - The 2 files are Hagistack's own neutron patches, upstream Apache-2.0 commits
    documented in `third-party/neutron/NOTICE.md`.
- The clean-room records (`files/*/AUTHORING.md`) are unchanged since run 1. They
  are the authoring agents' statements and were not verified independently.
  Independence is not inferred from hash mismatches alone.
- **L-1 fixed:** the SRPM License tags of openstack-nova and openstack-placement
  now read `Apache-2.0 AND MIT`.
- **L-2 fixed:** openstack-dashboard and python3-django-horizon read
  `Apache-2.0 AND MIT`, without the duplicate.
- **L-3 fixed:** the two `third-party/*/NOTICE.md` files name `defs/` and
  `test_genspec.py` as the check. They mention the old pipeline only as the older
  path.
- **SRPMs:** all 69 contain the spec, the source, its signature and key where
  signed, the pinned patches and licence texts, and `HAGISTACK-LICENSE`.
  0 are incomplete.
- **RPMs without a licence text:** the same set as run 1 and rc4. These are extras,
  meta, `-tests` and service subpackages that depend on a package carrying the text,
  plus three doc packages and Font Awesome and term.js, whose licence is inside the
  data.
- **New gap L-4:** `rocky10.2/THIRD_PARTY_NOTICES.md` still says "The RPMs are
  built from the RDO distgit packaging" at commits pinned in `gazpacho.manifest`.
  - The file is copied into every release candidate by `make-rpm-release.sh`.
  - That is no longer true for this RPM set.
  - Fix: describe the own definitions (`packaging/defs/`, `genspec.py`, `files/`
    under MIT, upstream sources pinned and signature-checked).
  - Also state there that installing needs RDO's dependency repository: a fresh
    install takes 87 packages from `delorean-master-testing`, none with one of our
    names.
  - This is not fixed here; it needs the Owner's go-ahead.

## Install, replace and rebuild (clean pinned containers)

- **Fresh install** (rc 0):
  - `rpm -V` of our packages showed no differences.
  - The users and 15 units checked out, with every ExecStart present.
  - 3 sudoers files and 6 logrotate files passed their checks.
  - Imports passed, including pymysql, and 6 management commands ran.
  - The placement vhost and the dashboard files are present.
  - Remove: 0 packages and 0 units were left.
- **Replace rc4** (rc 0):
  - Local edits were kept, with 3 `.rpmnew` files, and the same checks passed.
  - `rpm -V` shows only the 3 edited config files.
  - The users keep the attributes rc4 created: placement's shell `/bin/bash`, and
    nova in the `nobody` group. This is the same as run 1.
- **Rebuild from the SRPMs alone** (our names excluded from every other repository
  with the same tool):
  - 69/69 passed, and 0 packages with our names were installed from elsewhere.
  - Non-`.pyc` payload is identical for 182 of 195 RPMs (run 1: 175).
  - The 13 that differ are 12 doc packages (Sphinx HTML and search indexes) and the
    cinder man page. No configuration or code file differs.

## Not done or not verified

- Stage 6 (real machines).
- Independent audit, including of the licences.
- The cause of the 13 documentation differences on rebuild.
- %check of the packages; it is not run by this pipeline.
- Fixes for B-1 (Owner decision) and L-4.

## GCE

- Temporary resources of run-id `hs1111t`: VM `hagistack-or-n1` (e2-standard-8,
  Rocky Linux 10.2 x86_64, 100 GB pd-balanced), with its network, subnet, IAP
  firewall rule, router and NAT.
- They ran from 11:08 to 14:50 UTC, 3 h 42 min, against a cap of 4 h. The estimated
  cost is about US$1.4 at list prices, against a cap of US$3.
- All of them were deleted, and a residual check at 14:50 UTC found none left.
- Other work's resources were not touched. Between the start and the end:
  - the three `mkg-f5r20-*` instances and their network disappeared;
  - `sinter-v180-gate2-o6s1a` changed to RUNNING;
  - a NAT address of `sinter-v180-relv-router` was created at 13:45 UTC.
- The aarch64 Lima VM was not touched.

## Evidence (outside the repository)

`<TMP_WORKSPACE>/hagistack-ownpkg-2026-11-11/run-final3/` (the external temporary workspace):

- `artifacts-384eee75bb32ce5e/out/`: the 195 RPMs, 69 SRPMs, repodata,
  `RPM-SHA256SUMS` and `build-env.lock`. The local files match the SHA-256 lists
  made on the VM.
- `evidence-vm/ev3/`:
  - `SHA256SUMS.rpm` and `SHA256SUMS.srpm`, and `final.log`;
  - the build logs (`out-logs/`, `work-logs/`);
  - the origin check (`origin/`), `sig-per-def.txt` and `srcsha.out`;
  - `hostscan`, `compare/`, `payload.out` and `license.out`;
  - `fresh`, `replace`, `srpm` and `rdodeps`.
- `evidence-pre/`: the suites and the real-DNF exclusion check.
- `cfgcheck/`: the sample-configuration comparison with run 1.
- `gce/`: the estimate, the state before creation, and the creation, deletion and
  residual logs.
- `scripts/`: the verification scripts that were used.
- `tree-b46fe31.tar`: the exact tree that was built.
