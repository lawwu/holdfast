#!/bin/bash
# Build mackb and wrap it as build/MacKB.app (ad-hoc signed, for this Mac only).
# The same binary is the CLI and the app: launched from a .app it opens the window.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -scheme mac-kb -destination 'platform=macOS' -configuration Release \
  -derivedDataPath .build/xcode -skipMacroValidation -skipPackagePluginValidation build -quiet
P=.build/xcode/Build/Products/Release
APP=build/MacKB.app
rm -rf "$APP"
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
  <key>CFBundleName</key><string>MacKB</string>
  <key>CFBundleDisplayName</key><string>MacKB</string>
  <key>CFBundleIdentifier</key><string>net.lawrencewu.mackb</string>
  <key>CFBundleExecutable</key><string>mackb</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>MacKB transcribes recordings on this Mac.</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP" >/dev/null
echo "$PWD/$APP"
