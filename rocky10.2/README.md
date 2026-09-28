# Rocky Linux 10.2 + OpenStack 2026.1 Gazpacho

**Status: NOT IMPLEMENTED.** There is no `hagistack` shell in this directory.
This document does not say "Rocky is supported", and it does not call anything
"2026.1 support" that is not built from 2026.1.

**The target is 2026.1 Gazpacho on x86_64** — the same OpenStack release, and
the same architecture, as the Ubuntu 26.04 shell that is already verified on two
GCE machines. The 2025.1 Epoxy build described in §4 is kept as a research
record; it is **not** the deliverable and no Epoxy shell will be written.

> **About the RPMs described below.** Every result in §0–§3 was produced on an
> **aarch64** builder, because that is what was available locally. Those RPMs are
> `noarch`, and the spec defects they uncovered are architecture-independent and
> carry over directly — that is what they are for. **They are not evidence that
> the x86_64 build works**, and they are not the deliverable. The x86_64 build is
> tracked separately in §8.

---

## 0. Where this stands, in one table

Everything below was built on Rocky Linux 10.2 (**aarch64** — see the note
above; this is the investigation builder, not the target) from the released
2026.1 tarballs, with every input pinned. Nothing here is mixed with 2025.1 or
2025.2.

| 2026.1 component | version | build |
|---|---|---|
| keystone | 29.1.0 | **PASS** (2 spec deltas) |
| glance | 32.0.0 | **PASS** (no spec change needed) |
| placement | 15.0.0 | **PASS** (2 spec deltas) |
| nova | 33.0.2 | **PASS** (1 spec delta) |
| neutron | 28.0.2 | see §3.4 |
| horizon | 25.7.3 | **BLOCKED** — §3.5 |
| oslo.config | 10.3.0 | **PASS** |
| oslo.service | 4.5.1 | **PASS** |
| os-traits | 3.6.0 | **PASS** (1 spec delta) |
| ovsdbapp | 2.16.1 | **PASS** |
| stevedore | 5.7.0 | **PASS** |
| neutron-lib | 3.24.0 | **PASS** |
| os-ken | 4.1.2 | **PASS** (1 spec delta) |

**The conclusion is not "it works" and not "it cannot be done".** It is: the
service layer of 2026.1 builds on Rocky 10.2, the cause of every failure was
found and is small and mechanical, and one specific thing is still missing that
no amount of OpenStack packaging work will supply (§3.5). The deployment shell
is therefore not written yet, and §5 says exactly what would have to happen
first.

---

## 1. There is no 2026.1 packaging anywhere — this is built from master specs

Checked on 2026-09-28, by listing rather than sampling:

| Question | Answer |
|---|---|
| Does `rdo-packages` have a `gazpacho-rdo` distgit branch? | **No.** For every repo checked, the newest release branch is `epoxy-rdo` (2025.1). The only thing after it is `rpm-master`. |
| Is there a `centos10-gazpacho` or `centos10-2026.1` trunk tree? | **No.** `trunk.rdoproject.org` has exactly one EL10 tree, `centos10-master`. |
| Does the CentOS Stream 10 Cloud SIG ship an `openstack-2026.1`? | **No.** |
| Does 2026.1 exist upstream? | **Yes** — every deliverable has a `stable/2026.1` branch and a final release. |

So the only packaging that can be pointed at 2026.1 is RDO's **`rpm-master`**
spec, which tracks the development branch. `epoxy.manifest`'s specs carry real
version numbers; the `rpm-master` ones carry `Version: XXX` / `Release: XXX`
for DLRN to fill in at build time. `build-rpms.sh` substitutes them from the
manifest and says so in the log rather than leaving a confusing failure later.

The authoritative 2026.1 version of every component — including the libraries —
is the **2026.1 upper-constraints file**
(`releases.openstack.org/constraints/upper/2026.1`, 562 entries). That file is
what "one release" means for a library, and it is where every version in the
table above comes from. os-traits releases independently of the cycle; its
2026.1 pin is 3.6.0.

---

## 2. Pinning: what `build-rpms.sh` verifies before rpmbuild sees anything

`build-keystone-epoxy.sh` fetched raw files from a **branch**. A branch name
proves nothing about what you got. Every input is now pinned and checked, and
anything that does not match **stops the build**:

