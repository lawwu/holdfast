#!/usr/bin/env python3
"""Configure Sparkle only for signed distribution builds; never ship private keys."""
import base64
import json
import os
from pathlib import Path
import plistlib
import sys

ROOT = Path(__file__).resolve().parents[1]


def configure(app, env=os.environ):
    settings = json.loads((ROOT / 'packaging/sparkle.json').read_text())
    if len(base64.b64decode(settings['publicKey'], validate=True)) != 32:
        raise RuntimeError('Sparkle requires a 32-byte Ed25519 public key')
    path = app / 'Contents/Info.plist'
    info = plistlib.loads(path.read_bytes())
    enabled = (env.get('HOLDFAST_DISTRIBUTION') == '1'
               and env.get('HOLDFAST_SIGNING_IDENTITY', '-') != '-'
               and info['CFBundleIdentifier'] == 'app.holdfast')
    info.update(SUFeedURL=settings['feedURL'], SUPublicEDKey=settings['publicKey'],
                HoldfastUpdatesEnabled=enabled, SUAllowsAutomaticUpdates=False,
                SUEnableSystemProfiling=False, SUVerifyUpdateBeforeExtraction=True,
                SURequireSignedFeed=True)
    path.write_bytes(plistlib.dumps(info))


if __name__ == '__main__':
    configure(Path(sys.argv[1]))
