#!/usr/bin/env python3
"""Notarize a signed installer or disk image with Apple, then staple the ticket to it.

Credentials come from one of two places, so the same release scripts run on a Mac and in CI:
- HOLDFAST_NOTARY_PROFILE: a Keychain profile made with `xcrun notarytool store-credentials`.
- HOLDFAST_NOTARY_KEY, HOLDFAST_NOTARY_KEY_ID, HOLDFAST_NOTARY_ISSUER: an App Store Connect API
  key (.p8 file path, its key ID, and the issuer ID), as GitHub Actions uses.
"""
import json
import os
from pathlib import Path
import subprocess

KEY_VARIABLES = ['HOLDFAST_NOTARY_KEY', 'HOLDFAST_NOTARY_KEY_ID', 'HOLDFAST_NOTARY_ISSUER']


def credentials():
    """notarytool arguments for the configured credentials, or an error naming what is missing."""
    profile = os.environ.get('HOLDFAST_NOTARY_PROFILE')
    if profile and profile != '-':
        return ['--keychain-profile', profile]
    key, key_id, issuer = (os.environ.get(name) for name in KEY_VARIABLES)
    if key and key_id and issuer:
        if not Path(key).is_file():
            raise RuntimeError('HOLDFAST_NOTARY_KEY must be the path of an App Store Connect .p8 key')
        return ['--key', key, '--key-id', key_id, '--issuer', issuer]
    raise RuntimeError('A trusted release needs HOLDFAST_NOTARY_PROFILE, or HOLDFAST_NOTARY_KEY, '
                       'HOLDFAST_NOTARY_KEY_ID and HOLDFAST_NOTARY_ISSUER; see docs/releases.md')


def notarize(path, record_prefix):
    """Submit, wait, keep Apple's verdict and log beside the file, refuse anything not Accepted, staple."""
    path = Path(path)
    auth = credentials()
    result = subprocess.run(['xcrun', 'notarytool', 'submit', str(path), *auth, '--wait', '--output-format', 'json'],
                            check=True, capture_output=True, text=True)
    verdict = json.loads(result.stdout)
    folder = path.parent
    (folder / f'{record_prefix}.json').write_text(json.dumps(verdict, indent=2) + '\n')
    subprocess.run(['xcrun', 'notarytool', 'log', verdict['id'], *auth, str(folder / f'{record_prefix}-log.json')], check=True)
    if verdict.get('status') != 'Accepted':
        raise RuntimeError(f'Apple did not accept {path.name}; review {record_prefix}-log.json')
    subprocess.run(['xcrun', 'stapler', 'staple', str(path)], check=True)
    subprocess.run(['xcrun', 'stapler', 'validate', str(path)], check=True)
    return verdict
