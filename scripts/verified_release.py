"""Read and validate fresh installer evidence for packaging and publication.

Callers retain platform signature checks and publication policy. No accepted result
is cached: each invocation binds the reports to the bytes currently on disk.
"""
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re

INSTALLER_CHECKS = ('passed', 'payloadAndBundleValidated', 'bundledRuntimeValidated',
                    'approvalUndoStaleEditValidated', 'developerFallbacksDisabled')

@dataclass(frozen=True)
class VerifiedRelease:
    manifest: dict
    verification: dict
    installer: Path
    digest: str
    signed: bool


def verify_installer(folder, *, version=None, revision=None):
    folder = Path(folder).resolve()
    manifest = json.loads((folder / 'release-manifest.json').read_text())
    if manifest['sourceDirty']:
        raise RuntimeError('Build the release from the current committed source before uploading')
    if not re.fullmatch(r'\d+\.\d+\.\d+', manifest['version']):
        raise RuntimeError('Use a versioned installer built from committed source')
    if version is not None and manifest['version'] != version:
        raise RuntimeError('Manifest version does not match the release tag')
    if revision is not None and manifest['sourceRevision'] != revision:
        raise RuntimeError('Build the release from the current committed source before uploading')
    signed, notarized = manifest['developerIDSigned'], manifest['notarized']
    if type(signed) is not bool or type(notarized) is not bool or signed != notarized:
        raise RuntimeError('A release is either signed and notarized, or neither')
    name = manifest['installer']
    if not name or Path(name).name != name or name in ('.', '..'):
        raise RuntimeError('Installer must be a file in the release directory')
    installer = folder / name
    if installer.resolve().parent != folder:
        raise RuntimeError('Installer must be a file in the release directory')
    with installer.open('rb') as source:
        digest = hashlib.sha256()
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
        digest = digest.hexdigest()
    if digest != manifest['sha256']:
        raise RuntimeError('Installer checksum mismatch')
    if (folder / 'SHA256SUMS').read_text() != f'{digest}  {name}\n':
        raise RuntimeError('SHA256SUMS does not match the verified installer')
    verification = json.loads((folder / 'verification.json').read_text())
    if (verification.get('installerSHA256') != digest
            or verification.get('version') != manifest['version']
            or not all(verification.get(key) is True for key in INSTALLER_CHECKS)):
        raise RuntimeError('Run Tests/installer_integration.py against this exact installer first')
    return VerifiedRelease(manifest, verification, installer, digest, signed)
