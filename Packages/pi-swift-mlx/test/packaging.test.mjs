import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const adapter = dirname(dirname(fileURLToPath(import.meta.url)));
function run(command, args, options = {}) {
  const result = spawnSync(command, args, { encoding: 'utf8', timeout: 60000, ...options });
  assert.equal(result.status, 0, result.error?.message ?? result.stderr + result.stdout);
  return result.stdout;
}

test('npm archive carries both Swift packages and resolves its host outside the checkout', { timeout: 90000 }, () => {
  const scratch = realpathSync(mkdtempSync(join(tmpdir(), 'pi-swift-mlx-package-')));
  try {
    const [packed] = JSON.parse(run('npm', ['pack', '--json', '--pack-destination', scratch], { cwd: adapter }));
    const names = packed.files.map(file => file.path);
    for (const name of ['native/LocalMLX/Package.swift', 'native/LocalMLX/Package.resolved',
      'native/LocalMLX/Sources/LocalMLXHost/Host.swift', 'native/LocalMLX/scripts/build-host.sh',
      'native/ModelProviders/Package.swift', 'native/ModelProviders/Sources/ModelProviders/Inference.swift']) {
      assert.ok(names.includes(name), `Missing source: ${name}`);
    }
    assert.ok(!names.some(name => /(^|\/)(node_modules|test|\.build|build|\.git)\//.test(name)));
    run('tar', ['-xzf', join(scratch, packed.filename), '-C', scratch]);
    const unpacked = join(scratch, 'package');
    const manifest = JSON.parse(readFileSync(join(unpacked, 'native/manifest.json'), 'utf8'));
    assert.equal(manifest.protocolVersion, 1);
    for (const [path, hash] of Object.entries(manifest.files)) {
      const contents = readFileSync(join(unpacked, 'native', path));
      assert.equal(createHash('sha256').update(contents).digest('hex'), hash);
      assert.deepEqual(contents, readFileSync(join(adapter, '..', path)), `Stale source: ${path}`);
    }
    const providers = JSON.parse(run('swift', ['package', '--package-path', join(unpacked, 'native/ModelProviders'), 'dump-package']));
    assert.deepEqual(providers.dependencies, []);
    const local = JSON.parse(run('swift', ['package', '--package-path', join(unpacked, 'native/LocalMLX'), 'dump-package']));
    assert.ok(local.products.some(product => product.name === 'local-mlx-host'));
    const shared = local.dependencies.find(dependency => dependency.fileSystem?.[0]?.identity === 'modelproviders');
    assert.equal(shared.fileSystem[0].path, join(unpacked, 'native/ModelProviders'));

    // Exercise the installed wrapper's path selection without compiling MLX in every npm test.
    const fakeBin = join(scratch, 'bin'), capture = join(scratch, 'build-cwd');
    mkdirSync(fakeBin);
    writeFileSync(join(fakeBin, 'xcodebuild'), '#!/bin/bash\nset -eu\npwd > "$PACKAGE_TEST_CAPTURE"\nwhile [[ "$1" != "-derivedDataPath" ]]; do shift; done\nshift\nmkdir -p "$1/Build/Products/Release/mlx.bundle"\nprintf host > "$1/Build/Products/Release/local-mlx-host"\n', { mode: 0o755 });
    run('bash', ['scripts/build-host.sh'], { cwd: unpacked, env: {
      ...process.env, PATH: fakeBin + ':' + process.env.PATH, PACKAGE_TEST_CAPTURE: capture,
      PI_MLX_DERIVED_DATA: join(scratch, 'derived'), LOCAL_MLX_OUTPUT_DIR: join(scratch, 'host'),
    } });
    assert.equal(readFileSync(capture, 'utf8').trim(), join(unpacked, 'native/LocalMLX'));
    assert.ok(existsSync(join(scratch, 'host/local-mlx-host')));
    assert.ok(existsSync(join(scratch, 'host/mlx.bundle')));
    // An installed release can be repacked without the original sibling directories.
    run('node', ['scripts/stage-native.mjs'], { cwd: unpacked });
    mkdirSync(join(unpacked, 'native/LocalMLX/.build'), { recursive: true });
    writeFileSync(join(unpacked, 'native/LocalMLX/.build/private-build-output'), 'exclude');
    const [repacked] = JSON.parse(run('npm', ['pack', '--ignore-scripts', '--json', '--pack-destination', scratch], { cwd: unpacked }));
    assert.ok(!repacked.files.some(file => file.path.includes('.build/')));
  } finally { rmSync(scratch, { recursive: true, force: true }); }
});
