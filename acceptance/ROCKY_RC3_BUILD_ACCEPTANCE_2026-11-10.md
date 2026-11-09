# Rocky 10.2 — rc3 build from d689560 (python3333 fix) (2026-11-10)

Scope: the release candidate built from the current branch head, which adds the
build-rpms.sh re-staging fix for `neutron-destroy-patch-ports.service`
(`ExecStart=/usr/bin/python3333` in rc1/rc2). Approved by the Owner on
2026-11-10. This is the implementer's run, not an independent audit.

Code under test: `git archive d6895600ae7672241cdbe9f5e4f9bf89f5685a51`, no local
modification. Build-input identity `c81e4cd0f818f6eb`. It matches the value
computed locally before the run. rc2 was built from `aa19a5d` (`0c154e6518889f59`).

## Environment

- Google Compute Engine, one zone, a VPC created for this run only (IAP SSH,
  Cloud NAT, no external IP).
- One VM: n2-standard-8, pd-standard 100 GB, stock Rocky Linux 10.2 (x86_64),
  nested KVM.
- VM time ≈ 62 min (21:56–22:58 UTC). Estimated cost ≈ US$0.7 (list prices,
  not billing data).
- Everything created was deleted and its absence checked.

## Results

| Check | Result |
|---|---|
| Full build (`rpm-prepare --rpm-source build`) | exit 0, ≈ 37 min. Pass 1: 66 PASS, 3 FAIL (build order). Pass 2: the 3 PASS. 69/69 packages. `build.ok`: `packages=69 rpms=195 srpms=69` |
| Integrity | `RPM-SHA256SUMS` 195/195. `rpm -K` 0 failures. BUILDHOST `hagistack-builder` 195/195 |
| Set identity | `c7e3e619c7bc6a9f064a6c81ebca9a47fc9872400daf9f4570025f9e1ea7aacd` |
| Binary unit (`openstack-neutron-openvswitch`) | `ExecStart=/usr/bin/python3 -m neutron.cmd.destroy_patch_ports …` |
| SRPM copy of the unit | the RDO distgit original (`ExecStart=/usr/bin/python …`). SHA-256 `1608a97a…`, identical to the file at distgit commit `fa1f5135` |
| `/usr/bin/python33…` in any `.service` of the set | 0 |
| Fixes 1–3 | dashboard: 0 entries under `static/horizon/lib`, 0 bundles. The five LICENSE-row XStatic RPMs install their licence file. Font Awesome `CC-BY-4.0 AND OFL-1.1 AND MIT` |
| rc3 candidate (`make-rpm-release.sh`) | exit 0, both licence guards ok. Asset `hagistack-rpms-rocky10.2-rpms-2026.1-rc3-el10-x86_64.tar`, SHA-256 `66fa0620a0cd230e825125a859f9dc7bfbfe51f52ac274b827a7101670195f00`. Nothing published |
| All-in-one from rc3 | every phase completed. Horizon sign-in test PASS. Static libraries rebuilt (26). The four Neutron units active. One guest ACTIVE (24 s), SSH with the metadata key, metadata hostname |

## Every RPM compared with rc2 (file names and digests)

- 57 of 195 RPMs have identical file contents. 138 differ in 21,509 files:
  - **19,788 `.pyc`:** CPython embeds the source mtime. All 9,894 corresponding
    `.py` sources are identical.
  - **55 `pbr.json`:** these record the git hash of the throw-away repository
    that `%autosetup -S git` creates during the build.
  - **About 1,600 Sphinx HTML and index files** in `-doc` packages.
- Headers (name, version, licence, summary, Requires, Provides) are identical
  for all 138 RPMs.
- Two files carry content changes:
  1. `neutron-destroy-patch-ports.service`: the fix (`python3333` → `python3`).
  2. `/etc/neutron/neutron.conf` in `openstack-neutron-common`: one commented line,
     `#my_ip = <build VM private IP>`. The value is different in each build. See
     "Finding" below.
- This is a build-to-build comparison. It is not a reproducibility claim.

## Finding (not fixed here): the build VM's address in a generated sample config

The build container runs with `--network host`. oslo-config-generator writes the
running host's IPv4 address as the commented default of neutron's `my_ip`.

- rc1, rc2 and rc3 therefore each carry the private address of the VM they were
  built on, in one commented line of `openstack-neutron-common`'s `/etc/neutron/neutron.conf`.
- A scan of every RPM and SRPM payload in rc3 for that address and for the VM
  host name found only this one line.
- It has no functional effect.
- It is a publication-hygiene item of the same kind as the BUILDHOST check, and
  is left to the Owner's decision.

## Not repeated

The remote compute node, controller-only, and the database-check abnormal path
were not repeated. Their RPMs and code paths are unchanged apart from build
timestamps, and the 2026-11-09 acceptance stands for them.

## Verdict

The python3333 defect is fixed in rc3 and in its source RPM. Fixes 1–3 are kept.
The rc3 set installs and runs as all-in-one. RPM publication still depends on
the Owner's U-1 decision and on an independent audit. The `my_ip` hygiene item
above is open.
