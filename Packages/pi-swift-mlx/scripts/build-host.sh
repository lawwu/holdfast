#!/bin/bash
# Build from this package alone; no Holdfast checkout, app, or model download needed.
set -euo pipefail
PACKAGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${PI_MLX_DERIVED_DATA:-$PACKAGE_DIR/build/xcode}"
OUT="$PACKAGE_DIR/build/host"
SOURCE_OPTIONS=()
if [[ -n "${PI_MLX_SOURCE_PACKAGES:-}" ]]; then
  SOURCE_OPTIONS=(-clonedSourcePackagesDirPath "$PI_MLX_SOURCE_PACKAGES")
fi
cd "$PACKAGE_DIR/swift"
xcodebuild -scheme local-mlx-host -destination 'platform=macOS' -configuration Release \
  -derivedDataPath "$DERIVED" "${SOURCE_OPTIONS[@]}" -skipMacroValidation -skipPackagePluginValidation \
  DEBUG_INFORMATION_FORMAT=dwarf build -quiet
mkdir -p "$OUT"
cp "$DERIVED/Build/Products/Release/local-mlx-host" "$OUT/"
for bundle in "$DERIVED"/Build/Products/Release/*.bundle; do cp -R "$bundle" "$OUT/"; done
printf '%s\n' "$OUT/local-mlx-host"
