# Rocky Linux 10.2 — re-investigation, 2026-09-27/28

**Status: NOT IMPLEMENTED. There is no `hagistack` shell in this directory, and
this document does not say "Rocky is supported".**

**Update 2026-09-28 (second pass).** The release question of §1.8 has been
answered with measurements rather than argument, and it is **2025.1 Epoxy**:

* `epoxy-rdo` is the newest release branch in **every** `rdo-packages` distgit
  checked — 6 services and 8 libraries. There is no `flamingo-rdo` (2025.2) and
  no `gazpacho-rdo` (2026.1). Matching Ubuntu 26.04's 2026.1 would mean creating
  packaging that exists nowhere (§1.9).
* **All six core services now build on Rocky Linux 10.2 at one release** —
  keystone 27.0.0, placement 13.0.0, glance 30.0.0, neutron 26.0.0, nova 31.0.0
  and horizon 25.3.0 — producing **45 RPMs**, every input pinned by distgit
  **commit id** and tarball **sha256** (§1.10).
* Both remaining failures were diagnosed and fixed, and **neither was an EL10
  incompatibility** (§1.11): one was RDO hardcoding `x86_64` in a repository
  URL, the other was a 2025.1 service built against a **trunk** library.
* What still blocks a Rocky `hagistack` is now a **counted** quantity:
  **61 more source packages** — the OpenStack libraries — must also be built at
  Epoxy, because RDO's EL10 binaries for them are trunk builds (§1.12).

So the answer moved again: from *"the parts do not exist"*, to *"the parts that
exist are not a release"*, to **"one release can be built, and here is exactly
how much of it is left"**. Still not implemented, and still not called
supported.

---

## 1. What was measured (all on 2026-09-27/28)

Method: HTTP listings and repository metadata for availability; a
`quay.io/rockylinux/rockylinux:10` container (**Rocky Linux 10.2, "Red Quartz",
x86_64, Python 3.12.13**) for `dnf` resolution and one real install. No existing
VM was touched and nothing was installed on any host.

### 1.1 Released mirrors: still empty (the earlier finding, re-confirmed)

| Source | Result |
|---|---|
| `dl.rockylinux.org/pub/rocky/10/{BaseOS,AppStream,CRB}` | **no `openvswitch`, no `ovn`, no `rabbitmq`** — re-checked by listing `Packages/o/` and `Packages/r/` |
| `dl.rockylinux.org/pub/sig/10/cloud/x86_64/` | only `cloud-common/`. No OpenStack |
| `mirror.stream.centos.org/SIGs/10-stream/cloud/x86_64/` | only `okd-4.18 … okd-5.1`. **No `openstack-*` at all** (9-stream has `openstack-wallaby` … `openstack-epoxy`) |
| `mirror.stream.centos.org/SIGs/10-stream/nfv/x86_64/openvswitch-2/` | **249 RPMs, including real OVS and OVN** — see §1.2 and the correction note below |
| EPEL 10 | no `ovn`, no `openvswitch`, **no `rabbitmq-server`, no `erlang`** — but it *does* carry `python3-openstackclient-9.0.0-6.el10_2` |

So on a plain Rocky 10.2 with BaseOS + AppStream + CRB + EPEL, the answer is
unchanged: the parts are not there. They are one repository away, but that
repository is not part of Rocky's own configuration and has to be added by hand.

> **Correction, same day.** The first pass of this probe reported that the
> 10-stream NFV SIG mirror held only `openvswitch-selinux-extra-policy`. That
> was a measurement error, not a fact: the fetch was piped through `head -40`
> and the CentOS page theme's own links filled those forty lines, so only the
> last entry survived. Re-fetched without the truncation, the listing has **249
> RPMs**, `openvswitch3.4`/`3.5` and `ovn24.09`/`ovn26.03` among them. The
> corrected figure is used throughout this document. It is the same class of
> mistake the earlier research made in the other direction — reading one
> listing and generalising from it — and the lesson is the same one this project
> keeps relearning: a truncated listing is not an inventory.

### 1.2 Where the EL10 parts actually are

RDO's own repository files name the locations, and they are not the mirrors:

