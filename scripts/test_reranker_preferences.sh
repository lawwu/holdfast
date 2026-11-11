#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/holdfast-reranker-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
  "$repo_dir/Sources/holdfast/RerankerModels.swift" \
  "$repo_dir/Tests/RerankerPreferencesTests.swift" -o "$test_dir/reranker-tests"
"$test_dir/reranker-tests"
