#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/holdfast-crosslink-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
  "$repo_dir/Sources/holdfast/CrossLinkReply.swift" \
  "$repo_dir/Tests/CrossLinkReplyTests.swift" -o "$test_dir/crosslink-parser"
"$test_dir/crosslink-parser" "$@"