| Component | Version found | Where |
|---|---|---|
| Open vSwitch | `openvswitch3.5-3.5.3-5.el10s` (also 3.4) | **released mirror**: `mirror.stream.centos.org/SIGs/10-stream/nfv/x86_64/openvswitch-2/` (249 RPMs). RDO's own repo file points instead at `buildlogs.centos.org/centos/10-stream/nfv/x86_64/openvswitch-2/` (267 RPMs — a superset with newer builds) |
| OVN | `ovn26.03-26.03.1-178.el10s` (also `ovn24.09-24.09.3-22`) | same pair of locations |
| RabbitMQ | `rabbitmq-server-3.13.7-1.el10` | `trunk.rdoproject.org/centos10/rabbitmq/` |
| Erlang | `erlang-26.2.5-1.el10` | same |
| OpenStack services | see §1.3 | `trunk.rdoproject.org/centos10-master/component/<component>/<hash>/` |

OVS and OVN are therefore the **least** of the problems: they are on a released
SIG mirror, they are current (OVN 26.03), and Rocky 10.2 can consume them by
adding one repository. Worth knowing, though, that RDO itself points at
`buildlogs.centos.org` — a build-artifact area that gets pruned — rather than at
the released mirror, so following RDO's repo files verbatim is less stable than
pointing at the mirror directly.

### 1.3 `dnf` resolves a full OpenStack on Rocky 10.2 — but not one release

With `baseos + appstream + crb + epel` plus RDO's own
`current/delorean.repo` and `delorean-deps.repo` for `centos10-master`:

```
dnf install --assumeno --setopt=install_weak_deps=False \
    openstack-keystone openstack-glance openstack-neutron-ml2 \
    openstack-nova-api openstack-nova-compute openstack-nova-scheduler \
    openstack-nova-conductor openstack-dashboard python3-openstackclient \
    rabbitmq-server ovn24.09-central ovn24.09-host \
    mariadb-server memcached httpd python3-mod_wsgi
  -> Install 704 Packages.  Operation aborted.   (i.e. it RESOLVED)
```

What it would have installed, and which OpenStack cycle each belongs to:

| Package | Version | Built | Cycle |
|---|---|---|---|
| `openstack-keystone` | 27.1.0 | 2025-04-30 | **2025.1 Epoxy** |
| `openstack-neutron-ml2` | 26.1.0 | 2025-07-01 | **2025.1 Epoxy** |
| `openstack-dashboard` | 25.4.0 | 2025-05-14 | **2025.1 Epoxy** |
| `openstack-nova-*` | 32.1.0 | 2025-11-05 | **2025.2 Flamingo** |
| `openstack-placement-api` | 14.1.0 | 2025-11-19 | **2025.2 Flamingo** |
| `openstack-glance` | 32.1.0 | 2026-03-17 | **2026.1 Gazpacho** |
| `ovn26.03` / `openvswitch3.5` | 26.03.1 / 3.5.3 | — | — |

That is **three different OpenStack cycles in one deployment**. Upstream tests
no such combination. For comparison, Ubuntu 26.04 ships one coherent set
(keystone 29, glance 32, neutron 28, nova 33).

Two lesser findings from the same run:

* `openstack-placement` is the **SRPM** name; the installable packages are
  `openstack-placement-api` and `openstack-placement-common`. `dnf install
  openstack-placement` fails with "No match for argument" even though
  `repoquery` shows the name.
* Every other named package resolved individually as well.

### 1.4 One service really installs and really runs

Not resolution — an actual `dnf install` inside Rocky Linux 10.2:

```
openstack-keystone-27.1.0-0.20250430145156.5125d9f.el10.noarch   installed
python3-keystone-27.1.0-…                                        installed
httpd-2.4.63-13.el10_2.6, python3-mod_wsgi-5.0.0-4.el10          installed
keystone-manage --version            -> 27.1.0
keystone-manage db_sync --help       -> full usage, entry point works
python3 -c 'import keystone'         -> /usr/lib/python3.12/site-packages/keystone/__init__.py
```

Disk cost of that one install: **202 MB**.

So "OpenStack cannot be installed on Rocky 10.2" is **not** true any more, and
this document does not claim it.