* **distgit by commit id.** `git checkout --detach <sha>`, then `git rev-parse
  HEAD` is compared with the manifest and the tree must be clean. A commit id is
  content-addressed, so this fixes the whole spec tree — spec, patches, units,
  vhosts — not one file.
* **tarball by sha256**, in addition to the GPG signature `%prep` verifies.
* **signing key by sha256**, and *which* key is part of the manifest (§2.1).
* **spec patches** are reviewable files in `./spec-patches`, applied with
  `--dry-run` first. A patch that does not apply is a hard stop — a silently
  skipped patch means building something other than what was reviewed.
* **`--publish`** turns the output into a `priority=1` repository *and* writes an
  explicit `exclude=` into the RDO repositories for every package name built.
  Both halves are needed: without the exclude, the next `dnf builddep` upgrades a
  self-built release library straight back to RDO's trunk build. That was
  measured, not assumed — it is what silently re-broke a glance build during the
  Epoxy work (§4).
* **`--lock`** records every RPM in the builder (1014 packages) so the build
  environment can be recreated, not just the sources.

### 2.1 One release, two signing keys

OpenStack rotates its release signing key every cycle, and a stable point
release made after a rotation is signed with the newer key. Read out of the
`.asc` files and matched against the keys published at
`releases.openstack.org/_static/`:

| 2026.1 tarball | signed by |
|---|---|
| glance 32.0.0, placement 15.0.0, and the libraries | `0xb8e9315f4855…` — *"OpenStack Infra (2026.1/Gazpacho Cycle)"* |
| keystone 29.1.0, neutron 28.0.2, nova 33.0.2, horizon 25.7.3 (2026-09 point releases) | `0x30566c450e41…` |

RDO's `rpm-master` spec pins a third key (`0x2426b928…`) which signed **neither**.
So the manifest names the key per package and `build-rpms.sh` retargets
`%global sources_gpg_sign`, logging the substitution. A key id the manifest does
not pin stops the build: fetching whatever key a spec asks for would make
`%gpgverify` meaningless.

---

## 3. What actually broke, and why

### 3.1 The dominant cause: 2026.x deleted the generated WSGI scripts

Five of the seven spec patches in `./spec-patches` are the same finding. Across
2026.x, OpenStack projects removed their generated `*-wsgi` / API scripts and
replaced them with an importable module (`<project>/wsgi/api.py`, defining
`application`). The `rpm-master` specs still package the binaries:

| package | what the spec still lists | what 2026.1 declares |
|---|---|---|
| keystone 29.1.0 | `keystone-wsgi-admin`, `keystone-wsgi-public`, `httpd/wsgi-keystone.conf` | only `keystone-manage`, `keystone-status`; ships `keystone/wsgi/api.py` and `httpd/uwsgi-keystone.conf` |
| placement 15.0.0 | `placement-api` | only `placement-manage`, `placement-status`; ships `placement/wsgi/api.py` |
| nova 33.0.2 | `nova-api*`, `nova-metadata-wsgi` | eleven scripts, none an API server; ships `nova/wsgi/osapi_compute.py`, `nova/wsgi/metadata.py` |
| neutron 28.0.2 | `neutron-api`, `neutron-server` | 24 scripts, neither of those; ships `neutron/wsgi/api.py` |
| os-ken 4.1.2 | `osken`, `osken-manager` | **no console scripts at all** |

Upstream's own release notes name it: `remove-wsgi-scripts`,
`add-keystone-wsgi-module`, `add-placment-wsgi-module`.

**This is also why RDO's EL10 keystone has been stuck at 27.1.0**: its `%prep`
runs `sed -i 's#/local/bin#/bin#' httpd/wsgi-keystone.conf` against a file
upstream deleted after 27.x.

**It has a consequence beyond packaging.** The distgit also ships units and
vhosts that start those removed binaries:

```
openstack-nova-api.service           ExecStart=/usr/bin/nova-api
openstack-nova-metadata-api.service  ExecStart=/usr/bin/nova-api-metadata
neutron-server.service               ExecStart=/usr/bin/neutron-server
00-placement-api.conf                WSGIScriptAlias / /usr/bin/placement-api
```

All four are dead on 2026.1. The placement vhost is patched here, because it
would have produced a running-but-500 service rather than a build failure; the
units are left visibly dead on purpose, because pointing them at something
invented here would be worse than leaving the breakage where a reader can see
it. **On 2026.1 every one of these APIs has to be run as a WSGI application** —
which is the same shape Ubuntu 26.04 already uses, where keystone, placement,
nova-api and the neutron API are Apache vhosts and only the RPC/agent processes
are units. A Rocky `hagistack` would write that httpd configuration itself.

