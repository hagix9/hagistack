# Hagistack's own RPM packaging — stage 6-5-R2: change notices completed, nodocs-safe, in-file notices, commit-bound approvals (2026-11-13)

The implementer wrote this record. The independent audit is reported separately
below.

What was not done:
- No GCE resource was created, changed or deleted.
- No VM was created.
- No RPM was built.
- No key was generated or pinned.
- Nothing was signed.
- Nothing was pushed, tagged or released.

Implementation commit: `e4d72a8`. Branch: `feat/rocky-own-packaging-s65r1`, from
`7f9bc66251ffe0294c03aed55f6898b0c32f3c76`.
- The 21 untracked files are unchanged.
- `rocky10.2/packaging/__pycache__/` still has its 15:36 timestamp.
- Files were staged by explicit path only.
- Python ran with `-B` and `PYTHONDONTWRITEBYTECODE=1`.

## Owner decisions implemented

1. openstacksdk's and os-ken's rpm shebang rewriting is stated in their notices.
2. The notices survive an install with nodocs.
3. Apache-2.0 §4(b): what can be done in the files themselves is done.
4. The approval flow was reviewed in code. It now binds the commit.

## 1. openstacksdk and os-ken

Re-checked against the upstream tarballs in the old set's SRPMs:

| Package | Changed file | Upstream | Shipped in |
|---|---|---|---|
| openstacksdk 4.10.0 | `openstack/tests/ansible/hooks/post_test_hook.sh` | `#!/bin/sh` (rpm writes `#!/usr/bin/sh`) | `python3-openstacksdk-tests` |
| os-ken 4.1.2 | `os_ken/tests/mininet/run_mnet-test.sh` | `#!/bin/sh` (the same) | `python3-os-ken` |

What changed:
- **Both definitions declare the change** (`changes`), and **both files are marked**
  (section 3).
- **openstacksdk** raises its release 1 → 2 (`changelog_date` Fri Nov 13 2026).
  This is the only release raise of this stage.
- **os-ken** keeps the 2 it got in stage 6-5-R1 and has not been built since. Its
  notice now also lists the shebang line.

## 2. Notices that survive nodocs

**Before**, `HAGISTACK-CHANGES` was `%doc` in `/usr/share/doc/<package>/`. rpm
marks every file under its documentation paths (`%__docdir_path`, which includes
`/usr/share/doc`) as documentation. An install with
`dnf --setopt=tsflags=nodocs` or `rpm --excludedocs` leaves such files out, so
moving the file without `%doc` within `/usr/share/doc` would not help.

**Now:**
- **Location:** every binary package of a source package with stated changes
  installs exactly one plain file,
  `/usr/share/hagistack/changes/<package>/HAGISTACK-CHANGES`. It is not flagged
  as documentation, and it is listed without `%doc`. Nothing else in the release
  uses `/usr/share/hagistack`.
- **Ownership:** each such package owns `%dir /usr/share/hagistack`,
  `%dir /usr/share/hagistack/changes` and its own
  `%dir /usr/share/hagistack/changes/<package>`. rpm allows several packages to
  own a directory, and each package's notice file is its own.
- **Removed:** the relative/absolute `%doc` logic of stage 6-5. No spec lists
  `HAGISTACK-CHANGES` as `%doc`, and none puts it under `%{_docdir}`.
- **Kept:** `HAGISTACK-LICENSE` stays `%license`, which rpm installs even with
  nodocs. The notice is not treated as a licence text.

`release_check.py notices` refuses a release in each of these cases. The
documentation flag comes from `rpm -qp --qf '[%{FILENAMES}\t%{FILEFLAGS:fflags}\n]'`.
- a binary package does not install the notice exactly once at that path, for
  example because it is missing, also under `/usr/share/doc`, or present twice;
- the notice is flagged as documentation;
- the notice differs from the text its spec writes;
- the package lacks `HAGISTACK-LICENSE` or an MIT tag;
- its newest changelog entry is not for its own version and release;
- a file the spec marks lacks the mark.

**Not verified here:** a real install with nodocs. It is added to the GCE
acceptance (section 6).

## 3. §4(b): notices inside the changed files

Every changed file found in stages 6-5 and 6-5-R1 was sorted by whether a notice
can go inside it without breaking it:

