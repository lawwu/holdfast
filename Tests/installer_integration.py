#!/usr/bin/env python3
"""Inspect the exact pkg and exercise its bundled runtime without developer fallbacks."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('release_directory', type=Path)
parser.add_argument('--live-mlx', type=Path)
parser.add_argument('--model-id', default='mlx-community/Qwen3.5-2B-4bit')
args = parser.parse_args()
folder = args.release_directory.resolve()
metadata = json.loads((folder / 'release-manifest.json').read_text())
package = folder / metadata['installer']
digest = hashlib.sha256(package.read_bytes()).hexdigest()
assert digest == metadata['sha256']
state = None
domain = 'app.holdfast.installer-check-' + uuid.uuid4().hex
scratch_root = Path.home() / '.cache'
scratch_root.mkdir(exist_ok=True)


def run(*args, **kwargs):
    result = subprocess.run(list(map(str, args)), capture_output=True, text=True, **kwargs)
    assert result.returncode == 0, (args, result.returncode, result.stdout, result.stderr)
    return result


MACHO = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf',
         b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf', b'\xbe\xba\xfe\xca'}


def unsigned_copy(source, target, work):
    """Copy an app bundle with every code signature removed.

    macOS (App Management) refuses edits to an app signed with Developer ID, so the runtime tests
    below, which give the app a private identity and re-sign it, work on a copy that was never
    signed: signatures are stripped from each executable outside the bundle before it goes in.
    """
    for directory, folders, files in os.walk(source, followlinks=False):
        folders[:] = [f for f in folders if f != '_CodeSignature']
        here = Path(directory)
        destination = target / here.relative_to(source)
        destination.mkdir(parents=True, exist_ok=True)
        for name in folders:
            if (here / name).is_symlink():
                os.symlink(os.readlink(here / name), destination / name)
        folders[:] = [f for f in folders if not (here / f).is_symlink()]
        for name in files:
            path = here / name
            if path.is_symlink():
                os.symlink(os.readlink(path), destination / name)
                continue
            with path.open('rb') as handle:
                macho = handle.read(4) in MACHO
            if not macho:
                shutil.copy2(path, destination / name)
                continue
            loose = work / ('unsigned-' + uuid.uuid4().hex)
            shutil.copy2(path, loose)
            run('codesign', '--remove-signature', loose)
            shutil.move(loose, destination / name)
    return target


def reply(text='', calls=()):
    return dict(text=text, reasoning='', calls=list(calls),
                usage=dict(promptTokens=10, promptSeconds=.1, outputTokens=5, outputSeconds=.1), truncated=False)


try:
    with tempfile.TemporaryDirectory(prefix='holdfast-installer-check-', dir=scratch_root) as temporary:
        scratch = Path(temporary).resolve()
        expanded = scratch / 'expanded'
        run('pkgutil', '--expand-full', package, expanded)
        distribution = ET.parse(expanded / 'Distribution').getroot()
        assert distribution.find('options').attrib['hostArchitectures'] == 'arm64'
        assert any(v.attrib.get('min') == '15.0' for v in distribution.findall('.//os-version'))
        assert distribution.find('domains').attrib['enable_localSystem'] == 'true'
        payloads = list(expanded.rglob('Payload'))
        assert len(payloads) == 1
        payload = payloads[0]
        assert {p.name for p in payload.iterdir()} == {'Applications'}
        assert {p.name for p in (payload / 'Applications').iterdir()} == {'Holdfast.app'}
        assert not (payload.parent / 'Scripts').exists(), 'Installer scripts are not expected'
        package_info = ET.parse(payload.parent / 'PackageInfo').getroot()
        assert package_info.attrib['version'] == metadata['version']
        assert package_info.attrib['identifier'] == 'app.holdfast.installer'
        run('/usr/sbin/installer', '-showChoicesXML', '-pkg', package, '-target', '/')
        app = payload / 'Applications/Holdfast.app'
        binary = app / 'Contents/MacOS/holdfast'
        node = app / 'Contents/MacOS/node'
        runtime = app / 'Contents/Resources/pi'
        run('codesign', '--verify', '--deep', '--strict', app)
        info_path = app / 'Contents/Info.plist'
        info = plistlib.loads(info_path.read_bytes())
        assert info['CFBundleIdentifier'] == 'app.holdfast'
        assert info['CFBundleShortVersionString'] == metadata['version']
        assert run(binary, '--version').stdout.strip() == 'Holdfast ' + metadata['version']
        assert b'HOLDFAST_DEMO_CONTROL' not in binary.read_bytes(), 'Documentation capture driver must not ship'
        assert run(node, '--version').stdout.strip() == metadata['node']
        assert not (runtime / 'node_modules/@earendil-works/pi-durable').exists()
        assert not list(app.rglob('*.safetensors'))
        assert (app / 'Contents/Resources/ThirdPartyNotices/Node-LICENSE.txt').is_file()
        for executable in [binary, node]:
            assert run('lipo', '-archs', executable).stdout.strip() == 'arm64'
            libraries = '\n'.join(run('otool', '-L', executable).stdout.splitlines()[1:])
            assert not any(p in libraries for p in ['/opt/homebrew/', '/usr/local/', '/Users/'])
        node_entitlements = plistlib.loads(run('codesign', '-d', '--entitlements', ':-', node).stdout.encode())
        assert node_entitlements.get('com.apple.security.cs.allow-jit')
        assert not node_entitlements.get('com.apple.security.get-task-allow')
        print('PASS installer payload, version, architecture, signature integrity, licenses, and system-only linking', flush=True)

        # The checks above ran on the installer's own signed app. The runtime checks below edit and
        # re-sign it, which macOS forbids for a Developer ID app, so they use an unsigned copy.
        if metadata.get('developerIDSigned'):
            loose = scratch / 'loose'
            loose.mkdir()
            app = unsigned_copy(app, scratch / 'tested/Holdfast.app', loose)
            binary = app / 'Contents/MacOS/holdfast'
            node = app / 'Contents/MacOS/node'
            runtime = app / 'Contents/Resources/pi'
            info_path = app / 'Contents/Info.plist'

        # Use a unique preferences identity so test commands cannot alter the installed app's settings.
        info['CFBundleIdentifier'] = domain
        info_path.write_bytes(plistlib.dumps(info))
        signing_env = {**os.environ, 'HOLDFAST_DISTRIBUTION': '1', 'HOLDFAST_SIGNING_IDENTITY': '-'}
        run('python3', ROOT / 'scripts/sign_app.py', app, env=signing_env)
        run('defaults', 'write', domain, 'migratedAppIdentityV2', '-bool', 'true')
        vault = scratch / 'vault'
        (vault / 'finance').mkdir(parents=True)
        (vault / '.agent-eval-synthetic').write_text('synthetic holdfast agent evaluation\n')
        note = vault / 'finance/checklist.md'
        before = b'\xef\xbb\xbf# Checklist\r\n\r\n- [ ] Keep basis\r\n- [ ] Leave open\r\n'
        note.write_bytes(before)
        env = {k: v for k, v in os.environ.items() if not k.startswith(('HOLDFAST_', 'PI_', 'NODE_'))}
        env.update(PATH='/usr/bin:/bin:/usr/sbin:/sbin', HOLDFAST_VAULT=str(vault), HOLDFAST_AGENT_EVAL='1',
                   HOLDFAST_PACKS='none', HOLDFAST_EMBED='none', HOLDFAST_RERANK='0', HOLDFAST_THINK='0')

        def cli(*args, success=True):
            result = subprocess.run([str(binary), *args], env=env, capture_output=True, text=True, timeout=60)
            assert (result.returncode == 0) == success, result.stdout + result.stderr
            return result

        def bridge(request):
            result = run(binary, '_agent-eval', input=json.dumps(request) + '\n', env=env, timeout=60)
            return json.loads(result.stdout.splitlines()[-1])

        value = 1469598103934665603
        for byte in str(vault).encode():
            value = ((value ^ byte) * 1099511628211) & ((1 << 64) - 1)
        expected = Path.home() / 'Library/Application Support/Holdfast/vaults' / ('vault-' + format(value, 'x')[:8])
        assert not expected.exists()
        state = Path(bridge({'op': 'config'})['stateDir'])
        assert state == expected, (state, expected)

        def proposal():
            return dict(op='run_pi', conversationID=str(uuid.uuid4()), question='Mark Keep basis done', replies=[
                reply(calls=[dict(id='read', name='read_note', arguments=json.dumps({'path': 'finance/checklist.md'}))]),
                reply(calls=[dict(id='edit', name='propose_edit', arguments=json.dumps({
                    'path': 'finance/checklist.md', 'old_text': '- [ ] Keep basis', 'new_text': '- [x] Keep basis'}))]),
                reply('Waiting for Inbox approval. [1]')])

        response = bridge(proposal())
        assert 'error' not in response, response
        assert note.read_bytes() == before
        proposals = list((state / 'inbox').glob('*.md'))
        assert len(proposals) == 1
        cli('approve', '@inbox/' + proposals[0].stem)
        assert note.read_bytes() == before.replace(b'- [ ] Keep basis', b'- [x] Keep basis')
        cli('undo', '1')
        assert note.read_bytes() == before
        response = bridge(proposal())
        assert 'error' not in response, response
        changed = before + b'\r\nManual change\r\n'
        note.write_bytes(changed)
        proposals = list((state / 'inbox').glob('*.md'))
        assert len(proposals) == 1
        cli('approve', '@inbox/' + proposals[0].stem, success=False)
        assert note.read_bytes() == changed
        print('PASS bundled Node/Pi with a minimal PATH; proposal, approval, exact Undo, and stale refusal', flush=True)

        node.rename(node.with_name('node-hidden'))
        try:
            assert 'Node runtime is missing' in bridge(proposal()).get('error', '')
        finally:
            node.with_name('node-hidden').rename(node)
        runtime.rename(runtime.with_name('pi-hidden'))
        try:
            assert 'Install Pi' in bridge(proposal()).get('error', '')
        finally:
            runtime.with_name('pi-hidden').rename(runtime)
        print('PASS distribution build refuses missing bundled dependencies instead of using the developer checkout', flush=True)
        if args.live_mlx:
            env.update(HOLDFAST_BACKEND='mlx', HOLDFAST_MLX_DIR=str(args.live_mlx.resolve()),
                       HOLDFAST_MLX_REPO=args.model_id, HOLDFAST_AGENT_HARNESS='swift')
            (vault / 'finance/release-check.md').write_text('# Release check\n\nThe release check code is orchard42.\n')
            cli('index', '--no-embed')
            answer = cli('ask', '--no-embed', 'What is the release check code?')
            assert 'orchard42' in answer.stdout.lower(), answer.stdout + answer.stderr
            print('PASS real embedded MLX inference from the extracted, hardened app', flush=True)
    (folder / 'verification.json').write_text(json.dumps({'passed': True, 'installerSHA256': digest,
        'version': metadata['version'], 'payloadAndBundleValidated': True, 'bundledRuntimeValidated': True,
        'approvalUndoStaleEditValidated': True, 'developerFallbacksDisabled': True,
        'realEmbeddedMLXTested': bool(args.live_mlx), 'cleanMacInstallTested': False}, indent=2) + '\n')
finally:
    subprocess.run(['defaults', 'delete', domain], capture_output=True)
    if state is not None and state == expected and state.exists():
        shutil.rmtree(state)
