# Rocky Linux 10.2 installer — design and specification

Status: implemented in `rocky10.2/hagistack` 0.2.0-rocky (working tree of
2026-11-09). Not yet independently audited. This file states what the installer
is meant to do; [rocky10.2/README.md](../rocky10.2/README.md) tells a user how
to use it. If the two disagree, report it: the code is the arbiter of what
happens, this file of what is intended.

Version pins and supported platforms are governed by
[CURRENT_GENERATION_POLICY.md](CURRENT_GENERATION_POLICY.md) and are not
repeated here.

## 1. Purpose

A user who has a fresh Rocky Linux 10.2 x86_64 host, the Hagistack checkout and
a handful of settings runs **one command** and gets OpenStack 2026.1, and can
later add compute nodes, with nothing else to prepare: no RPM build of their
own, no hand-made DNF repository.

Constraints carried over unchanged: plain Bash, no Ansible/Kolla/Packstack/
DevStack; every input pinned; idempotent re-runs; nothing deleted from an
operator's configuration; no secret printed.

## 2. One entry point

`rocky10.2/hagistack` is the only user-facing command. Helper scripts it calls
(`build-rpms.sh`, `build-in-container.sh`) remain separate files because they
also run on their own, but a user never needs to call them.

| Command | Runs on | Result |
|---|---|---|
| `all-in-one` | the host | controller + hypervisor on one host (A) |
| `controller` | the host | controller services only, no `nova-compute` (B) |
| `compute-add --local` | a `controller` host | adds the hypervisor; host becomes all-in-one (C) |
| `compute-add --controller-ip IP` | the NEW compute host | remote compute node (D) |
| `compute-secrets` | controller | prints the compute credentials (+ RPM set identity) to a file |
| `rpm-bundle --output FILE` | controller | the controller's verified RPM set as a tarball |
| `discover-hosts` | controller | maps new compute hosts into cell1 |
| `rpm-prepare` | any | prepares/verifies the RPM set only |
| `status` | any | role, RPM set, phases, SELinux, services |

### 2.1 Roles and transitions

The role is recorded in `/etc/hagistack/deployment.env` (0600, no secrets,
KEY=VALUE parsed as data) once packages are installed. Allowed:

| Recorded role | `all-in-one` | `controller` | `compute-add --local` | `compute-add --controller-ip` |
|---|---|---|---|---|
| none | yes | yes | **refused** (no controller here) | yes |
| controller | yes (adds hypervisor) | yes (re-run) | yes | **refused** |
| all-in-one | yes (re-run) | **refused** (would not remove nova-compute) | yes (re-run) | **refused** |
| compute | **refused** | **refused** | **refused** | yes (re-run) |

Nothing ever removes a service. The only transition is controller → all-in-one.

### 2.2 Phases per configuration

| Phase | A | B | C | D |
|---|---|---|---|---|
| preflight (incl. RPM source + role check) | ✓ | ✓ | ✓ | ✓ |
| secrets | ✓ (generate/reuse) | ✓ | – | ✓ (must exist) |
| controller reachability | – | – | – | ✓ (before anything is changed) |
| RPM source | ✓ | ✓ | ✓ (recorded source) | ✓ |
| repositories, SELinux | ✓ | ✓ | ✓ | ✓ |
| packages | full set | full minus `openstack-nova-compute libvirt qemu-kvm` | compute set | compute set |
| MariaDB … Nova (API, scheduler, conductor) | ✓ | ✓ | – | – |
| OVN | central + chassis (gateway) | central + chassis (gateway) | – (already a chassis) | chassis only |
| nova-compute | ✓, waits for this host `up`, discover_hosts | – | ✓, same | ✓, DB keys commented out |
| metadata agent | ✓ | ✓ | – | ✓ |
| initial resources, Horizon | ✓ | ✓ | – | – |

Controller-only keeps `ovn-host` because the controller is the gateway chassis
(`enable-chassis-as-gw`) for router external gateways. On a controller with no
compute node a guest cannot be scheduled; that is correct, not a failure.

`compute-add --local` runs no controller configuration phase. `nova.conf`
already holds the compute settings (`compute_driver`, `virt_type`, `state_path`)
because the controller's Nova phase writes them on every role. MGMT_IP and
REGION_NAME are taken from `deployment.env`; a conflicting `--mgmt-ip` is refused.

### 2.3 Remote compute: where commands run, how credentials travel

1. Controller: `(umask 077; sudo ./hagistack compute-secrets > compute-secrets.env)`.
   Refuses a terminal. Contains exactly `RABBIT_PASS NOVA_SERVICE_PASS
   PLACEMENT_SERVICE_PASS NEUTRON_SERVICE_PASS METADATA_PROXY_SECRET` plus the
   non-secret `RPM_SET_SHA256`. No database or admin password.
