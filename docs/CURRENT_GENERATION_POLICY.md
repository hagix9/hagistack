# Current Generation policy

This file is the single source of truth for how Hagistack handles OS and OpenStack
versions. It is written for maintainers, coding agents and reviewers alike. Read it
before you change any version, pin, manifest, package source or supported-platform
statement, and before you review such a change.

Short summaries are in the *Version policy* section of [README.md](../README.md)
([日本語](../README.ja.md)). If they ever differ from this file, this file wins.

## Principle

Hagistack is **not** a tool that follows Git HEAD or an unverified "latest".

Hagistack verifies the newest target OS and the newest stable OpenStack release,
then **pins the verified versions as the Current Generation**.

"Follow the latest" means "notice new releases and validate them". It does **not**
mean "fetch whatever is newest at build time".

## Definitions

Only two terms exist. Do not add support tiers such as Previous, LTS or
Experimental.

- **Current Generation:** the OS + OpenStack combinations that Hagistack currently
  verifies and maintains. Their versions are explicitly pinned, and they have
  passed CI and real-OS acceptance. The values are those in the *Supported
  platforms* table of [README.md](../README.md) and in the pins the installers use.
  This file does not repeat them, so there is one place to update.
- **Legacy:** a generation that was verified earlier and has been replaced by a new
  Current Generation. Its code or documentation may remain in the tree, but it
  does not carry the guarantees of the Current Generation.

## Reproducibility

The Current Generation must be reproducible. Pin every input the current build
method needs, for example:

- OpenStack component versions;
- the source release (tarball) and its SHA-256;
- the packaging source and the exact packaging commit;
- any other input needed to get the same result again.

A branch name is not a pin.

## OS update policy

When a new minor release of a target OS appears (for example Rocky 10.2 → 10.3),
do **not** delete the existing version, and do **not** change the version string
without verification. Instead:

1. Recognise the new OS release as a candidate.
2. Verify the current Current Generation on that OS.
3. Make only the minimum compatibility fixes that are needed.
4. Run CI and real-OS acceptance.
5. Get an independent audit.
6. Update the Current Generation only after it passes.

If the existing implementation passes unchanged, do not re-implement anything.

Avoid doing an OS minor update and an OpenStack release update at the same time.
If something breaks, you must be able to tell which of the two caused it.

## OpenStack update policy

When a new stable OpenStack release appears, do not follow Git HEAD. Instead:

1. Recognise the new stable release as a candidate.
2. Check component and version compatibility.
3. Update the manifest and pins explicitly.
4. Make the package build reproducible.
5. Run local tests.
6. Run real-OS acceptance.
7. Get an independent audit.
8. Update the Current Generation only after it passes.

Release candidates, development branches and unreleased Git HEAD are never the
Current Generation. The only exception is an explicit verification exercise that
says so.

## Supply model: Rocky and Ubuntu are different

**Rocky Linux.**
Do not assume that Red Hat or RDO provides finished OpenStack RPMs. Hagistack
pins the OpenStack upstream release it has adopted and builds the Rocky packages
reproducibly, using pinned packaging sources as raw material.

The repository does not re-bundle RDO packaging text. Keep the established **RDO
non-bundling boundary**: RDO packaging stays outside the tree and is fetched from
the pinned commit at build time (see `rocky10.2/spec-adapt/RATIONALE.md`).

**Ubuntu.**
Use packages from the supported Ubuntu archive. An upstream fix does not enter the
Ubuntu Current Generation automatically. Where a needed fix has not reached a
supported Ubuntu package, the work may stay on **HOLD** until it does. Do not
introduce self-patched Ubuntu packages into the Current Generation lightly.

## Legacy policy

After a move to a new Current Generation, the previous one is no longer a
continuously supported target. Its code and documentation may stay. In principle:

- continuous CI is not guaranteed;
- compatibility with new dependencies is not guaranteed;
- security fixes are not backported;
- behaviour on newer OS environments is not guaranteed;
- real-OS acceptance does not continue.

Its status is: "verified earlier, may still work, but not guaranteed to the same
level as the Current Generation".

Breaking an old generation is not a goal. But do not add legacy compatibility
merely to avoid holding back a Current Generation update.

## What agents must not do

Do **not**:

- update a version pin only because a version is newer;
- follow Git HEAD or a development branch automatically;
- change the Current Generation without acceptance;
- assume an older OS has the same support as the Current Generation;
- add features for the sake of legacy compatibility;
- assume Rocky and Ubuntu get their packages the same way;
- bring an Ubuntu upstream fix in as a bundled patch before it has reached the
  Ubuntu package;
- weaken the RDO non-bundling boundary;
- update the OS and OpenStack together without a reason;
- rewrite historical evidence (`acceptance/`, `ubuntu26.04/*EVIDENCE*` and similar
  records) to match a new Current Generation. Those records describe the state
  they were written for; add a new dated record instead.

If something is unclear, do not guess and do not bump a version. Check this
policy first, then proceed.