### 1.5 How EL packaging differs from Ubuntu — measured, not assumed

This is the part a Rocky `hagistack` would be built from. Taken from
`dnf repoquery -l` (no install needed) and the keystone install above:

| Concern | Ubuntu 26.04 | Rocky 10.2 (RDO EL10) |
|---|---|---|
| Keystone start | package ships **and enables** `/etc/apache2/sites-available/keystone.conf` | ships **no** unit and **no** enabled vhost — only a template at `/usr/share/keystone/wsgi-keystone.conf`. The operator must copy it into `/etc/httpd/conf.d/` |
| Placement start | Apache vhost `placement-api.conf`, auto-enabled | `/etc/httpd/conf.d/00-placement-api.conf`, shipped **already in place** |
| Glance start | `glance-api.service` | `openstack-glance-api` ships no `/etc/` or unit in its own file list; comes from `openstack-glance-common` |
| Nova units | `nova-conductor`, `nova-scheduler`, `nova-compute` | `openstack-nova-conductor`, `openstack-nova-scheduler`, `openstack-nova-compute`, plus `openstack-nova-api` / `openstack-nova-metadata-api` as **real units** (not Apache vhosts) |
| Neutron | API under Apache (`neutron-api` vhost); `neutron-rpc-server` etc. | `neutron-dhcp-agent`, `neutron-l3-agent`, `neutron-metadata-agent` units; ML2 config at `/etc/neutron/plugins/ml2/ml2_conf.ini`, plus `/etc/neutron/ovn.ini` |
| Horizon | `conf-available/openstack-dashboard.conf`, settings in `/etc/openstack-dashboard/local_settings.py`, snippets under `…/dist-packages/openstack_dashboard/local/local_settings.d/` | `/etc/httpd/conf.d/openstack-dashboard.conf`, settings file named `local_settings` (**no `.py`**), snippets in **`/etc/openstack-dashboard/local_settings.d/`** |
| OVS units | `openvswitch-switch` | `openvswitch.service`, `ovsdb-server.service`, `ovs-vswitchd.service` |
| OVN units | `ovn-central`/`ovn-host` oneshot wrappers → `ovn-ovsdb-server-nb/sb`, `ovn-northd`, `ovn-controller` | `ovn-northd.service` (from `ovn26.03-central`), `ovn-controller.service` (from `ovn26.03-host`) — **no wrapper units** |
| Package prefix | none | almost everything is `openstack-…`, versioned OVS/OVN (`openvswitch3.5`, `ovn26.03`) |

**None of this is transferable from the Ubuntu shell by analogy.** Nine of the
rows above differ, including the one that matters most for a first run (how
Keystone is served).

---

## 1.6 Why RDO's EL10 builds fail — read from the build logs

The 2026-09-27 pass treated "the core packages FAILED to build" as a fact to
route around. On 2026-09-28 the actual `rpmbuild.log` files were read
(`trunk.rdoproject.org/centos10-master/component/<c>/<hash>/rpmbuild.log`), and
**not one of the failures is an EL10 incompatibility**. There are two causes,
both ordinary packaging debt:

### Cause A — the spec patches a file upstream deleted

`openstack-keystone`, `openstack-heat` and `openstack-trove-ui` all die in
`%prep`:

```
+ sed -i s#/local/bin#/bin# httpd/wsgi-keystone.conf
sed: can't read httpd/wsgi-keystone.conf: No such file or directory
error: Bad exit status from /var/tmp/rpm-tmp.0ih6aa (%prep)
```

The spec — at **both** `rpm-master` and `epoxy-rdo` — runs
`sed -i 's#/local/bin#/bin#' httpd/wsgi-keystone.conf`. Upstream keystone
stopped shipping that file after 27.x. Checked directly against opendev:

| keystone ref | `httpd/wsgi-keystone.conf` |
|---|---|
| tag `27.0.0` | **HTTP 200** — present |
| tag `29.0.0` | HTTP 404 — gone |
| branch `master` | HTTP 404 — gone |

That is why the newest EL10 keystone anyone can install is **27.1.0**: it is the
last version where the spec still matches upstream. The fix is one line in a
spec file.

