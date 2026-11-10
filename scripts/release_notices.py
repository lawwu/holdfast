#!/usr/bin/env python3
"""Include the licenses of the Swift dependencies used by the release."""
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
app = Path(sys.argv[1]).resolve()
checkouts = root / '.build/xcode/SourcePackages/checkouts'
notices = app / 'Contents/Resources/ThirdPartyNotices'
notices.mkdir(parents=True, exist_ok=True)
lookup = {p.name.lower(): p for p in checkouts.iterdir() if p.is_dir()}
dependencies = json.loads((root / 'Package.resolved').read_text())['pins']
for dependency in dependencies:
    directory = lookup[dependency['identity'].lower()]
    licenses = sorted(p for p in directory.iterdir() if p.is_file()
                      and p.name.lower().startswith(('license', 'licence', 'copying', 'notice')))
    if not licenses:
        raise RuntimeError('Missing dependency license: ' + dependency['identity'])
    for source in licenses:
        (notices / (dependency['identity'] + '-' + source.name)).write_bytes(source.read_bytes())
(notices / 'Swift-dependencies.json').write_text(json.dumps(dependencies, indent=2) + '\n')
(notices / 'README.txt').write_text('Holdfast includes the dependency licenses in this folder.\n'
    'JavaScript dependency licenses are also included beside their packages in Resources/pi/node_modules.\n'
    'Model weights are downloaded separately and are not included in this installer.\n')