### 3.2 PEP 625 renamed the sdists

`os-traits` fails before it starts:

```
cd os-traits-3.6.0
/var/tmp/rpm-tmp.4Ry5xa: line 44: cd: os-traits-3.6.0: No such file or directory
```

Upstream now publishes `os_traits-3.6.0.tar.gz`, unpacking into
`os_traits-3.6.0/`, while the spec builds both the filename and the setup
directory from the hyphenated project name. `build-rpms.sh` asks the spec what
filename it wants (`rpmspec -P`, so macros are expanded) and saves the download
under that name, which handles the drift generally; only the unpack directory
needed a patch.

### 3.3 The library layer had to be built, and it cascades

The six services could not be built against RDO's EL10 libraries: those are
trunk builds from **2025**, older than what 2026.1 requires.

```
nova     : os-traits >= 3.6      (EL10 has 3.5.0)
           oslo-service >= 4.5   (EL10 has 4.3.0)
neutron  : neutron-lib >= 3.24   (EL10 has 3.21.1)
           os-ken >= 4.1.1       (EL10 has 3.1.1)
           oslo-config >= 10.2   (EL10 has 10.0.0)
           ovsdbapp >= 2.14.1    (EL10 has 2.13.0)
```

And they cascade: `neutron-lib 3.24.0` needs `stevedore >= 5.6`, EL10 has 5.5.0.
Seven libraries were built at their 2026.1 pins to clear it, all of them PASS.
The cascade is real but it terminates — nothing in this chain needed a library
that does not exist at 2026.1.

One measurement worth keeping: of the 126 distinct minimum-version requirements
across the six services, **106 are already satisfied by what EL10 carries** and
only 14 were too old. That is why the library work here was seven packages and
not sixty — but see §3.6 for why "satisfied" is not the same as "one release".

### 3.4 neutron

neutron 28.0.2 cleared every dependency once the seven libraries were in place,
and then failed on §3.1 — `neutron-api` and `neutron-server` in `%files`. The
patch is in `spec-patches/neutron.patch`. Its result is recorded in §3.7.

### 3.5 horizon is blocked by something OpenStack packaging cannot fix

This is the one that matters, and it is a different class from everything above.

```
python3dist(qrcode) >= 8.2                 is needed by python-django-horizon
python3dist(xstatic-font-awesome) >= 6.2.1.2  is needed by python-django-horizon
```

Horizon 2026.1 needs a set of JavaScript-asset packages and one QR library at
versions **nobody ships for EL10**:

| needed by 2026.1 | available on Rocky 10.2 | where the old one comes from |
|---|---|---|
| `XStatic-Font-Awesome 6.2.1.2` | 4.7.0.0 | RDO `delorean-master-testing` |
| `XStatic-Angular 1.8.2.3` | 1.5.8.0 | RDO `delorean-master-testing` |
| `XStatic-jQuery 3.7.1.1` | 1.10.2.1 | RDO `delorean-master-testing` |
| `XStatic-JQuery-Migrate 3.3.2.2` | 1.2.1.1 | RDO `delorean-master-testing` |
| `qrcode 8.2` | 7.4.2 | **Rocky AppStream** |

And unlike every other gap in this document, **there is no distgit to pin**:
`rdo-packages` has no `qrcode-distgit` and no `xstatic-*-distgit`. These live in
RDO's third-party dependency repository and in Rocky's own AppStream, at
versions years behind. Building them means writing new spec files from scratch
for roughly ten packages — or shipping Horizon's static assets some other way
entirely.

That is the single blocker that stops this from being a complete 2026.1 set
today.

### 3.6 "Satisfied" is not "one release"

§3.3 says 106 of 126 minimum requirements are satisfied by EL10 today. That is a
statement about **lower bounds in `requirements.txt`**, not about releases.
RDO's EL10 libraries are 2025-era trunk builds: they clear 2026.1's floors while
being different software from what 2026.1 was tested against. `oslo.db` is 17.4.0
on EL10 where 2026.1 pins 18.0.0; `keystonemiddleware` is 10.11.0 where 2026.1
pins 12.0.0.

