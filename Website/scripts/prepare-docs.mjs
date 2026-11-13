import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { sources, root } from './content.mjs';
import { base } from '../site.mjs';
import { createHash } from 'node:crypto';

// Reviewed tour assets live on the site, not in each app release's download list.
const demoHashes = JSON.parse(await readFile(join(root, 'Demo/release-assets.json'), 'utf8'));
for (const [name, expected] of Object.entries(demoHashes)) {
  if (!['holdfast-tour.mp4', 'holdfast-tour.vtt', 'holdfast-sample-notes.zip'].includes(name)) {
    throw new Error(`Unexpected tour asset: ${name}`);
  }
  const actual = createHash('sha256').update(await readFile(join(root, 'Website/public/demo', name))).digest('hex');
  if (actual !== expected) throw new Error(`Tour asset checksum mismatch: ${name}`);
}
if (Object.keys(demoHashes).length !== 3) throw new Error('The tour requires video, captions, and sample notes');

const destination = join(root, 'Website/src/content/docs');
await rm(destination, { recursive: true, force: true });
await mkdir(destination, { recursive: true });
for (const page of sources) {
  let content = await readFile(join(root, page.source), 'utf8');
  if (!page.authored) {
    content = content.replace(/^# [^\n]+\n+/, '');
    content = `---\ntitle: ${JSON.stringify(page.title)}\nslug: ${JSON.stringify(page.route)}\ndescription: ${JSON.stringify(page.description)}\neditUrl: false\n---\n\n` + content;
  }
  const extension = page.source.endsWith('.mdx') ? '.mdx' : '.md';
  const target = join(destination, (page.route || 'index') + extension);
  await mkdir(dirname(target), { recursive: true });
  await writeFile(target, content);
}
// Only this explicit HTML guide is copied; never publish the repository wholesale.
let architecture = await readFile(join(root, 'docs/local-mlx-architecture.html'), 'utf8');
architecture = architecture
  .replaceAll('../Packages/pi-swift-mlx/README.md', `${base}/packages/pi-swift-mlx/`)
  .replaceAll('../Runtime/pi/README.md', `${base}/development/pi/`)
  .replace('<body>', `<body><div style="padding:12px 28px;border-bottom:1px solid var(--line)"><a href="${base}/architecture/">← Holdfast documentation</a></div>`);
await mkdir(join(root, 'Website/public/explore'), { recursive: true });
await writeFile(join(root, 'Website/public/explore/index.html'), architecture);
await writeFile(join(root, 'Website/public/favicon.svg'), await readFile(join(root, 'Website/src/assets/mark.svg')));
console.log(`Prepared ${sources.length} documentation pages and the architecture explorer.`);
