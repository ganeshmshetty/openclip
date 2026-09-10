#!/bin/bash
# Builds the styled OpenClip disk image (rendered background, icon layout, volume icon).
# Layout constants below must stay in sync with assets/dmg/background.html — see docs/dmg.md.
#
# Usage: ./scripts/make_dmg.sh <path-to-OpenClip.app> <output.dmg> [volume-name]

set -euo pipefail

APP_PATH="${1:-}"
OUTPUT_DMG="${2:-}"
VOLUME_NAME="${3:-OpenClip}"

if [ -z "$APP_PATH" ] || [ -z "$OUTPUT_DMG" ]; then
    echo "usage: $0 <path-to-OpenClip.app> <output.dmg> [volume-name]" >&2
    exit 2
fi

if [ ! -d "$APP_PATH" ]; then
    echo "error: app bundle not found at $APP_PATH" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# The background is drawn by Finder at its natural size, anchored to the top-left of the
# window's content area, and anything larger than that area makes the window scroll. The
# content area is the window height minus Finder chrome: a 28pt title bar, plus a ~36pt tab
# bar for users who leave "Show Tab Bar" on. So the window is sized taller than the canvas
# by CHROME_H, and the canvas bleeds to white so the leftover margin is invisible.
CANVAS_W=660
CANVAS_H=380
CHROME_H=68
WINDOW_W=$CANVAS_W
WINDOW_H=$((CANVAS_H + CHROME_H))
ICON_SIZE=128
TEXT_SIZE=13
ICON_Y=210
APP_X=170
DROP_X=490

# dmgbuild's hide_extensions is deliberately not used. It sets Finder's "hidden extension" bit,
# which is stored in a com.apple.FinderInfo extended attribute written onto the app bundle inside
# the image — and codesign counts that attribute as "resource fork, Finder information, or similar
# detritus not allowed", so `codesign --verify --strict` fails on the copy a user drags out of the
# DMG even though the same bundle verifies cleanly everywhere else. Finder hides .app extensions
# by default regardless, so the only people who saw a difference were those who had turned
# "Show all filename extensions" on, i.e. who asked to see it.
#
# dmgbuild writes the .DS_Store directly through the ds_store/mac_alias modules rather than
# driving Finder over AppleScript, so it needs no GUI session and only the items listed in
# icon_locations get a saved position. Leaving the hidden files (.background.tiff,
# .VolumeIcon.icns) unpositioned is what every shipping DMG does; give them one and Finder
# counts it towards the scrollable area, putting a scroll bar on the window for anyone
# browsing with hidden files shown.
DMGBUILD="$(command -v dmgbuild || true)"
if [ -z "$DMGBUILD" ]; then
    VENV_DIR="$PROJECT_DIR/build/.dmg-venv"
    if [ ! -x "$VENV_DIR/bin/dmgbuild" ]; then
        echo "==> Installing dmgbuild into build/.dmg-venv..."
        python3 -m venv "$VENV_DIR"
        "$VENV_DIR/bin/pip" install --quiet dmgbuild
    fi
    DMGBUILD="$VENV_DIR/bin/dmgbuild"
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> Rendering DMG background from assets/dmg/background.html..."
swift "$SCRIPT_DIR/render_html_png.swift" \
    "$PROJECT_DIR/assets/dmg/background.html" "$WORK_DIR/background.png" "$CANVAS_W" "$CANVAS_H" 1
swift "$SCRIPT_DIR/render_html_png.swift" \
    "$PROJECT_DIR/assets/dmg/background.html" "$WORK_DIR/background@2x.png" "$CANVAS_W" "$CANVAS_H" 2

# A multi-representation TIFF lets Finder pick the @2x rendition on Retina displays.
sips -s format tiff "$WORK_DIR/background.png" --out "$WORK_DIR/background-1x.tiff" > /dev/null
sips -s format tiff "$WORK_DIR/background@2x.png" --out "$WORK_DIR/background-2x.tiff" > /dev/null
tiffutil -cathidpicheck "$WORK_DIR/background-1x.tiff" "$WORK_DIR/background-2x.tiff" \
    -out "$WORK_DIR/background.tiff" > /dev/null

echo "==> Building volume icon..."
ICONSET="$WORK_DIR/VolumeIcon.iconset"
mkdir -p "$ICONSET"
for SPEC in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
    set -- $SPEC
    sips -z "$1" "$1" "$PROJECT_DIR/assets/app-icon.png" --out "$ICONSET/icon_$2.png" > /dev/null
done
iconutil -c icns "$ICONSET" -o "$WORK_DIR/VolumeIcon.icns"

APP_NAME="$(basename "$APP_PATH")"

cat > "$WORK_DIR/settings.py" <<PYTHON
format = "UDZO"
files = ["$APP_PATH"]
symlinks = {"Applications": "/Applications"}
icon = "$WORK_DIR/VolumeIcon.icns"
background = "$WORK_DIR/background.tiff"

default_view = "icon-view"
show_status_bar = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

window_rect = ((200, 100000), ($WINDOW_W, $WINDOW_H))
icon_size = $ICON_SIZE
text_size = $TEXT_SIZE
icon_locations = {
    "$APP_NAME": ($APP_X, $ICON_Y),
    "Applications": ($DROP_X, $ICON_Y),
}
PYTHON

echo "==> Packaging $(basename "$OUTPUT_DMG")..."
mkdir -p "$(dirname "$OUTPUT_DMG")"
rm -f "$OUTPUT_DMG"
"$DMGBUILD" -s "$WORK_DIR/settings.py" "$VOLUME_NAME" "$OUTPUT_DMG"

echo "==> DMG created: $OUTPUT_DMG"
