# Rocky Linux 10.2 — re-investigation, 2026-09-27/28

**Status: NOT IMPLEMENTED. There is no `hagistack` shell in this directory, and
this document does not say "Rocky is supported".**

What it does say is more precise than the previous verdict, and it corrects part
of it. The earlier research (`../HAGISTACK_RENEWAL_RESEARCH_2026-09-26.md` §
"Rocky Linux 10.2") concluded **NO-GO for a direct build from distributed RPMs**,
on the grounds that *no EL10 RPMs exist* — not for OpenStack, and not even for
Open vSwitch/OVN. That scope limit was correct to state, but **the factual claim
inside it was partly wrong**: it only looked at released mirrors.

Looking where RDO itself points, EL10 RPMs **do** exist, and on Rocky Linux 10.2
`dnf` resolves a complete OpenStack install — 704 packages — and the one service
tried actually installs and runs. The reason Rocky is still not implemented has
moved from *"the parts do not exist"* to *"the parts that exist are not a
release, and the places they come from are not stable enough to build a simple
Bash installer against."*

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

## 2. Why it is still not implemented

Not "the parts are missing". These four:

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
* **Building our own RPMs from the RDO SRPMs.** The SRPMs are present
  (`openstack-keystone-…el10.src.rpm` and friends). Whether the *failed* builds
  fail for a fixable reason was not examined — that is the single most
  informative unknown left, because if they build, the release-coherence problem
  largely goes away.
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

`probe-repos.sh` needs only `curl`; the `dnf` checks run if `dnf` is present
(i.e. on an EL host) and are skipped with a note otherwise.
