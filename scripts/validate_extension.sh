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
    else
      (if ($self | has_payload | not) then "\($p): missing required payload (url, script, or scriptCode)" else empty end)
    end
  ] + subErrors;

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
while IFS= read -r script; do
    if [ -n "$script" ] && [ ! -f "$SRC_DIR/$script" ]; then
        MISSING="$MISSING missing script file: $script"
    fi
done < <(jq -r '[.. | objects | .script?] | map(select(type == "string" and length > 0)) | unique[]' "$MANIFEST")

if [ -n "$MISSING" ]; then
    echo "validate_extension: $MANIFEST references missing script file(s):$MISSING" >&2
    exit 1
fi

echo "validate_extension: OK ($MANIFEST)"
exit 0