#!/usr/bin/env python3
"""Create a standard /Applications installer with explicit OS and CPU requirements."""
import argparse
import html
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET


def run(*args):
    subprocess.run(list(map(str, args)), check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('app', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--unsigned-preview', action='store_true')
    args = parser.parse_args()
    app, output = args.app.resolve(), args.output.resolve()
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    version = info['CFBundleShortVersionString']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or info['CFBundleIdentifier'] != 'app.holdfast':
        raise RuntimeError('Expected a versioned production Holdfast app')
    identity = os.environ.get('HOLDFAST_INSTALLER_IDENTITY')
    if not args.unsigned_preview and not identity:
        raise RuntimeError('Set HOLDFAST_INSTALLER_IDENTITY to a Developer ID Installer identity')
    if not (app / 'Contents/MacOS/node').is_file():
        raise RuntimeError('The installer must include its own Node runtime')
    for executable in [app / 'Contents/MacOS/holdfast', app / 'Contents/MacOS/node']:
        arch = subprocess.check_output(['lipo', '-archs', str(executable)], text=True).strip()
        if arch != 'arm64':
            raise RuntimeError('This installer targets Apple Silicon only: ' + arch)
    run('codesign', '--verify', '--deep', '--strict', app)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='holdfast-installer-') as temporary:
        work = Path(temporary)
        payload = work / 'payload'
        (payload / 'Applications').mkdir(parents=True)
        run('ditto', app, payload / 'Applications/Holdfast.app')
        component = work / 'component.plist'
        component.write_bytes(plistlib.dumps([{
            'RootRelativeBundlePath': 'Applications/Holdfast.app',
            'BundleIsRelocatable': False, 'BundleIsVersionChecked': True,
            'BundleHasStrictIdentifier': True, 'BundleOverwriteAction': 'upgrade',
        }]))
        package = work / 'Holdfast-component.pkg'
        run('pkgbuild', '--root', payload, '--component-plist', component,
            '--identifier', 'app.holdfast.installer', '--version', version,
            '--install-location', '/', '--ownership', 'recommended', package)
        requirements = work / 'requirements.plist'
        requirements.write_bytes(plistlib.dumps({'arch': ['arm64'], 'os': ['15.0']}))
        distribution = work / 'Distribution.xml'
        run('productbuild', '--synthesize', '--product', requirements, '--package', package, distribution)
        tree = ET.parse(distribution)
        root = tree.getroot()
        ET.SubElement(root, 'title').text = 'Holdfast'
        domains = root.find('domains')
        if domains is None:
            domains = ET.SubElement(root, 'domains')
        domains.attrib.update(enable_anywhere='false', enable_currentUserHome='false', enable_localSystem='true')
        ET.SubElement(root, 'welcome', {'file': 'Welcome.html', 'mime-type': 'text/html'})
        resources = work / 'resources'
        resources.mkdir()
        warning = ('<p><strong>Unsigned preview:</strong> this build has not been verified by Apple. '
                   'macOS may block it or require an explicit security exception.</p>' if args.unsigned_preview else '')
        (resources / 'Welcome.html').write_text(f'''<!doctype html><html><head><meta charset="utf-8">
<style>body{{font:14px -apple-system,sans-serif;line-height:1.5;padding:16px;color:#222}}h1{{font-size:24px}}</style>
</head><body><h1>Holdfast {html.escape(version)}</h1>
<p>A local-first knowledge base for your notes and documents.</p>{warning}
<p>Requires an Apple Silicon Mac (M1 or newer) with macOS 15 or later.</p>
<p>The installer places Holdfast in Applications. Open it there, choose a notes folder,
and download an answer model or connect a model server. Model downloads need internet access
and additional disk space. Node is included; no developer tools are needed for the core app.</p>
<p>Recording-file and stream imports require the optional ffmpeg tool. Video-link imports
also require yt-dlp. Microphone and Mac audio capture use macOS permissions.</p>
<p>The installer does not install background services. Notes and model downloads remain
in the locations managed by the app.</p></body></html>''')
        tree.write(distribution, encoding='utf-8', xml_declaration=True)
        signing = [] if args.unsigned_preview else ['--sign', identity, '--timestamp']
        run('productbuild', '--distribution', distribution, '--package-path', work,
            '--resources', resources, *signing, output)
    print(output)


if __name__ == '__main__':
    main()
