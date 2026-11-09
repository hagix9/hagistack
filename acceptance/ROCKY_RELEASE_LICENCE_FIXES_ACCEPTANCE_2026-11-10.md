# Rocky 10.2 — acceptance of the release licence fixes (2026-11-10)

Scope: the three fixes that remove the U-2 and C-3 licence blockers from the RPM
release, as approved by the Owner on 2026-11-10:

1. `openstack-dashboard` no longer ships the build-time copies of the XStatic
   libraries (`static/horizon/lib`) or the compressed bundles made from them
   (spec-adapt rule `horizon`).
2. The five XStatic RPMs whose PyPI sdists carry no licence file install the
   upstream licence text (`LICENSE` manifest rows, `third-party/licenses/`). The
   PYPI licence field is now one comma-joined field, which corrects Font Awesome's
   `License:` tag and summary.
3. `make-rpm-release.sh` refuses a set that regresses on 1 or 2 and copies
   `THIRD_PARTY_NOTICES.md` into the candidate.

U-1 (RDO packaging files) is unchanged and remains an Owner decision. This is
the implementer's run, not an independent audit.

Code under test: `git archive aa19a5da47fceef475e1e1f6c7e83565a4cd6a20` (no local
modification for the build and the install). Commit `6b21512` changes two test
files only (see "Unit suites").

## Environment

Google Compute Engine, one zone, a VPC created for this run only (IAP SSH, Cloud
NAT egress, no external IP). One VM, `n2-standard-8`, pd-standard 100 GB, stock
`rocky-linux-10` image (Rocky Linux 10.2, x86_64), nested KVM. The VM, firewall
rules, router, NAT, subnet and network were deleted afterwards and their absence
checked; the project's pre-existing resources were unchanged. VM time ≈ 66 min
(19:55–21:01 UTC). Estimated cost ≈ US$0.7 (list prices × time; billing not
obtained).

## Build: PASS

| Check | Result |
|---|---|
| Command | `hagistack rpm-prepare --rpm-source build`, exit 0, ≈ 38 min |
| Build inputs | `0c154e6518889f59…` (new: manifest, template, rules and `third-party/` changed) |
| Passes | pass 1: 66 PASS, 3 FAIL (neutron, nova, horizon, `rpmbuild exit 11`, build order); pass 2: the three PASS |
| Coverage | 69 expected (LICENSE rows not counted as packages), 69 PASS, none missing; `build.ok`: `packages=69 rpms=195 srpms=69` |
| Integrity | `RPM-SHA256SUMS` 195/195; `rpm -K` 0 failures; BUILDHOST `hagistack-builder` 195/195 |
| Set identity | `6bc12ad3cac3f6506125869a7d373763b7cb462da5fbfb2c35fa6546205f8f37` |

`%check` was not run (unchanged: not verified).

## Fix 1 — dashboard: PASS

| Check | Result |
|---|---|
| `openstack-dashboard` payload entries under `static/horizon/lib/` | 0 (rc1: 26 libraries) |
| `static/dashboard/{js,css}/output.*`, `manifest.json` in the payload | 0 |
| SWF files in the payload | 0 |
| RPM size | 4,282,837 bytes (rc1: 13,639,914) |
| Third-party banners in the extracted payload | none; the only matches were Horizon's own files that name the `smart-table` Angular module |
| `python3-django-horizon` | unchanged, still has Horizon's own `jquery.bootstrap.wizard.js` (covered in `THIRD_PARTY_NOTICES.md`) |
| After the all-in-one install | `static/horizon/lib` rebuilt with all 26 libraries from the installed XStatic packages; 2 JS + 4 CSS bundles and the manifest present; the login page is 200 and every bundle it references is 200 |
| After a plain `systemctl restart httpd` (the packaged drop-in rebuild only) | restart 11 s, httpd active, 0 error lines in its journal; tree and bundles rebuilt; referenced bundles 200 |
| `tests-horizon-login.sh` | PASS after the install and again after the restart (admin sign-in, both negative cases fail as they must) |

