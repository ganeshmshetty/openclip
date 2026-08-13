#!/bin/bash
# Builds OpenClip in Release mode and packages it into build/OpenClip.zip

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "Generating Xcode project..."
xcodegen generate

echo "Building OpenClip (Release)..."
xcodebuild -project OpenClip.xcodeproj -scheme OpenClip -configuration Release -destination 'generic/platform=macOS' ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build > /dev/null

BUILT_APP="$(find ~/Library/Developer/Xcode/DerivedData/OpenClip-*/Build/Products/Release -name "OpenClip.app" | head -n 1)"

if [ -z "$BUILT_APP" ]; then
    echo "Error: Release build output not found."
    exit 1
fi

echo "Signing app bundle and embedded frameworks ad-hoc..."
codesign --force --deep --sign - "$BUILT_APP"

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

