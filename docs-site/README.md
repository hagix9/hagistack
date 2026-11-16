# HAGISTACK documentation site

Japanese and English user guide for HAGISTACK on Rocky Linux 10.2 / OpenStack 2026.1,
built with [Astro](https://astro.build/) and [Starlight](https://starlight.astro.build/).
Planned address: `https://hagistack.fulltrust.co.jp/` (`/ja/`, `/en/`). It is not published yet.

## Build and preview locally

Node.js 22.12 or later.

```sh
cd docs-site
npm ci
npm run build          # static site in dist/, with the Pagefind search index
npm run preview        # http://localhost:4321/
```

`npm run dev` serves the pages with live reload; the search box works only in
`build` + `preview`.

## Checks

```sh
npm run check          # Astro/TypeScript diagnostics
npm run links          # after build: every internal link and #anchor exists; ja and en have the same pages
OSC=/path/to/openstack HAGISTACK=../rocky10.2/hagistack npm run commands
```

`npm run commands` checks every `openstack` command and option in the pages
against the `--help` of the given `openstack` binary, and every `./hagistack`
subcommand and option against the installer's parser. Use
python-openstackclient 9.0.1, the version the nodes get. It contacts no cloud.

## Content rules

- Pages live in `src/content/docs/ja/` and `src/content/docs/en/` with the same
  file names; the sidebar is in `astro.config.mjs`.
- Describe the current release (`rocky10.2-rpms-2026.1`) unless a page is in
  "In development" (`development/`). Do not present unverified features as
  released ones.
- Example output is an illustration and is marked as such; it is not a log.
- Example addresses use RFC 5737 documentation ranges (`192.0.2.0/24`,
  `198.51.100.0/24`), and the pages say they must be replaced.
- No credentials, private keys, tokens or real host names in pages or images.

## Publishing (Owner decisions; not done)

1. Merge the branch that adds `docs-site/` and `.github/workflows/docs.yml`.
2. In the repository settings, set Pages → Source to **GitHub Actions** and the
   custom domain to `hagistack.fulltrust.co.jp`; enable HTTPS.
3. Add the DNS record for `hagistack.fulltrust.co.jp` (a `CNAME` to
   `hagix9.github.io`).
4. Run the workflow (push to `master` under `docs-site/`, or run it by hand).