## Fix 2 — XStatic licence texts: PASS

| RPM | `License:` | Licence file installed |
|---|---|---|
| python3-XStatic-jQuery | MIT | `/usr/share/licenses/python3-XStatic-jQuery/LICENSE-jquery-3.7.1.txt` |
| python3-XStatic-JQuery-Migrate | MIT | `LICENSE-jquery-migrate-3.3.2.txt` |
| python3-XStatic-JQuery-quicksearch | MIT | `LICENSE-jquery-quicksearch-2.0.3.txt` |
| python3-XStatic-JQuery-TableSorter | MIT | `LICENSE-jquery-tablesorter-2.14.5.txt` |
| python3-XStatic-jquery-ui | MIT | `LICENSE-jquery-ui-1.13.0.txt` |
| python3-XStatic-Font-Awesome | `CC-BY-4.0 AND OFL-1.1 AND MIT` (rc1: `OFL-1.1`); summary `Font Awesome packaged for XStatic` | its own `data/LICENSE.txt` (unchanged) |

The installed jQuery and TableSorter files match their manifest SHA-256 pins. The
jQuery SRPM contains the licence file beside the spec and the sdist. XStatic,
XStatic-Angular and qrcode keep the licence files their sdists carry.

## Fix 3 — release candidate and guards: PASS

- `make-rpm-release.sh --tag rocky10.2-rpms-2026.1-rc2`: exit 0. Both new checks
  reported ok. The candidate contains `THIRD_PARTY_NOTICES.md` and
  `third-party/licenses/`. Asset `hagistack-rpms-rocky10.2-rpms-2026.1-rc2-el10-x86_64.tar`,
  106,547,200 bytes, SHA-256 `4f286b94c5c22f214d303839d95b83e707f987a259c87c830ac4dc78a9e4e489`.
  Nothing was published.
- Negative cases on copies of the set:
  - rc1's dashboard RPM swapped in: exit 1, "still ships third-party static copies", no candidate written.
  - rc1's `python3-XStatic-jQuery` swapped in: exit 1, "does not install its licence file", no candidate written.

## All-in-one from the new set: PASS

- `hagistack all-in-one --rpm-source build`: re-used the verified set (same build
  inputs, not rebuilt). Every phase completed.
- Two cirros guests ACTIVE (30 s / 23 s).
- SSH into the first guest with the key from the metadata service (after about 5 s).
- Metadata hostname `hs-rf-0.novalocal`.
- Guest-to-guest ping: 3 of 5 answered. Earlier runs answered 4 of 5, losing only
  the first ARP. Connectivity is shown; the extra loss is recorded, not explained.
- Guests deleted afterwards.

## Unit suites

Run on the VM (Rocky 10.2, `rpm-build`, `createrepo_c`):

- **First run, on `aa19a5d`:** two failures, both in tests added or changed with
  the fixes, not in product code.
  - The cross-check row count in `test-build-in-container.sh` did not exclude
    `LICENSE` rows.
  - A new `test_adapt.py` case assumed `SPEC_ADAPT_INPUTS` existed.
- **After fixing the tests (commit `6b21512`):**
  - `test-rpm-source.sh` 93/93
  - `test-build-in-container.sh` 37/37
  - `test_adapt.py` 70/70 (61 before, 9 new)
  - ALL SUITES PASSED.
- **Build identity:** `spec-adapt/test_adapt.py` is part of the build-input identity.
  The aa19a5d versions of the two test files were restored on the VM before the
  install, so the install re-used the set above. A build from `6b21512` gets a
  different input identity. The RPM inputs are the same.

## Verdict

Fixes 1–3 pass on x86_64. The U-2 and C-3 items that blocked the release are no
longer present in the built set: the dashboard redistributes no XStatic library,
and every XStatic RPM built here carries its licence text. U-1 is unchanged.
RPM publication still requires the Owner's decisions on U-1 (SRPMs and the RDO
packaging files in the binaries), on whether SRPMs are attached, and on
`openstack-neutron-openvswitch` (`python3333` unit), followed by an independent
audit of this change.
