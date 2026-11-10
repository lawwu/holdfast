#!/bin/bash
# Use the sibling Swift package in a checkout, or the bundled source in an npm install.
set -euo pipefail
PACKAGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NATIVE="$PACKAGE_DIR/../LocalMLX"
if [[ ! -f "$NATIVE/Package.swift" ]]; then
  NATIVE="$PACKAGE_DIR/native/LocalMLX"
fi
if [[ ! -f "$NATIVE/scripts/build-host.sh" ]]; then
  printf '%s\n' 'The LocalMLX source bundle is missing. Install the packed pi-swift-mlx release or use a complete repository checkout.' >&2
  exit 1
fi
export LOCAL_MLX_DERIVED_DATA="${PI_MLX_DERIVED_DATA:-${LOCAL_MLX_DERIVED_DATA:-$PACKAGE_DIR/build/xcode}}"
export LOCAL_MLX_OUTPUT_DIR="${LOCAL_MLX_OUTPUT_DIR:-$PACKAGE_DIR/build/host}"
export LOCAL_MLX_SOURCE_PACKAGES="${PI_MLX_SOURCE_PACKAGES:-${LOCAL_MLX_SOURCE_PACKAGES:-}}"
exec bash "$NATIVE/scripts/build-host.sh" "$@"
