#!/bin/bash
# Package regular Pi and the current reusable provider; no Durable runtime or dev dependencies.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$1"
test -f Runtime/pi/node_modules/@earendil-works/pi-coding-agent/package.json
DEST="$APP/Contents/Resources/pi"
mkdir -p "$DEST"
cp Runtime/pi/{runner.mjs,package.json,package-lock.json} "$DEST/"
cp -R Runtime/pi/node_modules "$DEST/"
PACKAGE_STAGE="$(mktemp -d)"
trap 'rm -rf "$PACKAGE_STAGE"' EXIT
npm pack ./Packages/pi-swift-mlx --pack-destination "$PACKAGE_STAGE" --ignore-scripts --json > "$PACKAGE_STAGE/pack.json"
PACKAGE_ARCHIVE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[0]["filename"])' "$PACKAGE_STAGE/pack.json")"
rm -rf "$DEST/node_modules/pi-swift-mlx"
mkdir -p "$DEST/node_modules/pi-swift-mlx"
tar -xzf "$PACKAGE_STAGE/$PACKAGE_ARCHIVE" -C "$DEST/node_modules/pi-swift-mlx" --strip-components=1
test ! -d "$DEST/node_modules/@earendil-works/pi-durable"
