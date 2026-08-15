#!/bin/bash
# new_extension.sh — scaffold a known-valid extension package into Extensions/raw/.
#
# Usage:
#   ./scripts/new_extension.sh <name> [--type js|group|url] [--with-npm]
#
# Generates Extensions/raw/<Name>.openclipext/ with an openclip.json manifest (reverse-DNS
# identifier, bare SF Symbol icons) plus any script files, then prints the install command.
# --with-npm scaffolds a TypeScript + esbuild package (npm bundle); it implies --type js.
# No app-code changes.

set -euo pipefail

DEFAULT_TYPE="url"
NAME=""
TYPE=""
WITH_NPM=""

usage() {
    cat <<'EOF'
Usage: ./scripts/new_extension.sh <name> [--type js|group|url] [--with-npm]

  <name>                 Package name; also the directory name (<Name>.openclipext).
  --type <kind>          Action kind to scaffold: js | group | url (default: url).
  --with-npm             Scaffold a TypeScript + esbuild npm bundle (implies --type js);
                         build with 'npm install && npm run build' before installing.
  -h, --help             Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --with-npm)
            WITH_NPM="1"
            shift
            ;;
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

if [[ -n "$WITH_NPM" ]]; then
    [[ -z "$TYPE" || "$TYPE" == "js" ]] || { echo "Error: --with-npm implies --type js (got '$TYPE')" >&2; exit 1; }
    TYPE="js"
fi

[[ -n "$TYPE" ]] || TYPE="$DEFAULT_TYPE"

case "$TYPE" in
    js|group|url) ;;
    *) echo "Error: unknown type '$TYPE' (expected js|group|url)" >&2; exit 1 ;;
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
    js)
        if [[ -n "$WITH_NPM" ]]; then
            write_manifest <<EOF
{
  "identifier": "$IDENTIFIER",
  "name": "$NAME",
  "action": {
    "title": "$NAME",
    "icon": "function",
    "type": "javascript",
    "script": "dist/main.js"
  }
}
EOF
            write_file "package.json" <<EOF
{
  "name": "com-example-$SLUG",
  "version": "1.0.0",
  "private": true,
  "type": "commonjs",
  "scripts": {
    "build": "esbuild src/main.ts --bundle --format=cjs --platform=browser --target=es2020 --outfile=dist/main.js",
    "typecheck": "tsc --noEmit"
  },
  "devDependencies": {
    "esbuild": "^0.28.0",
    "typescript": "^5.0.0"
  }
}
EOF
            write_file "tsconfig.json" <<'EOF'
{
  "compilerOptions": {
    "target": "es2020",
    "module": "esnext",
    "moduleResolution": "bundler",
    "strict": true,
    "noEmit": true,
    "lib": ["es2020"],
    "skipLibCheck": true
  },
  "include": ["src"]
}
EOF
            mkdir -p "$DEST_DIR/src"
            write_file "src/main.ts" <<'EOF'
// OpenClip extension entry point. Build with: npm run build
// The bridge types (openclip, OpenClipAction) come from openclip.d.ts in this folder.
export const action: OpenClipAction = (selection, options) => {
  return selection.trim().toUpperCase();
};
EOF
            write_file "src/openclip.d.ts" <<'EOF'
// openclip.d.ts — Ambient type declarations for OpenClip JS extension authoring.
// The runtime does NOT consume this file; it exists so editors and `tsc --noEmit` understand
// the `openclip.*` bridge and the entry signature.

interface OpenClipApp {
  bundleID: string;
  name: string;
}

interface OpenClipInput {
  text: string;
  matchedText: string;
  captures: string[];
  app: OpenClipApp;
  isSecondaryClick: boolean;
}

type OpenClipOptionValue = string | boolean;

interface OpenClipOptions {
  [identifier: string]: OpenClipOptionValue;
}

interface OpenClipStatusRequest {
  reason?: string;
  missing?: string[];
}

interface OpenClipFetchResponse {
  status: number;
  ok: boolean;
  text(): Promise<string>;
  json(): Promise<unknown>;
}

interface OpenClipBridge {
  readonly input: OpenClipInput;
  readonly options: OpenClipOptions;
  option(id: string): OpenClipOptionValue | undefined;
  paste(text: string): void;
  copy(text: string): void;
  cut(): void;
  openURL(url: string): void;
  keyPress(key: string, modifiers?: string[]): void;
  runShortcut(name: string, input?: string): void;
  notify(title: string, body: string): void;
  shareService(identifier: string, text?: string): void;
  toast(message: string, style?: 'success' | 'error' | 'info', options?: { keepVisible?: boolean }): void;
  requireConfiguration(request: OpenClipStatusRequest): void;
  fetch(url: string, options?: Record<string, unknown>): Promise<OpenClipFetchResponse>;
}

declare const openclip: OpenClipBridge;

type OpenClipAction = (selection: string, options: OpenClipOptions) => string | void | Promise<string | void>;
EOF
            write_file ".gitignore" <<'EOF'
node_modules/
EOF
            write_file "README.md" <<EOF
# $NAME

OpenClip extension scaffolded with \`--with-npm\`. TypeScript entry at \`src/main.ts\`; the
manifest points at the bundled \`dist/main.js\`.

## Build contract

The shipped artifact is \`dist/main.js\` (the manifest's \`script\`). Always rebuild before installing:

    npm install        # once
    npm run build      # after every edit to src/

Install (after build):

    ./scripts/install_extension.sh <this-folder>
EOF
            echo "note: npm scaffold is validated post-build — run 'npm install && npm run build' before install_extension.sh"
        else
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
        fi
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

if [[ -z "$WITH_NPM" ]] && ! "$BASE_DIR/scripts/validate_extension.sh" "$DEST_DIR"; then
    rm -rf "$DEST_DIR"
    exit 1
fi

echo "Scaffolded $TYPE extension at: Extensions/raw/$NAME.openclipext/"
echo "Files:"
find "$DEST_DIR" -type f | sed "s|$BASE_DIR/||" | sed 's/^/  /'
echo
echo "Install it with:"
echo "  ./scripts/install_extension.sh Extensions/raw/$NAME.openclipext"