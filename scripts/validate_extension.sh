#!/bin/bash
# validate_extension.sh — validate an extension package against the loader's manifest rules (via jq).
#
# Mirrors the checks the app's ManifestValidator + factory apply at load time:
#   * manifest must be valid JSON and resolve to openclip.json / manifest.json / Config.json
#   * required top-level fields (identifier, name), reverse-DNS identifier
#   * capabilities must be empty (host knows none)
#   * every action: recognized `type`, per-kind required fields, an executable payload
#   * group sub-actions are validated recursively
#   * option identifiers are unique and complete
#   * referenced script files must exist inside the package
#   * referenced local icon files must exist inside the package
#
# Usage: scripts/validate_extension.sh <extension-directory>
# Exit: 0 = manifest found and valid; 1 = manifest found but invalid; 2 = no manifest found.

set -u

SRC_DIR="${1:?Usage: validate_extension.sh <extension-directory>}"

if ! command -v jq >/dev/null 2>&1; then
    echo "validate_extension: jq is required but not installed" >&2
    exit 1
fi

if [ ! -d "$SRC_DIR" ]; then
    echo "validate_extension: not a directory: $SRC_DIR" >&2
    exit 1
fi

MANIFEST=""
for candidate in openclip.json manifest.json Config.json; do
    if [ -f "$SRC_DIR/$candidate" ]; then
        MANIFEST="$SRC_DIR/$candidate"
        break
    fi
done

if [ -z "$MANIFEST" ]; then
    echo "validate_extension: no manifest (openclip.json/manifest.json/Config.json) in $SRC_DIR" >&2
    exit 2
fi

if ! jq empty "$MANIFEST" >/dev/null 2>&1; then
    echo "validate_extension: $MANIFEST is not valid JSON" >&2
    exit 1
fi

