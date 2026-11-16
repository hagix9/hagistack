// Checks every internal link in the built site (dist/): the target page exists
// and, when the link has a #fragment, the target page has an element with that id.
// Also checks that every Japanese page has an English counterpart and vice versa.
// Usage: npm run build && npm run links
import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const dist = fileURLToPath(new URL('../dist/', import.meta.url));
const files = [];
(function walk(d) {
  for (const n of readdirSync(d)) {
    const p = join(d, n);
    if (statSync(p).isDirectory()) walk(p);
    else if (n.endsWith('.html')) files.push(p);
  }
})(dist);

const ids = new Map();
const idsOf = (file) => {
  if (!ids.has(file)) {
    const html = readFileSync(file, 'utf8');
    ids.set(file, new Set([...html.matchAll(/\sid="([^"]+)"/g)].map((m) => m[1])));
  }
  return ids.get(file);
};
const resolve = (path) => {
  const clean = decodeURIComponent(path.split('?')[0]);
  const cands = [join(dist, clean), join(dist, clean, 'index.html')];
  return cands.find((c) => existsSync(c) && statSync(c).isFile());
};

let bad = 0, checked = 0;
for (const file of files) {
  const html = readFileSync(file, 'utf8');
  if (/http-equiv="refresh"/.test(html)) continue; // redirect pages
  for (const m of html.matchAll(/<a\s[^>]*href="([^"]+)"/g)) {
    const href = m[1].replace(/&amp;/g, '&');
    if (/^(https?:|mailto:|#$)/.test(href)) continue;
    let [path, frag] = href.split('#');
    if (path === '') path = '/' + relative(dist, file).replace(/index\.html$/, '');
    if (!path.startsWith('/')) continue;
    checked++;
    const target = resolve(path);
    if (!target) { bad++; console.log(`MISSING  ${relative(dist, file)} -> ${href}`); continue; }
    if (frag && !idsOf(target).has(decodeURIComponent(frag))) {
      bad++; console.log(`NO ANCHOR ${relative(dist, file)} -> ${href}`);
    }
  }
}
const pages = (lang) => files.filter((f) => relative(dist, f).startsWith(lang + '/')).map((f) => relative(join(dist, lang), f)).sort();
const ja = pages('ja'), en = pages('en');
for (const p of ja) if (!en.includes(p)) { bad++; console.log(`NO EN PAGE for ja/${p}`); }
for (const p of en) if (!ja.includes(p)) { bad++; console.log(`NO JA PAGE for en/${p}`); }
console.log(`${checked} internal links checked, ${ja.length} ja / ${en.length} en pages, ${bad} problem(s)`);
process.exit(bad ? 1 : 0);
