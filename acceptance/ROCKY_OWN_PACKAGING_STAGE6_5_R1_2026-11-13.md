# Hagistack's own RPM packaging — stage 6-5-R1: Hagistack logo in the documentation (D2), complete change notices, GCE preconditions (2026-11-13)

The implementer wrote this record. The independent audit is reported separately
below.

What was not done:
- No GCE resource was created, changed or deleted.
- No VM was created.
- No RPM was built.
- Nothing was pushed, tagged or released.

Branch: `feat/rocky-own-packaging-s65r1`, started from
`ba3395cf9389986be7564873f302386e640be380`. The 21 untracked files are untouched,
and `rocky10.2/packaging/__pycache__/` still has the 15:36 timestamp of the stage
6-5 incident. Every Python run in this stage used `-B`.

## Owner decisions implemented

- **D2:** the OpenStack documentation theme's logos are replaced with Hagistack's.
- **Further notices:** the build-time changes of Keystone, Placement and Nova
  were investigated. Notices were added where distributed files are changed.
- T2 and B2 are kept.

## Commits

| Commit | Change |
|---|---|
| `3ec77b0` | D2 in `genspec.py` and `make-branding.py`; Keystone, Placement and Nova `changes`; 47 release raises; `release_check.py` and `make-rpm-release.sh`; `build-own.sh`; notices; tests |
| (this record) | stage 6-5-R1 record |

## 1. What the documentation theme puts in the documentation packages

All of this was checked on the old set's RPMs, read on macOS with `bsdtar`.

- **47 binary packages carry HTML documentation**: 46 `*-doc` packages and
  `python3-os-brick`. Each comes from its own source package.
- **47 definitions build HTML**, recomputed from the definitions. That matches
  the 47 packages. Three of them (barbicanclient, keystoneauth1,
  keystonemiddleware) were already changed by B2, so **44 more** change, as
  stage 6-5 said.
- **Each tree carries the same theme files.** The theme is `openstackdocstheme`.
  Among its files, these show the OpenStack logo; their sha256 is identical in
  all 47 trees:
  - `_static/images/logo-full.svg` and `.png` (135 × 35), `logo-vert.svg` and
    `.png` (59 × 54);
  - `openstack-logo-full.*` and `openstack-logo-vert.*`, which are
    byte-identical to the two above;
  - `_static/favicon.ico` (32 × 32, the OpenStack mark).
- **Where the logos appear in the pages.** The page header shows
  `<img src="_static/images/logo-full.svg" width="135px" height="35px">`, and the
  theme CSS uses `logo-full.svg` and `logo-vert.svg`.
- **Theme images that are not the OpenStack logo:**
  - `superuser1–4.png` are illustrations of people;
  - `license.png` is the Creative Commons badge;
  - `footer-*.png` are social-network icons, linking to OpenStack's and
    OpenInfra's accounts;
  - `search-icon.png` and `loading.gif`.
- **No project image is named like a logo.** No documentation tree has a file
  named `*logo*` or `*.ico` other than the theme's.

## 2. D2 implementation

**Why the files are replaced, and not the HTML or the theme.** The logo images
are replaced after `sphinx-build`, under the same file names. The HTML is not
edited at all, so every reference stays valid. Two other approaches were
rejected:
- **Switching the theme** (`-D html_theme=…`). Projects' `conf.py` files set
  theme options and load the theme's extension. Their behaviour with another
  theme could not be tested here, and a failed documentation build would spend
  the GCE run.
- **Overriding `html_static_path`.** It replaces each project's own static path.

**What `genspec.py` does**, for each definition that builds HTML
(`html_dirs()`):
- **Sources.** The five images from `files/_docs-branding/` become `Source80`–`84`.
  `branding/make-branding.py` generates them:
  - `hagistack-doc-logo-full.svg` and `-vert.svg`, the same drawing as the
    Horizon logos;
  - `-full.png` (135 × 35) and `-vert.png` (59 × 54), the mark;
  - `hagistack-doc-favicon.ico`.