### Cause B — missing BuildRequires on RDO's own Python libraries

```
nova     : No matching package to install: 'python3dist(os-traits) >= 3.6'
                                           'python3dist(oslo-limit) >= 2.9.2'
                                           'python3dist(oslo-service) >= 4.5'
glance   : No matching package to install: 'python3dist(glance-store) >= 5.3'
neutron  : No matching package to install: 'python3dist(neutron-lib) >= 4'
                                           'python3dist(os-ken) >= 4.1.1'
                                           'python3dist(oslo-policy) >= 5'
                                           'python3dist(ovsdbapp) >= 2.17'
           -> Not all dependencies satisfied / Some packages could not be found.
```

Every one of those is an OpenStack library that RDO itself builds. The core
services are simply ahead of the libraries in the same repository. This is a
build-ordering problem inside RDO's chain, not a platform problem.

**So "EL10 does not work" was never the right conclusion. "Nobody is keeping the
EL10 build green" is.**

## 1.7 A core service, built from one release, on Rocky 10.2 — done

The smallest useful proof: take one core service, build it from a **single**
OpenStack release with every input pinned, on Rocky Linux 10.2.

`build-keystone-epoxy.sh` in this directory does it and is re-runnable. Result:

```
openstack-keystone-27.0.0-1.el10.noarch.rpm        8783a27640c5ccb3…
python3-keystone-27.0.0-1.el10.noarch.rpm          91353e173f9df5c9…
python3-keystone+ldap-27.0.0-1.el10.noarch.rpm     e09d81cb9acddb22…
python3-keystone-tests-27.0.0-1.el10.noarch.rpm    c5a36a7ef291df03…
```

Inputs, all pinned and all fetched over https:

| Input | Source | sha256 (first 16) |
|---|---|---|
| spec | `rdo-packages/keystone-distgit` branch `epoxy-rdo` | `0185ee6f527ab5dc…` |
| tarball | `tarballs.openstack.org/keystone/keystone-27.0.0.tar.gz` (1 770 055 B) | `8f9462fcbe98e3d5…` |
| signature | same URL `+ .asc` | `327e654324ee7fba…` |
| signing key | `releases.openstack.org/_static/0x22284f69…txt` | `56ae1e9ba54e6099…` |

**The spec verifies the upstream GPG signature in `%prep`** — `%{gpgverify}
--keyring=%{SOURCE102} --signature=%{SOURCE101} --data=%{SOURCE0}` — so the
chain is signed, not merely checksummed. A third party can re-run the script and
get the same RPMs.

Two things worth recording:

* **Build environment**: Rocky Linux 10.2, Python 3.12.13, in a local VM. The
  builder was **aarch64**; every RPM produced is `noarch`, so the output is
  architecture-independent. An x86_64 builder was not used and the x86_64 path
  is therefore not separately proven.
* **One gap the automation had to fill**: `%install` runs
  `python3 setup.py compile_catalog`, which needs Babel registered as a
  setuptools command. `python3-babel` is pulled in by neither the static nor the
  dynamic `builddep` pass, so it is installed explicitly. Without it the build
  ends with `error: invalid command 'compile_catalog'`.

Build dependencies resolved cleanly — `dnf builddep` exit 0, zero unsatisfied —
from Rocky 10.2 BaseOS/AppStream/CRB + EPEL 10 + the RDO EL10 deps repository.

## 1.8 The release question, which is now the whole problem

`rdo-packages` distgit has release branches up to **`epoxy-rdo` (2025.1)** and
nothing after it — no `flamingo-rdo` (2025.2), no `gazpacho-rdo` (2026.1). Only
`rpm-master` continues, and that is the trunk whose builds are broken above.

So the three candidate paths for Rocky 10.2 are:

| Path | Packaging exists? | State |
|---|---|---|
| **2025.1 Epoxy**, self-built on EL10 from `epoxy-rdo` | **yes** | one core service **proven to build** (§1.7). The rest is the same work repeated. |
| **master** from RDO's centos10-master | yes, and pre-built | broken (§1.6), three-cycle mixture, hash-pinned URLs |
| **2026.1 Gazpacho** — the release Ubuntu 26.04 ships | **no, nowhere** | every spec would have to be branched and updated first |