Installing 2026.1 services on top of those is exactly the mixture this document
refuses to call "2026.1 support". A real single-release install needs every
OpenStack-owned package at its 2026.1 pin. The dependency closure of the six
services is **1145 packages**, of which **92 binaries from 68 source packages**
are OpenStack-owned. Eleven of those 68 are built here. **57 remain.**

That this is not merely pedantic was demonstrated during the Epoxy work, where
exactly this mixture produced a real, reproducible failure — see §4.

### 3.7 Build results

See §0 for the table. Logs are in the builder under `~/epoxy-build/logs/`.

---

## 4. Record: the 2025.1 Epoxy build (not the deliverable)

Kept because it is evidence, not because it is the plan. On 2025.1 Epoxy, from
`epoxy-rdo` distgit commits, all six core services built on Rocky Linux 10.2 —
keystone 27.0.0, placement 13.0.0, glance 30.0.0, neutron 26.0.0, nova 31.0.0,
horizon 25.3.0 — producing 45 RPMs. `epoxy.manifest` still drives it:

```
./build-rpms.sh --manifest epoxy.manifest
```

Two findings from that work carry over and are the reason this document is
shaped the way it is:

**A repository URL with an architecture written into it.** neutron and nova
failed with a pile of missing BuildRequires that all *existed*. One level down:

```
nothing provides python3.12dist(ovs) >= 2.10 needed by python3-ovsdbapp
```

because RDO's `delorean-deps.repo` points at the NFV SIG OVS repository as
`.../nfv/x86_64/openvswitch-2/` — literally, not `$basearch`. On any other
builder that repository yields nothing. The architecture-specific mirrors all
exist. Pointing one repo file at `$basearch` made both build. **"nova cannot be
built on Rocky 10" would have been the wrong conclusion; the builder was pointed
at the wrong repository.**

**A release service against a trunk library.** glance built and then failed
`%check` — 7 of 2228 tests, all in `TestImageKeystoneQuota`:

```
TypeError: KeystoneQuotaFixture.setUp.<locals>.fake_limits()
           missing 1 required positional argument: 'resource_name'
```

Epoxy glance's fixture matches the Epoxy `oslo.limit` callback signature; the
installed library was trunk 2.8.0 where Epoxy is 2.6.1. `requirements.txt` only
says `>=1.6.0`, so packaging resolved happily and **only the test suite
noticed**. Building `oslo.limit 2.6.1` and giving it repository priority fixed
it — and the first attempt at that failed too, because `dnf builddep` pulled the
trunk build straight back, which is why `--publish` writes an `exclude=` as well
as a repository.

That is §3.6 demonstrated rather than argued.

---

## 5. Why there is still no `hagistack` here, and what would change it

**Not** "the parts do not exist", and **not** "it does not build". These:

1. **Horizon has no path today** (§3.5). Ten-odd XStatic packages and `qrcode`
   at versions nobody packages for EL10, with no distgit to start from. A cloud
   without a dashboard is a defensible product; shipping one while calling it
   "2026.1 support" is not, so this is a decision to take deliberately rather
   than by omission.
2. **57 OpenStack source packages remain** (§3.6) before an *install* is one
   release rather than a build that happened to succeed. Each is mechanical —
   `build-rpms.sh` takes them as manifest rows — but each may carry its own
   small spec delta, and five of the first eleven did.
3. **Every API needs a WSGI server written by hand** (§3.1). No packaged unit or
   vhost starts keystone, placement, nova-api or the neutron API on 2026.1. This
   is real work for the shell, not a blocker: it is the same architecture Ubuntu
   26.04 already uses, and the Ubuntu shell's httpd handling ports across.
4. **It is unproven on x86_64, which is the actual target.** Every RPM in §0 is
   `noarch` and the builder was aarch64. The specs are fixed and the manifest is
   pinned, so the x86_64 build is expected to follow the same path — but
   "expected" is not "measured", and nothing has been installed or started
   anywhere. §8 tracks it.

**What would change the answer**, in the order it would matter:

* a way to get Horizon's static assets at 2026.1 on EL10 — packaged, vendored,
  or dropped;
* the remaining 57 source packages built and published as one repository;
* an actual install of that repository on a Rocky 10.2 host, with the services
  started under httpd, before any claim of support;
* and, separately: RDO publishing a `gazpacho-rdo` branch would remove the need
  for most of `./spec-patches`, because these are upstream packaging bugs that
  belong upstream. Every patch here is small enough to be a pull request.

---

## 6. How EL packaging differs from Ubuntu — measured, not assumed

