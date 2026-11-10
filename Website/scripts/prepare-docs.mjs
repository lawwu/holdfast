import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { sources, root } from './content.mjs';
import { base } from '../site.mjs';

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
