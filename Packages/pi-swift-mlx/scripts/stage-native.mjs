// npm releases carry a source snapshot; maintained Swift code lives in sibling packages.
import { createHash } from 'node:crypto';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const adapter = dirname(dirname(fileURLToPath(import.meta.url)));
const destination = join(adapter, 'native');
const packages = {
  LocalMLX: ['Package.swift', 'Package.resolved', 'Sources', 'README.md', 'scripts/build-host.sh'],
  ModelProviders: ['Package.swift', 'Sources', 'README.md'],
};
const digest = path => createHash('sha256').update(readFileSync(path)).digest('hex');
const available = Object.keys(packages).map(name => existsSync(join(adapter, '..', name, 'Package.swift')));
if (available.some(Boolean) && !available.every(Boolean)) {
  throw new Error('Both sibling Swift packages are required to prepare a new source snapshot.');
}

if (available.every(Boolean)) {
  const stage = mkdtempSync(join(adapter, '.native-stage-'));
  try {
    for (const [name, paths] of Object.entries(packages)) {
      for (const path of paths) {
        const target = join(stage, name, path);
        mkdirSync(dirname(target), { recursive: true });
        cpSync(join(adapter, '..', name, path), target, { recursive: true });
      }
    }
    const files = {};
    function inventory(directory) {
      for (const item of readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
        const path = join(directory, item.name);
        if (item.isDirectory()) inventory(path);
        else if (item.isFile()) files[relative(stage, path)] = digest(path);
        else throw new Error(`Unsupported source entry: ${relative(stage, path)}`);
      }
    }
    inventory(stage);
    const { version } = JSON.parse(readFileSync(join(adapter, 'package.json'), 'utf8'));
    writeFileSync(join(stage, 'manifest.json'), JSON.stringify({ formatVersion: 1, adapterVersion: version, protocolVersion: 1, files }, null, 2) + '\n');
    rmSync(destination, { recursive: true, force: true });
    renameSync(stage, destination);
  } finally { rmSync(stage, { recursive: true, force: true }); }
} else {
  // Repacking an installed release must preserve its exact source snapshot.
  const manifest = JSON.parse(readFileSync(join(destination, 'manifest.json'), 'utf8'));
  for (const [path, expected] of Object.entries(manifest.files)) {
    if (digest(join(destination, path)) !== expected) throw new Error(`Native source checksum mismatch: ${path}`);
  }
}
