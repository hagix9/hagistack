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
  packaging file is used as an input. A comparison of the built packages with
  RDO's packaging files found only two identical files: the two upstream Neutron
  commits in `third-party/neutron/`, which RDO also carries. (Release candidates up to rc4 were built from RDO
  distgit by the older path, `build-rpms.sh`.)
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
