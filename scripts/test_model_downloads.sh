#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/holdfast-download-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
  "$repo_dir/Sources/holdfast/LegacyCompatibility.swift" \
  "$repo_dir/Sources/holdfast/ModelDownloadSource.swift" \
  "$repo_dir/Tests/ModelDownloadSourceTests.swift" -o "$test_dir/download-tests"
"$test_dir/download-tests"

xcrun swiftc -swift-version 5 -parse-as-library \
  "$repo_dir/Sources/holdfast/ModelDownloadProgress.swift" \
  "$repo_dir/Tests/ModelDownloadProgressTests.swift" -o "$test_dir/progress-tests"
"$test_dir/progress-tests"

# Reuse the app's already-built Hub libraries; no MLX, GPU or real model needed.
if [[ "${1:-}" == "--integration" ]]; then
  products="$repo_dir/.build/xcode/Build/Products/Release"
  module_maps="$repo_dir/.build/xcode/Build/Intermediates.noindex/GeneratedModuleMaps"
  xcrun swiftc -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macos15.0" \
    -I "$products" -Xcc "-fmodule-map-file=$module_maps/yyjson.modulemap" \
    "$repo_dir/Sources/holdfast/LegacyCompatibility.swift" \
    "$repo_dir/Sources/holdfast/ModelDownloadSource.swift" \
    "$repo_dir/Sources/holdfast/ModelDownloadProgress.swift" \
    "$repo_dir/Sources/holdfast/ModelDownloader.swift" \
    "$repo_dir/Tests/ModelDownloadIntegration.swift" \
    "$products/Hub.o" "$products/HuggingFace.o" "$products/Jinja.o" \
    "$products/OrderedCollections.o" "$products/InternalCollectionsUtilities.o" \
    "$products/Crypto.o" "$products/EventSource.o" "$products/yyjson.o" \
    -o "$test_dir/download-integration"
  python3 "$repo_dir/Tests/model_download_integration.py" "$test_dir/download-integration"
fi