JQ_PROGRAM=$(cat <<'EOF'
# ---- helpers ----
def sv: if type == "string" then . else "" end;
def is_blank: (type != "string") or (length == 0) or (test("^[[:space:]]*$"));
def has_script:     ((.script? | sv | is_blank | not));
def has_scriptCode: ((.scriptCode? | sv | is_blank | not));
def has_url:        ((.url? | sv | is_blank | not));
def has_payload: has_script or has_scriptCode or has_url;
def kind: ((.type // "url") | ascii_downcase);
def known_kinds: ["url","urltemplate","js","javascript","applescript","shell","shellinline","script","scriptfile","textsnippet","snippet","text","websearch","web","search","keypress","keys","shortcut","keyboardshortcut","service","servicemenu","group","subactions"];
def is_group: ((kind == "group") or (kind == "subactions"));
def secondary_types: ["copy","paste","openURL","toast","success","none"];
def toast_styles: ["success","error","info"];

# Option metadata must be complete and unique; malformed options reject the manifest at decode.
def option_dups($p):
  ((.options? // []) as $opts
   | [ $opts[] | select(((.identifier? | sv) | is_blank) or ((.label? | sv) | is_blank) or ((.type? | sv) | is_blank))
        | "\($p): option requires identifier, label, and type" ]
     + [ $opts | group_by(.identifier) | map(select(length > 1))
         | map("\($p): duplicate option identifier \"\(.[0].identifier)\"") ]);

# ---- per-action validation (recursive over subActions) ----
def check_action($p):
  . as $self |
  def subErrors:
    if ($self | is_group) and (($self.subActions? | type) == "array") then
      [$self.subActions
       | range(0; length) as $i
       | $self.subActions[$i] | check_action("\($p).subActions[\($i)]")]
      | add
    else [] end;
  def secondaryErrors:
    if (($self.secondary? | type) == "object") then
      [
        (($self.secondary.type? | sv) as $st |
         if ($st | is_blank) then
           "\($p): secondary requires a type (copy, paste, openURL, toast, success, or none)"
         elif (secondary_types | index($st)) == null then
           "\($p): unknown secondary type \"\($st)\" (expected copy, paste, openURL, toast, success, or none)"
         else empty end),
        (if (($self | kind) == "js" or ($self | kind) == "javascript") then
           "\($p): secondary is not supported on javascript actions; branch on openclip.input.isSecondaryClick in the script instead"
         else empty end)
      ]
    else [] end;
  def toastErrors($key):
    (($self[$key]? | type) == "object") as $present |
    if $present then
      [
        (($self[$key].style? | sv) as $ts |
         if ($ts | is_blank) then empty
         elif (toast_styles | index($ts)) == null then
           "\($p): unknown \($key).style \"\($ts)\" (expected success, error, or info)"
         else empty end)
      ]
    else [] end;
  def scriptErrors:
    if (($self.script? | sv) | is_blank | not) then
      (($self.script? | sv) as $sc |
       if ($sc | startswith("/")) or ($sc | startswith("~")) or ($sc | contains(":")) or ($sc | test("(^|/)\\.\\.(/|$)")) then
         ["\($p): script path escapes extension directory \"\($sc)\""]
       else [] end)
    else [] end;
  ($self | option_dups($p)) +
  [
    (($self.type // "url") | ascii_downcase) as $t |
    if (known_kinds | index($t)) == null then
      "\($p): unknown action type \"\($t)\""
    elif ($t == "keypress" or $t == "keys") then
      (if (($self.keyPress? | sv) | is_blank) then "\($p): missing required field keyPress" else empty end)
    elif ($t == "shortcut" or $t == "keyboardshortcut") then
      (if (($self.shortcutName? | sv) | is_blank) then "\($p): missing required field shortcutName" else empty end)
    elif ($t == "group" or $t == "subactions") then
      (if (($self.subActions? | type) != "array" or (($self.subActions // []) | length) == 0) then "\($p): group requires non-empty subActions" else empty end)
    elif ($t == "service" or $t == "servicemenu") then
      empty
    else
      (if ($self | has_payload | not) then "\($p): missing required payload (url, script, or scriptCode)" else empty end)
    end
  ] + secondaryErrors + toastErrors("toast") + toastErrors("secondaryToast") + toastErrors("secondary-toast") + scriptErrors + subErrors;

# ---- top-level ----
. as $m |
def manifest_actions:
  if (($m.actions? | type) == "array") then $m.actions
  elif (($m.action? | type) == "object") then [$m.action]
  else [] end;

[
  (if (($m.identifier? | sv) | is_blank) then "manifest: missing identifier" else empty end),
  (if (($m.identifier? | sv) | test("^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$") | not) then "manifest: identifier should be reverse-DNS (e.g. com.example.name)" else empty end),
  (if (($m.name? | sv) | is_blank) then "manifest: missing name" else empty end),
  (if (($m.capabilities? // []) | length) > 0 then "manifest: capabilities must be empty or absent (host knows none)" else empty end),
  ($m | option_dups("manifest")),
  (manifest_actions as $acts
   | if ($acts | length) == 0 then ["manifest: requires actions (array) or action (object)"]
     else [$acts | range(0; length) as $i | $acts[$i] | check_action("actions[\($i)]")] | add
     end)
]
| flatten
EOF
)

ERRORS="$(jq -r "$JQ_PROGRAM | .[]" "$MANIFEST" 2>/dev/null)"

if [ -n "$ERRORS" ]; then
    echo "validate_extension: $MANIFEST failed validation:" >&2
    printf '%s\n' "$ERRORS" >&2
    exit 1
fi

# Referenced script files must exist inside the package.
MISSING=""
UNSAFE=""
real_base="$(cd "$SRC_DIR" && pwd -P)"
while IFS= read -r script; do
    [ -n "$script" ] || continue
    case "$script" in
        /*|~*|*:*)
            UNSAFE="$UNSAFE unsafe script path: $script"
            continue
            ;;
    esac
    if [ ! -f "$SRC_DIR/$script" ]; then
        MISSING="$MISSING missing script file: $script"
    else
        real_script="$(cd "$(dirname "$SRC_DIR/$script")" 2>/dev/null && pwd -P)/$(basename "$script")"
        case "$real_script" in
            "$real_base"/*) ;;
            *) UNSAFE="$UNSAFE script path escapes extension directory: $script" ;;
        esac
    fi
done < <(jq -r '[.. | objects | .script?] | map(select(type == "string" and length > 0)) | unique[]' "$MANIFEST")

if [ -n "$UNSAFE" ]; then
    echo "validate_extension: $MANIFEST references unsafe script file(s):$UNSAFE" >&2
    exit 1
fi

if [ -n "$MISSING" ]; then
    echo "validate_extension: $MANIFEST references missing script file(s):$MISSING" >&2
    exit 1
fi

# Referenced local icon files must exist inside the package.
# Mirrors the host's ExtensionManager.parseIcon (see Constants.imageExtensions):
# a value ending with a known image extension is resolved as a local file inside
# the package directory; everything else — `symbol(...)` / `symbol:` prefixes,
# bare SF Symbol names, and HTTP(S) URLs — is a symbol and needs no file.
MISSING_ICON=""
while IFS= read -r icon; do
    [ -n "$icon" ] || continue
    case "$icon" in
        symbol\(*|symbol:*|http://*|https://*) continue ;;
    esac
    icon_lower="$(printf '%s' "$icon" | tr '[:upper:]' '[:lower:]')"
    case "$icon_lower" in
        *.png|*.jpg|*.jpeg|*.icns|*.gif|*.svg)
            if [ ! -f "$SRC_DIR/$icon" ]; then
                MISSING_ICON="$MISSING_ICON missing icon file: $icon"
            fi
            ;;
        *) continue ;;
    esac
done < <(jq -r '[.. | objects | .icon?] | map(select(type == "string" and length > 0)) | unique[]' "$MANIFEST")

if [ -n "$MISSING_ICON" ]; then
    echo "validate_extension: $MANIFEST references missing local icon file(s):$MISSING_ICON" >&2
    exit 1
fi

# require() targets referenced by package .js files must exist inside the package,
# including transitive dependencies: the host loader evaluates requires recursively
# from every loaded module (modulePrelude → __resolveModule), so a module that
# require()s another module must be scanned too. Best-effort: only string-literal
# './' / '../' specifiers are scanned; the host loader remains authoritative for
# resolution and containment.
MISSING_REQ=""
SCANNED=""
# Physical package root (resolves symlinks, like the host's standardizedFileURL) so
# queue paths and the SRC_DIR prefix strip stay aligned.
ABS_SRC="$(cd "$SRC_DIR" && pwd -P)"
# Worklist of relative .js paths still to scan, seeded with the manifest-referenced
# script files. Each item is appended with a trailing newline so the pop below is
# always able to advance (bash 3.2 has no arrays).
QUEUE=""
while IFS= read -r script; do
    [ -n "$script" ] || continue
    [ -f "$SRC_DIR/$script" ] || continue
    QUEUE="${QUEUE}${script}"$'\n'
done < <(jq -r '[.. | objects | .script?] | map(select(type == "string" and length > 0)) | unique[]' "$MANIFEST")

while [ -n "$QUEUE" ]; do
    js_file="${QUEUE%%$'\n'*}"
    QUEUE="${QUEUE#*$'\n'}"
    [ -n "$js_file" ] || continue

    # Cycle guard: require() graphs can be cyclic; skip files already scanned.
    if printf '%s\n' "$SCANNED" | grep -Fqx "$js_file"; then
        continue
    fi
    SCANNED="$SCANNED
$js_file"

    script_dir="$(dirname "$js_file")"
    while IFS= read -r spec; do
        [ -n "$spec" ] || continue
        target="$SRC_DIR/$script_dir/$spec"
        found=""
        if [ -f "$target" ]; then
            found="$target"
        elif [ -f "$target.js" ]; then
            found="$target.js"
        elif [ -d "$target" ] && [ -f "$target/index.js" ]; then
            found="$target/index.js"
        fi
        if [ -n "$found" ]; then
            # A resolved .js module may itself require() further files — queue it.
            # Normalize ./ and ../ segments (as the host loader does) so the
            # recursive dirname resolution stays clean.
            norm="$(cd "$(dirname "$found")" && pwd -P)/$(basename "$found")"
            case "$norm" in
                "$ABS_SRC"/*.js) QUEUE="${QUEUE}${norm#$ABS_SRC/}"$'\n' ;;
                *) MISSING_REQ="$MISSING_REQ $js_file -> require(\"$spec\")" ;;
            esac
        else
            MISSING_REQ="$MISSING_REQ $js_file -> require(\"$spec\")"
        fi
    done < <(grep -oE 'require\(\s*["'"'"']\.\.?/[^"'"'"']*["'"'"']' "$SRC_DIR/$js_file" | sed -E -e 's/^require\(\s*["'"'"']//' -e 's/["'"'"']\)?$//')
done

if [ -n "$MISSING_REQ" ]; then
    echo "validate_extension: $MANIFEST references missing require() targets:$MISSING_REQ" >&2
    exit 1
fi

# npm bundles: only when the manifest targets dist/ does package.json imply a build contract.
HAS_DIST_SCRIPT="$(jq -r '[.. | objects | .script?] | map(select(type == "string" and startswith("dist/"))) | length' "$MANIFEST")"
if [ "${HAS_DIST_SCRIPT:-0}" -gt 0 ] && [ -f "$SRC_DIR/package.json" ]; then
    if [ ! -f "$SRC_DIR/dist/main.js" ]; then
        echo "validate_extension: $MANIFEST requires a build — run 'npm install && npm run build' in $SRC_DIR" >&2
        exit 1
    fi
    if [ "$SRC_DIR/dist/main.js" -ot "$SRC_DIR/package.json" ]; then
        echo "validate_extension: WARNING: dist/main.js is older than package.json — rebuild with 'npm run build'" >&2
    fi
    if find "$SRC_DIR/src" -type f \( -name '*.js' -o -name '*.ts' \) -newer "$SRC_DIR/dist/main.js" -print -quit 2>/dev/null | grep -q .; then
        echo "validate_extension: WARNING: src/ is newer than dist/main.js — rebuild with 'npm run build'" >&2
    fi
fi

echo "validate_extension: OK ($MANIFEST)"
exit 0