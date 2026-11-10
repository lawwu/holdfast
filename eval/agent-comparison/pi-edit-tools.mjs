// Installed Pi file tools with a scratch-directory boundary. The boundary is
// test infrastructure, not an approval policy or a change to edit matching.
import { readFile, writeFile, access, mkdir, realpath } from 'node:fs/promises';
import { dirname, relative, resolve, sep } from 'node:path';

export async function boundedFileTools(sdk, root) {
  root = await realpath(root);
  async function checked(path) {
    const absolute = resolve(root, path);
    const inside = value => { const rel = relative(root, value); return rel === '' || (!rel.startsWith('..' + sep) && rel !== '..' && !rel.startsWith(sep)); };
    if (!inside(absolute)) throw new Error('Evaluation tool path is outside the scratch vault');
    let ancestor = absolute;
    while (true) {
      try {
        if (!inside(await realpath(ancestor))) throw new Error('Evaluation tool symlink leaves the scratch vault');
        break;
      } catch (error) {
        if (error.code !== 'ENOENT') throw error;
        ancestor = dirname(ancestor);
      }
    }
    return absolute;
  }
  const readOps = {
    readFile: async path => readFile(await checked(path)),
    access: async path => access(await checked(path)),
    detectImageMimeType: async () => null
  };
  const writeOps = {
    writeFile: async (path, content) => writeFile(await checked(path), content, 'utf8'),
    mkdir: async path => { await mkdir(await checked(path), { recursive: true }); }
  };
  return [sdk.createReadTool(root, { operations: readOps }),
    sdk.createEditTool(root, { operations: { ...readOps, writeFile: writeOps.writeFile } }),
    sdk.createWriteTool(root, { operations: writeOps })];
}
