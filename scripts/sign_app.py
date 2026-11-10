#!/usr/bin/env python3
"""Sign nested code explicitly, preserving a separate entitlement set for each role."""
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

MACHO = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf',
         b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf', b'\xbe\xba\xfe\xca'}


def main():
    app = Path(sys.argv[1]).resolve()
    identity = os.environ.get('HOLDFAST_SIGNING_IDENTITY', '-')
    hardened = os.environ.get('HOLDFAST_DISTRIBUTION') == '1' or identity != '-'
    with tempfile.TemporaryDirectory(prefix='holdfast-sign-') as temporary:
        entitlements = {}
        for role, values in {
            'app': {'com.apple.security.device.audio-input': True},
            'node': {'com.apple.security.cs.allow-jit': True},
            'preview': {'com.apple.security.app-sandbox': True},
        }.items():
            path = Path(temporary) / (role + '.plist')
            path.write_bytes(plistlib.dumps(values))
            entitlements[role] = path

        def sign(path, role=None):
            args = ['codesign', '--force', '--sign', identity]
            if hardened:
                args += ['--options', 'runtime']
            args += ['--timestamp' if identity != '-' else '--timestamp=none']
            if role:
                args += ['--entitlements', str(entitlements[role])]
            subprocess.run([*args, str(path)], check=True)

        main_binary = app / 'Contents/MacOS/holdfast'
        preview = app / 'Contents/PlugIns/HoldfastPreview.appex'
        preview_binary = preview / 'Contents/MacOS/HoldfastPreview'
        for path in sorted(app.rglob('*'), key=lambda p: len(p.parts), reverse=True):
            if not path.is_file() or path.is_symlink() or path in [main_binary, preview_binary]:
                continue
            with path.open('rb') as source:
                magic = source.read(4)
            if magic in MACHO:
                sign(path, 'node' if path == app / 'Contents/MacOS/node' else None)
        for path in sorted(app.rglob('*.bundle'), key=lambda p: len(p.parts), reverse=True):
            sign(path)
        if preview.exists():
            sign(preview, 'preview')
        sign(app, 'app' if hardened else None)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)


if __name__ == '__main__':
    main()
