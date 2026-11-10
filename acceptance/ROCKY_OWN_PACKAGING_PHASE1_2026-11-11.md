# Hagistack's own RPM packaging — phase 1 on x86_64 (2026-11-11)

Scope: show that RPMs and SRPMs compatible with rc4 can be built for x86_64
from Hagistack's own package definitions, with no RDO spec or distgit file as
an input. Three representative source packages: python-stevedore (plain
library), python-oslo-config (library with epoch, tools, -3 links and Sphinx
docs), openstack-glance (service: four binary packages, systemd units, sudoers,
logrotate, a system user, gettext catalogues, config files from upstream).

Self-tested by the implementer. No independent audit.

## Environment

- One temporary GCE VM, e2-standard-4, Rocky Linux 10.2 x86_64, run-id
  `hs1111p`, about 31 minutes. Created after Owner approval, deleted with its
  network resources afterwards; a residual check found none left.
- Builds ran in the pinned builder image rc4 used
  (`quay.io/rockylinux/rockylinux:10.2@sha256:827d37bc…`), with the same builder
  repositories as rc4 plus rc4's own repository for 2026.1 build dependencies.
- Source tree: commit `15d4f36` (branch `feat/rocky-own-packaging`).

## Results

| Check | Result |
|---|---|
| Build (`rocky10.2/packaging/build-own.sh`) | 3/3 PASS: 7 RPMs, 3 SRPMs. Upstream signature verified by `%gpgverify` in each build; import check ran |
| Package names, EVR | identical to rc4 for all 7 binary packages |
| Provides / Requires / Obsoletes / Recommends / scriptlet kinds | identical to rc4, except the differences listed below |
| Files, modes, owners, config flags | identical to rc4 except as listed below; 12 glance `.mo` catalogues present as in rc4 |
| Fresh install in a clean container | from the new repository; user and group `glance` 161; `rpm -V` clean; both units pass `systemd-analyze verify`; sudoers `visudo -c` OK, 0440; `logrotate -d` OK; rootwrap filter links resolve; `glance-manage`, `oslo-config-generator`, `glance.wsgi.api` import run |
| Remove | packages, units and config removed; the system user is kept (sysusers policy) |
| Swap rc4 → new (same NEVR, reinstall from the new repository) | succeeds; a local edit to `glance-api.conf` is kept with no `.rpmnew`; rc4's dist.conf files are removed (the now empty `/usr/share/glance`, which rc4 did not own, stays); the existing user is left as rc4 created it |
| Rebuild from the SRPMs alone in a fresh container | 3/3 PASS, signature verified; non-`.pyc` payload identical to the first build except python-oslo-config-doc (Sphinx output varies between builds, as in rc3/rc4) |
| RDO content | 2,184 payload files of the 7 RPMs and 3 SRPMs compared with RDO's 64 service files and 59 spec files: 0 identical files; no mention of RDO, delorean or distgit in any packaging file. SRPMs contain only the upstream tarball, its signature, the release key, the generated spec and Hagistack's files |

### Differences from rc4 (all intended or harmless)

- openstack-glance: no `/usr/share/glance/*-dist.conf` (never read at run
  time); adds `/usr/lib/sysusers.d/openstack-glance.conf` and owns
  `/etc/glance/metadefs`; gains `Requires: systemd` and `user(glance)` /
  `group(glance)` provides from the sysusers file. Unit, logrotate and sudoers
  contents are Hagistack's own (`files/openstack-glance/AUTHORING.md`).
- python3-oslo-config: no `Obsoletes: python2-oslo-config` (meaningless on EL10).
- python3-stevedore, python3-oslo-config: the licence is shipped in the
  dist-info licence directory (marked as licence) but not also copied to
  `/usr/share/licenses/<package>/` as rc4 did. To be aligned in phase 3.
- No `pbr.json` in dist-info (pbr writes it only from a git checkout).

## Fixes made during the run

1. `%pyproject_check_import` now imports top-level modules only; importing
   every submodule reached stevedore's example `setup.py` files and
   `oslo_config.fixture` (test-only dependency).
2. glance's doc build no longer asks for os-api-ref and whereto, which its
   Sphinx configuration does not load and the builder repositories lack.
3. Site-packages copies of the gettext catalogues are dropped from the saved
   file list too (the list comes from the wheel RECORD).
4. python3-glance requires python3-pyxattr: `glance/image_cache/drivers/xattr.py`
   imports it and upstream metadata does not list it.

## Not covered

Services were not started against a database; no all-in-one deployment; the
other 62 source packages; the build dependencies still come from the builder
repositories rc4 used (including RDO's binary dependency repositories) and from
rc4's own repository.