**This is a scope decision, not a technical one, and it is not ours to make
silently.** Ubuntu 26.04 gives 2026.1. The realistic Rocky 10.2 path gives
**2025.1** — one year older — and costs a build pipeline. Making Rocky match
Ubuntu means creating 2026.1 packaging that does not exist anywhere today.

## 1.9 Which single release can actually be assembled — measured

`git ls-remote` on every relevant distgit (no API limits, so the whole list was
checked rather than sampled). Release branches, newest first:

| distgit | newest release branch |
|---|---|
| keystone, glance, placement, neutron, nova, horizon | **`epoxy-rdo`** (2025.1) |
| neutron-lib, os-traits, os-resource-classes, oslo-limit, oslo-service, oslo-policy, os-ken, ovsdbapp | **`epoxy-rdo`** (2025.1) |

No `flamingo-rdo`, no `gazpacho-rdo`, anywhere. And the `epoxy-rdo` specs are a
**coherent set** — this was read from the spec files at the pinned commits, not
inferred:

| service | spec `Version:` | cycle |
|---|---|---|
| keystone | 27.0.0 | 2025.1 |
| glance | 30.0.0 | 2025.1 |
| placement | 13.0.0 | 2025.1 |
| neutron | 26.0.0 | 2025.1 |
| nova | 31.0.0 | 2025.1 |
| horizon (`python-django-horizon`) | 25.3.0 | 2025.1 |

Compare §1.3, where RDO's **pre-built** centos10-master mixes three cycles
(keystone 27.1.0 / nova 32.1.0 / glance 32.1.0). Building from `epoxy-rdo`
avoids that entirely. Ubuntu 26.04 ships 2026.1 (keystone 29, glance 32,
neutron 28, nova 33); **Rocky cannot match that today**, and choosing Rocky
means choosing a release one year older.

## 1.10 Pinning the build inputs — a branch name is not a pin

`build-keystone-epoxy.sh` fetched raw files from the `epoxy-rdo` **branch**.
That proves nothing about what you got: RDO can push to that branch at any time
and the next run silently builds different software. It is replaced by
`epoxy.manifest` + `build-epoxy.sh`, in which every input is pinned and
verified **before** it is handed to `rpmbuild`:

* **distgit by commit id.** `git checkout --detach <sha>`, then `git rev-parse
  HEAD` is compared with the manifest and the tree is required to be clean.
  A commit id is content-addressed, so this fixes the *entire* spec tree —
  spec, patches, logrotate files and all — not just one file.
* **tarball by sha256**, in addition to the GPG signature the spec itself
  verifies in `%prep` via `%{gpgverify}`.
* **the signing key by sha256** as well.
* **a fetch failure or a digest mismatch stops the build**, and the bad file is
  deleted so no later step can pick it up. Nothing falls back to "latest".

The pinned commits, verified on 2026-09-28:

```
keystone   967070efb58987e2d9f5bdf81def3cb32f061a4e
placement  45766cd06ac2205d41c7abbe06e5dbad70fc5ac7
glance     6110108606fd6d927875699ba9dec6d1b57e4984
neutron    8ec48e57b963f0798cad147e7f14901b1b8a9ee4
nova       c4da8f3f133dcc8d9e1314aefa716e449afc98dc
horizon    5aff204f8f3eb8dc5534175fc5282eeb10005723
oslo-limit 7164a7b05f4d5c5e55c7111943cd99b27cbe0550
```

**Result — 45 RPMs, one release, on Rocky Linux 10.2:**

```
openstack-keystone-27.0.0        openstack-placement-api-13.0.0
python3-keystone-27.0.0          openstack-placement-common-13.0.0
python3-keystone+ldap-27.0.0     python3-placement-13.0.0
python3-glance-30.0.0            openstack-nova-31.0.0  (+ api, common, compute,
openstack-neutron-common-26.0.0     conductor, migration, novncproxy, scheduler,
openstack-neutron-ml2-26.0.0        serialproxy, spicehtml5proxy)
openstack-neutron-rpc-server-26.0.0   python3-nova-31.0.0
openstack-neutron-ovn-metadata-agent-26.0.0
openstack-neutron-periodic-workers-26.0.0
python3-neutron-26.0.0           python3-django-horizon-25.3.0
python3-oslo-limit-2.6.1         openstack-dashboard-25.3.0
```

