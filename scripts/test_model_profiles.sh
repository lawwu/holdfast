#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/holdfast-profile-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
  "$repo_dir/Packages/ModelProviders/Sources/ModelProviders/Inference.swift" \
  "$repo_dir/Packages/ModelProviders/Sources/ModelProviders/ModelProfile.swift" \
  "$repo_dir/Tests/ModelProfileTests.swift" -o "$test_dir/profile-tests"
"$test_dir/profile-tests"
