# Third-party notices for the Hagistack Rocky Linux 10.2 RPM release

This file is copied into every release candidate by `make-rpm-release.sh`.

## What the licence of each file is

- Hagistack's own work is under the MIT License in `LICENSE`: the `hagistack`
  script, the build scripts, and the RPM packaging in `packaging/` (the package
  definitions `packaging/defs/*.toml`, the spec generator `packaging/genspec.py`
  and the files in `packaging/files/`, such as systemd units, sudoers and
  logrotate files). Every source RPM carries this licence as `HAGISTACK-LICENSE`.
- **The software inside the RPMs is not.** Each piece of software is under its
  own licence, as stated in the licence texts it ships; the RPMs install those
  texts under `/usr/share/licenses/` (some subpackages rely on the copy in the
  package they depend on, and a few carry the licence inside the packaged files,
  as noted below). Almost all of it is OpenStack projects
  under the Apache License 2.0. An RPM's `License:` tag (also listed in
  `PACKAGE_MANIFEST.tsv`) is a summary of those licences; it does not replace
  the licence texts.
- The RPMs are generated from Hagistack's own package definitions. They are
  **not** generated from RDO distgit packaging: no RDO spec file or other RDO
  packaging file is used as an input. A byte comparison of the files in the
  264 packages (binary and source; 24,877 files, compiled `.pyc` bytecode
  excluded) with RDO's packaging files found
  two identical files: the two upstream Neutron commits in `third-party/neutron/`,
  which RDO also carries. Hagistack's own unit, logrotate, sudoers and
  configuration files share short lines with RDO's (keywords, commands and
  paths); none is a copy. (Release candidates up to rc4 were built from RDO
  distgit by the older path, `build-rpms.sh`.) So that rc4 installations
  upgrade cleanly, the package names, installed paths, modes, owners and the
  configuration directory layout follow rc4's binary packages. They were taken
  from rc4's package metadata, not from the contents of RDO's files.
- Sources: OpenStack release tarballs are checked against the SHA-256 pinned in
  the definition and against their upstream GPG signature, with the OpenStack
  release key pinned in `gazpacho.manifest`. The ten definitions built from PyPI
  sdists are checked against their pinned SHA-256 only; they have no upstream
  signature to check.
- RDO's binary repositories are used, together with Rocky Linux and EPEL, to
  install build dependencies on the builder and, on the nodes, to install the
  dependencies the RPMs need. Packages from those repositories are not part of
  this release.
- `third-party/` holds the files Hagistack redistributes from other projects,
  each with its own licence: two upstream Neutron changes (`third-party/neutron/`,
  Apache-2.0) and licence texts for the XStatic RPMs (`third-party/licenses/`).

## Source code

Every binary RPM is built from a source RPM published with it, in
`hagistack-srpms-<TAG>.tar`. Each source RPM holds the spec, the upstream source
archive (with its signature and the signing key where upstream signs it), the
pinned patches and licence texts, Hagistack's own files, and `HAGISTACK-LICENSE`.
`make-rpm-release.sh` refuses a candidate in which a binary has no source RPM, a
source RPM has no binary, a binary's `SOURCEPKGID` is not the header digest of
the source RPM it names, or a source RPM's `HAGISTACK-LICENSE` is missing or
differs from `LICENSE`.

## Changes made to the upstream sources

Hagistack changed the files listed here from the upstream release they come from.
The notice of these changes is carried in four places:

- **The spec file of the source RPM.** Each change is there, in its `Patch`
  lines and its `%prep`, `%build` and `%install` sections.
