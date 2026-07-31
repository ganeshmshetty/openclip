#!/bin/bash
# Fast local development build & run (No installation to /Applications required)

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "⚡️ Building Debug build..."
xcodegen
xcodebuild -scheme OpenClip -configuration Debug -destination 'platform=macOS,arch=arm64' build > /dev/null

APP_PATH="$(find /Users/ganesh/Library/Developer/Xcode/DerivedData/OpenClip-*/Build/Products/Debug -name "OpenClip.app" | head -n 1)"

if [ -z "$APP_PATH" ]; then
  echo "Error: Could not find built OpenClip.app in DerivedData"
  exit 1
fi

echo "Terminating old instances & launching from DerivedData..."
pkill -f OpenClip || true
"$APP_PATH/Contents/MacOS/OpenClip" > /tmp/openclip.log 2>&1 &

echo "Running directly from: $APP_PATH (logs at /tmp/openclip.log)"
