# Hagistack's own RPM packaging — stage 6-2: signed GCE approval and release readiness (2026-11-13)

The implementer wrote this record. An independent audit by a separate agent was run
on the changes; its results are given separately below. No GCE resource was created,
changed or deleted, and stage 6-1 was not re-run.

## Commits

| Commit | Change |
|---|---|
| `8e5578a` | `hs6.py` executes only an approval signed by the Owner (`FILE` + `FILE.sig`, `ssh-keygen -Y`, namespace `hagistack-stage6-approval`) with a key pinned in `OWNER_SIGNING_KEYS`; `hs6_approve.py`, the Owner's one-step tool |
| `8ff77e2` | `make-rpm-release.sh`: LICENSE and notices required, `srpms/` exactly the set's SRPMs, each with `HAGISTACK-LICENSE`; `THIRD_PARTY_NOTICES.md`: source offer, licence texts per package, external repositories |
| `947276e` | audit fixes A1–A6, B1–B2 |
| `2556398` | re-audit fix A2' (`python3 -I` enforced before any import) |

The commit ids above are those after the history rewrite of stage 6-3 (Owner
approved): before it, they were `656d43d`, `782b508`, `af3eab3` and `4d33980`, and
this record was `afefcbf`. The first commit had also added
`acceptance/stage6/__pycache__/hs6.cpython-313.pyc`, which holds a local absolute
path; the rewrite took it out of the history. The changes, authors, dates and
messages are otherwise unchanged (stage 6-3 record).

## GCE approval

- **Chat approval is not accepted.** The harness gets no verifiable sender from the
  chat, so it cannot tell the Owner's message from text the agent produced. The
  method-A records (`h6n121-chat*.json`, `h6r4env-chat.json`) were written by the AI
  agent; under the new harness they are refused (format 1, no signature).
- **New method.** One time, the Owner runs `python3 -I acceptance/stage6/hs6_approve.py
  --setup` (a passphrase-protected key, or `--sk` for a security key), and the public
  key is pinned. For each run, the Owner runs one command; it shows the conditions,
  asks for the run id, and signs with the passphrase or touch.
- **Fail-closed now.** `OWNER_SIGNING_KEYS` is empty, so nothing can be executed until
  the Owner's key is pinned.
- Tests (mock gcloud, no GCE): 137 on Python 3.9 and 3.13 after `947276e`; the
  approval classes (36) again after `2556398`. They cover: no approval, AI-written
  records, another key, another namespace, a copied signature, tampering (one byte),
  another run id, expiry, operations outside the scope, budget and hours over the
  limits, reuse of an approval for a second run, no pinned key, the test hooks with a
  real account, links and modes of `.sig`, cleanup after a harness change, and a
  normal Owner-signed run. Two mutants (signature check removed; reuse check removed)
  were each killed (7 and 1 failing tests).

## RPM release (set `6c43da…`, 195 RPMs, 69 SRPMs)

Checked on the real files, read on macOS with a header reader (no `rpm`):
- set identity recomputed, 0 checksum mismatches; BUILDHOST `hagistack-builder` on all 264;
- licence tags: Apache-2.0, MIT, BSD-3-Clause, CC-BY-4.0 AND OFL-1.1 AND MIT
  (Font Awesome); no GPL tag;
- every binary has its SRPM and every SRPM a binary; every SRPM holds
  `HAGISTACK-LICENSE`, identical to the repository's MIT `LICENSE`;
- no upstream source archive (69/69 listed) contains a `NOTICE` file, so Apache-2.0
  §4(d) asks for none;
- 38 RPMs install no licence text of their own; each has a sibling from the same SRPM
  that does, except Font Awesome and term.js, whose licence is in the packaged files;
- RDO: 2 files identical to RDO packaging files (the two upstream Neutron commits),
  0 mentions (stage 5 evidence, reused).

Not executed: `make-rpm-release.sh` after `8ff77e2`/`947276e` (needs Rocky/EL; its
last run, in h6n121, was before these changes).

## Independent audit

- First audit: Part A NO-GO (MEDIUM A1 committed `.pyc`, A2 key-set and tool-integrity
  checks, A3 cleanup blocked after a harness change), Part B GO.
- Re-audit of `947276e`: A1–A6 fixed; new MEDIUM A2' (planted module without `-I`).
- Re-check of `2556398`: **Part A GO, Part B GO**; BLOCKER/HIGH/MEDIUM 0. LOW: code
  in the Owner's own environment can run before the `-I` guard when started without
  `-I` (same-user residual risk); the `.pyc` in history.

## Owner decisions

1. Create the approval key and have its public line pinned, before any further GCE run.
2. Whether to rewrite the unpushed history to drop the `.pyc` from the first commit before a
   push (decided in stage 6-3: rewritten).
3. A run of `make-rpm-release.sh` on Rocky/EL with the current tree before publication.
4. Legal review, which this record does not settle: Apache-2.0 §4(b) notices for the
   Neutron patches, attribution for CC-BY/OFL (Font Awesome), trademarks (OpenStack,
   Rocky Linux, Font Awesome brand icons), and the unverified clean-room records
   (`files/*/AUTHORING.md`).
5. Whether SRPMs are attached to the release.