Still accurate, and still the starting point for a Rocky shell. Taken from
`dnf repoquery -l` and real installs.

| Concern | Ubuntu 26.04 | Rocky 10.2 (RDO EL10) |
|---|---|---|
| Keystone start | package ships **and enables** an Apache vhost | ships **no** unit and **no** enabled vhost — and on 2026.1 not even a wsgi script (§3.1) |
| Placement start | Apache vhost, auto-enabled | `/etc/httpd/conf.d/00-placement-api.conf`, shipped in place — but it points at a removed binary on 2026.1 |
| Nova API | Apache vhost, no unit | `openstack-nova-api.service` — dead on 2026.1 (§3.1) |
| Neutron API | Apache vhost; `neutron-rpc-server` + `neutron-periodic-workers` units | `neutron-server.service` — dead on 2026.1; the agent scripts are all still there |
| Horizon | `conf-available/openstack-dashboard.conf`, settings in `local_settings.d/` | `/etc/httpd/conf.d/openstack-dashboard.conf`, settings file named `local_settings` (**no `.py`**) |
| OVS / OVN units | `openvswitch-switch`; `ovn-central`/`ovn-host` wrappers | `openvswitch.service`, `ovsdb-server`, `ovs-vswitchd`; `ovn-northd`, `ovn-controller` — **no wrapper units** |
| Package prefix | none | almost everything is `openstack-…`, with versioned OVS/OVN (`openvswitch3.5`, `ovn26.03`) |

OVS and OVN themselves are the least of the problems: they are on the released
CentOS Stream 10 NFV SIG mirror, they are current (OVN 26.03), and Rocky 10.2
consumes them by adding one repository — pointed at `$basearch`, per §4.

---

## 7. Files here

| File | What it is |
|---|---|
| `README.md` | this document |
| `gazpacho.manifest` | **the target.** Pinned build inputs for OpenStack 2026.1 — distgit commit id, spec file, version, tarball sha256 and signing key, for six services and seven libraries |
| `epoxy.manifest` | the 2025.1 Epoxy inputs, kept as the §4 record |
| `build-rpms.sh` | builds any subset of a manifest on Rocky Linux 10.2, verifying every input first and stopping on a mismatch (§2). `--publish` writes a `priority=1` repository and excludes those names from RDO trunk; `--lock` records the build environment. Installs build dependencies, so run it in a throwaway VM |
| `spec-patches/` | one reviewable patch per package where RDO's `rpm-master` spec does not match the released 2026.1 tarball. Each carries a header explaining what upstream changed and why. Five of seven are the same WSGI-script removal (§3.1) |
| `probe-repos.sh` | re-runs the repository availability checks. Read-only |
| `build-keystone-epoxy.sh` | the original single-service proof. **Superseded by `build-rpms.sh`**: it fetched from a branch, which is not a pin. Kept for provenance |

---

## 8. The x86_64 build — the actual deliverable

x86_64 is the official target architecture for Rocky 10.2, matching Ubuntu
26.04, which is already verified on two GCE x86_64 machines up to guest boot and
cross-node Geneve traffic.

The aarch64 work in §0–§3 is reused as **investigation and spec repair**. None
of the aarch64 RPMs is shipped or treated as evidence for x86_64.

### 8.1 Where it was built, and why not locally

On a GCE `n2-standard-4` running the stock Rocky Linux 10 x86_64 image
(Rocky 10.2, Python 3.12.14), created for this and deleted afterwards. Building
locally would have meant qemu emulation of x86_64 on an Apple Silicon host for
60-odd packages, which is the wrong tool for a build this size. Cost of the
builder: about **$0.40**.

Everything was built with `--nocheck`. The test suites here reach 121 166 tests
(os-ken) and 21 189 (neutron); re-running them on a second architecture proves
little about `noarch` Python and costs hours. **So for x86_64 the honest claim
is "builds", not "passes its tests"** — §3.7 records which suites did run, on
aarch64.

### 8.2 Result: 182 RPMs, 61 packages, one release

All five core services and every OpenStack library they need:

```
keystone 29.1.0   glance 32.0.0   placement 15.0.0   neutron 28.0.2   nova 33.0.2
```

plus 56 libraries and clients at their exact 2026.1 upper-constraints versions.
Horizon is deliberately not built (§3.5).

### 8.3 The gate: a clean install from one release

