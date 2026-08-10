#!/bin/bash
# new_extension.sh — scaffold a known-valid extension package into Extensions/raw/.
#
# Usage:
#   ./scripts/new_extension.sh <name> [--type canvas|js|group|url]
#
# Generates Extensions/raw/<Name>.openclipext/ with an openclip.json manifest (reverse-DNS
# identifier, bare SF Symbol icons) plus any script files, then prints the install command.
# No app-code changes.

set -euo pipefail

DEFAULT_TYPE="url"
NAME=""
TYPE=""

usage() {
    cat <<'EOF'
Usage: ./scripts/new_extension.sh <name> [--type canvas|js|group|url]

  <name>                 Package name; also the directory name (<Name>.openclipext).
  --type <kind>          Action kind to scaffold: canvas | js | group | url (default: url).
  -h, --help             Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --type)
            [[ $# -ge 2 ]] || { echo "Error: --type requires a value" >&2; exit 1; }
            TYPE="$2"
            shift 2
            ;;
        --type=*)
            TYPE="${1#*=}"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Error: unknown flag: $1" >&2
            exit 1
            ;;
        *)
            if [[ -z "$NAME" ]]; then
                NAME="$1"
            else
                echo "Error: unexpected argument: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

[[ -n "$NAME" ]] || { echo "Error: missing package name" >&2; usage >&2; exit 1; }
[[ -n "$TYPE" ]] || TYPE="$DEFAULT_TYPE"

case "$TYPE" in
    canvas|js|group|url) ;;
    *) echo "Error: unknown type '$TYPE' (expected canvas|js|group|url)" >&2; exit 1 ;;
esac

# Slug for the reverse-DNS identifier: lowercased, non-alphanumerics -> "-", trimmed.
slug() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed 's/--*/-/g; s/^-//; s/-$//'
}

SLUG="$(slug "$NAME")"
if [[ "$SLUG" == "com" || -z "$SLUG" ]]; then
    # A name that slugs to nothing (e.g. "123") would produce a malformed identifier.
    SLUG="ext"
fi
IDENTIFIER="com.example.$SLUG"

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="$BASE_DIR/Extensions/raw/$NAME.openclipext"

if [[ -e "$DEST_DIR" ]]; then
    echo "Error: $DEST_DIR already exists" >&2
    exit 1
fi

mkdir -p "$DEST_DIR"

write_manifest() {
    cat > "$DEST_DIR/openclip.json"
}

write_file() {
    cat > "$DEST_DIR/$1"
}

case "$TYPE" in
    canvas)
        write_manifest <<EOF
{
  "identifier": "$IDENTIFIER",
  "name": "$NAME",
  "action": {
    "title": "$NAME",
    "icon": "plusminus",
    "type": "canvas",
    "script": "main.js"
  }
}
EOF
        write_file "main.js" <<'EOF'
const initialState = { count: 0 };

const handlers = {
  increment(state)      { return { ...state, count: state.count + 1 }; },
  reset(state)          { return { ...state, count: 0 }; }
};

function ui(state, input) {
  return h('stack', { spacing: 8 }, [
    h('text', { content: 'Count: ' + state.count, style: 'title' }),
    h('stack', { orientation: 'horizontal', spacing: 8 }, [
      h('button', { title: '+1', handler: 'increment' }),
      h('button', { title: 'Reset', handler: 'reset', style: 'accent' })
    ])
  ]);
}
EOF
        ;;
    js)
        write_manifest <<EOF
{
  "identifier": "$IDENTIFIER",
  "name": "$NAME",
  "action": {
    "title": "$NAME",
    "icon": "function",
    "type": "javascript",
    "script": "main.js"
  }
}
EOF
        write_file "main.js" <<'EOF'
function action(text) {
  return text.trim().toUpperCase();
}
EOF
        ;;
    url)
        write_manifest <<EOF
{
  "identifier": "$IDENTIFIER",
  "name": "$NAME",
  "action": {
    "title": "$NAME",
    "icon": "globe",
    "type": "url",
    "url": "https://www.google.com/search?q={query}"
  }
}
EOF
        ;;
    group)
        write_manifest <<EOF
{
  "identifier": "$IDENTIFIER",
  "name": "$NAME",
  "action": {
    "title": "$NAME",
    "icon": "folder",
    "type": "group",
    "subActions": [
      {
        "id": "upper",
        "title": "UPPERCASE",
        "type": "javascript",
        "scriptCode": "function action(t){ return t.toUpperCase(); }"
      },
      {
        "id": "lower",
        "title": "lowercase",
        "type": "javascript",
        "scriptCode": "function action(t){ return t.toLowerCase(); }"
      }
    ]
  }
}
EOF
        ;;
esac

if ! "$BASE_DIR/scripts/validate_extension.sh" "$DEST_DIR"; then
    rm -rf "$DEST_DIR"
    exit 1
fi

echo "Scaffolded $TYPE extension at: Extensions/raw/$NAME.openclipext/"
echo "Files:"
find "$DEST_DIR" -type f | sed "s|$BASE_DIR/||" | sed 's/^/  /'
echo
echo "Install it with:"
echo "  ./scripts/install_extension.sh Extensions/raw/$NAME.openclipext"