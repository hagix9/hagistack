# Hagistack's own RPM packaging — stage 6-7-R2: decision D1 applied, installation documents checked (2026-11-16)

Nothing was pushed, tagged or released. No GCE resource was used, no RPM was rebuilt, and `ubuntu26.04/` was not changed.

**Status: CONDITIONAL GO.** The independent audit found 0 BLOCKER. One Owner decision remains open, D2 below.

## D1: the GCP project identifier (Owner approved option C)

**What was changed.** Only unpublished history was rewritten: no commit reachable from any remote ref, and no force push.
- Tool: `git filter-branch --index-filter`, over `origin/master..HEAD` (101 commits).
- In five paths, the identifier was replaced with `<GCP_PROJECT>`:
  - `acceptance/stage6/hs6.py`;
  - `acceptance/stage6/test_hs6.py`;
  - `acceptance/stage6/APPROVAL.template.json`;
  - `acceptance/stage6/README.md`;
  - `acceptance/ROCKY_OWN_PACKAGING_STAGE6_LIVE_2026-11-12.md`.
- The first 32 commits did not contain it and kept their hashes. The other 69 were rewritten.

**The first pass missed one file.** Under `pipefail`, `git cat-file | grep -q` reported "no match" for the large `hs6.py`: grep exited early and the writer got SIGPIPE. The check was changed to read the whole blob, and the same range was filtered again.

**Checks** (executing agent, and again by the auditor):
- The range still starts on origin/master.
- Author, committer, dates and messages are equal to the backup for all 101 commits.
- Only the five paths differ. Each of the 342 rewritten blobs equals the original with only the replacement applied, and the file modes are unchanged.
- The identifier is in 0 of the commits in `origin/master..HEAD` outside `ubuntu26.04/`, and in 0 commit messages.

**Left as it is, outside the approval:** the two files under `ubuntu26.04/` that already carry the identifier on origin/master.

**Local refs only.** The pre-rewrite tip is kept as `refs/backup/d1-pre-rewrite`. That ref and the branch `feat/rocky-own-packaging` still hold the identifier. The publication commands push only `HEAD:refs/heads/master` and the tag.

**Configuration instead of code** (commit after the rewrite):
- `hs6.py` reads the project from `HS6_PROJECT`, validated as a GCP project ID.
- `hs6.py` and `hs6_approve.py` stop before doing anything when it is unset or malformed. Approvals still bind the project.
- The tests use a synthetic project, and new tests cover unset and malformed values.
- The full stage-6 suites passed: 290 tests on Python 3.9.6 and on 3.13.

## Installation documents

The release patch (kept on the external workspace) was extended for users of the published RPMs:
- the quick start and `rocky10.2/README*.md` start from the tag;
- the preflight example, the `hagistack.env` example and the `controller` example use the default `github` source, with `build` as the alternative;
- the requirements name the download from GitHub Releases (about 108 MB, once per node);
- the Horizon section records that the current sign-in test passed on a real Horizon in s66r5c, before and after a restart of the services.

**Checks:**
- Every `hagistack` subcommand and option in the documents exists in the installer's parser. The others belong to `firewall-cmd`, `openstack`, `git` and `build-rpms.sh`.
- English and Japanese match section for section.

## Release consistency

The formal release files from stage 6-7-R1 are unchanged:
- 195 RPMs and 69 SRPMs, set `0b61c809…`;
- RPM tar `565a1013…`, SRPM tar `db019350…`;
- lock `9ff85a2a…`, `SHA256SUMS` `4bd30d36…`.

**Checks:**
- The lock in the patch equals the candidate.
- The offline run of the installer's `github` path gives 14/14 PASS (executing agent and auditor).
- The documents state that the controller + compute acceptance (s66r5d) ran on a rebuild, not on these bytes.

## D2: the commit identity (Owner decision)

- All 102 outgoing commits carry one author and committer identity, an e-mail address in a real organisation's domain. A `git tag -a` made with the same configuration would carry it as the tagger.
- The same identity already appears in 28 of the 110 commits on origin/master.
- Rewriting the author fields is outside the D1 approval.

The options:
- **A.** Publish as it is.
- **B.** Set a no-reply identity for the tag and any new commit; the existing commits keep theirs.
- **C.** Rewrite the author and committer of the unpublished commits. This needs the Owner's approval under rule 14.

## Independent audit (separate agent)

**Result:** 0 BLOCKER.

**Fixed after the audit:**
- the publication commands also warn about `feat/rocky-own-packaging`;
- the requirements name the GitHub download.

**Left as NON-BLOCKER:**
- the committed lock keeps the candidate comment, because changing it would break the byte comparison with the asset;
- the root README's "Verified" table date;
- `ProjectSetting` does not test a malformed value for `hs6_approve.py`; the check is shared with `hs6.py`.

**Not verified:**
- g12b of `test-rpm-source.sh`, which runs on Rocky only;
- the real GitHub download, `rpm -K` and dnf, all after publication;
- the 290-test suites: the auditor ran 19 tests and checked the logs of the rest.