- **Replacement.** After `sphinx-build`, each of the 9 theme paths that exists is
  replaced (`test ! -e … || cp -p …`).
- **Guard.** The build then stops if any file in the HTML tree whose name
  contains "logo", or any `.ico`, is not byte-identical to one of Hagistack's
  five images. A theme that renamed or added a logo file therefore cannot slip
  through.
- **Notice.** The change is stated automatically (`DOC_CHANGE`). It is written
  into `HAGISTACK-CHANGES` and `%changelog`, and every binary package of these
  source packages carries the notice and `HAGISTACK-LICENSE`, as in B2.
- **Rule.** A source package that states changes must give `changelog_date`. The
  44 newly changed doc-building definitions and Keystone, Placement and Nova
  raise their release by one (47 definitions, dated Fri Nov 13 2026).

`build-own.sh` stages `files/_docs-branding/hagistack-doc-*` into the shared
SOURCES. The build input id already covers all of `packaging/`.

**Not changed in the documentation**, and stated in `THIRD_PARTY_NOTICES.md`:
- the header link to `https://www.openstack.org/`;
- the header menus and the footer links to OpenStack's and OpenInfra's sites and
  accounts;
- the social-network icons.

## 3. Change notices: what the build changes, by package

Every file that the binary RPMs install under `site-packages/` was compared with
the upstream tarball in its source RPM, for all 69 definitions. So were the files
installed elsewhere, outside documentation, licences, locales and man pages. All
of this was checked on the old set.

