# Hagistack's own RPM packaging — first x86_64 full build of all 69 definitions (2026-11-11)

Step 3-5 of the migration plan. Self-tested by the implementer. No independent
audit. **Not a release candidate**: the build found dependency gaps that were
fixed afterwards (commit `351f4ce`) and have not been rebuilt yet.

## Environment

- One temporary GCE VM, e2-standard-8, Rocky Linux 10.2 x86_64, run-id
  `hs1111q`, 00:59–04:50 UTC (about 3 h 50 min, within the 4 h stop rule).
  Created after Owner approval; it and its network resources were deleted
  afterwards and a residual check found none left.
- Builds ran in the pinned builder image of rc4. The production path is
  `hagistack rpm-prepare --rpm-source build`, which runs build-in-container.sh,
  now driving `packaging/build-own.sh`.

## Runs

| Run | Commit | Result |
|---|---|---|
| A1 production path, and B (rc4 repository as bootstrap, import check on), in parallel | `c975b3f` | both 58–59/69; the same 11 failures, so the bootstrap made no difference |
| A2 production path | `1974551` | 68/69; neutron's builddep failed (an EPEL python3-pyOpenSSL needs a cryptography EL lacks) |
| A3 production path | `5f8e48b` (`--nobest`) | 68/69; neutron failed on an ambiguous `#!/usr/bin/env python` in an upstream test helper |
| C completion of A3's build area | `0559f3d` (shebang fix, publish existing RPMs first) | neutron PASS; `collect_result` of build-in-container.sh: **195 RPMs, 69 SRPMs**, build-machine address guard clean (264 packages) |

The complete 195/69 set is therefore A3's 68 source packages plus neutron
rebuilt on a copy of A3's build area. A single production-path run building
all 69 at once has **not** been shown yet.

## Checks on the complete set

| Check | Result |
|---|---|
| Names and EVR vs rc4 | 195/195 identical; nothing missing, nothing extra |
| Payload vs RDO packaging (64 service files + 59 specs, by SHA-256) | 24,790 files in 264 packages: no RDO file. The only two matches are the upstream neutron patches Hagistack itself carries in `third-party/neutron/`. No mention of RDO, delorean or distgit in packaging files or specs |
| Fresh install of the installer's package set (87 packages) in a clean container | `rpm -V` clean; users keystone 163, glance 161, nova 162 (in qemu and libvirt), neutron and placement dynamic; 15 units pass `systemd-analyze verify` and every ExecStart exists; 3 sudoers pass `visudo -c` (0440); 6 logrotate files pass `logrotate -d`; keystone-, glance-, placement-, neutron-db-, nova-manage and openstack run |
| Remove | nothing of ours left, no unit left |
| Replace rc4 by the new set (same NEVR) | the reinstall succeeded; the checks after it did not finish before the stop rule and are not recorded |
| SRPM rebuild from the SRPMs alone | 68/69 PASS; neutron failed because the rebuild script lacked `--nobest` (test script defect). Non-`.pyc` payload identical to the build for 166 of 180 RPMs; the 14 others are Sphinx output, a man page date, and generated sample configurations |

## Findings, and what was changed after the run (commit `351f4ce`, not rebuilt)

1. **Functional dependencies rc4 declared but upstream metadata does not**:
   - system tools for neutron's agents (dnsmasq, haproxy, keepalived, ipset, iptables, conntrack-tools, radvd, ...);
   - for nova-compute: libvirt drivers, QEMU parts, xorriso, rsync and libguestfs;
   - os-brick's storage tools;
   - python3-openvswitch for ovsdbapp and os-ken;
   - openssh, sudo and python3-memcached for nova;
   - **PyMySQL** (through oslo.db's mysql extra);
   - the extras and -lang packages that libraries pulled in.

   All were restored with reasons; without PyMySQL a node could not reach its database.
2. Legacy names rc4 provided (python3-networking-ovn, python-keystoneauth,
   os-brick, django-horizon, ...) are provided again. The python2-era Obsoletes
   are not restored (meaningless on EL10).
3. `-tests` packages now require the package they test.
4. `build-own.sh` publishes every package as soon as it builds. Before that, a
   service built later in the same round generated its sample configuration
   against RDO trunk's library versions: `nova.conf` differed between two builds
   (option texts and defaults of oslo.log and oslo.db, no host data).
5. Already fixed during the run:
   - PEP 639 licence metadata;
   - two Sphinx extensions;
   - a doc file name;
   - the WSME namespace .pth;
   - psutil's version (Rocky ships 5.9.8);
   - the system tzdata instead of PyPI's;
   - `--nobest`;
   - publishing existing RPMs before the first round;
   - neutron's ambiguous shebang.

## Intended differences that remain

- dist.conf files that are never read, dead units (neutron-server, three nova API units), and upgrade-only scriptlets are not shipped.
- sysusers/tmpfiles files are added.
- Test tools are no longer required by `-tests` packages.
- Tests stay in some client libraries' site-packages, which rc4 removed.
- No `.doctrees` in HTML docs.
- Dashboard uses python3-pymemcache instead of python3-memcached.

## Not covered

- An all-in-one or multi-node deployment (step 3-6).
- The replace test's final checks.
- A single production-path run of all 69 on the latest commit.
- Cross-host nova resize/cold migration (the migration wrapper rejects SFTP-mode scp; Owner decision pending).