| Changed file | Inside the file | Otherwise |
|---|---|---|
| Neutron: 4 patched modules, `metadata.py` (Hagistack's shebang edit), 11 files with rpm's shebang rewriting | **comment line** | — |
| Neutron: 10 generated configuration samples (placeholders), installed in `/etc/neutron` | **comment line** (after generation and checks) | — |
| Neutron: `macvtap_agent.ini.sample` (generated, not installed) | not inside: not shipped | `HAGISTACK-CHANGES` (the generic sample line) |
| Keystone: `keystone.conf.sample` (generated, scrubbed), `sample_data.sh` (rpm shebang) | **comment line** | — |
| Placement: `placement.conf.sample`, `policy.yaml.sample` (generated, scrubbed) | **comment line** | — |
| Nova: `new_cert.sh`; openstacksdk: `post_test_hook.sh`; os-ken: `run_mnet-test.sh` (rpm shebang) | **comment line** | — |
| qrcode: `console_scripts.py` (shebang removed) | **comment line** (the module docstring stays the first statement) | — |
| Horizon: `manage.py` (shebang) | **comment line** | — |
| Horizon: `local_settings` | already marked: every change has a "Hagistack:" comment | — |
| Horizon: the seven replaced images; the documentation theme's images | not inside: they are images | Hagistack's own files. The SVGs carry a comment and the PNGs a text chunk naming Hagistack, plus `HAGISTACK-CHANGES` and `THIRD_PARTY_NOTICES.md` |
| barbicanclient, keystoneauth1, keystonemiddleware: `doc/source/conf.py`; Neutron and Horizon: `requirements.txt` | not inside: not installed | `HAGISTACK-CHANGES` (the documentation built from them is generated) |
| Horizon: `.svg.old` leftover | removed, not shipped | `HAGISTACK-CHANGES` |

**How the comment line is added.** A definition lists its files in `mark_files`
(path and stage), and `genspec.py` writes these steps:
- **When:** in `%prep`, after the patches and the definition's own edits; or in
  `%build`, after the samples are generated, scrubbed and checked.
- **Checks:** a `test -f` that stops the build if the file is missing, and a
  final `grep` that stops it if the line is absent.
- **The line:** `# Hagistack: this file is changed from the upstream release;
  the changes are listed in HAGISTACK-CHANGES under /usr/share/hagistack/changes/.`
- **Where:** after a `#!` line on line 1 and after a Python coding line on line 1
  or 2 (PEP 263), whichever is later, so neither moves. rpm's later shebang
  rewriting changes line 1 only.
- **Idempotent:** a file that already has the line is left alone.
- **Refused by the loader:**
  - a path outside the tree;
  - a type without `#` comments (`.py .sh .ini .conf .sample .yaml .cfg` only);
  - a stage other than prep or build;
  - `mark_files` without `changes`.
- **Notice list:** `HAGISTACK-CHANGES` lists the marked files.

Upstream copyright and licence headers are not touched; the line is only
inserted.

**Tested here** (macOS, BSD awk) on copies of the real upstream files:
- Files tested:
  - qrcode's `console_scripts.py`, after the shebang removal;
  - Horizon's `manage.py`;
  - Keystone's `sample_data.sh`;
  - Neutron's `constants.py`;
  - a file with a shebang and a coding line;
  - a file with a coding line only;
  - a comment line followed by a coding line (latin-1; audit L1);
  - an empty file;
  - a file without a final newline;
  - a one-line file;
  - an INI sample.
- Results:
  - the mark is placed after the shebang and coding lines;
  - a second run adds nothing;
  - the Python files parse and the docstring stays;
  - `bash -n` passes.
- **Not tested:** the builder's GNU awk, which reads the same POSIX program.

**Still a legal question.** Whether these notices, which are now inside the
files, in each binary package (nodocs-safe), in the SRPM specs and in the
release documents, meet §4(b) is not decided here.

## 4. The approval key and flow (code review)

Each requirement against the code (`acceptance/stage6/hs6_approve.py`, `hs6.py`):

| Requirement | Code | Result |
|---|---|---|
| The key is made locally | `--setup` runs `/usr/bin/ssh-keygen -t ed25519` (or `-sk`) to `~/.ssh/hagistack-owner-approval`; no network call in the tool | OK |
| The private key is never sent | the tool reads only the `.pub` line; signing is `ssh-keygen -Y sign` locally | OK |
| The private key cannot enter git | default outside the repository; **new: `--setup` and signing refuse a key path inside the repository** | fixed |
| Only the public key is pinned | `pinned_ok`: the pinned set must be exactly the Owner's public line | OK |
| The signature covers the exact commit and run id | run id was signed; **the commit was not, so `commit` was added to the signed approval (format 3)**. The harness refuses a non-cleanup operation unless HEAD is that commit with no changed tracked file. `hs6_approve.py` signs only a checkout with no changed tracked file | fixed |
| Only approved operations run | `operations` signed; any other is refused | OK |
| Cost, time and resource limits | budget ≤ US$8 and hours ≤ 6 signed and enforced (guard, node max run duration); project, zone and node shapes fixed in code | OK |
| No reuse for another run or commit | used approvals and run ids are recorded at init and refused again; the commit binding is new | OK |
| No passphrase-less key or agent | refused | OK |
| No agent shell | refused | OK |
| No planted code | `python3 -I` enforced | OK |

What did not change:
- **Cleanup** (`teardown`, `residual`) still runs after HEAD moved or files
  changed, with a warning, so a run can always be cleaned up.
- **The same-user risk stays, as the README says.** An agent running as the same
  OS user could edit `hs6.py` or call `gcloud` itself. The harness binds what it
  runs, not what else the user account can do.

## 5. Tests run here

| Suite | Python | Result |
|---|---|---|
| `packaging/test_genspec.py` | 3.13 | **36** OK |
| `packaging/branding/test_branding.py` | 3.13, 3.9 | 5 OK |
| `tests/test_release_check.py` | 3.13 / 3.9 | **20** OK / 20 OK (1 skipped on 3.9: genspec needs 3.11) |
| `acceptance/stage6/test_hs6.py` | 3.13, 3.9 | **151** OK on each at `e4d72a8`; **152** on 3.13 after the audit fixes (L2 test added) |
| marking steps on real upstream files | bash and BSD awk | OK (section 3) |
| `bash -n` | bash 3.2 | OK: `make-rpm-release.sh`, `build-own.sh`, `run-all.sh`, `hagistack` (none changed in this stage) |

New or changed tests:
- **`test_genspec.py`:**
  - every notice is at `/usr/share/hagistack/changes/<package>/`, listed once
    with its three directories, and never `%doc` or under `%{_docdir}`;
  - the marked files per definition (Neutron 26, Horizon 1, qrcode 1,
    Keystone 2, Placement 2, Nova 1, openstacksdk 1, os-ken 1) get the steps in
    the right stage and appear in the notice;
  - the mark is shell- and awk-safe;
  - bad `mark_files` entries are refused;
  - 11 definitions declare changes.
- **`test_release_check.py`:**
  - refused: the notice under `/usr/share/doc`, twice, or missing;
  - refused: the notice flagged as documentation;
  - refused: a release without its own changelog entry;
  - refused: a marked file without the mark;
  - genspec's mark equals `release_check`'s.
- **`test_hs6.py`:** a `CommitBinding` class.
  - the approved commit runs;
  - refused: another HEAD, changed tracked files, no commit, format 2, an
    unreadable checkout;
  - cleanup after HEAD moved;
  - `HS6_GIT` refused with a real account;
  - the key must be outside the repository.

**Spec comparison** (69 specs generated at `7f9bc66` and now):
- **54 change:** the 53 specs with notices, whose notice path moved, and
  openstacksdk, which has a notice for the first time.
- **15 are byte-identical.** None of them has a notice.
- **Only openstacksdk's release changes.** The other 53 already have releases
  above the old set and have not been built since.

**Not verified** (they need the x86_64 builder): rpm parsing of the 54 changed
specs, the marking steps on the builder, the documentation flags in real RPMs,
an install with nodocs, and `release_check.py` on real RPMs.

## 6. GCE plan (additions to stage 6-5-R1 section 6)

Unchanged:
- n1 n2-standard-8, Rocky Linux 10.2 x86_64, US$8 and 6 h;
- operations `init,network,n1,ssh,upload,download,teardown,residual`;
- the candidate is downloaded before the install;
- the estimate is about US$3.5, and the time is not well known.

Added steps, after the release candidate exists:
- **nodocs:** install a sample of packages with notices (Neutron, Horizon,
  qrcode, Keystone, Nova, openstacksdk-tests, one `*-doc`) into a scratch root
  with `rpm --root <dir> --excludedocs --nodeps -i`. Every
  `/usr/share/hagistack/changes/<package>/HAGISTACK-CHANGES` must be there and
  `/usr/share/doc` must not be.
- **Doc flags:** `rpm -qp --qf '[%{FILENAMES} %{FILEFLAGS:fflags}\n]'` must show
  no `d` flag on any notice. `release_check.py` also checks this.
- **Marks:** `grep` the installed marked files for the line. `release_check.py`
  also checks this.
- **Documentation:** open one documentation page and the dashboard. Hagistack's
  logos must be shown, and no image request may fail.

The approval now names the commit. The Owner signs after the commit to run is
final, and any later commit needs a new approval.

## Independent audit

**Audit** (separate agent, of `e4d72a8`/`8aefd6b`):
- **Its checks:**
  - regenerated the 69 specs (54 changed, 15 identical, only openstacksdk's
    release raised);
  - checked the 170 binary packages with a notice (one notice, one
    `HAGISTACK-LICENSE`, three `%dir`, no `%doc`);
  - matched the 16 shipped files with a rewritten shebang to `mark_files`
    (none missed);
  - ran the marking on edge cases (modes kept, idempotent);
  - reviewed the key and approval flow in code;
  - ran its own tests.
- **Verdict NO-GO**, on one BLOCKER:
  - **B1:** Neutron's `etc/neutron/plugins/ml2/macvtap_agent.ini.sample` was in
    `mark_files`, but no RPM installs it (the macvtap agent package ships only
    its `conf.d` directory). `release_check.py notices` would have refused the
    set, after the GCE build had been spent, and the notice and this record
    claimed it was installed and marked.
- **MEDIUM:**
  - **M1:** `installed_as` accepted the same file name in another place, so one
    of Neutron's two `l3_agent.py` (or `ovs_agent.py`) could lose its mark and
    still pass.
  - **M2:** the commit binding covers the harness checkout, not what
    `upload`/`ssh` send to a node, and a comment said "the commit is what runs".
- **LOW:**
  - **L1:** a comment line followed by a coding line put the mark before the
    coding line, which would break a latin-1 file. No current target has one.
  - **L2:** an unreadable checkout stopped `teardown`/`residual`.
  - **L3:** `git status` does not show assume-unchanged or skip-worktree files
    (same-user risk, already in the README).
- **Not verified:** EL10's `%__docdir_path` value, real file flags and a nodocs
  install, GNU awk, and `%{CHANGELOGNAME}` returning the newest entry. All are
  in the GCE plan.

**Fixes** (this update):
- **B1:** the entry was removed (Neutron 27 → 26 marked files). All 10 other
  samples were checked as installed in the old set.
- **M1:** a marked path matches an installed path by its full relative path. The
  file name is used only for `.sample` files, and only when no full-path match
  exists. A test covers it.
- **M2:** the README states the limit. Each upload's SHA-256 is checked against
  the node and kept in `remote/*.log`, and the comment in `hs6_approve.py` is
  corrected.
- **L1:** the first two lines are held back, and the mark goes after the later of
  a `#!` on line 1 and a coding line on line 1 or 2. Tested on the comment and
  coding case: the latin-1 file compiles.
- **L2:** for cleanup operations, an unreadable checkout gives a warning, not a
  stop. A test covers it.
- **L3:** not changed (README).
- **After the fixes:**
  - `test_genspec` 36, `test_branding` 5, and `test_release_check` 21 (3.13)
    and 21 with 1 skipped (3.9) pass;
  - the `CommitBinding` tests (9) pass;
  - the full harness run is below;
  - still 54 specs change.

**Re-audit 1** (same agent, of `aab4f48`):
- **Resolved:** B1, M2, L1 and L2. It re-ran the new awk on all edge cases,
  including the latin-1 case, which now compiles. Modes are kept, a second run
  adds nothing, and no temp file is left. The comparison is still 54 specs
  changed, 15 identical, and only openstacksdk's release raised.
- **New BLOCKER R1, caused by the M1 fix:** Keystone's `tools/sample_data.sh` is
  installed as `/usr/share/keystone/sample_data.sh`. The strict full-path match
  could not find it, so `release_check.py notices` would always have refused a
  real build. The test covered only site-packages files and samples.

**Fix of R1** (this update):
- A `mark_files` entry may name its installed path (`installed = "/…"`).
  `genspec.py` writes it into the spec as
  `# hagistack-mark-installed: <path> <installed>`, and `release_check.py` then
  looks for the mark at exactly that path.
- File names are no longer guessed. A unique-name fallback would have brought M1
  back.
- The entries with a named place:
  - Keystone's `sample_data.sh`;
  - Horizon's `manage.py`;
  - all 13 generated samples (Neutron 10, Keystone 1, Placement 2). A test
    requires the installed path for every build-stage entry.

  The other 20 entries are site-packages files, matched by their full relative
  path.
- Against the old set's file lists, each of the 35 entries maps to exactly one
  installed file, read from the generated specs the same way `release_check.py`
  reads them.
- New tests:
  - `test_release_check.py`: a file installed elsewhere is found at its named
    place, and refused there without the mark, even if another copy is marked;
  - `test_genspec.py`: bad `installed` values are refused; the Keystone and
    Horizon entries name their place; every build-stage entry names its place.
- **Results:**
  - `test_genspec` 38;
  - `test_release_check` 22 (3.13), and 22 with 1 skipped (3.9);
  - `test_branding` 5 (both);
  - `test_hs6` **152/152** on 3.13. The harness is unchanged since `aab4f48`.
    The 3.9 run is below.
  - 54 specs change, and only openstacksdk's release is raised.

**Re-audit 2:** (below)

## Owner steps after this stage

1. Create the key, once:
   `python3 -I acceptance/stage6/hs6_approve.py --setup` (or `--setup --sk`). Send
   the printed public line; it is pinned by a commit.
2. Sign the run, after that commit:
   `python3 -I acceptance/stage6/hs6_approve.py --run-id <rid> --ops init,network,n1,ssh,upload,download,teardown,residual`
3. Unchanged: the §4(b) sufficiency (legal) and the Hagistack logo under MIT.
