# Third-party component: OpenStack Neutron, two upstream changes

This directory holds files that Hagistack did **not** write and **does**
redistribute. Everything else under `rocky10.2/` is either Hagistack's own work or
is fetched at build time from a pinned external source and never stored here (see
`../../spec-adapt/RATIONALE.md`).

| | |
|---|---|
| Upstream project | OpenStack Neutron — <https://opendev.org/openstack/neutron> (mirror: <https://github.com/openstack/neutron>) |
| Licence | Apache License, Version 2.0 — full text in [`LICENSE`](LICENSE) |
| Author / copyright | Terry Wilson `<twilson@redhat.com>` (author and `Signed-off-by` of both changes, kept in the patch headers). The one file touched that carries a copyright line, `neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/maintenance.py`, says `Copyright 2019 Red Hat, Inc.`; the patch does not touch that header, so it stays in the file when the patch is applied. The other three touched files carry only the Apache-2.0 licence header and no copyright line. |
| Upstream NOTICE file | none. Neutron 28.0.2 ships a `LICENSE` and no `NOTICE`, so there is nothing to reproduce. |

## The files

| File | Upstream commit | Subject | SHA-256 |
|---|---|---|---|
| `0001-Ensure-MaintenanceWorker-lock-set-before-connect.patch` | `83f1d8305651a0ab23629c88d70bfa237055158c` | Ensure MaintenanceWorker lock set before connect (Related-Bug #2155155) | `4f981103be17689f9186776b5059c55bb33950dae47740fd52575be7849387e4` |
| `0002-Only-set-the-maintenance-worker-lock-on-the-worker.patch` | `91abb5e720e1c515dbfbe9b2313fbdff92b2abbf` | Only set the maintenance worker lock on the worker (Closes-Bug #2156979) | `136ce37c86bf3ac8dd7f737b23c5e2b60bdb17326cac6876852ebc4bfb96d9cf` |

They are pinned by SHA-256 in `../../gazpacho.manifest` (`PATCH` rows) and checked by
`spec-adapt/adapt.py` before the build uses them.

## What Hagistack uses them for

Neutron 28.0.2 (OpenStack 2026.1) lets the OVN maintenance worker lose its OVSDB
lock silently: it keeps running and every northbound write fails with `NOT_LOCKED`.
Both upstream changes are on master and stable/2026.2 and are not in stable/2026.1.
The Rocky Linux 10 `openstack-neutron` RPM that Hagistack builds carries them as
`Patch0001` and `Patch0002`, applied to the 28.0.2 source tarball. They are carried
together and never apart: the first alone would make RPC workers request the
maintenance lock as well. The resulting package is Neutron under Apache-2.0.

## Changes made to the upstream commits (Apache-2.0 §4(b))

The two commits were cherry-picked onto the `28.0.2` tag and exported with
`git format-patch --zero-commit`. Compared with the commits as published upstream:

* the changed lines (`+` and `-`) are identical;
* in `impl_idl_ovn.py` the unchanged context lines differ, because that function is
  written differently in 28.0.2 than on master. This is the one place where the text
  is not upstream's;
* the line offsets and function names in the hunk headers (`@@ ... @@`) follow 28.0.2;
* the `index` lines carry 28.0.2 blob ids, the `From <sha>` line is zeroed, and the
  subject carries the series number (`[PATCH 1/2]`, `[PATCH 2/2]`).

The commit messages, including the `Change-Id` and `Signed-off-by` lines, are
unchanged apart from the added `(cherry picked from commit <sha>)` trailer that
`git cherry-pick -x` appends.

## About `LICENSE`

`LICENSE` is the canonical Apache-2.0 text from
<https://www.apache.org/licenses/LICENSE-2.0.txt> (SHA-256
`cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30`). Neutron's own
`LICENSE` file (28.0.2, SHA-256
`5df2a0d87d6c562f0ea11c688ac52532aa28d744cabc7994ff0537f64b3b3320`) is the same text
up to the end of section 9 and omits the closing marker and the appendix, so the
canonical file is used here to give the complete text.

## What this notice does not say

It covers only the two patch files in this directory, which stay under the Apache
License 2.0. The rest of Hagistack is under the MIT License in the repository root
(`../../../LICENSE`); that licence does not apply to the two patch files or to the
`LICENSE` in this directory.
