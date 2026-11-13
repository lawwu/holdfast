#!/usr/bin/env python3
"""Build the experiment from a snapshot of real app sources; never edit the app."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
STAGE = ROOT / '.build/crosslink-experiment/source'
DERIVED = ROOT / '.build/crosslink-experiment/xcode'


def main():
    STAGE.mkdir(parents=True, exist_ok=True)
    sources = STAGE / 'Sources/holdfast'
    if sources.exists():
        shutil.rmtree(sources)
    shutil.copytree(ROOT / 'Sources/holdfast', sources)
    manifest = (ROOT / 'Package.swift').read_text()
    for package in ['LocalMLX', 'ModelProviders']:
        manifest = manifest.replace(f'path: "Packages/{package}"', f'path: "{ROOT}/Packages/{package}"')
    needle = '.product(name: "MLXLLM", package: "mlx-swift-lm"),'
    assert manifest.count(needle) == 1
    manifest = manifest.replace(needle, needle + '\n                .product(name: "MLXGuidedGeneration", package: "mlx-swift-lm"),')
    (STAGE / 'Package.swift').write_text(manifest)
    shutil.copy2(ROOT / 'Package.resolved', STAGE / 'Package.resolved')
    shutil.copy2(HERE / 'Experiment.swift', sources / 'CrossLinkExperiment.swift')
    (sources / 'main.swift').write_text('''import Foundation
let launchedAsApp = false
Task.detached {
    do { try await CrossLinkExperiment.main(); exit(0) }
    catch { FileHandle.standardError.write(Data("\\(error)\\n".utf8)); exit(1) }
}
dispatchMain()
''')
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted((ROOT / 'Sources/holdfast').glob('*.swift'))}
    for p in [ROOT / 'Package.swift', ROOT / 'Package.resolved', HERE / 'Experiment.swift']:
        hashes[str(p.relative_to(ROOT))] = hashlib.sha256(p.read_bytes()).hexdigest()
    (STAGE.parent / 'source-hashes.json').write_text(json.dumps(hashes, indent=2) + '\n')
    subprocess.run(['xcodebuild', '-scheme', 'holdfast', '-destination', 'platform=macOS,arch=arm64',
                    '-configuration', 'Release', '-derivedDataPath', str(DERIVED),
                    '-clonedSourcePackagesDirPath', str(ROOT / '.build/xcode/SourcePackages'),
                    '-onlyUsePackageVersionsFromResolvedFile', '-skipMacroValidation',
                    '-skipPackagePluginValidation', '-jobs', '4', 'build', '-quiet'], cwd=STAGE, check=True)
    print(DERIVED / 'Build/Products/Release/holdfast')


if __name__ == '__main__':
    main()