| Package | Difference found | Notice |
|---|---|---|
| Neutron | 4 patched files, 12 shebangs (11 by rpm, 1 by Hagistack), generated samples | B2 (already) |
| qrcode | 1 shebang line removed | B2 (already) |
| Horizon | outside `site-packages` (`/usr/share/openstack-dashboard`) | B2 (already) |
| **Keystone** | `/etc/keystone/keystone.conf`, generated and scrubbed (placeholders); `/usr/share/keystone/sample_data.sh`, shebang rewritten by rpm | **added** |
| **Placement** | `placement.conf` and `policy.yaml`, generated and scrubbed (placeholders) | **added** |
| **Nova** | `nova/tests/unit/ssl_cert/new_cert.sh`, shebang rewritten by rpm; generated samples only checked, not edited | **added** |
| openstacksdk | `openstack/tests/ansible/hooks/post_test_hook.sh`, `#!/bin/sh` rewritten to `#!/usr/bin/sh` by rpm | recorded in the notices (Owner decision) |
| os-ken | `os_ken/tests/mininet/run_mnet-test.sh`, the same | recorded in the notices (Owner decision) |
| all others | identical to upstream (plus generated console scripts and Hagistack's own files) | none |

Two of the flagged differences were false positives of the comparison:
- Glance's `glance-image-import.conf` and `glance-swift.conf` are identical to
  upstream's `.sample` files.
- osprofiler's `/usr/bin/osprofiler` is a generated console script, not
  upstream's `devstack/lib/osprofiler`.

**openstacksdk and os-ken** are left to the Owner, as the instruction asks for
build-tool-only changes. Each has a single test helper script rewritten from
`/bin/sh` to `/usr/bin/sh`. Both already build HTML documentation, so they
already carry `HAGISTACK-CHANGES` for the documentation logos. Adding the
shebang line would add one line to each notice.

## 4. Release checks

Each of these refuses the release:
- **Horizon's eight OpenStack-logo files** in any RPM: unchanged since stage 6-5.
- **The documentation theme's five logo images** in any RPM, by content: added.
  Words such as "OpenStack" in text are never matched.
- **A missing Hagistack image**, at any of the 9 theme paths in an HTML
  documentation tree (`/usr/share/doc/…/html/_static`), or in
  `openstack-dashboard`.
- **No HTML documentation tree** in the set.
- **A missing or wrong notice**, in any binary of a source RPM whose spec writes
  `HAGISTACK-CHANGES`: the notice equal to the spec's text, the changelog,
  `HAGISTACK-LICENSE`, and an MIT tag. This covers the 50 source packages
  automatically, because it reads the specs.

The existing checks are unchanged: RPM/SRPM correspondence, the exact candidate
composition, and no mixing of sets. `make-rpm-release.sh` passes the
documentation images, and its git-cleanliness list includes
`packaging/files/_docs-branding`.

## 5. Tests run here

| Suite | Python | Result |
|---|---|---|
| `packaging/test_genspec.py` | 3.13 | **31** OK |
| `packaging/branding/test_branding.py` | 3.13 and 3.9 | **5** OK |
| `tests/test_release_check.py` | 3.13 and 3.9 | **15** OK |
| `bash -n` | bash 3.2 | OK: `make-rpm-release.sh`, `build-own.sh`, `run-all.sh`, `hagistack` |

What the suites check:
- **`test_genspec.py`:**
  - all 47 HTML builds replace the 9 paths and carry the guard, and no other
    definition does;
  - the doc images exist and say Hagistack;
  - exactly 9 definitions declare changes;
  - stated changes need a date.
- **`test_branding.py`:** the doc images are the generator's output, the doc
  SVGs are shapes only, and the PNG sizes are the theme's.
- **`test_release_check.py`:** the doc trees pass; the theme hashes are refused,
  and so are a missing or wrong doc image and a set with no doc tree.

**Spec comparison:** all 69 specs were generated from the base `ba3395c` and from
`3ec77b0`. **50 change**: the 44 doc builds, the 3 doc builds already in B2, and
Keystone, Placement and Nova. **19 are byte-identical**, including Neutron,
Horizon and qrcode.

**Reused:** `acceptance/stage6/test_hs6.py`, 143/143 on Python 3.13 and 3.9 (stage
6-5). The harness was not changed in this stage.

**Not verified** (they need `rpmbuild` and an x86_64 builder):
- rpm parsing of the 50 changed specs;
- the documentation builds with the replacement and the guard;
- `release_check.py` on real RPMs;
- how the documentation pages look.

## 6. GCE preconditions

The plan is unchanged from stage 6-5 section 6 (n1, n2-standard-8, Rocky Linux
10.2 x86_64, US$8 and 6 h, operations
`init,network,n1,ssh,upload,download,teardown,residual`). These points were
re-evaluated:
- **Build time.** The run builds all 69 definitions either way, so D2 adds only
  the file replacement and the guard after each documentation build, which
  takes seconds. The time basis is still the stage 5 build VM's lifetime of
  3 h 42 min, measured on e2-standard-8 with pd-balanced, so it is not well
  known. The candidate is downloaded before the install.
- **Risks that stop the build early.** These fail closed and spend the run:
  - the documentation guard, if the builder's `openstackdocstheme` ships a logo
    file under another name;
  - `test_genspec.py` or `test_branding.py` on the builder.
- **Cost.** About US$3.5, unchanged.
- **Old and new sets.** The old set `6c43da…` and the asset `da5471b0…` stay as
  they are. The new set has its own build directory and identity, and new release
  numbers for 53 source packages: the 6 of stage 6-5 and the 47 of this stage.
- **Owner steps, unchanged:**
  1. Create the key (`hs6_approve.py --setup`) and send the public line.
  2. The line is pinned by a commit.
  3. Sign the run approval for that commit.

  None of these was started here.

## Independent audit

(below)

## Owner decisions

1. The GCE run (section 6), after the key is pinned.
2. openstacksdk and os-ken: whether their one-line rpm shebang change goes into
   their notice. Today it is recorded in `THIRD_PARTY_NOTICES.md` only.
3. Unchanged from stage 6-5: §4(b) sufficiency, `%doc` with `nodocs` (L2), and
   the Hagistack logo under MIT.
