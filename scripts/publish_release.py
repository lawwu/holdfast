#!/usr/bin/env python3
"""Upload a verified installer as a draft, then optionally publish the GitHub release."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def output(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def run(*args):
    subprocess.run(list(map(str, args)), cwd=ROOT, check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--publish', action='store_true')
    parser.add_argument('--allow-unsigned-preview', action='store_true')
    args = parser.parse_args()
    version = (ROOT / 'VERSION').read_text().strip()
    tag = 'v' + version
    folder = ROOT / 'build/releases' / version
    manifest = json.loads((folder / 'release-manifest.json').read_text())
    installer = folder / manifest['installer']
    if manifest['sourceDirty'] or manifest['sourceRevision'] != output('git', 'rev-parse', 'HEAD'):
        raise RuntimeError('Build the release from the current committed source before uploading')
    if output('git', 'status', '--porcelain', '--untracked-files=no'):
        raise RuntimeError('Commit tracked changes before publishing')
    if output('git', 'branch', '--show-current') != 'main':
        raise RuntimeError('Publish releases from main')
    if hashlib.sha256(installer.read_bytes()).hexdigest() != manifest['sha256']:
        raise RuntimeError('Installer checksum mismatch')
    test_result = json.loads((folder / 'verification.json').read_text())
    if test_result.get('installerSHA256') != manifest['sha256'] or not test_result.get('passed'):
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
    status = ('**Signed and notarized by Apple.**\n\n' if trusted else
              '**Unsigned preview — not notarized by Apple.** macOS may block this installer or require '
              'an explicit security exception. For a routine installation, use a future signed release.\n\n')
    body = folder / 'release-notes.md'
    body.write_text(status + notes)
    repository = 'lawwu/holdfast'
    existing_tag = subprocess.run(['git', 'rev-parse', '--verify', 'refs/tags/' + tag], cwd=ROOT, capture_output=True)
    if existing_tag.returncode:
        run('git', 'tag', '-a', tag, '-m', 'Holdfast ' + tag, manifest['sourceRevision'])
    if output('git', 'rev-list', '-n', '1', tag) != manifest['sourceRevision']:
        raise RuntimeError('The version tag already points to another commit; choose a new version')
    run('git', 'push', 'origin', 'HEAD:main', 'refs/tags/' + tag)
    current = subprocess.run(['gh', 'release', 'view', tag, '--repo', repository, '--json', 'isDraft'],
                             cwd=ROOT, capture_output=True, text=True)
    if current.returncode == 0:
        if not json.loads(current.stdout)['isDraft']:
            raise RuntimeError('This release is already published; published assets are never replaced')
        run('gh', 'release', 'edit', tag, '--repo', repository, '--notes-file', body, '--prerelease')
    else:
        run('gh', 'release', 'create', tag, '--repo', repository, '--verify-tag', '--draft', '--prerelease',
            '--title', 'Holdfast ' + tag, '--notes-file', body)
    run('gh', 'release', 'upload', tag, '--repo', repository, '--clobber',
        installer, folder / 'SHA256SUMS', folder / 'release-manifest.json')
    if args.publish:
        run('gh', 'release', 'edit', tag, '--repo', repository, '--draft=false', '--prerelease', '--latest=false')
    print(output('gh', 'release', 'view', tag, '--repo', repository, '--json', 'url', '--jq', '.url'))


if __name__ == '__main__':
    main()
