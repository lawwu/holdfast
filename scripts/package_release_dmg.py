#!/usr/bin/env python3
"""Wrap the exact tested installer app in a verified, read-only DMG; signed and notarized for a signed release."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import time

import notary
from verified_release import verify_installer

# hdiutil on hosted macOS runners: its own size estimate from -srcfolder can come up short as the
# app grows, and it sometimes fails with "Resource busy" while the system scans new files.
# Give it an explicit size with this much room over the staged files, and retry a failure.
DMG_HEADROOM = 1.25
DMG_EXTRA_MB = 64
DMG_ATTEMPTS = 3
DMG_RETRY_SECONDS = 15


def run(*args):
    """Run a tool; on failure, raise with its own error output (otherwise CI shows only the exit status)."""
    result = subprocess.run(list(map(str, args)), capture_output=True)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).decode(errors='replace').strip()
        raise RuntimeError(f'{Path(str(args[0])).name} {args[1] if len(args) > 1 else ""} failed '
                           f'(exit {result.returncode}): {detail or "no output"}')
    return result


def folder_megabytes(folder):
    """Bytes the staged files take, rounded up to whole megabytes (symlinks count as nothing)."""
    total = sum(path.lstat().st_size for path in folder.rglob('*') if path.is_file() and not path.is_symlink())
    return -(-total // (1024 * 1024))


def create_image(staging, volume, image):
    size = int(folder_megabytes(staging) * DMG_HEADROOM) + DMG_EXTRA_MB
    for attempt in range(1, DMG_ATTEMPTS + 1):
        try:
            run('hdiutil', 'create', '-srcfolder', staging, '-volname', volume, '-size', f'{size}m',
                '-format', 'UDZO', '-fs', 'HFS+', image)
            return
        except RuntimeError as error:
            image.unlink(missing_ok=True)
            if attempt == DMG_ATTEMPTS:
                raise
            print(f'hdiutil create failed (attempt {attempt} of {DMG_ATTEMPTS}), retrying: {error}', flush=True)
            time.sleep(DMG_RETRY_SECONDS * attempt)


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
    verified = verify_installer(folder)
    metadata = verified.manifest
    version, signed = metadata['version'], verified.signed
    installer, digest = verified.installer.name, verified.digest
    identity = os.environ.get('HOLDFAST_SIGNING_IDENTITY', '')
    if signed and (not identity or identity == '-'):
        raise RuntimeError('A signed release needs HOLDFAST_SIGNING_IDENTITY to sign its disk image')
    image = folder / (f'Holdfast-{version}-macos-arm64' + ('' if signed else '-unsigned') + '.dmg')
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
            f'Holdfast {version}' + ('' if signed else ' — unsigned preview') + '\n\n'
            'Copy Holdfast.app into Applications. To install for your own account, '
            'use the Applications folder inside your home folder.\n\n'
            'On a managed Mac, right-click Holdfast.app and choose Install with Privilege Management '
            'if your organization provides that option. Your organization must allow the app; '
            'the disk image does not grant permission or change security policies.\n\n'
            + ('Holdfast is signed with Apple Developer ID and notarized by Apple.\n\n' if signed else
               'This preview is not signed with Apple Developer ID or notarized by Apple. '
               'Gatekeeper and your organization\'s approval requirements still apply.\n\n')
            + 'Requires Apple Silicon and macOS 15 or later.\n'
            'https://lawwu.github.io/holdfast/getting-started/\n')
        create_image(staging, f'Holdfast {version}', image)
        if signed:
            # Sign the image itself, have Apple notarize it, and staple the ticket, so a downloaded
            # DMG opens without a Gatekeeper warning even offline.
            run('codesign', '--sign', identity, '--timestamp', image)
            notary.notarize(image, 'dmg-notarization')
            run('spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose=2', image)
        run('hdiutil', 'verify', image)
        mount = work / 'mounted'
        mount.mkdir()
        run('hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', mount, image)
        try:
            mounted = mount / 'Holdfast.app'
            run('codesign', '--verify', '--deep', '--strict', mounted)
            if signed:
                run('spctl', '--assess', '--type', 'exec', '--verbose=2', mounted)
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
        'developerIDSigned': signed, 'notarized': signed,
    }, indent=2) + '\n')
    print('PASS: mounted DMG contains the exact tested app, with valid signatures and bundled runtime.')
    print(image)


if __name__ == '__main__':
    main()
