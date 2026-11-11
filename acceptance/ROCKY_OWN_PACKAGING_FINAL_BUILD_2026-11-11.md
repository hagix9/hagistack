# Hagistack's own RPM packaging — final x86_64 full build and licence check (2026-11-11)

Step 5 of the migration plan. The implementer self-tested this build. **No
independent audit was done.**

Nothing was pushed or released. Stage 6 (real-machine acceptance) was not started.

## Environment

- One temporary GCE VM: e2-standard-8, Rocky Linux 10.2 x86_64, run-id `hs1111r`.
  - It ran from 06:03 to 08:28 UTC, about 2 h 25 min, against a cap of 4 h.
  - Estimated cost was about US$1.1, against a cap of US$3.
- The VM, its router and NAT, its firewall rule, subnet and network were created
  for this task and deleted afterwards.
  - A residual check found none of them left.
  - Resources of other work were not touched. This includes a network that
    appeared during the run.
- Build: one run of the production path `hagistack rpm-prepare --rpm-source build`.
  - Tree: HEAD `adb43e5`.
  - Build input id: `4357bb3018e1b3a2`.
  - Builder image: rc4's pinned image.

## Required results

| # | Requirement | Result |
|---|---|---|
| 1 | 69 SRPMs from one build input | **met**. The single run passed 69/69 in pass 1, with no pass 2 and no RPM from another run |
| 2 | 195 x86_64 RPMs | **met**. 195 RPMs, repodata consistent. RPM set identity `b6906a1d8aa9503f…` |
| 3 | Names and EVR equal to rc4 | **met**. 195/195 names, 0 missing, 0 extra. No package differs in Epoch, Version, Release or Arch |
| 4 | Signature or pinned SHA-256 | **met**. 59 sources have `gpgverify` with a good signature from the pinned OpenStack release key. 10 PyPI sources are checked against a pinned SHA-256, and staging stops on any mismatch. Patches and extra licence texts are checked against a pinned SHA-256 |
| 5 | 0 build failures, 0 missing dependencies | **met** |
| 6 | No build-host data | **met**. The build-machine address guard is clean over 264 packages. A text scan of every payload for the host name, address, build directory and build id finds nothing. BUILDHOST is the fixed `hagistack-builder` |
| 7 | SHA256SUMS of SRPMs and RPMs | **met**. `RPM-SHA256SUMS` (from the build, equal to a recomputation) and `SRPM-SHA256SUMS`. The downloaded copies match both |

## Comparison with rc4 (all 195)

Classes:

- A: intended, no functional impact.
- B: functional impact unverified, or present under a condition.
- C: function lost, or installation blocked.

**No C was found.**

### Unchanged

- Configuration files under `/etc`: path, mode, owner, group and `%config` flag
  are equal for every file rc4 had. Three directories are added.
- Systemd units: only the four units rc4 shipped without a binary are absent.

### A

- **Removed Obsoletes.** Python 2 names, networking-ovn, ovn-migration-tool and
  python-keystoneauth. EL10 never shipped them. The legacy Provides are kept.
- **Added Provides.** `user()`/`group()` from sysusers.
- **Added Requires.** The functional dependencies restored in `351f4ce`.
  `-tests` packages require their base.
- **Removed Requires:**
  - test tools from `-tests` packages;
  - `-doc` packages requiring their library;
  - `/bin/sh` and platform-python where no scriptlet or Python wrapper remains;
  - version floors (haproxy, python3-libvirt) that EL10 exceeds.
- **Removed Requires that upstream does not use.** The upstream sources were
  searched:
  - `openssl` (keystone, nova);
  - `pytz` (oslo.serialization);
  - `pynacl` (oslo.db);
  - `debtcollector` (oslo.context);
  - `fontawesome-fonts-web` (horizon uses python3-XStatic-Font-Awesome 6).
- **osprofiler no longer requires oslo.messaging.** Only its optional messaging
  driver uses it, and that driver raises a clear error when it is missing. Every
  service that uses osprofiler requires oslo.messaging itself.
- **Dashboard uses python3-pymemcache instead of python3-memcached.**
- **Removed scriptlets:**
  - the dashboard's pretrans/post/preun. These were the upgrade path from an old
    `local_settings.d` layout and a `SECRET_KEY` rewrite. The installer writes
    the key; without one, Horizon's own key store is used;
  - nova-api's systemd scriptlets (it has no units).
