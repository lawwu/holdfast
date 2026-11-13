#!/usr/bin/env python3
"""Build a signed, notarized installer, or an explicitly selected local unsigned preview."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import plistlib
import subprocess

import notary

ROOT = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    return subprocess.run(list(map(str, args)), cwd=ROOT, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--unsigned-preview', action='store_true')
    args = parser.parse_args()
    version = (ROOT / 'VERSION').read_text().strip()
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise RuntimeError('VERSION must contain a three-part numeric version')
    if not args.unsigned_preview:
        for name in ['HOLDFAST_SIGNING_IDENTITY', 'HOLDFAST_INSTALLER_IDENTITY']:
            if not os.environ.get(name) or os.environ.get(name) == '-':
                raise RuntimeError('A trusted release needs ' + name + '; see docs/releases.md')
        notary.credentials()  # fail before a long build when nothing can notarize it
    out = ROOT / 'build/releases' / version
    out.mkdir(parents=True, exist_ok=True)
    app = out / 'Holdfast.app'
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    dirty = bool(subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=no'], cwd=ROOT).strip())
    dirty = dirty or bool(subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard',
        'Sources', 'Packages', 'Runtime', 'QuickLook', 'scripts', 'packaging', 'Tests', 'docs', '.github',
        'VERSION', 'Package.swift', 'Package.resolved'], cwd=ROOT).strip())
    if dirty and not args.unsigned_preview:
        raise RuntimeError('Commit the release inputs before building a signed release')
    env = {**os.environ, 'HOLDFAST_DISTRIBUTION': '1', 'HOLDFAST_APP': str(app),
           'HOLDFAST_BUNDLE_ID': 'app.holdfast', 'HOLDFAST_APP_NAME': 'Holdfast',
           'HOLDFAST_VERSION': version, 'HOLDFAST_DERIVED_DATA': str(ROOT / '.build/distribution-xcode')}
    if args.unsigned_preview:
        env['HOLDFAST_SIGNING_IDENTITY'] = '-'
    run('bash', 'scripts/make_app.sh', env=env)
    name = f'Holdfast-{version}-macos-arm64' + ('-unsigned' if args.unsigned_preview else '') + '.pkg'
    package = out / name
    run('python3', 'scripts/make_installer.py', app, package,
        *(['--unsigned-preview'] if args.unsigned_preview else []), env=env)
    if not args.unsigned_preview:
        notary.notarize(package, 'notarization')
        run('spctl', '--assess', '--type', 'install', '--verbose=2', package)
    checksum = hashlib.sha256(package.read_bytes()).hexdigest()
    (out / 'SHA256SUMS').write_text(f'{checksum}  {name}\n')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    metadata = {'version': version, 'buildNumber': info['CFBundleVersion'],
                'sourceRevision': revision, 'sourceDirty': dirty,
                'architecture': 'arm64', 'minimumMacOS': '15.0', 'installer': name,
                'sha256': checksum, 'developerIDSigned': not args.unsigned_preview,
                'notarized': not args.unsigned_preview,
                'node': json.loads((ROOT / 'packaging/node-runtime.json').read_text())['version']}
    (out / 'release-manifest.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print('Release artifacts: ' + str(out))


if __name__ == '__main__':
    main()