2. Operator copies it over a channel they trust (scp), installs it as
   `/etc/hagistack/secrets.env` (root, 0600) on the new node, shreds copies.
3. New node: `sudo ./hagistack compute-add --controller-ip IP [rpm options]`.
4. Controller: `sudo ./hagistack discover-hosts` (also happens within 300 s
   via `discover_hosts_in_cells_interval`).

Hagistack does not SSH between nodes and holds no cross-node credential: the
operator moves one file. That keeps the trust model to "whoever can copy
secrets.env". Several compute nodes are added by repeating 2–4 per node.

No NIC or bridge is ever changed on any node except creating the empty OVS
bridge `br-ex` on the controller; the provider NIC is never attached to it
(unchanged limitation).

## 3. RPM preparation

Rocky ships no OpenStack. Four sources, chosen with `--rpm-source`; all end in a
verified local directory used as a `file://` repository with `priority=1`, so
the OpenStack half of the installer is shared by all of them.

| Source | When | What hagistack does |
|---|---|---|
| `github` (default) | normal users | download the Release asset pinned in `rpm-release.lock`, verify, unpack |
| `build` | explicit choice | run the existing `build-rpms.sh` in a disposable Rocky 10.2 container on this host |
| `bundle` | compute node of a controller that built from source | verify a tarball made by `rpm-bundle` against the controller's set identity |
| `repo-url` | existing repositories (compatibility) | use `--repo-url` as before; nothing verified |

Default selection: `--repo-url` given → `repo-url`; `--rpm-bundle` given →
`bundle`; host already deployed → the recorded source; otherwise `github`.
`--repo-url` combined with another source is refused.

**No silent fallback.** A failed download never starts a build; a failed build
never downloads; nothing falls back to "latest".

### 3.1 RPM set identity

`RPM-SHA256SUMS` lists `<sha256>  <file>` for every RPM, sorted by name
(`LC_ALL=C`). The set identity is the SHA-256 of that file. Equal identities
mean byte-identical RPMs.

Verification of a set (`rpm_verify_set`), all of which must pass:

1. the RPM files present equal the listing exactly (no missing, extra or altered file);
2. the identity equals the expected one (lock, compute-secrets or `--rpm-set-sha256`);
3. repodata: every file named in `repomd.xml` exists inside `repodata/` with the
   recorded checksum; every package in `primary` exists with the recorded
   checksum; no RPM is absent from `primary`; the declared count matches
   (Python standard library; repodata is gzip-compressed for that reason);
4. `rpm -K --nosignature` passes for every RPM.

### 3.2 GitHub Release source and its trust anchor

A checksum file published next to an asset proves nothing: whoever can replace
the asset can replace it. The trust anchor is **`rocky10.2/rpm-release.lock` in
the Git checkout the user runs**. It pins:

`LOCK_FORMAT, LOCK_STATUS, RELEASE_TAG, BASE_URL, ASSET_NAME, ASSET_SHA256,
ASSET_SIZE, RPM_SET_SHA256, RPM_COUNT, MANIFEST_SHA256`

Download path: `${BASE_URL}/${RELEASE_TAG}/${ASSET_NAME}` with curl (`-f`,
retries, timeouts) into a staging directory under `/var/lib/hagistack/rpms`.
Then: size and SHA-256 against the lock → tar members checked **before**
extraction (regular files only, only `RPM-SHA256SUMS`, `repo/*.rpm`,
`repo/repodata/*`; no absolute path, no `..`) → unpack → §3.1 with
`RPM_SET_SHA256` → RPM count. `MANIFEST_SHA256` must equal this checkout's
`gazpacho.manifest`, so a release cannot be paired with a checkout that pins
different inputs.

GitHub Releases are not treated as a DNF repository: the asset is one tarball,
fetched once.

`LOCK_STATUS=unpublished` (the state shipped today) makes `github` stop with
guidance and download nothing. A release is never treated as published until
the lock says so, and the lock is committed only after the release exists and
has been audited. `--rpm-lock-file` exists to test a mirror (for example a
local HTTP server before publication); it is a deliberate operator choice.

GitHub limits (checked 2026-11): a release asset must be under 2 GiB; a release
may hold up to 1000 assets. The RPM set is far below the size limit as one tar.
RPMs are never committed to Git history.

### 3.3 Source build

`build` runs `build-in-container.sh` in `quay.io/rockylinux/rockylinux:10.2`
**pinned by digest** (`--build-image NAME@sha256:…` to override; a tag alone is
refused), with podman installed on the host if missing:

- `/src` = `rocky10.2/` read-only; `/build` = persistent work directory
  (clones, tarballs, rpmbuild state); `/out` = result.
