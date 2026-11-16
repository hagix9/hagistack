---
title: Download
description: The GitHub Release of rocky10.2-rpms-2026.1, the RPMs and SRPMs, supported OS and architecture, release notes.
---

## Current release

| Item | Value |
|---|---|
| Release name | Hagistack for Rocky Linux 10.2 — OpenStack 2026.1 |
| Tag | `rocky10.2-rpms-2026.1` |
| GitHub Release | [github.com/hagix9/hagistack/releases/tag/rocky10.2-rpms-2026.1](https://github.com/hagix9/hagistack/releases/tag/rocky10.2-rpms-2026.1) |
| OS | Rocky Linux 10.2 |
| Architecture | x86_64 |
| OpenStack | 2026.1 (Gazpacho) |

You normally do not download the RPMs by hand: the installer downloads and verifies them.

```bash
git clone --branch rocky10.2-rpms-2026.1 https://github.com/hagix9/hagistack.git
```

## Files

| File | Content | SHA-256 |
|---|---|---|
| `hagistack-rpms-rocky10.2-rpms-2026.1-el10-x86_64.tar` | 195 binary RPMs (all noarch) with repository metadata and `RPM-SHA256SUMS` | `565a10133cbb26b6f871f53514c7f8ebc0b3329c206a8b0ed7d2b93690ab713b` |
| `hagistack-srpms-rocky10.2-rpms-2026.1.tar` | 69 source RPMs (spec, upstream source, patches, licences) | `db019350729477a7f12d4cfed5dd067e813eb0158a3f5b19d5191785708fdd25` |
| `PACKAGE_MANIFEST.tsv` | per RPM: name, version, licence, source RPM, SHA-256 | `f49fe50bd263c5ddb3c411c6fc347da7c2a7ffddb4d03cffea47b4776bc483e6` |
| `rpm-release.lock.candidate` | equal to `rocky10.2/rpm-release.lock` in the tag | `9ff85a2a5fffcb32ac5d1f400e25a1164d22c04af8c89a22c902c959e4c00da4` |
| `SHA256SUMS` | the SHA-256 of each file | `4bd30d36466e9ea43e7f5ea24d89c0f524edfc558fd950f18abba7728b5280df` |
| `LICENSE`, `THIRD_PARTY_NOTICES.md`, `RELEASE-README.md`, `gazpacho.manifest`, `build-env.lock` | licence, third-party notices, readme, build inputs and environment | — |

RPM-set identity (SHA-256 of `RPM-SHA256SUMS`): `0b61c809ad2e90d5ab07502ae0732aaf61475278b032585cc98d9418c1f62000`

## Check by hand

```bash
sha256sum -c --ignore-missing SHA256SUMS
tar -xf hagistack-rpms-rocky10.2-rpms-2026.1-el10-x86_64.tar
( cd repo && sha256sum -c ../RPM-SHA256SUMS )
sha256sum RPM-SHA256SUMS
```

The last value must equal `RPM_SET_SHA256` in `rocky10.2/rpm-release.lock` in the tag.
The trust anchor is **the lock in the Git tag**, not the `SHA256SUMS` next to the download.
The `third-party/` files listed in `SHA256SUMS` are identical to `rocky10.2/third-party/` in the tag and are not attached to the release (hence `--ignore-missing`).

## Licences

- HAGISTACK's own code: MIT License (`LICENSE`)
- The software inside the RPMs: its own licences (mostly Apache License 2.0). See `THIRD_PARTY_NOTICES.md`, the licence column of `PACKAGE_MANIFEST.tsv`, and the source RPMs.
- Changes to upstream sources are listed in `THIRD_PARTY_NOTICES.md` and installed as `/usr/share/hagistack/changes/<package>/HAGISTACK-CHANGES`.
- HAGISTACK is not an OpenStack Foundation release. See `THIRD_PARTY_NOTICES.md` for trademarks.

## Release notes

The release notes are on the [GitHub Release](https://github.com/hagix9/hagistack/releases/tag/rocky10.2-rpms-2026.1). They cover:

- the verified configurations and which tests used the published RPMs
- known limitations (unsigned RPMs, SELinux permissive, no automatic firewall, live migration and three or more nodes not verified, x86_64 and Rocky Linux 10.2 only)
