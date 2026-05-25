#!/usr/bin/env bash
# Builds the aspace CLI and packages the menu bar app as a .app bundle.
# Stamps both binaries with `git describe` (or $VERSION) so they self-identify
# instead of reporting "dev".
#
# Run from the repo root:  ./Scripts/build-app.sh
#
# Output:
#   .build/<config>/aspace          (CLI binary, same one referenced by
#                                    ~/.local/bin/aspace if you symlinked it)
#   build/Aspace.app                (menu bar app bundle)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CONFIG=${CONFIG:-release}
APP_NAME="Aspace"
BUNDLE_ID="com.asumaran.aspace"

# Pick a version: explicit $VERSION wins, then `git describe --tags --dirty`,
# then a hardcoded fallback.
if [[ -z "${VERSION:-}" ]]; then
  VERSION="$(git describe --tags --dirty 2>/dev/null || echo dev)"
fi

# Stamp Sources/DisplayKit/Version.swift, restoring it after the build so
# the repo stays clean. Backup lives outside Sources/ so SPM doesn't warn
# about an unhandled file.
VERSION_FILE="Sources/DisplayKit/Version.swift"
VERSION_BAK="$(mktemp -t aspace-version)"
cp "$VERSION_FILE" "$VERSION_BAK"
trap 'mv "$VERSION_BAK" "$VERSION_FILE"' EXIT
cat > "$VERSION_FILE" <<EOF
public enum AspaceVersion {
    public static let current = "${VERSION}"
}
EOF
echo ">> Stamped Version.swift with: ${VERSION}"

echo ">> Building aspace CLI ($CONFIG)..."
swift build -c "$CONFIG" --product aspace

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
