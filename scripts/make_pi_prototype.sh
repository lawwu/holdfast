#!/bin/bash
# Compatibility build entry point. The standard app now uses regular Pi too.
set -euo pipefail
cd "$(dirname "$0")/.."
export HOLDFAST_APP="${HOLDFAST_PI_APP:-build/Holdfast Pi.app}"
export HOLDFAST_BUNDLE_ID="${HOLDFAST_BUNDLE_ID:-app.holdfast.pi-regular}"
export HOLDFAST_APP_NAME="${HOLDFAST_APP_NAME:-Holdfast Pi}"
export HOLDFAST_DERIVED_DATA="${HOLDFAST_DERIVED_DATA:-.build/harness-xcode}"
exec bash scripts/make_app.sh "$@"
