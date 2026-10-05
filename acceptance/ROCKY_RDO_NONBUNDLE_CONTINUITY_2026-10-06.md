# Rocky: continuity between the PR #6 evidence and the RDO non-bundling tree

## A. Scope

This note explains how the Rocky Neutron acceptance records in this directory, which
describe the tree merged by PR #6, relate to the current tree after RDO packaging text was
no longer stored in the repository (`rocky10.2/spec-adapt/`, `rocky10.2/third-party/neutron/`)
and the MIT License was added. It is a pointer, not new acceptance evidence, and it does not
replace or correct any other file in this directory.

## B. The other records are historical evidence

The hashes, file names and `rocky10.2/spec-patches/neutron.patch` references in the other
records describe the candidate trees that were examined when they were written. They have
not been rewritten for the current tree. Where such a record differs from the current tree,
the record is right about the state it describes, and the current tree is right about the
current state. For example, the statement in `ROCKY_ONLY_SCOPE_2026-10-02.md` that the Rocky
product files are byte-identical to the audited `40472e8` candidate describes the PR #6 tree
(`rocky10.2/` tree `48ac5fc84b53…`), not the current tree.

## C. Baseline continuity

| | |
|---|---|
| Tree used as the old-method baseline in the real Rocky 10 builds (`0218ab3`) | `rocky10.2/` tree `48ac5fc84b53ba31e2e5f72f86d77462ff1944a6` |
| Tree after PR #6 (`c2f7dba90725dc27aa303b0f31475f1c3c016402`) | `rocky10.2/` tree `48ac5fc84b53ba31e2e5f72f86d77462ff1944a6` (same) |
| RDO non-bundling and MIT change, as first committed (`a6d0d6c4273258bb4f2223ef13b28f933d5a7dd6`) | the change on top of that baseline; Git patch-id `0404419860deca62c9d064d0350cfd0c0ff2e023` |
| Same change applied on `c2f7dba` (`2ff010e384bdd9f694208353a36f37676c216227`) | same patch-id; its `rocky10.2/` tree `63f8a46a688752df6bda4e691c2cc7c82bbc9c2e` equals that of `a6d0d6c` |

The old state stays available in Git history at `c2f7dba` and `0218ab3`. This note does not
say that the tree that was built and the current tree are byte-identical: they are not.

## D. What replaced `spec-patches/neutron.patch`

`rocky10.2/spec-patches/neutron.patch` (SHA-256
`d3755588c744d756218e5b673dff1a33aa943000769c31b373ffd91d58073098` at `c2f7dba`) is the
mechanism PR #6 used. It is deleted, together with the ten other files in `spec-patches/`.
Its two jobs now live in two places:

* the packaging and spec changes: rules in `rocky10.2/spec-adapt/`, applied to the pinned
  RDO source at build time; and
* the two upstream Neutron fixes, as Patch0001 and Patch0002: `rocky10.2/third-party/neutron/`
  (Apache-2.0, with its own `LICENSE` and `NOTICE.md`), pinned by `PATCH` rows in
  `rocky10.2/gazpacho.manifest`.

The package row for Neutron is unchanged (`28.0.2`, release `2`).

## E. What was verified, and what was not

On a disposable Rocky 10 builder, packages built by the old method and by `spec-adapt` were
compared. The package list, the spec files and the Neutron runtime result matched, apart
from the differences recorded in that comparison. The comparison evidence is not part of
this repository.

Relative to those builds:

* These files that run during a build are byte-identical to the files hashed on the Rocky
  builder: `build-rpms.sh` (SHA-256 `645183b97e2a…`), `gazpacho.manifest` (`e564330b35543a…`),
  `spec-adapt/adapt.py` (`1228eff19dbbb9…`) and `spec-adapt/rules.py` (`e89a81bc744e3b…`).
* `hagistack` (`11549f6c0e1d41…`) and `tests-neutron-maintenance-lock.py` (`13a56bfc0e8384…`)
  are byte-identical to the files in the builder archives (`new-tree` and `final-tree`).
  Relative to `c2f7dba`, their changes are comments
  and a docstring only.
* The two Neutron patches have the SHA-256 values of the patches that passed the runtime
  test: `4f981103be17689f…` (0001) and `136ce37c86bf3ac8…` (0002).
* `rocky10.2/` in `2ff010e` is identical to `rocky10.2/` in `a6d0d6c`, the first commit of
  this change.
* These files differ from at least one of the builder archives but are read by neither
  build nor install: `spec-adapt/test_adapt.py`, `spec-adapt/RATIONALE.md`,
  `third-party/neutron/NOTICE.md` and the two `rocky10.2` READMEs.
* The Rocky test run had 55 tests; `test_adapt.py` now has 61. The six added tests are five
  static licence tests, which read repository files only, and one CLI test
  (`test_cli_refuses_a_patch_name_that_already_exists_in_the_distgit`); none of them was
  part of the 55-test Rocky run.
* Not every file was re-verified on Rocky.

## F. References to `spec-patches/neutron.patch` in the other records

The other records mention that file because it was the build mechanism at the time. They do
not describe the current build path. Today `build-rpms.sh` runs `spec-adapt/adapt.py` and
does not read `spec-patches/`.

## G. Git history

Identify the states by commit, not by branch name: `0218ab3`, `c2f7dba`, `a6d0d6c`,
`2ff010e`. As the root README states, Hagistack's own code and documentation in the current
tree are under the MIT License. `rocky10.2/third-party/neutron/` stays under Apache-2.0, and
quotations from other projects keep their own licences; neither is covered by the MIT
License. This is not a statement about earlier revisions.
