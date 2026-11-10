#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/holdfast-agent-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
  "$repo_dir/Sources/holdfast/AgentRuntime.swift" \
  "$repo_dir/Sources/holdfast/AgentJournal.swift" \
  "$repo_dir/Tests/AgentRuntimeTests.swift" -o "$test_dir/agent-tests"
"$test_dir/agent-tests"
