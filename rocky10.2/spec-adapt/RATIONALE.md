# Why Hagistack adapts RDO specs with rules instead of patches

## What this replaced

The Rocky Linux 10 build packages OpenStack 2026.1 from RDO's `rpm-master` specs,
pointed at the released 2026.1 tarballs. Those specs do not always fit the tarballs,
so Hagistack changes them. It used to do that with eleven unified-diff patches in
`spec-patches/`.

A unified diff cannot be written without copying the text it edits: every hunk carries
the unchanged lines around the change and the lines it removes. Eleven patches meant
that Hagistack was redistributing well over a hundred lines of RDO's packaging text, and a review
of the pinned distgit trees found no licence grant that covers that text. Hagistack
cannot grant, or promise, rights in text it does not own.

## What it does now

* **The third-party text stays outside this repository.** `build-rpms.sh` fetches each
  RDO distgit at the exact commit named in `gazpacho.manifest` and works on a copy.
  Nothing from those repositories is stored here.
* **Hagistack applies its own edits to that pinned external source.** `rules.py`
  describes each edit as a small operation: where to look (a section, a macro, the tail
  of a path) and what Hagistack wants there. The only multi-line text in it is text
  Hagistack wrote. `adapt.py` is a line editor that understands spec sections; it is
  deliberately not a spec parser.
* **No mechanical conversion.** The rules were written as rules. They are not a diff
  turned into `sed` commands, a regular expression per hunk, or the old patches stored in
  another encoding; any of those would still be the same text in a different shape.
* **What a rule may contain** is what any tool that edits a file has to name: macro
  names, package names, paths, section names and similar functional identifiers. Nothing
  longer is quoted, and the comments in `rules.py` describe a change in their own words.

## Fail-closed

An edit that does not fit must stop the build, not skip itself, because a silently
skipped edit builds something other than what was reviewed. `adapt.py` exits non-zero and
writes nothing when:

* the manifest has a row it does not understand, is malformed, or names a package the
  rules do not know;
* the rules were written for a different version of the package than the manifest builds;
* an input file's SHA-256 is not the reviewed one;
* the input already is the adapted result (so a second run cannot slip through);
* a selector finds more or fewer lines than the rule expects, or finds an old value other
  than the one it expects; or
* the result's SHA-256 is not the reviewed one.

`build-rpms.sh` also validates every SPEC and PATCH row up front, so asking for a subset of
packages cannot hide a broken row, and it stops if adaptation of a package fails.

## Provenance

Each RDO input is pinned by what the manifest already pins for the package (the distgit
repository and the full 40-character commit, checked after checkout) plus, in a `SPEC`
row, the file name and two SHA-256 values: the file as RDO published it, and the file
after adaptation. The second value is what makes the result reviewable: it is the hash of
a text a person looked at, so a changed rule or a changed input cannot change the build
without changing a pin.

## Changing a rule or moving to a newer RDO commit

1. Update the package row (commit, version) in the manifest.
2. Run the tests. They stop at the first rule that no longer fits.
3. Edit `rules.py`, review the adapted file, and put its new SHA-256 values in the `SPEC`
   row. The input hash is of the file at the new commit; the output hash is of the result.
4. Build on Rocky Linux 10 and compare with the previous packages.

## Neutron is a separate case

The Neutron fixes for the OVN maintenance-worker lock race are upstream OpenStack changes
under Apache-2.0 that Hagistack does redistribute, so they are not rules: they are two
patch files with the licence text and a notice, in `../third-party/neutron/`, pinned by
`PATCH` rows. Only the two `Patch000N:` lines that name them in the spec are a rule.

## What this does not settle

* It removes a source of third-party text from the repository. It does not itself
  license anything: Hagistack's own files are under the MIT License in the repository
  root, and `../third-party/` keeps its own licence.
* A matching output hash shows that the rules produce the text that was reviewed, not that
  the text builds. The Rocky Linux 10 build is what shows that.