- **Added scriptlets.** neutron-rpc-server's systemd scriptlets.
- **File differences:**
  - `dist.conf` files that are never read are not shipped;
  - `.doctrees` are not shipped;
  - `pbr.json` is not shipped;
  - the licence flag is set on dist-info licence files;
  - egg-info is now dist-info;
  - tests stay in some client libraries' site-packages;
  - sysusers/tmpfiles files are added;
  - `HAGISTACK-LICENSE` is added;
  - extra locale directories are added;
  - two neutron command modules are now executable.

### B

- **B-1. openstack-nova-novncproxy now only Recommends `novnc`** (rc4: Requires).
  - Hagistack's installer runs dnf with `install_weak_deps=False`, but it does
    not install novncproxy.
  - An operator who installs novncproxy without weak dependencies gets a proxy
    that exits at start, because `/usr/share/novnc` is missing.
  - Owner decision: make it Requires again, or keep it weak.
- **B-2. Sample configurations built against RDO trunk libraries.** See R-1.
  - The files are comments only, so service defaults are not affected.
  - The option texts they document are wrong for the shipped libraries.

## Finding R-1: own library names were satisfied by RDO trunk at build time

`build-env.lock` lists 35 packages whose names Hagistack builds, but at RDO
trunk versions. Examples:

- python3-oslo-log 7.2.1-0.20250903…;
- oslo.cache 3.12;
- oslo.db 17.4;
- oslo.context;
- keystoneauth1;
- openstacksdk.

### Cause

- `publish_repo()` excludes from the delorean repositories only the names
  already built.
- Round 1 builds in alphabetical order. python-castellan, the third package,
  pulled RDO's oslo.log, oslo.context and others before Hagistack built them.
- Later `dnf builddep` calls report them "already installed" and never replace
  them with Hagistack's versions.
- The fix in `351f4ce` (publish after every build) does not cover this case.

### Effect on the 195 RPMs

- Runtime code and Requires are not affected. The Requires are generated from
  each package's own metadata.
- Content generated at build time is affected. The sample configurations of
  keystone, nova, placement and the neutron packages (11 RPMs, checked) document
  oslo.log 7.2.1 options. Examples:
  - `watch_log_file`, which oslo.log 8.1.1 removed;
  - old `default_log_levels`;
  - missing oslo.db and oslo.cache options.

### Reproducibility

- Every SRPM rebuilt from the SRPM alone: 69/69 PASS.
- 175 of 195 RPMs are equal to the build in non-`.pyc` payload. 20 differ.
- A targeted rebuild of 5 SRPMs, in which every Hagistack name came from
  Hagistack's own repository, explains the 11 configuration RPMs.
