#!/bin/bash
# Build inference-only local-mlx-host and keep its Metal bundles beside the executable.
set -euo pipefail
PACKAGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${LOCAL_MLX_DERIVED_DATA:-$PACKAGE_DIR/build/xcode}"
OUT="${LOCAL_MLX_OUTPUT_DIR:-$PACKAGE_DIR/build/host}"
BUILD=(xcodebuild -scheme local-mlx-host -destination 'platform=macOS' -configuration Release
  -derivedDataPath "$DERIVED")
if [[ -n "${LOCAL_MLX_SOURCE_PACKAGES:-}" ]]; then
  BUILD+=(-clonedSourcePackagesDirPath "$LOCAL_MLX_SOURCE_PACKAGES")
fi
cd "$PACKAGE_DIR"
"${BUILD[@]}" -skipMacroValidation -skipPackagePluginValidation \
  DEBUG_INFORMATION_FORMAT=dwarf build -quiet
mkdir -p "$OUT"
cp "$DERIVED/Build/Products/Release/local-mlx-host" "$OUT/"
for bundle in "$DERIVED"/Build/Products/Release/*.bundle; do cp -R "$bundle" "$OUT/"; done
printf '%s\n' "$OUT/local-mlx-host"
