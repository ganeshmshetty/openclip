#!/bin/bash
# Helper script to install a local extension directory or snippet into ~/.openclip/extensions
# Usage: ./scripts/install_extension.sh <path_to_extension_or_script>

set -e

SRC_PATH="$1"

if [ -z "$SRC_PATH" ] || [ ! -e "$SRC_PATH" ]; then
    echo "Usage: ./scripts/install_extension.sh <path_to_extension_or_script>"
    exit 1
fi

EXT_DIR="$HOME/.openclip/extensions"
mkdir -p "$EXT_DIR"

FILENAME="$(basename "$SRC_PATH")"
DEST_PATH="$EXT_DIR/$FILENAME"

echo "Installing $SRC_PATH to $DEST_PATH..."
cp -R "$SRC_PATH" "$DEST_PATH"

echo "Extension installed to $DEST_PATH"