- **Inside the binary RPMs.** Two groups of source packages carry a list of
  their changes.
  - **Eleven with changes declared in their definitions** (`changes` in
    `packaging/defs/`): Neutron, Horizon, qrcode, barbicanclient,
    keystoneauth1, keystonemiddleware, Keystone, Placement, Nova, openstacksdk
    and os-ken.
  - **The 47 that build HTML documentation.** `genspec.py` adds one change to
    each of them: the documentation theme's logos are replaced (see below).

  From these lists:
  - every binary package built from them installs the list as
    `/usr/share/hagistack/changes/<package>/HAGISTACK-CHANGES`;
  - the `%changelog` of those binary packages repeats it.

  The notice is a plain file, not documentation. rpm marks every file under
  `/usr/share/doc` as documentation, and an install with
  `--setopt=tsflags=nodocs` (or `rpm --excludedocs`) leaves such files out; the
  notice is therefore not put there. `make-rpm-release.sh` refuses a release in
  which a binary package lacks the notice, carries it twice, carries it flagged
  as documentation, or carries a notice other than the one its spec writes.
- **Inside the changed files**, where their format allows. Each changed file that
  is installed and takes `#` comments (Python and shell sources, the generated
  configuration samples) gets one comment line saying that it is changed and
  pointing to `HAGISTACK-CHANGES`. The line goes after a `#!` line and a Python
  coding line, so neither moves. The definitions list these files
  (`mark_files`), and the release check refuses a set in which one of them lacks
  the line. The other changed files carry no line inside them:
  - Hagistack's images that replace upstream's, and the documentation theme's
    replaced images, are image files. They are Hagistack's own files, and the
    SVGs and PNGs say so in a comment or a text chunk.
  - Built documentation is generated, and the edited `doc/source/conf.py` and
    `requirements.txt` files are not installed.
  - Horizon's removed leftover file is not shipped at all.
- **This file and `third-party/`.**

Whether the notices above meet §4(b) of the Apache License 2.0 is a legal
judgement that this file does not make.

The list has four kinds of change:
- **upstream changes Hagistack backports** (the Neutron patches);
- **Hagistack's own edits** (requirements, shebangs, Sphinx settings);
- **changes made by the RPM build tools** (shebang rewriting);
- **generated files.**

Hagistack's own packaging files (units, sudoers, logrotate and the like) are not
changes to upstream files; they are new files under the MIT License.

- **Neutron 28.0.2** (`openstack-neutron`, `openstack-neutron-common`,
  `python3-neutron` and the other packages from the same source RPM):
  - Two upstream Neutron commits are applied as `Patch0001` and `Patch0002`
    (`third-party/neutron/`). They change
    `neutron/common/ovn/constants.py`,
    `neutron/plugins/ml2/drivers/ovn/mech_driver/mech_driver.py`,
    `neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/impl_idl_ovn.py` and
    `neutron/plugins/ml2/drivers/ovn/mech_driver/ovsdb/maintenance.py`.
    `third-party/neutron/NOTICE.md` says how the patches differ from the
    commits as published upstream.
  - `requirements.txt`: the version is dropped from the `psutil` requirement.
  - `neutron/tests/fullstack/servers/metadata.py`: the shebang
    `#!/usr/bin/env python` becomes `#!/usr/bin/python3`.
- **Horizon** (`python-django-horizon` source RPM):
  - `requirements.txt`: the `tzdata` requirement is removed.
  - The installed `manage.py` gets the shebang `#!/usr/bin/python3`.
  - **The OpenStack logo is replaced with Hagistack's own images.** These are
    `static/dashboard/img/logo.svg`, `logo-splash.svg`, `favicon.ico`,
    `apple-touch-icon.png` and `safari-pinned-tab.svg`, and the material theme's
    inline logo (`openstack-one-color.svg` and its unused `-alt` variant). Each
    is replaced in the source tree before the static files are collected. An
    unused leftover of upstream's, `openstack-one-color-alt.svg.old` (the
    OpenStack wordmark), is removed.
  - `/etc/openstack-dashboard/local_settings` is upstream's
    `local_settings.py.example` with Hagistack's changes, each marked with a
    "Hagistack:" comment. Among them, the page title is set to
    `SITE_BRANDING = 'Hagistack Dashboard'` (upstream: `OpenStack Dashboard`).