This is the measurement that decides whether a real host can be attempted.
Against a clean `--installroot`, with **RDO's OpenStack component repositories
disabled** so nothing can silently fall back to a trunk snapshot:

```
Install 710 Packages

  307 baseos          Rocky 10.2
  224 appstream       Rocky 10.2
   88 hagistack-epoxy our 2026.1 build
   47 epel            EPEL 10
   36 delorean-master-testing   third-party Python libs, NOT OpenStack
    3 crb / 3 nfv-ovs / 2 storage
```

**Every OpenStack package came from the 2026.1 repository**, with three
deliberate exceptions, none of which is a release mixture:

* `python3-cliff 4.13.3` and `python3-requestsexceptions 1.4.0` come from
  **EPEL 10** at exactly the versions 2026.1 pins. A released distribution
  repository carrying the right version is better than building it again.
* `openstack-network-scripts` is a CentOS network-scripts compatibility package,
  not an OpenStack release component.

The 36 packages from `delorean-master-testing` are third-party Python libraries
that neither Rocky nor EPEL package — `eventlet`, `httplib2`, `retrying`,
`flask-restful`, `pysaml2` and similar. That repository is RDO's **dependency**
tree, not its OpenStack component tree, so using it mixes no releases. Removing
it entirely is not possible today: without it, keystone, glance, neutron and
nova are all unsatisfiable.

### 8.4 What the x86_64 build taught that aarch64 had not

Five more spec defects, all in `./spec-patches`:

* **`oslo.cache`, `oslo.privsep`** — PEP 625 again, this time in the metadata
  directory: the build writes `oslo_cache-4.1.1.dist-info` while the spec
  packages `oslo.cache-…`. `oslo.privsep`'s wildcard does not save it, because
  the wildcard is only on the version.
* **`oslo.utils`, `tooz`** — build dependencies that only exist in
  `test-requirements.txt` and that EL10 does not package at all (`tzdata`,
  `kubernetes`, `python-consul2`, `sherlock`, `sysv-ipc`). Added to each spec's
  own `excluded_brs`, the mechanism it already uses for this.
* **`cliff`** — 4.13.3 still ships `cliff/tests` in the sdist but no longer
  installs them into the wheel, so the `-tests` subpackage cannot be built.
* **`tooz`** — three separate faults in one spec, the last of which is the one
  that mattered: `Requires: python3-tooz+zake`, for an extras subpackage whose
  extra upstream deleted. That single line made `python3-tooz` uninstallable and
  was the last thing standing between the build and a clean install.

And one class of defect was **removed from the patch set entirely**. The PEP 625
unpack-directory problem (`cd os_traits-3.6.0` where the spec says
`os-traits-3.6.0`) hit six packages. Rather than six near-identical patches,
`build-rpms.sh` now reads the top-level directory out of the tarball and points
`%autosetup -n` at it. On the x86_64 run it corrected five specs by itself:

```
%autosetup -n set to the tarball's actual directory: tooz-8.1.0 (spec said %{pypi_name}-%{upstream_version})
%autosetup -n set to the tarball's actual directory: osc_lib-4.4.0 (spec said %{library}-%{upstream_version})
…
```

### 8.5 How each API has to be started on 2026.1 — read from the RPMs

Not inferred: this is `rpm -qlp` on the packages that were actually built.

| Service | What the RPM ships | Usable on 2026.1? |
|---|---|---|
| keystone | `/usr/share/keystone/uwsgi-keystone.conf` only — a template, not installed into `conf.d` | **No unit, no vhost.** The shell must write an httpd vhost at `keystone/wsgi/api.py` |
| glance | `/usr/bin/glance-wsgi-api`, `openstack-glance-api.service` | **Yes** — glance kept a real daemon, so the unit works as-is |
| placement | `/etc/httpd/conf.d/00-placement-api.conf` | **Yes, after our patch** retargets it from the removed `/usr/bin/placement-api` to the module |
| neutron | `neutron-rpc-server.service`, `neutron-ovn-metadata-agent.service` | RPC and metadata units work. **There is no API unit or vhost at all** — the shell must write one at `neutron/wsgi/api.py` |
| nova API | `openstack-nova-api.service`, `openstack-nova-metadata-api.service`, `openstack-nova-os-compute-api.service` | **All three are dead** — every `ExecStart` names a binary 33.0.2 no longer builds. The shell must write httpd vhosts at `nova/wsgi/osapi_compute.py` and `nova/wsgi/metadata.py` and leave these units disabled |
| nova compute/scheduler/conductor | real units | **Yes** |

