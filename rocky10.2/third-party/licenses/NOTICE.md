# Third-party licence texts for the XStatic RPMs Hagistack builds

This directory holds licence texts that Hagistack did **not** write and **does**
redistribute. They are not covered by Hagistack's MIT License (the repository-root
`LICENSE`); each file is the licence of the component it names.

Five of the ten XStatic and other PyPI packages come from sdists that carry no
licence file at all, so built as they are their RPMs would carry none either. The
texts below are added to those RPMs as `%license` documents. Each is named with
its SHA-256 by `extra_licenses` in the package's definition under
`../../packaging/defs/`, which `../../packaging/test_genspec.py` holds equal to the
`LICENSE` rows of `../../gazpacho.manifest`; `../../packaging/build-own.sh` stops
the build before anything is built if a file is missing, is a symlink or differs.
(The older RDO-distgit path, `HAGISTACK_PACKAGING=rdo`, checks the same rows with
`spec-adapt/adapt.py --check` and `build-rpms.sh`.)

| File | RPM | Component and version bundled | Source of the text | SHA-256 |
|---|---|---|---|---|
| `LICENSE-jquery-3.7.1.txt` | python3-XStatic-jQuery | jQuery 3.7.1 (MIT) | `https://raw.githubusercontent.com/jquery/jquery/3.7.1/LICENSE.txt`, unchanged | `d4db9ebe6f29f5168eac45ad713f055623ac5d0dcd5ba92da23d650ae012020d` |
| `LICENSE-jquery-migrate-3.3.2.txt` | python3-XStatic-JQuery-Migrate | jQuery Migrate 3.3.2 (MIT) | `https://raw.githubusercontent.com/jquery/jquery-migrate/3.3.2/LICENSE.txt`, unchanged | `5cb3a35c5966f3715ccd4a8bcf1d70c921c76efd1af83a9fee66923ada36e29d` |
| `LICENSE-jquery-quicksearch-2.0.3.txt` | python3-XStatic-JQuery-quicksearch | jquery.quicksearch 2.0.3 (MIT) | `https://raw.githubusercontent.com/DeuxHuitHuit/quicksearch/2.0.3/LICENSE`, unchanged | `a4b60f2086c2992c7d46c96c19cc74c63149f2f05bcde9331b8a2c7c96a8dfa7` |
| `LICENSE-jquery-ui-1.13.0.txt` | python3-XStatic-jquery-ui | jQuery UI 1.13.0 (MIT; the CC0 part covers demos, which are not shipped) | `https://raw.githubusercontent.com/jquery/jquery-ui/1.13.0/LICENSE.txt`, unchanged | `de33fb695880d0b07615d4b86f78cd43796906959ade5fdfef70968827a0db78` |
| `LICENSE-jquery-tablesorter-2.14.5.txt` | python3-XStatic-JQuery-TableSorter | jQuery TableSorter 2.14.5 (MIT or GPL; Hagistack uses MIT) | Written by Hagistack: upstream ships no licence file at tag `v2.14.5`. The file states the upstream dual-licence declaration (header of `js/jquery.tablesorter.js` and README "Licensing" at that tag), the copyright line upstream gives (`Copyright (c) 2007 Christian Bach`), and the standard MIT terms upstream links to | `38b85a91f2c8f2e556d028569a523e6b48ab35733f831e585b9f0ddb7cd0f37e` |

The upstream files were fetched on 2026-11-10 at the tags of the versions the
XStatic sdists bundle (each bundled file was compared with the upstream tag in
the release licence review).
