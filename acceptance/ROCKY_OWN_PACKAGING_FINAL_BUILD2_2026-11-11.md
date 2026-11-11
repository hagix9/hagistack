# Hagistack's own RPM packaging — second full build after the R-1 fix (2026-11-11)

This is the one rebuild the Owner approved after finding R-1 in
`ROCKY_OWN_PACKAGING_FINAL_BUILD_2026-11-11.md`. The implementer self-tested it.
**No independent audit was done.**

Nothing was pushed or released. Stage 6 (real-machine acceptance) was not started.
No further full build was started after this one.

## Result: STOP (the new final check refused the build environment)

- All 69 definitions were built in one run of the production path.
  - Rounds 1 to 3 built 69, 12 and 4 definitions.
  - There was no pass 2.
- The final environment check of `build-own.sh` then stopped the run.
  - The check was added in `6f664e8`.
  - The build environment held 15 packages with Hagistack's names from **EPEL**.
- Because of the STOP, `hagistack rpm-prepare` collected no RPM and no SRPM.
  - **No artifact set of this run exists.**
  - The required results 1–7 are therefore **not met** for this run.
  - Nothing was compared, installed or rebuilt from this run.

## Environment

- One temporary GCE VM: e2-standard-8, Rocky Linux 10.2 x86_64, run-id `hs1111s`.
  - It ran from 08:45 to 10:29 UTC, about 1 h 45 min, against a cap of 4 h.
  - Estimated cost was about US$0.7, against a cap of US$3.
- The VM, its router and NAT, its firewall rule, subnet and network were created
  for this task and deleted afterwards.
  - A residual check at 10:29 UTC found none of them left.
  - No resource of other work was touched.
  - Three instances of other work that were RUNNING at 08:43 UTC were
    TERMINATED at 10:29 UTC. The deletion log shows only `hagistack-or-*`
    operations.
- Tree: HEAD `6f664e8`. Build input id: `d4fb48adb289ab0c`.
- Builder image: rc4's pinned image.
- Before the build, every test suite of the tree passed on the VM in the pinned
  image: 93, 54, 13 and 17 checks, and 71 unit tests.

## What the R-1 fix achieved

- `195 package names excluded from RDO's repositories before the first build`.
- No package with a Hagistack name came from an RDO repository.
  - Of the 79 packages in `build-env.lock` that carry a Hagistack name, 64 are this
    build's own (`-N.el10`), 15 are EPEL's (`.el10_3`) and **0** are RDO's.
  - Run 1 had 35 such packages from RDO trunk.
- The waiting rule worked: definitions were retried only after something they
  missed was built (round 2: 12, round 3: 4).

## Finding R-2: own library names are satisfied by EPEL at build time

- **Cause.**
  - `build-in-container.sh:304` enables EPEL in the builder.
  - The exclusion of `6f664e8` covers only RDO's `delorean.repo` and
    `delorean-deps.repo`.
  - The first build dependency that needed these libraries, that of
    `python-barbicanclient` in round 1, installed them from EPEL.
  - Hagistack had not built them yet at that point.
  - They stayed installed for every later build, as in R-1.
- **Packages.** 15, all at the same upstream version as Hagistack's own:
  - `python3-oslo-config` 10.3.0, `python3-oslo-log` 8.1.1, `python3-oslo-utils` 10.0.1,
    `python3-oslo-i18n` 6.7.2, `python3-oslo-serialization` 5.9.1, `python3-oslo-context` 6.3.0
  - `python3-stevedore` 5.7.0, `python3-debtcollector` 3.0.0
  - `python3-keystoneauth1` 5.13.1, `python3-openstacksdk` 4.10.0,
    `python3-os-service-types` 1.8.2, `python3-osc-lib` 4.4.0
  - `python-oslo-i18n-lang`, `python-oslo-log-lang`, `python-oslo-utils-lang`
- **Effect.**
  - The packages built in this run were built against EPEL's packaging of the same
    upstream versions, not only against Hagistack's own.
  - Whether that changes any built file was not checked, because no artifact set
    was collected.
  - The check worked as designed: it refused to call this "built only against our
    own libraries".
- **Fix (not made; it needs a further full build, which needs the Owner's approval).**
  - Apply the same exclusion to EPEL's repository files as well, or to every
    repository except `hagistack-own`.
  - Add a test that covers an EPEL repository file.

## Correction to run 1's record

- Run 1's origin list (`build-env-own-names-origin.txt`) marked two packages as
  this build's own. They were in fact EPEL's:
  - `python3-stevedore` 5.7.0-5.el10_3
  - `python3-os-service-types` 1.8.2-4.el10_3
- The list classified packages by name only.
- Run 1's build environment therefore held 37 packages with Hagistack's names from
  elsewhere: 35 from RDO and 2 from EPEL. Run 1's record says 35.
- Run 1's record and artifacts are left unchanged, as required.

## Not covered

- rc4 comparison, payload and licence audit, install, replace and SRPM rebuild of
  this run: **not run**, because there is no artifact set.
- Whether L-1 and L-2 (the SRPM licence tags) are fixed in built SRPMs.
  - `test_genspec.py` checks it on the generated specs and passed.
  - No built SRPM of this run was collected to confirm it.
- Independent audit.

## Evidence

The evidence is kept outside the repository, in the task's temporary directory:

- `run-final2/evidence-build/ev.tgz` holds `container.log`, the pass 1 log and
  results, every per-definition log, `build-env.lock` and `own-names.txt`.
  - Its SHA-256 is in `ev.tgz.sha256`.
- `own-names-in-lock.txt` classifies every package with a Hagistack name in the
  lock.
- `rpms.txt` lists the files rpmbuild left in the builder. They were not collected
  and are not an artifact set.
- `gce/` holds the cost estimate, the pre-existing resources, and the creation,
  deletion and residual logs.