- **qrcode** (`python3-qrcode`): the `#!/usr/bin/env python` shebang line is
  removed from the Python modules that have one.
- **python-barbicanclient, python-keystoneauth1, python-keystonemiddleware**:
  `doc/source/conf.py`, one Sphinx extension is removed from the list of
  extensions so that the documentation builds.
- **Configuration samples** that Keystone, Neutron and Placement generate at
  build time from their upstream sources: option values that would name the
  build machine are replaced with placeholders. Nova's generated samples carry
  upstream's own placeholders and are only checked.
- **Keystone:** `tools/sample_data.sh` (installed as
  `/usr/share/keystone/sample_data.sh`) gets its shebang rewritten by rpm
  (`#!/usr/bin/env bash` becomes `#!/usr/bin/bash`).
- **Nova:** `nova/tests/unit/ssl_cert/new_cert.sh` (in `python3-nova-tests`) gets
  the same rewriting.
- **HTML documentation (47 source packages).** It is built with OpenStack's
  documentation theme, `openstackdocstheme`. The theme's OpenStack logo images
  and its favicon are replaced in the built HTML with Hagistack's own; see
  "Trademarks". The documentation text and the theme's other files are
  unchanged.
- **openstacksdk:** `openstack/tests/ansible/hooks/post_test_hook.sh` (in
  `python3-openstacksdk-tests`) gets its shebang rewritten by rpm (`#!/bin/sh`
  becomes `#!/usr/bin/sh`).
- **os-ken:** `os_ken/tests/mininet/run_mnet-test.sh` (in `python3-os-ken`), the
  same rewriting.
- **Shebangs, every package.** rpm's build policy (`brp-mangle-shebangs`, part of
  Rocky Linux's `redhat-rpm-config`) rewrites `#!/usr/bin/env python3` and similar
  interpreter lines of executable files to `#!/usr/bin/python3`; in Neutron this
  touches executable modules such as `neutron/cmd/destroy_patch_ports.py`.
- **Generated files.** The builds compile translation catalogues (`.po` to `.mo`)
  and generate files from the upstream sources (configuration samples, man pages,
  Horizon's collected static files). These are new files made from upstream
  files, not edits of them.

## Licence texts per package

Some subpackages install no licence text of their own: meta and service
subpackages, `-tests` packages and extras that depend on the package carrying the
text, and the documentation packages `openstack-glance-doc`,
`python-cinderclient-doc` and `python-keystonemiddleware-doc`, whose texts are in
the other packages built from the same source RPM. Font Awesome and term.js carry
their licence inside the packaged files. Every text is in the release asset. If
you redistribute single packages, include the licence texts of the source RPM
they come from.

## Repositories the RPMs need, not part of this release

The RPMs install only together with packages from these repositories, which the
Hagistack installer configures. Their packages are under their own licences and
are distributed by their own projects:

- Rocky Linux 10 BaseOS, AppStream and CRB;
- EPEL 10 (`epel-release`);
- the CentOS Stream 10 NFV SIG Open vSwitch repository,
  `https://mirror.stream.centos.org/SIGs/10-stream/nfv/$basearch/openvswitch-2/`;
- RDO's EL10 dependency repositories (third-party libraries only, no OpenStack
  component repository):
  `https://trunk.rdoproject.org/centos10-master/deps/latest/`,
  `https://trunk.rdoproject.org/centos10-master/build-deps/latest/` and
  `https://trunk.rdoproject.org/centos10-master/rabbitmq/`.

## JavaScript, CSS and fonts used by the dashboard

`openstack-dashboard` does not ship copies of the JavaScript and CSS libraries
Horizon uses. Its httpd drop-in rebuilds the static tree before httpd starts,
from the XStatic packages installed on the node. Each library therefore reaches a
node only in its own XStatic package, under that package's licence:

