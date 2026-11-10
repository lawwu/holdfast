#!/usr/bin/env python3
"""Bundle the pinned official Node binary; never copy a Homebrew-linked executable."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    app = Path(sys.argv[1]).resolve()
    metadata = json.loads((ROOT / 'packaging/node-runtime.json').read_text())
    cache = ROOT / 'build/downloads'
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / metadata['url'].rsplit('/', 1)[1]
    if not archive.exists():
        partial = archive.with_suffix('.download')
        try:
            subprocess.run(['/usr/bin/curl', '--fail', '--location', '--proto', '=https', '--tlsv1.2',
                            '--retry', '3', '--output', str(partial), metadata['url']], check=True)
            if hashlib.sha256(partial.read_bytes()).hexdigest() != metadata['sha256']:
                raise RuntimeError('Node archive checksum mismatch')
            partial.replace(archive)
        finally:
            partial.unlink(missing_ok=True)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != metadata['sha256']:
        raise RuntimeError('Cached Node archive checksum mismatch; remove it and retry')
    prefix = f"node-{metadata['version']}-darwin-{metadata['architecture']}"
    target = app / 'Contents/MacOS/node'
    notices = app / 'Contents/Resources/ThirdPartyNotices'
    notices.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive) as source:
        # Read only these exact members; no archive-controlled paths are extracted.
        target.write_bytes(source.extractfile(prefix + '/bin/node').read())
        (notices / 'Node-LICENSE.txt').write_bytes(source.extractfile(prefix + '/LICENSE').read())
    target.chmod(0o755)
    actual = subprocess.check_output([str(target), '--version'], text=True).strip()
    if actual != metadata['version']:
        raise RuntimeError('Bundled Node version does not match its pin')
    libraries = '\n'.join(subprocess.check_output(['/usr/bin/otool', '-L', str(target)], text=True).splitlines()[1:])
    if any(value in libraries for value in ['/opt/homebrew/', '/usr/local/', '/Users/']):
        raise RuntimeError('Bundled Node links to developer-machine libraries')
    (notices / 'Node-source.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print('Bundled official Node ' + actual)


if __name__ == '__main__':
    main()
