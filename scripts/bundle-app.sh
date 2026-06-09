#!/usr/bin/env bash
# Build the universal (x86_64 + arm64) release binary, assemble BwocMcc.app,
# ad-hoc codesign it, and produce a distributable zip under dist/.
# Prints the zip path to stdout; writes "<zip>.sha256" alongside it.
set -euo pipefail
cd "$(dirname "$0")/.."

VER="$(cat VERSION)"
APP_NAME="BwocMcc"
BUNDLE_ID="tech.bemind.bwoc-mcc"
DISPLAY_NAME="BWOC Control Center"

echo "▸ universal release build (x86_64 + arm64)…" >&2
swift build -c release --arch arm64 --arch x86_64 1>&2

BIN=".build/apple/Products/Release/${APP_NAME}"
DIST="dist"
STAGE="${DIST}/${APP_NAME}.app"

echo "▸ assembling ${APP_NAME}.app (v${VER})…" >&2
rm -rf "$DIST"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN" "$STAGE/Contents/MacOS/${APP_NAME}"

# Ship the desktop-mascot sprite atlas as a plain Resources file (Bundle.main),
# not a SwiftPM .bundle — codesign rejects the flat bundle as malformed.
cp "Sources/${APP_NAME}/Resources/mascot_sheet.png" "$STAGE/Contents/Resources/"
cat >"$STAGE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${DISPLAY_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VER}</string>
    <key>CFBundleVersion</key><string>${VER}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 BeMindLabs</string>
</dict>
</plist>
PLIST

echo "▸ codesigning (ad-hoc)…" >&2
# No --deep: the nested SwiftPM resource bundle is a flat data dir (no Contents/)
# that codesign --deep rejects; it's sealed as a resource of the app signature.
codesign --force --sign - "$STAGE" 1>&2

ZIP="${DIST}/${APP_NAME}-${VER}-universal.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$STAGE" "$ZIP"
shasum -a 256 "$ZIP" | awk '{print $1}' >"${ZIP}.sha256"

echo "$ZIP"
