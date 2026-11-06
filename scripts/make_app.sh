#!/bin/bash
# Build mackb and wrap it as build/Holdfast.app (ad-hoc signed, for this Mac only).
# Holdfast is the product name; mackb stays the codename (binary, CLI, bundle id, data folder).
# The same binary is the CLI and the app: launched from a .app it opens the window.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -scheme mac-kb -destination 'platform=macOS' -configuration Release \
  -derivedDataPath .build/xcode -skipMacroValidation -skipPackagePluginValidation build -quiet
P=.build/xcode/Build/Products/Release
APP=build/Holdfast.app
rm -rf "$APP" build/MacKB.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$P/mackb" "$APP/Contents/MacOS/mackb"
# SwiftPM resource bundles (MLX's Metal shaders, tokenizer resources). MLX looks
# next to the binary, SwiftPM's Bundle.module in Resources: put them in both.
for b in "$P"/*.bundle; do
  cp -R "$b" "$APP/Contents/Resources/"
  cp -R "$b" "$APP/Contents/MacOS/"
done
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Holdfast</string>
  <key>CFBundleDisplayName</key><string>Holdfast</string>
  <key>CFBundleIdentifier</key><string>net.lawrencewu.mackb</string>
  <key>CFBundleExecutable</key><string>mackb</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Holdfast transcribes recordings on this Mac.</string>
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
  <key>CFBundleIdentifier</key><string>net.lawrencewu.mackb.preview</string>
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
ENT=$(mktemp -t holdfast-ent).plist
cat > "$ENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/></dict></plist>
PLIST
# Sign inside-out: the resource bundles, the extension (with its sandbox), then the app.
for b in "$APP"/Contents/MacOS/*.bundle "$APP"/Contents/Resources/*.bundle; do codesign --force --sign - "$b" >/dev/null; done
codesign --force --sign - --entitlements "$ENT" "$EXT" >/dev/null
rm -f "$ENT"
codesign --force --sign - "$APP" >/dev/null
# Register the preview with Quick Look (a built app outside /Applications isn't picked up on its own).
pluginkit -a "$EXT" 2>/dev/null || true
qlmanage -r >/dev/null 2>&1 || true
echo "$PWD/$APP"
