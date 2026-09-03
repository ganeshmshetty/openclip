#!/bin/bash
# release_update.sh
#
# Builds a Release archive, ad-hoc signs it, zips it, generates a Sparkle
# appcast.xml signed with an Ed25519 private key, and packages a .dmg.
# The resulting .zip, .dmg, and appcast.xml are ready to upload to a GitHub Release.
#
# Prerequisites:
#   1. Generate Ed25519 keys once:
#        ./scripts/bin/generate_keys --account openclip
#      This saves the private key to your macOS Keychain and prints the public
#      key (add to Info.plist SUPublicEDKey).
#
#   2. For CI (GitHub Actions), export the private key as a secret:
#        SPARKLE_ED_PRIVATE_KEY=<base64 private key>
#
# Usage:
#   ./scripts/release_update.sh [version]
#
# Example:
#   ./scripts/release_update.sh 1.2.0
#   → build/release/OpenClip-v1.2.0.zip
#   → build/release/OpenClip-v1.2.0.dmg
#   → build/release/appcast.xml
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/release"
DERIVED_DATA="$PROJECT_DIR/build/DerivedData"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    # Read from project.yml MARKETING_VERSION
    VERSION=$(grep 'MARKETING_VERSION' "$PROJECT_DIR/project.yml" | head -1 | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
    if [ -z "$VERSION" ]; then
        echo "error: Could not determine version. Pass it as an argument: $0 <version>"
        exit 1
    fi
fi

echo "==> Generating Xcode project..."
xcodegen generate

echo "==> Building OpenClip v$VERSION (Release)..."
mkdir -p "$BUILD_DIR"
rm -rf "${BUILD_DIR:?}"/*

xcodebuild \
    -project "$PROJECT_DIR/OpenClip.xcodeproj" \
    -scheme OpenClip \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    build 2>&1 | tail -5

APP_PATH="$DERIVED_DATA/Build/Products/Release/OpenClip.app"
if [ ! -d "$APP_PATH" ]; then
    echo "error: Build did not produce OpenClip.app at $APP_PATH"
    exit 1
fi

echo "==> Ad-hoc signing (required for Apple Silicon)..."
codesign --force --deep -s - "$APP_PATH"

echo "==> Packaging OpenClip-v$VERSION.zip..."
ZIP_NAME="OpenClip-v$VERSION.zip"
cd "$BUILD_DIR"
# Remove stale files if present
rm -f "$ZIP_NAME" "$BUILD_DIR/appcast.xml"
rm -rf ~/Library/Caches/Sparkle_generate_appcast
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_NAME"

echo "==> Generating appcast.xml with Ed25519 signature..."

# Locate generate_appcast — first check scripts/bin, then SPM checkout, then /tmp/sparkle.
GENERATE_APPCAST=""
if [ -x "$SCRIPT_DIR/bin/generate_appcast" ]; then
    GENERATE_APPCAST="$SCRIPT_DIR/bin/generate_appcast"
elif [ -x "/tmp/sparkle/bin/generate_appcast" ]; then
    GENERATE_APPCAST="/tmp/sparkle/bin/generate_appcast"
else
    SPM_SPARKLE=$(find "$DERIVED_DATA/SourcePackages/artifacts" -name "generate_appcast" -type f 2>/dev/null | head -1)
    if [ -n "$SPM_SPARKLE" ]; then
        GENERATE_APPCAST="$SPM_SPARKLE"
    fi
fi

if [ -z "$GENERATE_APPCAST" ]; then
    echo "warning: generate_appcast not found. Download the Sparkle release archive:"
    echo "  curl -sL 'https://github.com/sparkle-project/Sparkle/releases/latest' | tar xJ -C /tmp/sparkle"
    echo ""
    echo "Zip created at: $BUILD_DIR/$ZIP_NAME"
    exit 1
fi

DOWNLOAD_PREFIX="https://github.com/ganeshmshetty/openclip/releases/download/v$VERSION/"

echo "==> Extracting release notes for v$VERSION from CHANGELOG.md..."
NOTES_FILE="$BUILD_DIR/OpenClip-v$VERSION.md"
awk -v ver="## v$VERSION" '
    $0 ~ ver { flag=1; next }
    flag && /^## v/ { flag=0 }
    flag && !/^---$/ { print }
' "$PROJECT_DIR/CHANGELOG.md" > "$NOTES_FILE"

if [ ! -s "$NOTES_FILE" ]; then
    echo "warning: No entry found for v$VERSION in CHANGELOG.md; generating default note."
    echo "OpenClip version $VERSION release." > "$NOTES_FILE"
fi

if [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
    printf '%s\n' "$SPARKLE_ED_PRIVATE_KEY" | "$GENERATE_APPCAST" \
        --ed-key-file - \
        --download-url-prefix "$DOWNLOAD_PREFIX" \
        --embed-release-notes \
        --full-release-notes-url "https://github.com/ganeshmshetty/openclip/releases/tag/v$VERSION" \
        -o appcast.xml \
        "$BUILD_DIR"
else
    "$GENERATE_APPCAST" \
        --account openclip \
        --download-url-prefix "$DOWNLOAD_PREFIX" \
        --embed-release-notes \
        --full-release-notes-url "https://github.com/ganeshmshetty/openclip/releases/tag/v$VERSION" \
        -o appcast.xml \
        "$BUILD_DIR"
fi

# Ensure sparkle:edSignature is present in the enclosure tag
if ! grep -q 'sparkle:edSignature=' "$BUILD_DIR/appcast.xml"; then
    SIGN_UPDATE=""
    if [ -x "$SCRIPT_DIR/bin/sign_update" ]; then
        SIGN_UPDATE="$SCRIPT_DIR/bin/sign_update"
    elif [ -x "/tmp/sparkle/bin/sign_update" ]; then
        SIGN_UPDATE="/tmp/sparkle/bin/sign_update"
    else
        SPM_SIGN_UPDATE=$(find "$DERIVED_DATA/SourcePackages/artifacts" -name "sign_update" -type f 2>/dev/null | head -1)
        if [ -n "$SPM_SIGN_UPDATE" ]; then
            SIGN_UPDATE="$SPM_SIGN_UPDATE"
        fi
    fi

    if [ -n "$SIGN_UPDATE" ] && [ -x "$SIGN_UPDATE" ]; then
        if [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
            SIG=$(printf '%s\n' "$SPARKLE_ED_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - -p "$BUILD_DIR/$ZIP_NAME" 2>/dev/null || true)
        else
            SIG=$("$SIGN_UPDATE" --account openclip -p "$BUILD_DIR/$ZIP_NAME" 2>/dev/null || true)
        fi
        if [ -n "$SIG" ]; then
            sed -i '' "s|type=\"application/octet-stream\"|type=\"application/octet-stream\" sparkle:edSignature=\"$SIG\"|g" "$BUILD_DIR/appcast.xml"
        fi
    fi
fi

if ! grep -q 'sparkle:edSignature=' "$BUILD_DIR/appcast.xml"; then
    echo "error: appcast.xml does not contain a valid sparkle:edSignature." >&2
    exit 1
fi

echo "==> Packaging OpenClip-v$VERSION.dmg..."
DMG_NAME="OpenClip-v$VERSION.dmg"
rm -f "$BUILD_DIR/$DMG_NAME"
STAGING_DIR="$(mktemp -d)"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname "OpenClip" -srcfolder "$STAGING_DIR" -ov -format UDZO "$BUILD_DIR/$DMG_NAME" > /dev/null
rm -rf "$STAGING_DIR"

echo ""
echo "==> Done! Release artifacts created:"
echo "    $BUILD_DIR/$ZIP_NAME"
echo "    $BUILD_DIR/$DMG_NAME"
echo "    $BUILD_DIR/appcast.xml"
