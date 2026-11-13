#!/usr/bin/env python3
"""Generate and validate the signed update feed for the exact tested release DMG."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / '.build/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin'
SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
DMG_NAME = 'Holdfast-macos-arm64.dmg'
PKG_NAME = 'Holdfast-macos-arm64.pkg'
REPOSITORY = 'lawwu/holdfast'


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_feed(feed, version, build_number=None, image=None):
    items = ET.parse(feed).findall('./channel/item')
    if len(items) != 1:
        raise RuntimeError('The update feed must contain exactly this release')
    item = items[0]
    enclosure = item.find('enclosure')
    expected_url = f'https://github.com/{REPOSITORY}/releases/download/v{version}/{DMG_NAME}'
    if (enclosure is None or enclosure.get('url') != expected_url
            or item.findtext(SPARKLE + 'shortVersionString') != version
            or not (item.findtext(SPARKLE + 'version') or '').isdigit()
            or (build_number is not None and item.findtext(SPARKLE + 'version') != str(build_number))):
        raise RuntimeError('The update feed does not match the release version, build or DMG URL')
    signature = enclosure.get(SPARKLE + 'edSignature', '')
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise RuntimeError('The update DMG must have a Sparkle signature matching the embedded public key')
    if image is not None and enclosure.get('length') != str(image.stat().st_size):
        raise RuntimeError('The update feed has the wrong DMG length')
    return signature


def validated_feed(folder, manifest):
    report = json.loads((folder / 'sparkle-verification.json').read_text())
    feed = folder / 'appcast.xml'
    image = folder / f"Holdfast-{manifest['version']}-macos-arm64.dmg"
    if (not manifest.get('developerIDSigned') or not manifest.get('notarized')
            or report.get('passed') is not True
            or report.get('sourceRevision') != manifest['sourceRevision']
            or report.get('diskImageSHA256') != sha256(image)
            or report.get('appcastSHA256') != sha256(feed)):
        raise RuntimeError('The update feed must be verified against the exact signed release')
    check_feed(feed, manifest['version'], manifest['buildNumber'], image)
    return feed


def generate(folder):
    # Reuse all existing DMG/installer/signature checks before creating an update.
    from publish_release import dmg_assets
    manifest = json.loads((folder / 'release-manifest.json').read_text())
    if not manifest['developerIDSigned'] or not manifest['notarized']:
        raise RuntimeError('Unsigned previews cannot enter the update feed')
    image = dmg_assets(folder, manifest)[0]
    settings = json.loads((ROOT / 'packaging/sparkle.json').read_text())
    secret = os.environ.get('SPARKLE_PRIVATE_KEY')
    key_args = ['--ed-key-file', '-'] if secret else ['--account', settings['keychainAccount']]

    def sparkle(tool, *args):
        subprocess.run([str(TOOLS / tool), *key_args, *map(str, args)], check=True,
                       input=(secret + '\n') if secret else None, text=True)

    with tempfile.TemporaryDirectory(prefix='holdfast-appcast-') as temporary:
        staging = Path(temporary)
        archive = staging / DMG_NAME
        shutil.copyfile(image, archive)
        # Embed the short user-facing notes, avoiding another release download.
        notes = ROOT / 'docs/releases' / f"v{manifest['version']}.md"
        archive.with_suffix('.md').write_text(notes.read_text())
        sparkle('generate_appcast', '--download-url-prefix',
                f"https://github.com/{REPOSITORY}/releases/download/v{manifest['version']}/",
                '--link', 'https://lawwu.github.io/holdfast/', '--embed-release-notes',
                '--maximum-deltas', '0', staging)
        feed = staging / 'appcast.xml'
        signature = check_feed(feed, manifest['version'], manifest['buildNumber'], archive)
        sparkle('sign_update', '--verify', archive, signature)
        sparkle('sign_update', '--verify', feed)
        shutil.copyfile(feed, folder / 'appcast.xml')
    report = dict(passed=True, sourceRevision=manifest['sourceRevision'],
                  diskImageSHA256=sha256(image), appcastSHA256=sha256(folder / 'appcast.xml'))
    (folder / 'sparkle-verification.json').write_text(json.dumps(report, indent=2) + '\n')
    validated_feed(folder, manifest)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('release_directory', type=Path)
    generate(parser.parse_args().release_directory.resolve())