Every one is `noarch`. The builder was aarch64; the output is
architecture-independent, and an x86_64 builder is still not separately proven.

### Fixing the dependency versions, and distributing the result

Pinning the *sources* is not enough. RDO's centos10-master repositories carry
**trunk** versions of the OpenStack libraries, and they are almost always newer
than the release ones — so a self-built 2025.1 library does not stay installed.
Measured: `python3-oslo-limit` was downgraded to Epoxy 2.6.1, and the very next
`dnf builddep` pulled trunk 2.8.0 straight back, after which glance failed its
tests again with exactly the same error.

`build-epoxy.sh --publish` therefore does two things, not one:

* `createrepo_c` over the built RPMs, published as `[hagistack-epoxy]` with
  `priority=1`; and
* an explicit `exclude=` in the RDO repositories for **every package name it
  built**, so trunk cannot re-supply any of them at any version.

After that, `dnf` offers exactly one candidate:

```
$ dnf repoquery --qf '%{version}-%{release} (%{reponame})' python3-oslo-limit
2.6.1-1.el10  (hagistack-epoxy)
```

`build-epoxy.sh --lock` additionally writes `build-env.lock`, every RPM present
in the builder as `name-epoch:version-release.arch` — **1012 packages** — so the
build environment itself can be recreated, not just the sources. A local
`createrepo_c` repository is also the answer to *how would this be distributed*:
a directory of signed RPMs plus one `.repo` file, which is the same shape as
any other EL repository and needs no hash-pinned URLs (§2.2).

## 1.11 The two build failures — and why neither was an EL10 problem

The first run of `build-epoxy.sh` gave **3 PASS / 3 FAIL**. Both failure causes
were found and fixed, and this is the part that matters: *neither was EL10, and
neither was the release*.

### Failure A — neutron and nova: an architecture hardcoded in RDO's repo file

`rpmbuild` exited 11, "Failed build dependencies", naming `os-vif`,
`oslo-versionedobjects`, `tooz`, `websockify`, `glanceclient`, `neutronclient`
and `neutron-lib-tests`. Every one of those **does exist** on EL10 — checked
with `repoquery`. The real message was one level down:

```
package python3-os-vif-4.1.0 requires python3.12dist(ovsdbapp) >= 0.12.1,
  but none of the providers can be installed
- nothing provides python3.12dist(ovs) >= 2.10 needed by python3-ovsdbapp-2.13.0
```

`python3dist(ovs)` is the Python module that ships **with Open vSwitch**, and
RDO's `delorean-deps.repo` points at it with the architecture written into the
URL:

```
[centos10-nfv-ovs]
baseurl=https://buildlogs.centos.org/centos/10-stream/nfv/x86_64/openvswitch-2/
```

On any builder that is not x86_64 that repository yields nothing. The
architecture-specific mirrors all exist (`aarch64` and `x86_64` both answer
HTTP 200 on `mirror.stream.centos.org` and `buildlogs.centos.org`); RDO simply
does not use `$basearch`. Pointing one repo file at
`.../nfv/$basearch/openvswitch-2/` made `python3-openvswitch3.5` resolvable and
**neutron 26.0.0 and nova 31.0.0 then both built, exit 0**.

This is worth stating plainly because it is exactly the kind of thing that gets
written up as "nova cannot be built on Rocky 10". It can. The builder was
pointed at the wrong repository.

### Failure B — glance: a 2025.1 service against a trunk library

glance built and then failed `%check`: **7 failures out of 2228 tests**, all in
one class, `TestImageKeystoneQuota`:

```
TypeError: KeystoneQuotaFixture.setUp.<locals>.fake_limits()
           missing 1 required positional argument: 'resource_name'
```

Epoxy glance's test fixture matches the Epoxy `oslo.limit` callback signature.
The installed library was **oslo.limit 2.8.0**, a trunk build from 2025-09-03;
Epoxy is **2.6.1**. glance's `requirements.txt` only says `oslo.limit>=1.6.0`,
so packaging resolves happily and **only the test suite notices**.