- inside: CRB, EPEL 10, RDO `delorean.repo` + `delorean-deps.repo` (mutable;
  their digests are logged), build tools; then `build-rpms.sh --nocheck` with
  `BUILD_SRPMS=1`. Pass 1 builds everything; the services fail on build order
  because the manifest lists them before their libraries; pass 2 rebuilds
  exactly the packages pass 1 reported as failed (the recorded two-pass
  procedure, automated). A `STOP` (pin/verification failure) is never retried.
- `%_buildhost` is fixed to `hagistack-builder` so RPM headers carry no
  cloud-internal host name.
- result: `repo/` (flat, gzip repodata), `srpms/`, `logs/`, `build-env.lock`;
  hagistack writes `RPM-SHA256SUMS` and verifies (§3.1).

The host never gets builddep packages or RDO's trunk repositories; they live in
the container. A second host is therefore not required.

Work directory: `/var/lib/hagistack/rpm-build/<input-id>/`, where input-id is
the SHA-256 over `gazpacho.manifest`, `build-rpms.sh`, `build-in-container.sh`,
`spec-adapt/`, `spec-templates/`, `third-party/`. Same inputs → the verified
result is reused, no rebuild. Old work directories are not deleted
automatically.

`build-rpms.sh` remains usable on its own exactly as before; the additions
(`BUILD_SRPMS`, `RESULTS_FILE`) are opt-in environment variables.

### 3.4 Multi-node consistency

- Every node records its set identity in `deployment.env` when packages are
  installed. A later run whose prepared set differs **stops** before installing
  anything (switching sets is an upgrade, and hagistack does not do upgrades).
- `compute-secrets` carries the controller's `RPM_SET_SHA256`. `compute-add`
  stops when the node's set differs from it.
- Reuse without rebuilding: `github` nodes download the same pinned asset;
  for a controller that built from source, `rpm-bundle` + `--rpm-source bundle`
  ships the controller's set, verified against the identity in compute-secrets.
- `repo-url` cannot be verified; both sides using it is accepted with a warning.

### 3.5 Cache and re-runs

Verified sets carry `.hagistack-verified`. A re-run re-verifies the cached set
fully (§3.1) and reuses it: no download, no build. A cached set that no longer
verifies is moved aside as `<dir>.broken.<timestamp>` (never deleted) and, for
`github`, fetched again.

## 4. Configuration

Settings: command line > environment > config file (`hagistack.env`, parsed,
never sourced; searched in `./`, beside the script, `/etc/hagistack/`) >
default. New keys: `RPM_SOURCE RPM_BUNDLE RPM_LOCK_FILE BUILD_IMAGE
RPM_SET_EXPECTED` (CLI: `--rpm-source --rpm-bundle --rpm-lock-file
--build-image --rpm-set-sha256`). `REPO_URL` is now validated
(`http(s)://` or `file:///`, restricted characters).

Fixed in this revision: the config file default was `./hagistack.env`, which
made a missing file fatal and the documented search unreachable.

## 5. Failure behaviour

- Preflight and RPM preparation change nothing that a failure leaves half-done:
  downloads go to a staging directory and are only moved into place after
  verification; failed staging is removed.
- `compute-add` checks controller reachability before any repository, SELinux
  or package change.
- Every other phase keeps the existing contract: add/edit only, idempotent,
  `INCOMPLETE` banner and exit 4 when a phase is skipped.

## 6. Release of RPMs (process)

1. Build with `--rpm-source build` (or `rpm-prepare --rpm-source build`).
2. `make-rpm-release.sh --set-dir … --tag … --out …` writes the asset, the SRPM
   tarball, `PACKAGE_MANIFEST.tsv`, `SHA256SUMS`, provenance files and
   `rpm-release.lock.candidate`. It refuses RPMs whose BUILDHOST is not the
   neutral name and a set whose SRPMs are incomplete. It publishes nothing.
3. Licence audit of the exact set (see the release candidate's audit file).
   Unresolved items block publication.
4. Independent audit, Owner approval, then publication and commit of the lock.

## 7. Acceptance

Separately, each on real Rocky 10.2 x86_64 (nested KVM):

- RPM: source build through hagistack; GitHub path against a mock server;
  checksum/size/identity mismatch, 404, network failure, incomplete set,
  repodata inconsistency, unsafe tar, unpublished lock (automated:
  `rocky10.2/tests/test-rpm-source.sh`); cache reuse; `--repo-url`
  compatibility; multi-node identity check.
- OpenStack: all-in-one; controller-only; controller → `compute-add --local`;
  remote compute; two remote compute nodes; registration; guest boot; guest
  network reachability across nodes; re-runs.

A configuration is PASS only when it was itself run; all-in-one success does
not imply the others.

## 8. Release conditions (Rocky)

- every item in §7 PASS or explicitly accepted as UNVERIFIED by the Owner;
- licence audit with no unresolved blocker for the published files;
- independent audit;
- Owner approval for push, tag, Release creation and lock commit.
