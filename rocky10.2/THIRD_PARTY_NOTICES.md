# Third-party notices for the Hagistack Rocky Linux 10.2 RPM release

This file is copied into every release candidate by `make-rpm-release.sh`.

## What the licence of each file is

- Hagistack's own work (the `hagistack` script, the build scripts, the
  spec-adaptation rules) is under the MIT License in `LICENSE`.
- **The RPMs are not.** Each RPM carries the licence of the software inside it:
  its `License:` tag (also listed in `PACKAGE_MANIFEST.tsv`) and the licence
  files it installs under `/usr/share/licenses/`. Almost all of them are
  OpenStack projects under the Apache License 2.0.
- The RPMs are built from the RDO distgit packaging (`https://github.com/rdo-packages`)
  at the exact commits pinned in `gazpacho.manifest`, with Hagistack's edits
  applied by rule. Those distgit repositories do not carry a licence statement
  of their own; the `License:` tag of an RPM describes the packaged software,
  not the packaging files.
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