- built and released here: `python3-XStatic`, `-Angular`, `-Font-Awesome`,
  `-jQuery`, `-JQuery-Migrate`, `-JQuery-quicksearch`, `-JQuery-TableSorter`,
  `-jquery-ui`, `-term-js`, and `python3-qrcode`;
- every other XStatic package comes from the RDO dependency repository on the
  node. It is not part of this release.

Notes on the XStatic packages built here:

- **jQuery TableSorter 2.14.5** is dual licensed by its author under MIT and GPL.
  Hagistack distributes it under the MIT License
  (`third-party/licenses/LICENSE-jquery-tablesorter-2.14.5.txt`).
- **Font Awesome 6.2.1** (`python3-XStatic-Font-Awesome`): icons CC BY 4.0, fonts
  SIL OFL 1.1, code MIT, as its own `LICENSE.txt` states. The brand icons
  represent trademarks of their owners; the licences do not grant trademark
  rights.
- **term.js 0.0.7** (`python3-XStatic-term-js`) is MIT licensed by Christopher
  Jeffrey (full text in `term.js`). Its header states that parts derive from
  Fabrice Bellard's jslinux terminal, used "with the author's permission".

## Trademarks

The OpenStack word mark and the OpenStack logos are trademarks of the OpenStack
Foundation d/b/a Open Infrastructure Foundation ("OpenInfra"). Rocky Linux and
Font Awesome are trademarks of their owners. The names are used here only to say
what the software is and what it runs on. This release is not an OpenStack
release, is not "OpenStack Powered" or "OpenStack Compatible", and is not
affiliated with, endorsed by or sponsored by OpenInfra, the Rocky Enterprise
Software Foundation or Fonticons, Inc. The licences listed above cover
copyright; they grant no trademark rights.

**The dashboard shows Hagistack's own logo**, not the OpenStack logo. Horizon's
images that show the OpenStack logo are replaced (see "Changes made to the
upstream sources"). `make-rpm-release.sh` refuses a release in which any RPM
still carries one of them. The images are Hagistack's own work, generated from
geometry by `packaging/branding/make-branding.py`, and are under the MIT
License. That licence covers copyright; it is not a trademark licence for the
Hagistack name or logo.

**The HTML documentation shows Hagistack's logo too.** The 46 `*-doc` packages
and `python3-os-brick`, which carries its HTML documentation, are built with
OpenStack's documentation theme, `openstackdocstheme`.
- After the HTML is built, the theme's OpenStack logo images
  (`_static/images/logo-full`, `logo-vert`, `openstack-logo-full` and
  `openstack-logo-vert`, as `.svg` and `.png`) and its favicon
  (`_static/favicon.ico`) are replaced with Hagistack's.
- The build stops if one of those files is missing, or if any file under
  `_static/` whose name says "logo", or any `.ico` there, is not one of
  Hagistack's.
- `make-rpm-release.sh` refuses a release in which any RPM carries one of the
  theme's logo images, or a documentation tree lacks Hagistack's.

The rest of the theme stays as upstream ships it:
- **The page header still links to `https://www.openstack.org/`**, and the
  header menus and the footer link to the sites and social-network accounts of
  OpenStack and of the OpenInfra Foundation. The footer has the networks' icons
  (Facebook, LinkedIn, Twitter, YouTube).
  These are the upstream project's documentation pages and say what they are.
- **`python3-XStatic-Font-Awesome`** contains the Font Awesome brand icons
  (`brands.*`, `fa-brands-400.*`), which show the logos of other companies.

Hagistack does not change these files.

## Code inside the Horizon source

`python3-django-horizon` contains `horizon/static/horizon/lib/jquery/jquery.bootstrap.wizard.js`,
which is part of the Horizon source release. Its author dual licenses it under
MIT and GPL; it is distributed here under the MIT License:

```
The MIT License (MIT)

Copyright (c) 2013 - Vincent Gabriel & Jason Gill

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```
