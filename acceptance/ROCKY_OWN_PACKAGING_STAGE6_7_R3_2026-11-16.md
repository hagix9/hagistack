# Hagistack's own RPM packaging — stage 6-7-R3: D2 decided, release commit made locally (2026-11-16)

Nothing was pushed, tagged or released. No history was rewritten, no GCE resource was used, no RPM was rebuilt, and `ubuntu26.04/` was not changed.

## D2: commit identity (Owner approved option B)

- **Existing unpublished commits.** Their author and committer stay as they are. There were 103 at the start of this stage, from `origin/master` (8225c50) to `a4ae8b1`.
- **New commits and the tag.** This record's commit, the release commit and the release tag use the account's GitHub no-reply identity:
  - name `hagix9`;
  - the ID-based no-reply address of the account.
- **How the address was confirmed.** The Owner chose it from the account's GitHub e-mail settings. The API token has no `user:email` scope, so the address could not be read there.
- **How it is applied.** It is set per command with `git -c user.name=… -c user.email=…`. Neither the repository's nor the global Git configuration was changed.

## Exception record (AGENTS.md rule 15)

| Field | Value |
|---|---|
| Rule excepted | Rule 5: no unnecessary organisation identifiers or e-mail addresses in published material |
| What is exempted | Only the author and committer e-mail address and name of the existing unpublished commits in `origin/master..a4ae8b1` (103 commits; one identity, an address in a real organisation's domain). The same identity already appears in 28 of the 110 commits on `origin/master`. |
| What is not exempted | Any other identifier, personal data or secret, in any file, commit message or asset. Any commit made after this record; those use the no-reply identity. The release tag's tagger. |
| Reason | Removing the identity would rewrite the author fields of every unpublished commit. The Owner chose not to rewrite history further (D2 option B), after the limited D1 rewrite. |
| Approval | The Owner, in the stage 6-7-R3 instruction: "D2について、選択肢Bを承認する" (chat, 2026-11-16). The expiry was chosen by the Owner in the same session. |
| Expiry | When the push that publishes the release `rocky10.2-rpms-2026.1` completes. It applies to that one push only. A later push of other commits with this identity needs a new approval. |

## Release commit

The release commit applies the patch prepared in stage 6-7-R2, unchanged. It touches seven files:
- `rocky10.2/rpm-release.lock`
- `README.md` and `README.ja.md`
- `rocky10.2/README.md` and `rocky10.2/README.ja.md`
- `docs/ROCKY_INSTALLER_DESIGN.md`
- `rocky10.2/tests/test-rpm-source.sh`

It is the last commit on the branch, so the tag `rocky10.2-rpms-2026.1` will point at it. Its SHA is given in the final report of this stage. It cannot be written here, because this record is committed before it.

The release files are unchanged from stage 6-7-R1:

| File | SHA-256 |
|---|---|
| `hagistack-rpms-rocky10.2-rpms-2026.1-el10-x86_64.tar` (195 RPMs) | `565a10133cbb26b6f871f53514c7f8ebc0b3329c206a8b0ed7d2b93690ab713b` |
| `hagistack-srpms-rocky10.2-rpms-2026.1.tar` (69 SRPMs) | `db019350729477a7f12d4cfed5dd067e813eb0158a3f5b19d5191785708fdd25` |
| `rpm-release.lock.candidate` | `9ff85a2a5fffcb32ac5d1f400e25a1164d22c04af8c89a22c902c959e4c00da4` |
| `SHA256SUMS` | `4bd30d36466e9ea43e7f5ea24d89c0f524edfc558fd950f18abba7728b5280df` |
| `PACKAGE_MANIFEST.tsv` | `f49fe50bd263c5ddb3c411c6fc347da7c2a7ffddb4d03cffea47b4776bc483e6` |

- The RPM set identity is still `0b61c809…`.
- The controller + compute acceptance (s66r5d) ran on a rebuild with different bytes, not on these RPMs. The documents say so.
