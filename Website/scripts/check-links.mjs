import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { base, origin } from '../site.mjs';

const dist = fileURLToPath(new URL('../dist/', import.meta.url));
function files(directory) {
  return readdirSync(directory).flatMap(name => {
    const path = join(directory, name);
    return statSync(path).isDirectory() ? files(path) : [path];
  });
}
const paths = files(dist);
const pages = paths.filter(path => path.endsWith('.html'));
assert(pages.length >= 13, 'Expected the complete documentation and architecture explorer');
assert(existsSync(join(dist, '.nojekyll')));
assert(existsSync(join(dist, 'pagefind/pagefind.js')), 'Search index is missing');
assert(!paths.some(path => /\.(?:swift|safetensors|sqlite)$/.test(path)), 'Unexpected app or model data in the site');
const decode = text => text.replaceAll('&amp;', '&').replaceAll('&#39;', "'").replaceAll('&quot;', '"');
let checked = 0;
for (const page of pages) {
  const html = readFileSync(page, 'utf8');
  const route = relative(dist, page).replace(/index\.html$/, '');
  const address = new URL(`${base}/${route}`, origin);
  // Astro emits a virtual canonical URL for the special 404 page.
  const navigation = page.endsWith('/404.html') ? html.replace(/<link\b[^>]*rel="canonical"[^>]*>/g, '') : html;
  for (const [, raw] of navigation.matchAll(/(?:href|src)=["']([^"']+)["']/g)) {
    const url = new URL(decode(raw), address);
    if (url.origin !== origin) continue;
    assert(url.pathname.startsWith(base + '/'), `Escaped the Pages subpath: ${page}: ${raw}`);
    let target = join(dist, decodeURIComponent(url.pathname.slice(base.length + 1)));
    if (url.pathname.endsWith('/')) target = join(target, 'index.html');
    assert(existsSync(target), `Broken local link: ${page}: ${raw}`);
    if (url.hash && target.endsWith('.html')) {
      const id = decodeURIComponent(url.hash.slice(1));
      const ids = [...readFileSync(target, 'utf8').matchAll(/id=["']([^"']+)["']/g)].map(match => decode(match[1]));
      assert(ids.includes(id), `Missing anchor: ${page}: ${raw}`);
    }
    checked++;
  }
}
console.log(`PASS: ${pages.length} pages, ${checked} local links/assets, anchors, Pages base path, and search index.`);