- 9 differences are not analysed: 8 doc packages (including python-cinderclient-doc's HTML) and the cinder man page in
  python3-cinderclient.

### Licence

The generated text is upstream OpenStack option help (Apache-2.0), produced by
upstream code that RDO packaged. No RDO packaging file or text is involved.

### Fix (not implemented, not rebuilt)

- Exclude every name the definitions produce from the delorean repositories from
  the start, not only the names built so far.
- Fail the build when `build-env.lock` holds an own name not from
  `hagistack-own`.
- Then do one full build and compare again.

## Licence check (self-review, not independent)

### 6-1. RDO contamination

- 264 packages (24,887 files) were compared by SHA-256 with 131 RDO packaging
  files. The only matches are the two Hagistack neutron patches in
  `third-party/neutron/`. Those are upstream commits that Hagistack's own rc1
  SRPMs carried.
- No mention of rdo, delorean, rdoproject or distgit was found in:
  - the payloads' `/etc`, units, sysusers and tmpfiles;
  - the specs;
  - `defs/`, `files/` and `genspec.py`.
- Each of the 6 `files/` directories has an `AUTHORING.md` that covers every
  file in it.
- Every Hagistack file starts with "Written for Hagistack" where a comment is
  possible.
- The SRPMs separate the two origins. The upstream tarball (with its `.asc` and
  key) is apart from the Hagistack files and `HAGISTACK-LICENSE`.
- A hash mismatch alone is not taken as proof. The clean-room statements in
  `AUTHORING.md` are records by the authoring agents and were not verified
  independently.

### 6-2. Upstream licences

- **Sources.**
  - 57 Apache-2.0.
  - 1 Apache-2.0 AND MIT (horizon).
  - 9 MIT.
  - 1 BSD-3-Clause.
  - 1 CC-BY-4.0 AND OFL-1.1 AND MIT (Font Awesome).
- **No upstream NOTICE files exist.**
- **The two neutron patches** are Apache-2.0 upstream commits, documented in
  `third-party/neutron/NOTICE.md`.
- **Five XStatic packages** get their bundled component's licence text from
  `third-party/licenses/`. Each text is pinned by SHA-256.
- **SRPMs.** All 69 contain the spec, the source, its signature and key where
  signed, and `HAGISTACK-LICENSE`. 0 are incomplete.
- **Binary RPMs.** RPMs with Hagistack files carry `AND MIT` and ship
  `HAGISTACK-LICENSE`.
- **RPMs that ship no licence text.** 46 RPMs ship no licence text, or no Apache
  text. Every one of them is equal to rc4 in this respect:
  - extras and meta packages without files;
  - `-tests` packages, which require their base;
  - the nova and glance service packages, whose Apache text is in their python3
    package;
  - three doc packages (glance-doc requires openstack-glance;
    cinderclient-doc and keystonemiddleware-doc require nothing);
  - Font Awesome and term.js, whose licence is inside the data.
- **L-1.** The SRPM License tags of openstack-nova and openstack-placement read
  `Apache-2.0`, although the SRPMs contain MIT files. The tag comes from the main
  package, which has none.
- **L-2.** openstack-dashboard and python3-django-horizon read
  `Apache-2.0 AND MIT AND MIT`. This is a duplicate, harmless under SPDX.
- **L-3.** `third-party/licenses/NOTICE.md` and `third-party/neutron/NOTICE.md`
  still name the old pipeline's checks (`spec-adapt`, `build-rpms.sh`). The
  definitions now pin the same SHA-256s, and `test_genspec.py` checks them.

### 6-3. RDO binaries

- **Build time.** 128 of the 754 build packages came from RDO repositories.
  This includes the 35 own names of R-1. Nothing from them is copied into the
  RPMs except the generated content described in R-1.
- **Runtime.** A fresh install of the installer's package set takes 104 packages
  from the new set and 87 from RDO's dependency repository
  (`delorean-master-testing`). None of the 87 has a Hagistack name. They include:
  - Django;
  - eventlet;
  - kombu and amqp;
  - pyroute2;
  - 22 XStatic packages;
  - rdo-openvswitch;
  - openstack-network-scripts.

  **The published RPMs therefore need RDO's dependency repository at install
  time.** This must be stated with any publication.

## Install, replace and rebuild (in clean pinned containers)

**First attempt not valid.** The first attempt of these tests could not read the
mounted repositories under SELinux, so it tested nothing of the new set. It was
re-run with `--security-opt label=disable`. The first output is kept as
`attempt1-selinux`.

| Test | Result |
|---|---|
| Fresh install (15 top packages, 104 of ours) | rc 0. `rpm -V` clean. Users keystone 163, glance 161, nova 162 (in qemu and libvirt); neutron and placement are dynamic. 15 units pass `systemd-analyze verify`, and every ExecStart exists. 3 sudoers pass `visudo -c` (0440). 6 logrotate files pass `logrotate -d`. Imports pass, including pymysql. keystone-, glance-, placement-, neutron-db-, nova-manage and openstack run |
| Remove | nothing of ours left, no unit left |
| Replace rc4 by the new set (same NEVR) | rc 0. Every package now comes from the new set. Local edits of nova.conf and neutron.conf are kept, with 3 `.rpmnew` (the two edited files and rc4's key-rewritten local_settings). The same checks pass. Existing users keep rc4's shell and home |
| SRPM rebuild from SRPMs alone | 69/69 PASS. Payload as described under R-1 |

## Not covered

- Stage 6: deployment on real hosts.
- The 9 unanalysed reproducibility differences.
- An independent licence audit.
- A rebuild after the R-1 fix.