Building `oslo-limit` 2.6.1 from its own `epoxy-rdo` commit, publishing it at
`priority=1` and excluding the trunk package (§1.10) fixed it:

```
rpmbuild exit=0    PASS glance      Ran: 2228 tests
```

That is the mixed-release problem of §1.3 caught in the act, on a real build,
rather than argued from version numbers. It is also the strongest available
evidence that "2025.1 services + trunk libraries" is not merely untested but
**observably incompatible**, and therefore that the library set has to be built
too.

## 1.12 What is left, counted

The recursive dependency closure of the nine core packages
(`dnf repoquery --requires --resolve --recursive`) is **1145 packages**:

| source | count | needs building for a single release? |
|---|---|---|
| Rocky BaseOS / AppStream / CRB | 870 | no — the distribution |
| RDO `delorean-master-testing` / `build-deps` (third-party Python) | 179 | no — release-agnostic |
| **RDO `delorean-component-*` (OpenStack-owned)** | **92** | **yes** |
| other (storage SIG, EPEL) | 4 | no |

Those 92 binary RPMs come from **68 source packages**. Seven are now built
(the six services plus `oslo.limit`), which leaves **61**: the oslo libraries,
`neutron-lib`, `os-ken`, `ovsdbapp`, `os-vif`, `os-traits`,
`os-resource-classes`, `glance-store`, `keystoneauth1`, `keystonemiddleware`,
the service clients, `openstacksdk`, `os-brick`, `taskflow`, `tooz`, `cliff`,
`stevedore` and the rest. Every one of them has an `epoxy-rdo` branch, so the
work is *known*, bounded and mechanical — `build-epoxy.sh` already takes them
as manifest rows — but it is 61 builds that have not been done.

**Until they are, an install on Rocky 10.2 still pulls trunk libraries, and
this document will not call that a single release.** That is why there is still
no `hagistack` shell here: the six services build, the platform is fine, and
the library set is the remaining cost.

## 2. Why it is still not implemented

Not "the parts are missing". These four:

These reasons apply to **RDO's pre-built centos10-master**, which is what §1.3
describes. They do NOT apply to the self-built 2025.1 path of §1.7, whose only
open question is the release choice in §1.8.

1. **It is not a release.** Three OpenStack cycles mixed (§1.3). Nobody tests
   keystone 2025.1 with nova 2025.2 and glance 2026.1. A bug found there is a
   bug nobody upstream will recognise.
2. **The repository URLs move.** `current/delorean.repo` pins each component to
   a **content-hash directory** (`…/component/keystone/dc/62/dc6299e8…_b1b2606b/`).
   A Bash installer cannot hardcode those; it would have to fetch
   `delorean.repo` at run time, which means two runs a week apart silently
   install different software. That is the opposite of a reproducible shell.
3. **The builds are stalled and the core ones failed.** `status_report.csv` for
   `centos10` (253 rows, fetched 2026-09-27) shows `openstack-keystone`,
   `openstack-glance`, `openstack-nova`, `openstack-neutron`,
   `openstack-placement` and `python-django-horizon` all **FAILED**, with their
   last attempts between **2026-05-13 and 2026-05-30** — about four months ago.
   What is installable is the last build that happened to succeed, months
   earlier. There is no `stable/2026.1` EL10 branch at all; only `master`,
   which RDO itself labels *"Latest (untested!) trunk repos"*.
4. **Rocky does not ship the data plane itself.** OVS and OVN exist, and on a
   released mirror, but that mirror is the *CentOS Stream 10* NFV SIG — not part
   of Rocky Linux's own repository set, and built as `el10s`. Adding it is one
   line, and it is the smallest of the four problems; it is listed because it
   is still a dependency on another distribution's SIG rather than on Rocky.

**Maintenance burden, stated plainly, against the goal of a plain-Bash builder:**
a Rocky shell would have to fetch a repo file at run time, install from a CI
artifact store that its own publisher disclaims, and support a combination of
three OpenStack releases that has no upstream. Every one of those is a recurring
cost that the Ubuntu shell simply does not have: there, `apt-get install
keystone` gets a tested 2026.1 package from the distribution, and the same
command will get the same thing next year.

