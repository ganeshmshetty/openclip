#!/bin/bash
# Builds OpenClip in Release mode and packages it into build/OpenClip.zip

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "Generating Xcode project..."
xcodegen generate

echo "Building OpenClip (Release)..."
xcodebuild -project OpenClip.xcodeproj -scheme OpenClip -configuration Release -destination 'platform=macOS' build > /dev/null

BUILT_APP="$(find ~/Library/Developer/Xcode/DerivedData/OpenClip-*/Build/Products/Release -name "OpenClip.app" | head -n 1)"

if [ -z "$BUILT_APP" ]; then
    echo "Error: Release build output not found."
    exit 1
fi

mkdir -p "$PROJECT_DIR/build"
OUTPUT_ZIP="$PROJECT_DIR/build/OpenClip.zip"

echo "Packaging $BUILT_APP into $OUTPUT_ZIP..."
ditto -c -k --sequesterRsrc --keepParent "$BUILT_APP" "$OUTPUT_ZIP"

echo "Release package created at: $OUTPUT_ZIP"
