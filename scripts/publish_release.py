#!/usr/bin/env python3
"""Upload a verified installer as a draft, then optionally publish the GitHub release."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from release_ref import resolve

ROOT = Path(__file__).resolve().parents[1]


def dmg_assets(folder, manifest):
    """Only upload a disk image verified against this exact installer."""
    if manifest.get('developerIDSigned') or manifest.get('notarized'):
        raise RuntimeError('Signed releases need a separately signed and notarized disk image')
    report_path = folder / 'dmg-verification.json'
    report = json.loads(report_path.read_text())
    image = folder / f"Holdfast-{manifest['version']}-macos-arm64-unsigned.dmg"
    checksum = image.with_suffix('.dmg.sha256')
    checks = ['passed', 'mountedReadOnly', 'appMatchesInstaller',
              'signatureIntegrityValidated', 'bundledRuntimeValidated']
    if (report.get('version') != manifest['version']
            or report.get('sourceRevision') != manifest['sourceRevision']
            or report.get('installerSHA256') != manifest['sha256']
            or report.get('diskImage') != image.name
            or not all(report.get(key) is True for key in checks)):
        raise RuntimeError('Verify the DMG against this exact tested installer before uploading')
    digest = hashlib.sha256(image.read_bytes()).hexdigest()
    if (digest != report.get('diskImageSHA256')
            or checksum.read_text() != f'{digest}  {image.name}\n'):
        raise RuntimeError('DMG checksum mismatch')
    return [image, checksum, report_path]


def demo_assets():
    """Attach only the reviewed, committed walkthrough files for this tag."""
    manifest_path = ROOT / 'Demo/release-assets.json'
    if not manifest_path.exists():
        return []
    assets = []
    for name, digest in json.loads(manifest_path.read_text()).items():
        if name not in {'holdfast-tour.mp4', 'holdfast-tour.vtt', 'holdfast-sample-notes.zip'}:
            raise RuntimeError('Unexpected demo asset: ' + name)
        path = ROOT / 'Website/public/demo' / name
        output('git', 'ls-files', '--error-unmatch', str(path.relative_to(ROOT)))
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise RuntimeError('Demo asset checksum mismatch: ' + name)
        assets.append(path)
    if len(assets) != 3:
        raise RuntimeError('The walkthrough requires video, captions, and sample notes')
    return assets


def output(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def run(*args):
    subprocess.run(list(map(str, args)), cwd=ROOT, check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--tag', required=True, help='Existing version tag to publish; never creates or pushes tags')
    parser.add_argument('--publish', action='store_true')
    parser.add_argument('--allow-unsigned-preview', action='store_true')
    parser.add_argument('--include-dmg', action='store_true', help='Require and upload a verified unsigned disk image')
    args = parser.parse_args()
    release = resolve(args.tag, root=ROOT)
    version, tag = release['version'], release['tag']
    if release['revision'] != output('git', 'rev-parse', 'HEAD'):
        raise RuntimeError('Check out the release tag before uploading its artifacts')
    folder = ROOT / 'build/releases' / version
    manifest = json.loads((folder / 'release-manifest.json').read_text())
    installer = folder / manifest['installer']
    if manifest['sourceDirty'] or manifest['sourceRevision'] != output('git', 'rev-parse', 'HEAD'):
        raise RuntimeError('Build the release from the current committed source before uploading')
    if output('git', 'status', '--porcelain', '--untracked-files=no'):
        raise RuntimeError('Commit tracked changes before publishing')
    if manifest['version'] != version:
        raise RuntimeError('Manifest version does not match the release tag')
    if hashlib.sha256(installer.read_bytes()).hexdigest() != manifest['sha256']:
        raise RuntimeError('Installer checksum mismatch')
    if (folder / 'SHA256SUMS').read_text() != f"{manifest['sha256']}  {manifest['installer']}\n":
        raise RuntimeError('SHA256SUMS does not match the verified installer')
    test_result = json.loads((folder / 'verification.json').read_text())
    required_checks = ['passed', 'payloadAndBundleValidated', 'bundledRuntimeValidated',
                       'approvalUndoStaleEditValidated', 'developerFallbacksDisabled']
    if (test_result.get('installerSHA256') != manifest['sha256']
            or test_result.get('version') != version
            or not all(test_result.get(key) is True for key in required_checks)):
        raise RuntimeError('Run Tests/installer_integration.py against this exact installer first')
    trusted = manifest['developerIDSigned'] and manifest['notarized']
    if args.publish and not trusted and not args.allow_unsigned_preview:
        raise RuntimeError('Unsigned publication requires --allow-unsigned-preview; it remains a prerelease')
    if trusted:
        run('pkgutil', '--check-signature', installer)
        run('xcrun', 'stapler', 'validate', installer)
        run('spctl', '--assess', '--type', 'install', installer)
    notes_path = ROOT / 'docs/releases' / (tag + '.md')
    notes = notes_path.read_text() if notes_path.is_file() else ''
    if not notes:
        raise RuntimeError('Add release notes for this version before uploading')
    status = ('**Developer ID signed and notarized by Apple.**\n\n' if trusted else
              '**Unsigned preview — not notarized by Apple.** macOS may block this installer or require '
              'an explicit security exception. For a routine installation, use a future signed release.\n\n')
    body = folder / 'release-notes.md'
    testing = ('\n\nAutomated checks cover the installer, bundled Pi runtime, Inbox approvals, Undo, '
               'and stale-edit refusal. Real MLX inference was not run for this artifact; '
               'hardware inference tests remain a separate local check.\n'
               if not test_result.get('realEmbeddedMLXTested') else '')
    body.write_text(status + notes + testing)
    disk_image = dmg_assets(folder, manifest) if args.include_dmg else []
    walkthrough = demo_assets()
    repository = 'lawwu/holdfast'
    current = subprocess.run(['gh', 'api', f'repos/{repository}/releases/tags/{tag}'],
                             cwd=ROOT, capture_output=True, text=True)
    if current.returncode == 0:
        if not json.loads(current.stdout)['draft']:
            raise RuntimeError('This release is already published; published assets are never replaced')
        run('gh', 'release', 'edit', tag, '--repo', repository, '--notes-file', body, '--prerelease')
    elif 'HTTP 404' in current.stderr:
        run('gh', 'release', 'create', tag, '--repo', repository, '--verify-tag', '--draft', '--prerelease',
            '--title', 'Holdfast ' + tag, '--notes-file', body)
    else:
        raise RuntimeError('Could not check the existing release: ' + current.stderr.strip())
    run('gh', 'release', 'upload', tag, '--repo', repository, '--clobber',
        installer, folder / 'SHA256SUMS', folder / 'release-manifest.json', folder / 'verification.json', *disk_image, *walkthrough)
    if args.publish:
        run('gh', 'release', 'edit', tag, '--repo', repository, '--draft=false', '--prerelease', '--latest=false')
    print(output('gh', 'release', 'view', tag, '--repo', repository, '--json', 'url', '--jq', '.url'))


if __name__ == '__main__':
    main()
