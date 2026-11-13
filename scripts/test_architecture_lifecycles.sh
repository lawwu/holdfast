#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/holdfast-lifecycle-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
  "$repo_dir/Sources/holdfast/LoadedModel.swift" \
  "$repo_dir/Sources/holdfast/ModelDownloads.swift" \
  "$repo_dir/Sources/holdfast/ModelDownloadProgress.swift" \
  "$repo_dir/Tests/ArchitectureLifecycleTests.swift" -o "$test_dir/lifecycles"
"$test_dir/lifecycles"
xcrun swiftc -swift-version 5 -parse-as-library \
  "$repo_dir/Sources/holdfast/AudioSourceProcess.swift" \
  "$repo_dir/Tests/AudioSourceProcessTests.swift" -o "$test_dir/audio-source"
"$test_dir/audio-source"