This is the same division Ubuntu 26.04 already uses, so the Ubuntu shell's
Apache handling carries over — with EL names (`httpd`, `/etc/httpd/conf.d`) and
one extra job: on Ubuntu the packages enable their own vhosts, and here nothing
does.

### 8.6 Not done

* **Nothing has been installed or started on a real host.** §8.3 is a dependency
  resolution, not a deployment. No service has answered a request.
* **`%check` was not run on x86_64** for any package.
* **Horizon** is still blocked (§3.5) and is not in the 182.
* There is still **no `hagistack` shell** in this directory.

---

## 9. GCE acceptance, 2026-09-29 — Rocky 10.2 x86_64, OpenStack 2026.1

The goal of all of the above, reached: a plain Bash shell installs 2026.1 on
Rocky 10.2 and boots guests on two nodes that talk to each other.

Six things are kept apart on purpose, because they are six different claims:

| claim | result |
|---|---|
| **builds** | 182 RPMs, 61 packages, all 2026.1 (§8) |
| **`%check`** | **not run on x86_64.** Ran on aarch64 for 9 packages (§3.7) |
| **dependency resolution** | `dnf install --assumeno` resolved 710 packages (§8.3) — a dry run, and labelled as one |
| **real install** | **`dnf install` exit 0, "Complete!", 992 packages on the host** |
| **API response** | every service answered a **token-authenticated** call |
| **guest boot** | **ACTIVE in 18 s on both nodes, cloud-init completed** |

### 9.1 Environment and cost

| | |
|---|---|
| node1 | `hagistack-rocky-node1`, n2-standard-4, 60 GB, `10.146.0.31` |
| node2 | `hagistack-rocky-node2`, n2-standard-2, 40 GB, `10.146.0.32` |
| image | `rocky-linux-10` (Rocky 10.2, Python 3.12.14), nested virtualisation on |
| builder | `hagistack-rocky-build`, n2-standard-4, deleted after the build |
| cost | builder ≈ $0.40, node1 ≈ $0.75, node2 ≈ $0.10 — order **$1.25**, list-price estimate |

### 9.2 Provenance of the real install

From the transaction itself, not from a plan:

```
281 appstream        67 baseos       3 crb          Rocky 10.2
 88 hagistack-gazpacho                              our 2026.1 build
 50 epel                                            EPEL 10
 35 delorean-master-testing                         third-party python, NOT OpenStack
 19 centos10-rabbitmq   6 nfv-ovs    2 storage
```

**No `delorean-component-*` repository was configured on either node**, and the
shell refuses to stay quiet if one is: it checks and warns that the install is
not a single release.

The 35 packages from `delorean-master-testing` were each checked against the
2026.1 deliverable list and the upper-constraints file. **Not one is an
OpenStack deliverable.** They are third-party Python libraries — `eventlet`,
`httplib2`, `pysaml2`, `kombu`, `paste`, `retrying`, `zipp` and similar — plus
RDO's OVS compatibility shims (`rdo-openvswitch`, `openstack-network-scripts`).
Honestly stated: several are **older than the 2026.1 upper-constraints pin**
(`amqp` 5.2.0 against 5.3.1, `httplib2` 0.22.0 against 0.31.2). Upper-constraints
is a testing pin, not a requirement; the services' own lower bounds are
satisfied, which is what the RPM dependencies encode. **The OpenStack layer is
one release. The third-party Python layer is whatever EL10 has** — exactly the
position any distribution-packaged OpenStack is in.

### 9.3 Results

**node1 — all-in-one — PASS**

| item | evidence |
|---|---|
| real install | `dnf install` exit 0, 992 packages |
| all-in-one | **exit 0, no phases skipped** |
| keystone | `openstack token issue` succeeded — served by httpd from `keystone/wsgi/api.py` |
| glance | `openstack image list` succeeded — `openstack-glance-api.service`, the one packaged unit that still works |
| placement | `GET /resource_providers` with a real token — the packaged vhost, retargeted by our spec patch |
| neutron | `openstack network list` succeeded — httpd from `neutron/wsgi/api.py` |
| nova | `openstack compute service list` succeeded — httpd from `nova/wsgi/osapi_compute.py` |
| OVN | chassis registered, `br-ex` mapped to `physnet1`, loopback ovsdb manager for os_vif |
| **guest boot** | **ACTIVE in 18 s**, port ACTIVE |
| **cloud-init** | **`=== datasource: ec2 net ===`, `instance-id: i-00000005`, ssh key injected, `demo1 login:`** |
| re-run safety | two consecutive runs: **exit 0, 88 unchanged lines, 0 units restarted, 0 phases skipped**, guest still ACTIVE |

