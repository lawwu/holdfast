#!/usr/bin/env python3
"""Wrap the exact tested unsigned installer app in a verified, read-only DMG."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile


def run(*args):
    return subprocess.run(list(map(str, args)), check=True, capture_output=True)


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def bundle_hash(bundle):
    """Compare every file, executable bit, and symlink before and after packaging."""
    entries = []
    for path in sorted(bundle.rglob('*')):
        relative = path.relative_to(bundle).as_posix()
        if path.is_symlink():
            entries.append([relative, 'link', os.readlink(path)])
        elif path.is_file():
            entries.append([relative, path.stat().st_mode & 0o111, sha256(path)])
    return hashlib.sha256(json.dumps(entries, separators=(',', ':')).encode()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('release_directory', type=Path)
    args = parser.parse_args()
    folder = args.release_directory.resolve()
    metadata = json.loads((folder / 'release-manifest.json').read_text())
    verification = json.loads((folder / 'verification.json').read_text())
    version = metadata['version']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or metadata['sourceDirty']:
        raise RuntimeError('Use a versioned installer built from committed source')
    if metadata['developerIDSigned'] or metadata['notarized']:
        raise RuntimeError('This helper supports unsigned previews; signed DMGs need their own notarization workflow')
    installer = metadata['installer']
    if Path(installer).name != installer:
        raise RuntimeError('Installer must be a file in the release directory')
    digest = sha256(folder / installer)
    checks = ['passed', 'payloadAndBundleValidated', 'bundledRuntimeValidated',
              'approvalUndoStaleEditValidated', 'developerFallbacksDisabled']
    if (digest != metadata['sha256'] or digest != verification.get('installerSHA256')
            or verification.get('version') != version
            or not all(verification.get(key) is True for key in checks)):
        raise RuntimeError('The exact installer must pass its integration tests before DMG packaging')
    image = folder / f'Holdfast-{version}-macos-arm64-unsigned.dmg'
    if image.exists():
        raise RuntimeError('Refusing to overwrite an existing disk image: ' + str(image))
    with tempfile.TemporaryDirectory(prefix='holdfast-dmg-') as temporary:
        work = Path(temporary)
        expanded = work / 'expanded'
        run('pkgutil', '--expand-full', folder / installer, expanded)
        apps = list(expanded.glob('*/Payload/Applications/Holdfast.app'))
        if len(apps) != 1:
            raise RuntimeError('Expected exactly one Holdfast app in the installer')
        app = apps[0]
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        if info['CFBundleIdentifier'] != 'app.holdfast' or info['CFBundleShortVersionString'] != version:
            raise RuntimeError('Installer app identity or version does not match')
        run('codesign', '--verify', '--deep', '--strict', app)
        original_hash = bundle_hash(app)
        staging = work / 'staging'
        staging.mkdir()
        run('ditto', app, staging / 'Holdfast.app')
        (staging / 'Applications').symlink_to('/Applications')
        (staging / 'Install Holdfast.txt').write_text(
            f'Holdfast {version} — unsigned preview\n\n'
            'On a managed Mac, right-click Holdfast.app and choose Install with Privilege Management '
            'if your organization provides that option. Your organization must allow the app; '
            'the disk image does not grant permission or change security policies.\n\n'
            'Otherwise, copy Holdfast.app into Applications. To install for your own account, '
            'use the Applications folder inside your home folder.\n\n'
            'This preview is not signed with Apple Developer ID or notarized by Apple. '
            'Gatekeeper and your organization\'s approval requirements still apply.\n\n'
            'Requires Apple Silicon and macOS 15 or later.\n'
            'https://lawwu.github.io/holdfast/getting-started/\n')
        run('hdiutil', 'create', '-srcfolder', staging, '-volname', f'Holdfast {version}',
            '-format', 'UDZO', '-fs', 'HFS+', image)
        run('hdiutil', 'verify', image)
        mount = work / 'mounted'
        mount.mkdir()
        run('hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', mount, image)
        try:
            mounted = mount / 'Holdfast.app'
            run('codesign', '--verify', '--deep', '--strict', mounted)
            if bundle_hash(mounted) != original_hash:
                raise RuntimeError('Mounted app differs from the tested installer payload')
            for executable in ['holdfast', 'node']:
                binary = mounted / 'Contents/MacOS' / executable
                if run('lipo', '-archs', binary).stdout.decode().strip() != 'arm64':
                    raise RuntimeError('Expected an Apple Silicon executable')
                expected = 'Holdfast ' + version if executable == 'holdfast' else metadata['node']
                if run(binary, '--version').stdout.decode().strip() != expected:
                    raise RuntimeError('Mounted runtime version does not match')
        finally:
            run('hdiutil', 'detach', mount)
    image_digest = sha256(image)
    image.with_suffix('.dmg.sha256').write_text(f'{image_digest}  {image.name}\n')
    (folder / 'dmg-verification.json').write_text(json.dumps({
        'version': version, 'sourceRevision': metadata['sourceRevision'],
        'installerSHA256': digest, 'diskImage': image.name, 'diskImageSHA256': image_digest,
        'appBundleSHA256': original_hash, 'passed': True, 'mountedReadOnly': True,
        'appMatchesInstaller': True, 'signatureIntegrityValidated': True,
        'bundledRuntimeValidated': True, 'privilegeManagementPolicyTested': False,
        'developerIDSigned': False, 'notarized': False,
    }, indent=2) + '\n')
    print('PASS: mounted DMG contains the exact tested app, with valid signatures and bundled runtime.')
    print(image)


if __name__ == '__main__':
    main()
