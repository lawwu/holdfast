#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/holdfast-migration-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
  "$repo_dir/Sources/holdfast/LegacyCompatibility.swift" \
  "$repo_dir/Sources/holdfast/Migrate.swift" \
  "$repo_dir/Sources/holdfast/Profile.swift" \
  "$repo_dir/Tests/NamingMigrationTests.swift" -o "$test_dir/migration-tests"
"$test_dir/migration-tests"