**node2 — compute-add — PASS**

| item | evidence |
|---|---|
| credential delivery | exactly **5** keys, **0** database or admin keys |
| compute-add | **exit 0, every phase completed** |
| `[database]` safety | commented out, and the journal shows **0 database lines** |
| registration | both nodes `up` in `compute service list` and `hypervisor list` |
| OVN | **2 chassis**, hostnames matching nova's host, geneve encaps `10.146.0.31` and `10.146.0.32` |
| **guest boot on node2** | **ACTIVE in 12 s** |
| re-run safety | exit 0, 13 unchanged lines, **0 units restarted**, 0 phases skipped |

**Cross-node traffic — PASS**

```
30 packets transmitted, 30 received, 0% packet loss
rtt min/avg/max/mdev = 0.991/1.332/2.736/0.280 ms
```

and the tunnel carrying it, captured on the physical NIC:

```
IP 10.146.0.31.47109 > 10.146.0.32.geneve: Geneve, Flags [C], vni 0x2,
   options [8 bytes]: IP 10.10.10.50 > 10.10.10.52: ICMP echo request
IP 10.146.0.32.iris-lwz > 10.146.0.31.geneve: Geneve, Flags [C], vni 0x2,
   options [8 bytes]: IP 10.10.10.52 > 10.10.10.50: ICMP echo reply
```

### 9.4 What Rocky needed that Ubuntu did not

Every one of these was found from an installed file or a failure, not by
analogy. The last one cost the most time and is the most instructive.

| | |
|---|---|
| **host identity** | Neutron's OVN driver binds a port by matching `Chassis.hostname` to nova's `binding:host_id`. Rocky leaves nova on the short name while ovn-controller records the FQDN, so every boot failed with *"Refusing to bind port … due to no OVN chassis for host"* — with the chassis plainly visible in `ovn-sbctl show`. Both sides are now set from one variable |
| **metadata `root_helper`** | lives in `[AGENT]`, not `[DEFAULT]`. In the wrong section it silently reads as the built-in `sudo`, the haproxy spawn dies with *"a terminal is required to read the password"*, the `ovnmeta` namespace exists with nothing listening in it, and the only symptom is a guest that cannot reach `169.254.169.254` |
| **`/etc/keystone/keystone.conf`** | does not exist; the RPM ships only a dist conf |
| **`/etc/neutron/plugin.ini`** | required by `neutron-rpc-server.service`, created by nothing |
| **`neutron-db-manage`** | in the main `openstack-neutron` package, which also ships the dead `neutron-server.service` |
| **nova `state_path`** | unset, nova writes its node identity into site-packages, gets EACCES and exits — after logging enough to look healthy |
| **nova `compute_driver`** | Ubuntu gets it from `nova-compute-kvm`'s own conf; EL ships nothing |
| **metadata agent ovsdb** | runs as `neutron` and cannot read the root-owned OVS socket |
| **`default` security group** | not a unique name once the service project exists |
| **`ProcSubset=pid`** | Rocky's httpd does **not** have it, so the Ubuntu defect does not apply here — checked, not assumed |

### 9.5 Not done

* **Horizon.** Not built and not installed. Its 2026.1 dependencies —
  `XStatic-Font-Awesome 6.2.1.2`, `XStatic-Angular 1.8.2.3`,
  `XStatic-jQuery 3.7.1.1`, `XStatic-JQuery-Migrate 3.3.2.2`, `qrcode 8.2` —
  are not packaged for EL10 at those versions and have **no distgit to build
  from**, so roughly ten new spec files would have to be written. It did not
  block anything above, and it is still part of the goal.
* **SELinux is permissive.** `openstack-selinux` is published only in RDO's
  OpenStack component repositories, which this shell refuses to enable. The
  shell sets `httpd_can_network_connect`, then drops to permissive and says so
  every run and in `hagistack status`.
* **`%check` was not run on x86_64** for any package.
* **No physical-LAN path.** `br-ex` has no NIC attached on GCE, so the provider
  network and its floating IPs were never routed off-host.
* **Live migration, volumes, more than two nodes** — not attempted.
