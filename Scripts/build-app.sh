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

# Embed Sparkle.framework. SPM links against it but does not copy it into
# the .app bundle for us.
SPARKLE_FRAMEWORK="$(swift build -c "$CONFIG" --product AspaceApp --show-bin-path)/Sparkle.framework"
if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
  mkdir -p "$OUT/Contents/Frameworks"
  cp -R "$SPARKLE_FRAMEWORK" "$OUT/Contents/Frameworks/Sparkle.framework"
  echo ">> Embedded Sparkle.framework"
fi

# Sparkle update configuration. SUFeedURL is always set so the app knows
# where to look; SUPublicEDKey is only added when SPARKLE_PUBLIC_KEY is
# provided (typically by CI from a secret). Without the key Sparkle will
# refuse to install updates, which is the safe default for local builds.
SU_FEED_URL="${SPARKLE_FEED_URL:-https://raw.githubusercontent.com/asumaran/aspace/main/appcast.xml}"
SPARKLE_PLIST_KEYS=""
SPARKLE_PLIST_KEYS+="    <key>SUFeedURL</key>
    <string>${SU_FEED_URL}</string>
"
if [[ -n "${SPARKLE_PUBLIC_KEY:-}" ]]; then
  SPARKLE_PLIST_KEYS+="    <key>SUPublicEDKey</key>
    <string>${SPARKLE_PUBLIC_KEY}</string>
"
fi

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
${SPARKLE_PLIST_KEYS}</dict>
</plist>
PLIST

# Make the binary look for embedded frameworks in Contents/Frameworks.
# SPM links against Sparkle expecting an @rpath that includes this directory;
# without it dyld can't find the library at launch.
if [[ -d "$OUT/Contents/Frameworks/Sparkle.framework" ]]; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$OUT/Contents/MacOS/$APP_NAME" 2>/dev/null || true
fi

# Re-sign everything (framework first so the app's signature can include it).
if [[ -d "$OUT/Contents/Frameworks/Sparkle.framework" ]]; then
  codesign --force --deep --sign - "$OUT/Contents/Frameworks/Sparkle.framework" >/dev/null
fi
codesign --force --sign - "$OUT/Contents/MacOS/$APP_NAME" >/dev/null

echo ">> Done. Open with:  open $OUT"