---

## 3. What was NOT investigated

Stated so that nobody mistakes this for a complete survey:

* **Source builds / `pip` into a venv.** Not attempted. Python 3.12.13 on
  Rocky 10.2 is a plausible base, and `python3-openstackclient` is already in
  EPEL 10, but nothing here evaluates building the services from source — and
  the non-Python parts (OVS, OVN, libvirt integration, SELinux policy) are the
  hard part, not the Python.
* ~~**Building our own RPMs from the RDO SRPMs.**~~ **Done on 2026-09-28** —
  see §1.6 for why the RDO builds fail and §1.7 for a core service built from
  source. What remains unexamined is the *rest* of the set: glance, neutron,
  nova, placement and horizon were not built, and the libraries those need
  (`os-traits`, `oslo-limit`, `oslo-service`, `glance-store`, `neutron-lib`,
  `os-ken`, `oslo-policy`, `ovsdbapp`) were not built either. Keystone is the
  easiest of them; nothing here shows the others are as easy.
* **Containers (Kolla/podified).** Out of scope by the project's own constraint:
  this repository builds with plain Bash on the host.
* **Whether the resolved 704-package set actually runs.** Only keystone was
  installed, and only far enough to prove its entry points work. Nothing was
  configured, no database was created, no service was started, and no
  cross-release interaction was exercised.
* **Rocky 9 + 2025.1 Epoxy via the 9-stream Cloud SIG.** Still the obvious
  fallback if an EL platform is required — `openstack-epoxy` genuinely exists
  there as a released repository — and still unverified.

---

## 4. What would change the answer

Re-run `./probe-repos.sh` and look for **all** of these:

1. `mirror.stream.centos.org/SIGs/10-stream/cloud/x86_64/` gains an
   `openstack-<release>/` directory (i.e. the Cloud SIG ships EL10), **or** RDO
   publishes a `centos10-<release>` branch beside `centos10-master`.
2. `status_report.csv` shows `SUCCESS` for keystone, glance, nova, neutron,
   placement and horizon, with timestamps from the same cycle.
3. The six core services resolve at **one** OpenStack version.
4. OVS and OVN stay on the released 10-stream NFV SIG mirror. **This one is
   already met** (249 RPMs, OVN 26.03) — it is listed so that a future probe
   notices if it stops being true.
5. The repository can be addressed by a **stable URL** — not a content hash that
   changes on every build.

Conditions 1–3 are about the software; 4–5 are about whether a shell script can
sanely be pointed at it. Both halves have to hold. Today 4 is met and 1, 2, 3
and 5 are not.

If they do, §1.5 is the starting point: the package names, unit names and
configuration paths are already measured, and the Ubuntu shell's structure
(phases, idempotent `ini_set`, no-drop rule, honest skip/exit-4 reporting)
carries over unchanged — only the packaging layer differs.

---

## 5. Files here

| File | What it is |
|---|---|
| `README.md` | this document |
| `probe-repos.sh` | re-runs every availability check in §1 and prints a verdict line per condition in §4. Read-only: it fetches HTTP listings and repository metadata and installs nothing |
| `build-keystone-epoxy.sh` | the original single-service proof (§1.7). **Superseded by `build-epoxy.sh`**: it fetches from the `epoxy-rdo` *branch*, which is not a pin. Kept because §1.7 refers to it |
| `epoxy.manifest` | the pinned build inputs — distgit **commit id**, spec file, tarball name and **sha256** — for keystone, placement, glance, neutron, nova, horizon and oslo.limit. Add a row to build another package |
| `build-epoxy.sh` | builds any subset of the manifest on Rocky Linux 10.2, verifying every input first and **stopping** on a fetch failure or digest mismatch (§1.10). `--publish` turns the output into a `priority=1` repository and excludes those names from RDO trunk; `--lock` records the whole build environment. It installs build dependencies, so run it in a throwaway VM or container, not on a host you care about |

`probe-repos.sh` needs only `curl`; the `dnf` checks run if `dnf` is present
(i.e. on an EL host) and are skipped with a note otherwise.
