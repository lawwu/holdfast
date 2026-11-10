#!/bin/bash
# Build holdfast and wrap it as build/Holdfast.app (ad-hoc signed, for this Mac only).
# The same binary is the CLI and the app: launched from a .app it opens the window.
set -euo pipefail
cd "$(dirname "$0")/.."
DERIVED="${HOLDFAST_DERIVED_DATA:-.build/xcode}"
if [[ "${1:-}" != "--package-only" ]]; then
  npm ci --prefix Runtime/pi --omit=dev --ignore-scripts --no-audit --no-fund
  xcodebuild -scheme holdfast -destination 'platform=macOS' -configuration Release \
    -derivedDataPath "$DERIVED" -clonedSourcePackagesDirPath .build/xcode/SourcePackages \
    -skipMacroValidation -skipPackagePluginValidation DEBUG_INFORMATION_FORMAT=dwarf build -quiet
fi
P="$DERIVED/Build/Products/Release"
APP="${HOLDFAST_APP:-build/Holdfast.app}"
BUNDLE_ID="${HOLDFAST_BUNDLE_ID:-app.holdfast}"
APP_NAME="${HOLDFAST_APP_NAME:-Holdfast}"
test -x "$P/holdfast"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$P/holdfast" "$APP/Contents/MacOS/holdfast"
# SwiftPM resource bundles (MLX's Metal shaders, tokenizer resources). MLX looks
# next to the binary, SwiftPM's Bundle.module in Resources: put them in both.
for b in "$P"/*.bundle; do
  cp -R "$b" "$APP/Contents/Resources/"
  cp -R "$b" "$APP/Contents/MacOS/"
done
bash scripts/bundle_pi_runtime.sh "$APP"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>holdfast</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
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
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
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
ENT=$(mktemp -t holdfast-ent)
cat > "$ENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/></dict></plist>
PLIST
# App icon: drawn by scripts/make_icon.swift (the same mark the app shows) into AppIcon.icns.
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
swiftc Sources/holdfast/AppIcon.swift scripts/make_icon.swift -o "$(dirname "$ICONSET")/make-icon"
"$(dirname "$ICONSET")/make-icon" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"
# Sign inside-out: the resource bundles, the extension (with its sandbox), then the app.
for b in "$APP"/Contents/MacOS/*.bundle "$APP"/Contents/Resources/*.bundle; do codesign --force --sign - "$b" >/dev/null; done
codesign --force --sign - --entitlements "$ENT" "$EXT" >/dev/null
rm -f "$ENT"
codesign --force --sign - "$APP" >/dev/null
# Register the preview with Quick Look (a built app outside /Applications isn't picked up on its own).
pluginkit -a "$EXT" 2>/dev/null || true
qlmanage -r >/dev/null 2>&1 || true
echo "$PWD/$APP"
