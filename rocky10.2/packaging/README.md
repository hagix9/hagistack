# Hagistack's own RPM packaging (work in progress)

This directory is the replacement for building from RDO distgit. Nothing here
reads, translates or rephrases RDO's (or any distribution's) spec files or the
files kept next to them. Status: phase 1 — three representative packages,
specs generated and checked statically; not yet built on x86_64.

## Inputs

| Input | Where | Pinned by |
|---|---|---|
| Upstream release tarball and its detached signature | tarballs.openstack.org | SHA-256 in the definition (also in `../gazpacho.manifest`), signature checked by `%gpgverify` in `%prep` |
| OpenStack release signing key | releases.openstack.org/_static | SHA-256 in a `KEY` row of `../gazpacho.manifest` |
| Package definition | `defs/<srpm-name>.toml` | Git |
| Hagistack's own files (systemd units, sudoers, logrotate, sysusers, small scripts) | `files/<srpm-name>/` | Git; how each was written is in `files/<srpm-name>/AUTHORING.md` |

Build and runtime requirements come from upstream's own metadata through
`pyproject-rpm-macros` and the Python dependency generator; a definition only
adds what upstream metadata cannot say (for example `qemu-img`).

## Pieces

- `genspec.py` writes a spec from a definition. Shared building blocks: the
  signature check, the pyproject build, an import check, Sphinx HTML, gettext
  catalogues, config files copied from upstream `etc/`, Hagistack files,
  sysusers (`%sysusers_create_compat`) and systemd scriptlets
  (`%systemd_post` and friends).
- `defs/*.toml` state facts per package: pins, binary package names, files with
  owner, mode and config flag, units, users. Names, epochs, modes and owners
  follow what rc4 published, so the new packages can replace rc4's.
- `build-own.sh <outdir> <name>...` fetches and verifies the inputs, generates
  the spec and runs `rpmbuild -ba` (RPMs and SRPMs).
- `test_genspec.py` — static tests: every definition generates; pins agree with
  the manifest; sources are only OpenStack's release servers and `files/`;
  every file in `files/<name>/` is used and marked as Hagistack's; malformed
  definitions are refused.

Run the tests with Python 3.11 or newer: `python3 -I test_genspec.py`.

## Definition format (summary)

`[source]`: `name`, `project`, `version`, `release`, `epoch`, `tarball`,
`sha256`, `signing_key`, `license` (SPDX), `summary`, `description`, and
optionally `check = "import"`, `check_import_exclude`, `doc` (Sphinx source
directory), `buildrequires`, `locale_domain`, `drop_after_install`.

`[[package]]`: `name`, `kind` (`python`, `python-tests`, `files`,
`sphinx-html`), and as needed `summary`, `description`, `requires`,
`recommends`, `provides`, `modules`, `tests_path`, `bin`, `bin_symlinks`,
`install` (`src` = `upstream:<path in tarball>` or `file:<name in files/>`,
`dest`, `mode`, `user`, `group`, `config`), `dirs`, `symlinks`,
`systemd_units`, `sysusers`, `docs`, `licenses`.
