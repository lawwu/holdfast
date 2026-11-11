#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/holdfast-custom-model-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
# Foundation-only: no model download or GPU required.
xcrun swiftc -swift-version 5 -parse-as-library \
  "$repo_dir/Packages/LocalMLX/Sources/LocalMLX/LocalModelFiles.swift" \
  "$repo_dir/Sources/holdfast/CustomLocalModels.swift" \
  "$repo_dir/Tests/CustomLocalModelTests.swift" -o "$test_dir/custom-model-tests"
"$test_dir/custom-model-tests"
