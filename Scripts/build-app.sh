#!/usr/bin/env bash
# Wraps the SPM-built AspaceApp binary into a proper macOS .app bundle.
# Run from the repo root:  ./Scripts/build-app.sh
#
# Output: ./build/Aspace.app
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CONFIG=${CONFIG:-release}
APP_NAME="Aspace"
BUNDLE_ID="com.asumaran.aspace"
VERSION=${VERSION:-0.1.0}

echo ">> Building AspaceApp ($CONFIG)..."
swift build -c "$CONFIG" --product AspaceApp

BUILT_BIN="$(swift build -c "$CONFIG" --product AspaceApp --show-bin-path)/AspaceApp"
if [[ ! -x "$BUILT_BIN" ]]; then
  echo "Error: built binary not found at $BUILT_BIN" >&2
  exit 1
fi

OUT="build/${APP_NAME}.app"
echo ">> Assembling bundle at $OUT..."
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS"
mkdir -p "$OUT/Contents/Resources"

cp "$BUILT_BIN" "$OUT/Contents/MacOS/$APP_NAME"

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS will run it without Gatekeeper griping at us locally.
codesign --force --sign - "$OUT/Contents/MacOS/$APP_NAME" >/dev/null

echo ">> Done. Open with:  open $OUT"
