#!/bin/bash
# Build Holdfast.app. Local builds are ad-hoc signed; release builds can use Developer ID.
# The same binary is the CLI and the app: launched from a .app it opens the window.
set -euo pipefail
cd "$(dirname "$0")/.."
DERIVED="${HOLDFAST_DERIVED_DATA:-.build/xcode}"
APP_VERSION="${HOLDFAST_VERSION:-$(cat VERSION)}"
APP_BUILD_NUMBER="${HOLDFAST_BUILD_NUMBER:-$(git rev-list --count HEAD)}"
BUILD_OPTIONS=()
if [[ -n "${HOLDFAST_BUILD_JOBS:-}" ]]; then
  BUILD_OPTIONS+=(-jobs "$HOLDFAST_BUILD_JOBS")
fi
if [[ "${HOLDFAST_DISTRIBUTION:-0}" == "1" ]]; then
  export HOLDFAST_BUNDLE_NODE=1
  SWIFT_FLAGS='$(inherited) -D HOLDFAST_DISTRIBUTION'
  SWIFT_FLAGS+=" -file-prefix-map \"$PWD=/src/holdfast\" -debug-prefix-map \"$PWD=/src/holdfast\""
  BUILD_OPTIONS+=("OTHER_SWIFT_FLAGS=$SWIFT_FLAGS")
fi
if [[ "${1:-}" != "--package-only" ]]; then
  npm ci --prefix Runtime/pi --omit=dev --ignore-scripts --no-audit --no-fund
  xcodebuild -scheme holdfast -destination "platform=macOS,arch=$(uname -m)" -configuration Release \
    -derivedDataPath "$DERIVED" -clonedSourcePackagesDirPath .build/xcode/SourcePackages \
    -skipMacroValidation -skipPackagePluginValidation DEBUG_INFORMATION_FORMAT=dwarf \
    ${BUILD_OPTIONS[@]+"${BUILD_OPTIONS[@]}"} build -quiet
fi
P="$DERIVED/Build/Products/Release"
APP="${HOLDFAST_APP:-build/Holdfast.app}"
BUNDLE_ID="${HOLDFAST_BUNDLE_ID:-app.holdfast}"
APP_NAME="${HOLDFAST_APP_NAME:-Holdfast}"
test -x "$P/holdfast"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$P/holdfast" "$APP/Contents/MacOS/holdfast"
# Sparkle is dynamic; SwiftPM does not embed frameworks in this hand-built app bundle.
mkdir -p "$APP/Contents/Frameworks"
ditto .build/xcode/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"
# SwiftPM resource bundles (MLX's Metal shaders, tokenizer resources). MLX looks
# next to the binary, SwiftPM's Bundle.module in Resources: put them in both.
for b in "$P"/*.bundle; do
  cp -R "$b" "$APP/Contents/Resources/"
  cp -R "$b" "$APP/Contents/MacOS/"
done
bash scripts/bundle_pi_runtime.sh "$APP"
if [[ "${HOLDFAST_BUNDLE_NODE:-0}" == "1" ]]; then
  python3 scripts/bundle_node_runtime.py "$APP"
  python3 scripts/release_notices.py "$APP"
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>holdfast</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
  <key>CFBundleVersion</key><string>$APP_BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <!-- Citation and note links: selectable text hands link clicks to macOS, which sends them back here. -->
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>$BUNDLE_ID.links</string>
    <key>CFBundleURLSchemes</key><array><string>holdfast</string><string>holdfast-note</string><string>holdfast-rel</string></array>
  </dict></array>
  <key>NSAppTransportSecurity</key><dict>
    <!-- A model on another Mac: plain http on the home network and to Tailscale names (the tailnet encrypts). -->
    <key>NSAllowsLocalNetworking</key><true/>
    <key>NSExceptionDomains</key><dict>
      <key>ts.net</key><dict>
        <key>NSIncludesSubdomains</key><true/>
        <key>NSExceptionAllowsInsecureHTTPLoads</key><true/>
      </dict>
    </dict>
  </dict>
  <!-- holdfast listen: another app's audio (a call) and the microphone, transcribed on this Mac. -->
  <key>NSAudioCaptureUsageDescription</key><string>Holdfast transcribes a call or another app's audio on this Mac when you ask it to listen. Nothing is sent anywhere.</string>
  <key>NSMicrophoneUsageDescription</key><string>Holdfast transcribes your side of a call on this Mac when you ask it to listen. Nothing is sent anywhere.</string>
  <key>NSHumanReadableCopyright</key><string>“Prove all things; hold fast that which is good.” 1 Thessalonians 5:21</string>
</dict></plist>
PLIST
python3 scripts/configure_updates.py "$APP"
# Quick Look preview for Markdown (Space in Finder shows a note rendered): a
# data-based preview extension, built from QuickLook/ with swiftc, sandboxed as
# extensions must be. Signed before the app, so the app's signature covers it.
EXT="$APP/Contents/PlugIns/HoldfastPreview.appex"
mkdir -p "$EXT/Contents/MacOS"
swiftc -O -parse-as-library -application-extension -module-name HoldfastPreview \
  -target "$(uname -m)-apple-macos15.0" -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -framework QuickLookUI -Xlinker -e -Xlinker _NSExtensionMain \
  QuickLook/PreviewProvider.swift -o "$EXT/Contents/MacOS/HoldfastPreview"
cat > "$EXT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Holdfast Preview</string>
  <key>CFBundleDisplayName</key><string>Holdfast Preview</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID.preview</string>
  <key>CFBundleExecutable</key><string>HoldfastPreview</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
  <key>CFBundleVersion</key><string>$APP_BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSExtension</key><dict>
    <key>NSExtensionPointIdentifier</key><string>com.apple.quicklook.preview</string>
    <key>NSExtensionPrincipalClass</key><string>HoldfastPreview.PreviewProvider</string>
    <key>NSExtensionAttributes</key><dict>
      <key>QLIsDataBasedPreview</key><true/>
      <key>QLSupportedContentTypes</key><array><string>net.daringfireball.markdown</string></array>
      <key>QLSupportsSearchableItems</key><false/>
    </dict>
  </dict>
</dict></plist>
PLIST
# App icon: drawn by scripts/make_icon.swift (the same mark the app shows) into AppIcon.icns.
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
swiftc Sources/holdfast/AppIcon.swift scripts/make_icon.swift -o "$(dirname "$ICONSET")/make-icon"
"$(dirname "$ICONSET")/make-icon" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"
# Sign nested executables and native Node modules before signing their containers.
python3 scripts/sign_app.py "$APP"
# Register the preview with Quick Look (a built app outside /Applications isn't picked up on its own).
if [[ "${HOLDFAST_DISTRIBUTION:-0}" != "1" ]]; then
  pluginkit -a "$EXT" 2>/dev/null || true
  qlmanage -r >/dev/null 2>&1 || true
fi
case "$APP" in
  /*) echo "$APP" ;;
  *) echo "$PWD/$APP" ;;
esac
