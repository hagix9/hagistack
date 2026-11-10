# Rocky 10.2 — rc4 build from 7b12a35 (no build-machine address in the set) (2026-11-10)

Scope: the release candidate built from the branch head that keeps the build
machine's addresses out of the RPM set (7b12a35): neutron's generated sample
config gets `<host_ipv4>` / `<host_ipv6>` placeholders, and the builder refuses
a set in which any RPM or SRPM contains one of its own addresses. Approved by
the Owner on 2026-11-10. This is the implementer's run, not an independent audit.

Code under test: `git archive 7b12a354d44ccc9ef031e48925baf42039048eb3`, no local
modification. Build-input identity `5ddeb7af1b4aa93c`. It matches the value
computed locally before the run. rc3 was built from `d689560` (`c81e4cd0f818f6eb`).

## Environment

- Google Compute Engine, one zone, a VPC created for this run only (IAP SSH,
  Cloud NAT, no external IP).
- One VM: n2-standard-8, pd-standard 100 GB, stock Rocky Linux 10.2 (x86_64),
  nested KVM.
- VM time ≈ 62 min (12:42–13:44 UTC). Estimated cost ≈ US$0.7 (list prices,
  not billing data).
- Everything created was deleted and its absence checked.

## Results

| Check | Result |
|---|---|
| Full build (`rpm-prepare --rpm-source build`) | exit 0, ≈ 40 min. Pass 1: 66 PASS, 3 FAIL (build order). Pass 2: the 3 PASS. 69/69 packages. `build.ok`: `packages=69 rpms=195 srpms=69` |
| Address guard in the build | `no build machine address in 264 packages (2 addresses searched)` (195 RPMs + 69 SRPMs) |
| Independent scan (not the guard's code) | the VM's addresses from `ip addr` and its host name, full and short, in every RPM and SRPM payload: 0 packages with a hit |
| `/etc/neutron/neutron.conf` (`openstack-neutron-common`) | `#my_ip = <host_ipv4>`, `#my_ipv6 = <host_ipv6>`. Compared with rc3, only these two lines differ |
| Integrity | `RPM-SHA256SUMS` 195/195. `rpm -K` 0 failures. BUILDHOST `hagistack-builder` 195/195 |
| Set identity | `a7c372bdd648a03a84ab1727b39d9e7130b7bf6fa5dc7ad205d0138790aebf72` |
| python3333 fix | binary unit `ExecStart=/usr/bin/python3 -m neutron.cmd.destroy_patch_ports …`. SRPM copy is the RDO original (SHA-256 `1608a97a…`). `/usr/bin/python33…` in any `.service`: 0 |
| Fixes 1–3 | dashboard: 0 entries under `static/horizon/lib`, 0 bundles. The five LICENSE-row XStatic RPMs install their licence file. Font Awesome `CC-BY-4.0 AND OFL-1.1 AND MIT` |
| rc4 candidate (`make-rpm-release.sh`) | exit 0, every guard ok. Asset `hagistack-rpms-rocky10.2-rpms-2026.1-rc4-el10-x86_64.tar`, SHA-256 `25d03d26ef6604ce04aa4507b53cc310b97de08a7957249a1948c243e4d70870`. `MANIFEST_SHA256` matches the committed manifest. Nothing published |
| All-in-one from rc4 | the set was reused (same build inputs, still verifies). Every phase completed. Horizon sign-in test PASS. Static libraries rebuilt (26). The four Neutron units active, with the placeholder lines in the installed `neutron.conf`. One guest ACTIVE (25 s), SSH with the metadata key, metadata hostname |

## Every RPM compared with rc3 (file names and digests)

- 48 of 195 RPMs have identical file contents. 147 differ in 21,597 files:
  - **19,874 `.pyc`:** CPython embeds the source mtime. All 9,937 corresponding
    `.py` sources are identical.
  - **55 `pbr.json`:** the git hash of the throw-away repository that
    `%autosetup -S git` creates during the build.
  - **Sphinx output** in `-doc` packages (HTML, `searchindex.js`,
    `environment.pickle`). `searchindex.js` differs in entry order.
  - **Three man pages** (`cinder.1`, `glance.1`, `nova.1`): the build date in
    the `.TH` line (rc3 was built on 2026-11-09 UTC, rc4 on 2026-11-10).
- Headers (name, version, licence, summary, Requires, Provides) are identical
  for all 147 RPMs.
- One file carries a content change: `/etc/neutron/neutron.conf`, the fix.
- This is a build-to-build comparison. It is not a reproducibility claim.

## Not covered

- The guard searches unpacked payloads, scriptlets, triggers and changelogs.
  Source tarballs inside the SRPMs are pinned upstream inputs and are not unpacked.
- The per-package build logs kept under the build directory are not part of the
  release assets and were not scanned.
- The remote compute node, controller-only, and the database-check abnormal path
  were not repeated. Their code paths are unchanged, and the 2026-11-09
  acceptance stands for them.

## Verdict

rc4 contains no address of the machine that built it. The python3333 fix and
fixes 1–3 are kept. The rc4 set installs and runs as all-in-one. RPM publication
still depends on the Owner's U-1 decision and on an independent audit.
