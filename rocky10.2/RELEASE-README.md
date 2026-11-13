# Hagistack RPM release for Rocky Linux 10.2 (OpenStack 2026.1)

This file ships with every release candidate made by `make-rpm-release.sh`.
The release holds the OpenStack 2026.1 RPMs that the `hagistack` installer
installs on Rocky Linux 10.2. It is not an OpenStack Foundation release (see
"Trademarks" in `THIRD_PARTY_NOTICES.md`).

## What the release holds

| File | Content |
|---|---|
| `hagistack-rpms-<TAG>-el10-x86_64.tar` | the binary RPMs (`repo/`, with repository metadata) and `RPM-SHA256SUMS`; the file `hagistack` downloads |
| `hagistack-srpms-<TAG>.tar` | the source RPM of every binary RPM: spec, upstream source archive, patches, licence texts |
| `PACKAGE_MANIFEST.tsv` | one line per RPM: name, epoch, version, release, architecture, licence tag, source RPM, sha256 |
| `SHA256SUMS` | the sha256 of every other file in the release |
| `rpm-release.lock.candidate` | the lock that pins this release; committed as `rocky10.2/rpm-release.lock` when the release is published |
| `LICENSE` | the MIT License of Hagistack's own work |
| `THIRD_PARTY_NOTICES.md` | which licence covers what, changes made to upstream sources, trademarks |
| `third-party/` | files from other projects that Hagistack redistributes, with their licences |
| `gazpacho.manifest`, `build-env.lock` | the pinned build inputs and the build environment |
| `RELEASE-README.md` | this file |

## Supported systems

- **Operating system:** Rocky Linux 10.2. Other EL10 distributions are not
  verified.
- **Architecture:** x86_64 only.
- **Other repositories needed:** Rocky Linux BaseOS, AppStream and CRB, EPEL 10,
  the CentOS NFV SIG Open vSwitch repository and RDO's EL10 dependency
  repositories. The installer configures them (see `THIRD_PARTY_NOTICES.md`).

## Installing

Use the `hagistack` installer from the Git tag of this release. The release is
published in this order: `rpm-release.lock.candidate` is committed as
`rocky10.2/rpm-release.lock`, that commit is tagged `<TAG>`, and the release is
created from the tag. So the tag holds the lock, which pins this release's asset
by sha256, size and RPM-set identity:

```sh
git clone --branch <TAG> https://github.com/hagix9/hagistack.git
cd hagistack/rocky10.2
sudo ./hagistack all-in-one            # plus your settings; see README.md
```

The installer downloads the asset and verifies it against the lock. It checks
every RPM against `RPM-SHA256SUMS`, the identity of that listing, the repository
metadata and `rpm -K`. The trust anchor is the lock in the Git checkout, not
`SHA256SUMS` next to the download. The RPMs are not GPG-signed.

To use the RPMs without the installer, unpack the asset. `repo/` is then a DNF
repository with complete metadata. The packages also need the other
repositories listed above.

## Checking a download by hand

```sh
sha256sum -c SHA256SUMS
tar -xf hagistack-rpms-<TAG>-el10-x86_64.tar
( cd repo && sha256sum -c ../RPM-SHA256SUMS )
sha256sum RPM-SHA256SUMS      # must equal RPM_SET_SHA256 in rocky10.2/rpm-release.lock at <TAG>
```

## Known limitations

These are listed in full under "Known limitations" in `rocky10.2/README.md`:

- The RPMs are not signed, and the added repositories use `gpgcheck=0`.
- SELinux is switched to permissive. No OpenStack SELinux policy is shipped, and
  enforcing mode is not verified.
- No host firewall is configured. Keep the nodes on a trusted network.
- Cinder, Swift, the noVNC console proxy and other services are not installed.
- The provider NIC is not attached to `br-ex`.
- The package test suites (`%check`) were not run.
- These are not verified: live migration, three or more nodes, and floating IPs
  reached from outside the host.

## Source code and licences

Every binary RPM's source RPM is in `hagistack-srpms-<TAG>.tar`. The release
generator refuses a release where they do not correspond.

Licences: the RPM `License:` tags (also in `PACKAGE_MANIFEST.tsv`) summarise the
licence of each package. The licence texts are installed with the packages and
are in the source RPMs. Hagistack's own packaging is under the MIT License
(`LICENSE`). See `THIRD_PARTY_NOTICES.md`.
