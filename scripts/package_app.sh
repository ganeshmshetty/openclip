#!/bin/bash
# Builds OpenClip in Release mode and packages it into build/OpenClip.zip

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

DERIVED_DATA="$PROJECT_DIR/build/DerivedData"

echo "Generating Xcode project..."
xcodegen generate

echo "Building OpenClipAXHelper (Release)..."
xcodebuild -project OpenClip.xcodeproj -scheme OpenClipAXHelper -configuration Release -destination 'generic/platform=macOS' ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO -derivedDataPath "$DERIVED_DATA" build > /dev/null

echo "Building OpenClip (Release)..."
xcodebuild -project OpenClip.xcodeproj -scheme OpenClip -configuration Release -destination 'generic/platform=macOS' ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO -derivedDataPath "$DERIVED_DATA" build > /dev/null

BUILT_APP="$DERIVED_DATA/Build/Products/Release/OpenClip.app"
BUILT_HELPER="$DERIVED_DATA/Build/Products/Release/OpenClipAXHelper.app"

if [ ! -d "$BUILT_APP" ]; then
    echo "Error: Release build output for OpenClip.app not found at $BUILT_APP."
    exit 1
fi

if [ ! -d "$BUILT_HELPER" ]; then
    echo "Error: Release build output for OpenClipAXHelper.app not found at $BUILT_HELPER."
    exit 1
fi

echo "Embedding OpenClipAXHelper into OpenClip.app..."
mkdir -p "$BUILT_APP/Contents/Helpers"
rm -rf "$BUILT_APP/Contents/Helpers/OpenClipAXHelper.app"
cp -R "$BUILT_HELPER" "$BUILT_APP/Contents/Helpers/"

echo "Signing embedded helper and app bundle..."
codesign --force --deep --sign - "$BUILT_APP/Contents/Helpers/OpenClipAXHelper.app"
codesign --force --deep --sign - "$BUILT_APP"

echo "Verifying code signatures..."
codesign --verify --deep --strict "$BUILT_APP/Contents/Helpers/OpenClipAXHelper.app"
codesign --verify --deep --strict "$BUILT_APP"

mkdir -p "$PROJECT_DIR/build"
OUTPUT_ZIP="$PROJECT_DIR/build/OpenClip.zip"
OUTPUT_DMG="$PROJECT_DIR/build/OpenClip.dmg"

echo "Packaging $BUILT_APP into $OUTPUT_ZIP..."
ditto -c -k --sequesterRsrc --keepParent "$BUILT_APP" "$OUTPUT_ZIP"

echo "Packaging $BUILT_APP into $OUTPUT_DMG..."
STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT
cp -R "$BUILT_APP" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname "OpenClip" -srcfolder "$STAGING_DIR" -ov -format UDZO "$OUTPUT_DMG" > /dev/null

echo "Release packages created:"
echo "  ZIP: $OUTPUT_ZIP"
echo "  DMG: $OUTPUT_DMG"

