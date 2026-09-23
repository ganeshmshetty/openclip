#!/bin/bash
# Fast local development build & run (No installation to /Applications required)

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "⚡️ Building Debug build..."
xcodegen
xcodebuild -scheme OpenClip -configuration Debug -destination 'platform=macOS,arch=arm64' build > /dev/null

# Ask Xcode where it just built, rather than globbing DerivedData: several OpenClip-*
# folders can exist (the hash changes with the project path) and picking the wrong one
# silently launches a stale binary.
BUILT_PRODUCTS_DIR="$(xcodebuild -scheme OpenClip -configuration Debug -destination 'platform=macOS,arch=arm64' -showBuildSettings 2>/dev/null | awk -F' = ' '/[[:space:]]BUILT_PRODUCTS_DIR = /{print $2; exit}')"
APP_PATH="$BUILT_PRODUCTS_DIR/OpenClip.app"

if [ ! -d "$APP_PATH" ]; then
  # Fall back to the most recently built bundle.
  APP_PATH="$(ls -dt "$HOME/Library/Developer/Xcode/DerivedData/OpenClip-"*/Build/Products/Debug/OpenClip.app 2>/dev/null | head -n 1)"
fi

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
  echo "Error: Could not find built OpenClip.app in DerivedData"
  exit 1
fi

echo "Terminating old instances & launching from DerivedData..."
pkill -f OpenClip || true
sleep 0.3
/usr/bin/python3 -c "import subprocess, sys; subprocess.Popen([sys.argv[1]], stdout=open('/tmp/openclip.log', 'a'), stderr=subprocess.STDOUT, start_new_session=True)" "$APP_PATH/Contents/MacOS/OpenClip"

echo "Running directly from: $APP_PATH (logs at /tmp/openclip.log)"


