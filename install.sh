#!/usr/bin/env bash
# Build, bundle, codesign, and install BwocMcc.app into /Applications, then
# relaunch it. Idempotent — safe to re-run after any code change.
#
#   ./install.sh            # release build → /Applications, relaunch
#   ./install.sh --login    # also register as a (hidden) Login Item
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="BwocMcc"
BUNDLE_ID="tech.bemind.bwoc-mcc"
DISPLAY_NAME="BWOC Control Center"
STAGE=".build/${APP_NAME}.app"
DEST="/Applications/${APP_NAME}.app"
VER="$(cat VERSION 2>/dev/null || echo 0.1.0)"

echo "▸ building release binary…"
swift build -c release

echo "▸ assembling ${APP_NAME}.app (v${VER})…"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp ".build/release/${APP_NAME}" "$STAGE/Contents/MacOS/${APP_NAME}"

# Ship the desktop-mascot sprite atlas as a plain Resources file (Bundle.main),
# not a SwiftPM .bundle — codesign rejects the flat bundle as malformed.
cp "Sources/${APP_NAME}/Resources/mascot_sheet.png" "$STAGE/Contents/Resources/"
cat > "$STAGE/Contents/Info.plist" <<PLIST
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

echo "▸ codesigning (ad-hoc)…"
# No --deep: the only nested "bundle" is the SwiftPM resource bundle, a flat
# data dir (no Contents/) that codesign --deep rejects as malformed. It's data,
# not code — sealing it as a resource of the app signature is enough.
codesign --force --sign - "$STAGE" >/dev/null

echo "▸ installing → ${DEST}"
pkill -x "$APP_NAME" 2>/dev/null && echo "  (stopped running instance)" || true
rm -rf "$DEST"
cp -R "$STAGE" "$DEST"

if [[ "${1:-}" == "--login" ]]; then
    echo "▸ registering Login Item…"
    osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"${DEST}\", hidden:true}" >/dev/null 2>&1 || true
fi

echo "▸ launching…"
open "$DEST"
sleep 1
if pgrep -x "$APP_NAME" >/dev/null; then
    echo "✅ ${APP_NAME} running — lotus icon is in your menu bar."
else
    echo "⚠️  ${APP_NAME} did not start — check Console.app for crash logs."
    exit 1
fi
