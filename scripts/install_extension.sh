#!/bin/bash
# Helper script to install a local extension directory or snippet into ~/.openclip/extensions.
# Directory/zip packages are validated against the manifest rules before installing; a package
# that fails validation is rejected here (exit 1) instead of being copied and silently dropped
# by the app at load time.
# Usage: ./scripts/install_extension.sh <path_to_extension_or_script>

set -e

SRC_PATH="$1"

if [ -z "$SRC_PATH" ] || [ ! -e "$SRC_PATH" ]; then
    echo "Usage: ./scripts/install_extension.sh <path_to_extension_or_script>"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Resolve a directory to validate: the package itself, or the extracted contents of a .zip.
CHECK_DIR=""
CLEANUP_DIR=""
if [ -f "$SRC_PATH" ] && [[ "$SRC_PATH" == *.zip ]]; then
    CLEANUP_DIR="$(mktemp -d)"
    unzip -q -o "$SRC_PATH" -d "$CLEANUP_DIR"
    CHECK_DIR="$CLEANUP_DIR"
elif [ -d "$SRC_PATH" ]; then
    CHECK_DIR="$SRC_PATH"
fi

if [ -n "$CHECK_DIR" ]; then
    set +e
    "$SCRIPT_DIR/validate_extension.sh" "$CHECK_DIR"
    STATUS=$?
    set -e
    if [ -n "$CLEANUP_DIR" ]; then
        rm -rf "$CLEANUP_DIR"
    fi
    case $STATUS in
        0) ;;
        1)
            echo "Install aborted: extension failed validation." >&2
            exit 1
            ;;
        2)
            # No manifest found — a snippet/standalone script; install it as-is.
            ;;
    esac
fi

EXT_DIR="$HOME/.openclip/extensions"
mkdir -p "$EXT_DIR"

FILENAME="$(basename "$SRC_PATH")"
DEST_PATH="$EXT_DIR/$FILENAME"

echo "Installing $SRC_PATH to $DEST_PATH..."
# Replace any existing package wholesale: `cp -R src dest` nests inside an
# existing destination directory, which would leave stale files behind.
rm -rf "$DEST_PATH"
cp -R "$SRC_PATH" "$DEST_PATH"

echo "Extension installed to $DEST_PATH"
