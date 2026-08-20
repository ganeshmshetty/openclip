# AGENTS.md — Authoring & Packaging OpenClip Extensions (Manifest Schema)

This file is the single source of truth for writing an OpenClip extension manifest by hand.
It is self-contained: every key, enum value, and JSON effect `type` string below was verified
against the source of truth (`Sources/Core/Extensions/Manifest/`, `DefaultActionFactory.swift`,
`OpenClipJSHost.swift`, `ActionResult.swift`, `ActionResultHandler.swift`, `ShellResultMapper`,
`ActionVisibility.swift`). Do not invent keys — if a field is not documented here, the decoder
ignores it.

Overrides user guidance: none. If any statement below conflicts with `AGENTS.md` at the repo root,
that root file wins (it is the higher-level, always-loaded contract); open an issue rather than
"fixing" it in a manifest.

---

## 1. What an extension is

An extension is a **directory** (conventionally named `<name>.openclipext`) containing an
`openclip.json` manifest plus optional script files and local image assets, copied into
`~/.openclip/extensions`. On startup the app scans that directory, decodes each manifest, and
registers one action (or, for a `group`, a group row plus its sub-actions) into the action menu.
Installing = placing the folder under `~/.openclip/extensions`; uninstalling = removing it. There
is no compilation, framework, or approval step — a manifest plus an optional script is a complete
extension.

---

## 2. Manifest structure

The loader decodes `~/.openclip/extensions/<dir>/openclip.json` (legacy names `manifest.json` and
`Config.json` are also accepted). Top level:

```jsonc
{
  // REQUIRED. Unique package id; also the prefix of every generated action id.
  // Accepts aliases: "id", "Identifier".
  "identifier": "com.example.words",

  // REQUIRED. Display name of the package. Aliases: "Name".
  "name": "Word Tools",

  // OPTIONAL. Declared package version. "version" is not used for loading; it is recorded in the
  // validation log line (e.g. "Loaded extension manifest <id> (v1.0.1, schema 1, ...)").
  "version": "1.0.0",

  // OPTIONAL. Minimum OpenClip version this package requires ("1.2.3"). Min-only and decode-only:
  // an incompatible package still loads but is gated "Needs Update" until the app is newer (see
  // §11). Absent or malformed → treated as compatible.
  "minOpenClipVersion": "1.2.3",

  // OPTIONAL. Declared runtime capabilities. The host's known-capability set is EMPTY on day one,
  // so any non-empty list here REJECTS the manifest at load time. Reserved for future use; do not
  // write it yet.
  "capabilities": [],

  // REQUIRED. Either an ARRAY of action objects ("actions"),
  // or a SINGLE action object ("action"). Alias: "Actions".
  "actions": [ /* ...one object per Action kind in §3... */ ],

  // OPTIONAL. Manifest-level option defaults, shared by all actions
  // (per-action `options` may override; see §4). Alias: "Options".
  "options": [ /* ...see §4... */ ]
}
```

Every action id is derived by the **uniform action-id rule** (`ExtensionManager.uniformActionID`):

- Explicit `metadata.id` wins.
  - If it contains a `.` it is used verbatim.
  - If it is a bare slug (no dot) it is prefixed: `"\(manifest.identifier).\(id)"`.
- Otherwise it is index-based: `"\(manifest.identifier).action.\(index)"`.

So with `identifier: "com.example.words"`, an action with `"id": "upper"` becomes
`com.example.words.upper`, and one with no `id` at index 0 becomes `com.example.words.action.0`.
Option values are keyed by this final action id at runtime.

---

## 3. Action kinds (`type`)

`type` is normalized case-insensitively (`ExtensionActionKind.init(rawType:)`); absent values
default to `url`. **Unknown/unsupported `type` strings now reject the whole package at load**
(via the manifest validation pass, `ManifestValidator`), instead of silently routing as `url`.
The former interactive-canvas kind `"canvas"` is rejected at validation with
`unknownActionKind("canvas")`. Recognized inputs for each kind:

| Kind | Accepted `type` strings | Runtime action |
| :--- | :--- | :--- |
| url | `url`, `urltemplate` | `URLTemplateAction` |
| javascript | `js`, `javascript` | `JavaScriptAction` (JavaScriptCore) |
| applescript | `applescript` | `AppleScriptAction` (NSAppleScript) |
| shell | `shellinline`, `shell`, `script`, `scriptfile` | inline `CustomAction` (zsh) or `ScriptAction` (file) |
| textsnippet | `textsnippet`, `snippet`, `text` | `CustomAction` text snippet |
| websearch | `websearch`, `web`, `search` | same as url (URL template) |
| keypress | `keypress`, `keys` | `KeyPressAction` |
| shortcut | `shortcut`, `keyboardshortcut` | `ShortcutAction` |
| service | `service`, `servicemenu` | `NamedServiceAction` |
| group | `group`, `subactions` | `GroupAction` row + sub-actions |

Common action fields (all OPTIONAL unless noted):

```jsonc
{
  "id": "com.example.words.upper",     // see §2 id rule
  "title": "UPPERCASE",                // shown in the menu; defaults to manifest.name
  "icon": "symbol(textformat.upper)",  // SF Symbol / local image / bare name (see below)
  "type": "javascript",                // default "url"
  "regex": ".*",                       // LEGACY pre-rules visibility gate (see §5)
  "secondary": { "type": "copy", "value": "Copied text" },  // secondary-click outcome; literal value, NON-JS kinds only (see §5b)
  "toast": { "message": "Copied" },    // primary-click toast (see §5b)
  "secondaryToast": { "message": "Copied" },  // secondary-click toast (see §5b)
  "requirements": { /* ... */ },       // see §5
  "options": [ /* per-action option overrides, see §4 */ ],
  "loading": true,                       // slow action: early-close + spinner toast, see §5d
  "loadingMessage": "Searching…"         // loading toast text; defaults to "Opening <title>…"
}
```

**Icons** (`parseIcon`): `symbol(Name)` → SF Symbol; a bare string (e.g. `"textformat.upper"`) is
treated as an SF Symbol too; a string ending in `.png`/`.jpg`/`.jpeg`/`.icns`/`.gif`/`.svg` is read
as a local file inside the package directory. Default symbol: `wand.and.stars`.

### 3a. url

```jsonc
{
  "title": "Search Wikipedia",
  "type": "url",
  "url": "https://en.wikipedia.org/wiki/Special:Search?search={query}"
}
```

The `url` value is a template with placeholders (see §6b). Selected text is inserted
percent-encoded; the action opens the URL. `websearch` behaves identically.

### 3b. javascript (inline or file)

```jsonc
{
  "title": "JSON Prettify",
  "type": "javascript",
  "scriptCode": "function action(sel) { try { return JSON.stringify(JSON.parse(sel), null, 2); } catch (e) { return 'invalid: ' + e.message; } }"
}
```

`scriptCode` holds the inline JS. **Alternate form**: omit `scriptCode` and set
`"script": "main.js"` — the file is read from the package directory and its `js` extension routes it
to the same runtime. Runs under the `openclip.*` bridge (§7). Option values are available as
`openclip.options` / `openclip.option(id)` (§4).

**Module mode (file scripts)**: a `script:` file action runs with CommonJS bindings in scope —
`require`, `module`, `exports`, `__dirname` — so code can be split across local files
(`require('./lib/helper.js')`). `require` resolves Node-style (exact file → `.js` append →
`dir/index.js`) relative to the requiring file, and modules are cached per run (cycles get partial
exports). Entry dispatch prefers `module.exports` as a function → `module.exports.action` →
`module.exports.main` → in-scope `action` → in-scope `main`. Containment is the **package
directory only**: `../` and symlink escapes are rejected (`.toast(.error)` with "resolves
outside the extension package"), as are absolute paths and bare specifiers — Node builtins (`fs`,
`os`, …) get an explicit "Node builtin" message, other bare names get "bundle npm libraries with
esbuild". Inline `scriptCode` actions have **no** modules (byte-identical legacy behavior). The full
contract is `docs/developer-guide/extensions-modules.md`.

**Async mode**: set `"async": true` to run the script asynchronously — the entry function may return
a `Promise` (which the host awaits) and a `fetch(url, options)` polyfill is available for HTTP calls
(§7). Without the flag, scripts run synchronously and a promise-like return is ignored.

### 3c. applescript (inline or file)

```jsonc
{
  "title": "New Note",
  "type": "applescript",
  "scriptCode": "tell application \"Notes\" to make new note with properties {body:OPENCLIP_TEXT}"
}
```

Inline via `scriptCode`, or file via `"script": "main.applescript"` (or `.scpt`). The script runs as
an `osascript` subprocess; the selection is injected as a top-level `property OPENCLIP_TEXT`
(accessible by the bare name `OPENCLIP_TEXT` — `openclip_text` is the same identifier, as
AppleScript names are case-insensitive), and
`{text}`/`{query}`/`{matched}`/`{captureN}` placeholders are substituted (unencoded, §6b). Both
authoring styles are supported: bare top-level statements **or** an explicit `on run … end run`
handler. A non-empty string the script returns becomes `.text` — implicitly returned text, delivered
per the user's per-click preference (preview/paste/copy, §5b), defaulting to today's paste behavior.
Errors become `.failure` (shown as an error toast).

### 3d. shell (inline or file)

```jsonc
{
  "title": "Count words",
  "type": "shell",
  "scriptCode": "echo \"$OPENCLIP_TEXT\" | wc -w"
}
```

- `type` `shell`/`shellinline` + `scriptCode` → runs inline under `/bin/zsh -c`.
- `type` `script`/`scriptfile`, or any unknown non-url kind with **no** `url`/`scriptCode`, reads the
  file named by `"script"` (default `script.sh`) from the package dir and runs it directly.

The command is executed **with a 30-second kill watchdog** (`Constants.scriptTimeout`) and a
non-zero exit surfaces as an error status. Selection/match data arrive via env vars (§6c), and
stdout is interpreted per §8 (JSON effects, plain-text implicit return, or empty-text success).

### 3e. textsnippet

```jsonc
{
  "title": "Wrap in blockquote",
  "type": "textsnippet",
  "scriptCode": "> {text}"
}
```

Holds a template in `scriptCode`; `{text}`/`{query}` etc. are substituted (unencoded) and the result
is implicitly returned (`.text`), delivered per the user's per-click preference (§5b).

### 3f. keypress

```jsonc
{
  "title": "Bold",
  "type": "keypress",
  "keyPress": "command+b"
}
```

`keyPress` is a `[modifier+]…key` string. Modifier tokens: `command`/`cmd`, `shift`,
`option`/`alt`, `control`/`ctrl`; the last token is the key. Examples: `"return"`, `"command+shift+v"`.
At run time the effect door posts a synthetic key event to the frontmost app. **Key names are
QWERTY/ANSI assumed** — letters `a–z` and digits `0–9` use the ANSI-QWERTY virtual-key layout, so a
non-QWERTY physical layout may remap them; named keys `return`/`enter`, `escape`/`esc`, `tab`,
`space`, `delete`/`backspace`, `forwarddelete`, `up`/`down`/`left`/`right`, `home`/`end`,
`pageup`/`pagedown` are handled. Unknown keys are skipped (no-op), never thrown.

### 3g. shortcut

```jsonc
{
  "title": "Run my shortcut",
  "type": "shortcut",
  "shortcutName": "Trim Whitespace"
}
```

Runs the named Shortcuts.app shortcut via `/usr/bin/shortcuts run`, passing the selection as input
(`-i` temp file). Executes under the same 30-second watchdog; a missing binary or non-zero exit
surfaces as an error status.

### 3h. service

```jsonc
{
  "title": "Share selection",
  "type": "service",
  "serviceName": "com.apple.Notes.SharingExtension"
}
```

`serviceName`, when set, is treated as a **sharing-service identifier** and invokes that service
directly via `NSSharingService(named:)` — e.g. `com.apple.Notes.SharingExtension` opens the Notes
**inline popup** with the selected text (the analogue of PopClip's `popclip.share`). If the name is
not a registered sharing service it falls back to a service-menu service via `NSPerformService`
(legacy service-menu names). Without `serviceName`, the kind maps to the generic macOS **share
picker** (`showServices`) on the selected text. Nothing is required.

### 3i. group

```jsonc
{
  "title": "Text tools",
  "type": "group",
  "subActions": [
    { "id": "upper", "title": "UPPERCASE", "type": "url", "url": "https://example.com/?q={text}" },
    { "id": "bold",  "title": "Bold",      "type": "keypress", "keyPress": "command+b" }
  ]
}
```

A group materializes as a **menu row that reveals a sub-menu** plus **one registry entry per
sub-action**. Membership is by the **ID-prefix convention**:

- group id = uniform id of the group (`manifest.identifier` + group id or `.action.<index>`),
- each sub-action id = `"\(groupID).\(subID)"` where `subID` is the sub-action's `id` (or its index).

For `identifier: "com.example.words"`, group `id:"tools"` → group id `com.example.words.tools` and
sub-action ids `com.example.words.tools.upper`, `com.example.words.tools.bold`.

There is **no `parentGroupID` field** — that design was deliberately deferred. Sub-actions are
matched to their group purely by this id-prefix. **Do not write a `parentGroupID` key.** Nested
groups are not flattened (a sub-action of kind `group` is skipped). The group row itself is
structural only — running it returns `.none`. The group row is registered by the factory's
`createActions` (the registry/loader path); the single-action seam treats a bare group as
schema-only (produces nothing).

### 3j. Sub-menu relevance (`menuRelevance`)

Any action — most usefully a sub-action inside a `group` — may declare one optional key that
dresses up how it appears in the group's sub-menu:

```jsonc
{
  "id": "upper",
  "title": "UPPERCASE",
  "type": "url",
  "url": "https://example.com/?q={text}",
  "menuRelevance": "\\S"                      // optional regex: only list when the selection matches
}
```

- **`menuRelevance`** (regex): when present, the sub-action is listed in the sub-menu only if the
  selected text (trimmed, case-insensitive, dot-matches-newlines) matches. Absent → always listed.
  A malformed pattern never hides the action (defensive). This is a *menu-time* filter only — it
  does not affect `requirements`-based visibility or the popup bar.

The builtin **Transform** group is the reference: its four case-conversion sub-actions
(UPPERCASE, lowercase, Title Case, camelCase) self-filter to no-ops. The factory wraps any action
declaring this key in a passive decorator that forwards the original action's identity and behavior
— registry sorting, disable, and perform are unaffected.

---

## 4. Options & requirements

### 4a. Option metadata (`ExtensionOptionMetadata`)

```jsonc
{
  "options": [
    {
      "identifier": "lang",          // REQUIRED. Option key. Aliases: "id", "Identifier".
      "label": "Language",           // REQUIRED. UI label. Aliases: "Label".
      "type": "string",              // OPTIONAL, default "string": "string"|"boolean"|"multiple"|"secret"
      "default": "en",               // OPTIONAL. Default value if unset. Aliases: "Default".
      "values": ["en", "fr", "es"]   // OPTIONAL. Picker choices for type "multiple". Aliases: "options", "Options".
    }
  ]
}
```

Manifest-level `options` are shared defaults; an action may declare its own `options` **overrides**
which replace manifest options with the same `identifier` in place (declaration order preserved,
action-only options appended). Option metadata lives in **Core** (`ExtensionOptionMetadata`), and
only the JSON manifest remains canonical — custom-actions JSON is retired.

### 4b. Secret vs non-secret storage

The app injects `KeychainActionOptionStore` (`AppDelegate`) into the factory. At runtime:

- **`type: "secret"`** values are read/written in the **macOS Keychain**, keyed by account
  `"action.<actionID>.option.<optionID>"` — they never reach UserDefaults. An empty secret value
  deletes the Keychain entry.
- **All other types** (`string`, `boolean`, `multiple`) are stored in `SettingsStore` under the
  same `"action.<actionID>.option.<optionID>"` key (`SettingKey.actionOption`). Values live in
  `~/.openclip` user defaults, never by direct `UserDefaults` calls.

The config sheet edits these through the same store, so a user's saved value is what the runtime
reads.

### 4c. `requirements` (`ActionRequirements`)

```jsonc
"requirements": {
  "regex": "^\\d+$",          // OPTIONAL. Gate on selection; see §5.
  "regexNegated": false,      // OPTIONAL, default false (alias "regex-negated").
  "apps": ["com.apple.Safari"], // OPTIONAL. Bundle-id list.
  "appsMode": "allow",        // OPTIONAL, default "allow": "allow"|"deny" (alias "apps-mode").
  "requiresSelection": true,  // OPTIONAL, default true (alias "requires-selection").
  "requiredOptions": ["lang"] // OPTIONAL. Option ids whose resolved value must be non-blank.
}
```

`requiredOptions` drives the **required-option UX**: at perform time, if any listed option's
resolved value is blank, the action short-circuits to the configuration sheet (`.openConfiguration`
with the missing ids) **before** any script runs, so the user is prompted to fill it in. (JS can
also request configuration at script time via `openclip.requireConfiguration` — §7.)

---

## 5. Visibility rules (when an action is shown)

`ActionVisibility.isEnabled` evaluates in this fixed order (pure function; no AppKit/UserDefaults):

1. **requiresSelection** (default `true`): an all-whitespace selection disables the action unless
   `requiresSelection: false`.
2. **apps allow/deny**: allow → enabled only in listed bundle ids; deny → disabled in listed ids.
3. **regex** (from `requirements.regex` or the legacy top-level `regex`): matched with
   `.dotMatchesLineSeparators, .caseInsensitive`; on success it builds the match info used for
   `{matched}`/`{captureN}` placeholders and capture env. `regexNegated: true` inverts enabled/disabled.

A malformed regex **enables** the action (defensive — a bad manifest never hides an action). With
**no** rules attached, every extension action defaults to "enabled iff a non-blank selection exists".

### 5b. Primary/secondary result delivery (`secondary`, `toast`, `secondaryToast`)

Every action run is a **delivery decision**: which result wins, and which companion toast (if any)
surfaces. The pipeline — **Select → Probe → Toast** — is decided once per run by
`ActionResultDelivery` (`Sources/Core/Actions/ActionResultDelivery.swift`) before the effect door
runs:

1. **Select** — a **secondary** activation (right-click or ⇧-click) uses the action's declared
   `secondary` outcome when one is declared; otherwise the raw runtime result wins, except a
   secondary click on a `.paste` primary derives `.copy` (**the paste→copy default**). A primary
   click always uses the raw result, so a non-paste primary with no declaration behaves the same on
   both clicks. An **implicitly returned `.text`** (JS string return, AppleScript output, shell
   stdout, text snippet) is resolved to preview/paste/copy by the **per-click preference** — the
   General tab's "When an action returns text" pickers (`primaryClickBehavior` for a primary click,
   `secondaryClickBehavior` for a secondary click; defaults primary=paste, secondary=copy); a
   `.preview` preference keeps the popup open for the card render instead of delivering.
2. **Apply probe** — a chosen `.paste` is downgraded to `.copy` whenever the target cannot paste.
   The **probe always applies**: to primary *and* secondary clicks, and to declared *and* derived
   pastes alike — a paste is never delivered to a target that can't paste. The unified
   `PasteAvailability` answer (a `denyPaste` per-app rule first, else the live `PasteAvailabilityProbe`
   reporting the AX Edit ▸ Paste disabled/unavailable) says no → `.copy`.
3. **Toast** — the click's declared toast (`toast` for primary, `secondaryToast` for secondary) wins;
   otherwise the default **"Copied"** toast fires only when a paste context was delivered as a copy
   (derived at select, declared, or downgraded by the probe) or a `.copyDefinition` is delivered.
4. **One toast per run** — a script-emitted `.toast` (JS `openclip.toast`, shell JSON `"toast"`)
   **suppresses** the delivery companion toast: nothing beyond the script's own toast surfaces. The
   precedence is **script toast > declared per-click toast (`toast`/`secondaryToast`) > default
   "Copied"**. The default "Copied" is a **delivery-side** fallback, not a script surface — it never
   overrides, or appears alongside, a script's own toast.

Only `.paste` outcomes are ever downgraded to `.copy`; an explicit `.copy` stays a copy, and
non-text results (openURL, notify, keyPress, …) pass through untouched.

**Implicit returned text is user-governed.** A runtime that "just returns a string" (JS string
return, AppleScript output, shell plain-text stdout, a text snippet) produces a `.text` result —
a *presentation* result that is not delivered directly. The user's **General-tab setting** ("When an
action returns text") decides, per click: **preview** (render the text in the native AI result card,
popup stays open), **paste** (probe applies as usual), or **copy**. Defaults: primary pastes,
secondary copies — identical to today. The picker never governs explicit outcomes (`openclip.paste`
effects, JSON effects, declared `secondary`, builtins); a declared `secondary` still wins for static
kinds even when the raw result is `.text`.

**Declarable keys** (per action, all optional). The factory wraps any action declaring them in a
`DeliveryDecoratedAction` carrying the mapped `ActionDelivery`; non-declaring actions stay plain
(nil delivery) and inherit the paste→copy default. Builtins declare delivery the same way
(`Action.delivery`).

- **`secondary`** — the secondary-click outcome. **Scoped to non-JS kinds:** a `javascript` action
  that declares `secondary` is rejected at install/load time (use the in-script
  `openclip.input.isSecondaryClick` branch instead, §5c). Shape:

  ```jsonc
  "secondary": {
    "type": "copy",        // "copy" | "paste" | "openURL" | "toast" | "success" | "none"
    "value": "Look up: https://example.com/search?q=selection",  // literal value for copy / paste / openURL
    "message": "…"         // message for type "toast"
  }
  ```

  `value` is a **literal string** — the factory maps it verbatim onto the `.copy`/`.paste`/`.openURL`
  payload (`DefaultActionFactory.actionResult(from:)`), so **no** `{text}`/`{query}` placeholder
  substitution happens for `secondary.value`. Use the JS `openclip.input.isSecondaryClick` branch or
  a script-side expression if you need the selection in the payload.

  Example — a Look Up action that opens the URL on primary click and copies on secondary:

  ```jsonc
  {
    "title": "Look Up",
    "type": "url",
    "url": "https://en.wikipedia.org/wiki/Special:Search?search={query}",
    "secondary": { "type": "copy", "value": "Look up: https://en.wikipedia.org/wiki/Special:Search?search=selection" }
  }
  ```

  > **Fail-open note:** a `secondary` of type `copy`/`paste`/`openURL` whose `value` is missing (or
  > an `openURL` with an unparseable `value`) silently becomes a no-op `.success` — declare `value`
  > for those types. `toast` reads `message`; `success`/`none` need neither.

- **`toast`** / **`secondaryToast`** — a one-line companion toast shown after the action completes,
  per click. Valid on **all** kinds. Shape:

  ```jsonc
  "toast": { "message": "Copied", "style": "success" },   // "success" | "error" | "info" (default success)
  "secondaryToast": { "message": "Copied", "style": "success" }
  ```

  `secondary-toast` (dash form) is accepted as an alias for `secondaryToast`. These are
  **delivery-side effects** — companion notices rendered by the floating toast surface,
  not new `ActionResult` cases (§8). They do not change dismissal.

**`after` is removed.** There is no `after` manifest key and no legacy result translator (the old
`after` orchestration step and its adapter were deleted). Copy/paste forcing is expressed three ways: a declared
`secondary` result (static kinds, above), the JS `openclip.input.isSecondaryClick` branch (JS,
§5c), or the derived paste→copy default (secondary click on a paste primary, no declaration).

The delivery inputs (click intent + app policy) are snapshotted when the action performs, *before*
dismissal `hide()` clears the session context, so the per-app `denyPaste` rule still applies to
pastes that dismiss the popup. The AI-result card's **Paste** button (and the built-in Paste/Cut
actions, all `PasteRequiringAction`s) is gated by the same **unified** answer (`PasteAvailability`,
pure Core): the `denyPaste` per-app rule wins over the live AX probe, and the probe is skipped
entirely when a rule answers — no Accessibility dependency for those apps. The trigger sites start
the probe in parallel with selection retrieval and apply it to `modeStore.canPaste` before the
first frame, so Paste/Cut never flash out after render; `false` hides the card's Paste button and
the bar/search drop Paste/Cut. Nothing is cached — with no rule the probe tracks the target app's
focus context, which can differ between shows in the same app. Card
Paste/Copy are explicit user requests: they carry no delivery context and are
never re-decided — an explicit Paste always pastes.

`.copy`/`.cut` and non-text results are never downgraded. This is a **presentation/delivery**
decision (App target only) — Core stays pure; `canPaste` and the app policy are injected inputs.
The per-app `denyPaste` toggle is user-editable in Preferences → Application Rules. Set
`deny-paste` only via `AppRule`; a manifest has **no** `denyPaste` delivery key (delivery is
declared via `secondary`/`toast`/`secondaryToast` above).

### 5c. JS: imperative secondary via `openclip.input.isSecondaryClick`

JavaScript actions cannot declare a manifest `secondary` (rejected at validation — see §5b). Instead
the secondary behavior is authored **imperatively** in the script: branch on the read-only
`openclip.input.isSecondaryClick` boolean (true for a right-click or ⇧-click) and emit an explicit
effect for each path — `openclip.paste(...)` for the primary, `openclip.copy(...)` for the
secondary — rather than relying on a string-return convention or a manifest `secondary`.

```javascript
function action(selection) {
  if (openclip.input.isSecondaryClick) {
    openclip.copy("Result: " + selection);   // secondary click → copy
  } else {
    openclip.paste("Result: " + selection);  // primary click → paste
  }
}
```

The chosen effect arrives at delivery as the action's primary result (`raw`); the paste→copy probe
and the click's declared `toast`/`secondaryToast` still apply to it exactly as for static kinds
(§5b). The non-secondary branch (the `else` above) is the primary behavior.

### 5d. `loading` (slow actions)

`loading: true` declares that an action is slow (e.g. an AppleScript that activates an app and
blocks until it launches). On click the popup closes immediately and a `[spinner] <message>`
toast appears; when the result lands the toast swaps to a description — "Copied" on a
paste→copy downgrade, or the action's error status — or fades when the result carries none
(`.success`, an opened URL, an honored paste, a native copy). It is presentation metadata only: when
the result lands, the resulting toast and the delivery companion follow the one-toast-per-run
precedence of §5b.

The spinner's message is `loadingMessage` when declared (a static string, used verbatim), otherwise
the host falls back to `Opening <title>…`. Example:

```json
{
  "action": {
    "title": "Apple Music",
    "type": "applescript",
    "script": "main.applescript",
    "loading": true,
    "loadingMessage": "Searching Apple Music…"
  }
}
```

The toast is a compact, single-line popup centered on the popup bar's frame (the anchor frame is
captured before the popup hides, so loading toasts that early-close still render where the popup
was; it never follows the live cursor). It renders `[icon | spinner] message` in one row with
modest vertical padding (never a multi-line sheet). The "Copied" toast renders a ✓ checkmark icon
**plus** the "Copied" text — the icon alone (bare right-mark) is not a valid representation — in
the theme's resting foreground (black on light, white on dark), not green. The toast is sized from
a laid-out content measurement (`layoutSubtreeIfNeeded()` before reading the hosting view's
`fittingSize`); reading `fittingSize` before a layout pass yields a stale, oversized frame. The
hosting view sits in a plain container so the window's constraint engine never tracks the SwiftUI
content (an `NSHostingView` as a direct contentView that re-measures during the display cycle
crashes with "marked as needing another Update Constraints in Window pass"). Info/error toasts
auto-dismiss after `PopupMetrics.toastDurationNanoseconds` (0.5 s); loading toasts have no timer
and stay until the result lands.

---

## 6. Data made available to actions

### 6a. Input context

Shared by all runtimes: the selected text, the regex-matched substring, regex capture groups, and
the source app's bundle id (see §5). The **JS host plus each script's env vars / globals** are the
two concrete exposure points (§7, §6c).

### 6b. Placeholders (`TextPlaceholderEngine`)

Used in URL templates, text snippets, and AppleScript:

| Placeholder | Meaning |
| :--- | :--- |
| `{text}`, `{query}` | the full selected text |
| `{matched}` | the regex-matched substring (full selection if no regex) |
| `{capture1}`…`{captureN}` or `{1}`…`{N}` | regex capture groups |
| `{bundleID}` | source app bundle identifier |

For `url` these are **percent-encoded**; for snippets/AppleScript they are substituted verbatim.

### 6c. Env vars (shell/script-file actions)

A script-file action (`ScriptAction`) and inline shell run with the selection on stdin and these env
vars: `OPENCLIP_TEXT`, `OPENCLIP_MATCHED`, `OPENCLIP_CAPTURE_1`…`N`, `OPENCLIP_BUNDLE_ID`,
`OPENCLIP_ACTION_ID`. The action id is the uniform/group id from §2.

---

## 7. The JavaScript `openclip.*` bridge (`OpenClipJSHost`)

Read-only input context:

- `openclip.input.text`, `openclip.input.matchedText`, `openclip.input.captures` (array),
  `openclip.input.app.bundleID`, `openclip.input.app.name`,
  `openclip.input.isSecondaryClick` (true on a right-click or ⇧-click — see §5c)
- `openclip.options` — `{ optionID: stringValue }` resolved through the option store
- `openclip.option(id)` — functional form returning the same value string

Entry points: the code is wrapped in an IIFE; if you define `action(selection, options)` or
`main(selection, options)` it is called with the selection and options dict; otherwise the top-level
code runs. A returned non-null string maps to `.text` (implicitly returned text — delivered per the
user's per-click preference, §5b). For a **file** script (`"script": "main.js"`),
the code runs in module mode and `require('./…')` is available for local files within the package
(§3b); inline `scriptCode` has no `require`.

**Async mode (`"async": true`)** — the entry function may return a `Promise`; the host awaits it and
a rejected promise surfaces as `.toast(.error)`. A script with no entry point (top-level side
effects only) still settles. Async scripts also get a `fetch(url, options)` polyfill bridged to
URLSession: `options` = `{ method, headers, body }` (default GET); the response is
`{ status, ok, text(): Promise<string>, json(): Promise<any> }`; network errors reject the promise.

Side effects (each appends an effect; multiple effects run as a `.sequence` in call order):

- `openclip.paste(text)`
- `openclip.copy(text)`
- `openclip.cut(text)`
- `openclip.openURL(url)`
- `openclip.keyPress(key, ["command","shift","option","control", ...])`
- `openclip.runShortcut(name)`
- `openclip.notify(title, body)`
- `openclip.shareService(identifier, text?)` — invoke a specific macOS sharing service by its
  identifier (e.g. `com.apple.Notes.SharingExtension` → the Notes inline popup). `text` defaults to
  the selected text when omitted.
- `openclip.toast(message, style?, options?)` — transient toast; style `"success"`|`"error"`|`"info"`
  (else `"info"`); `options = { keepVisible }` — `keepVisible: true` keeps the popup open (no
  auto-dismiss)
- `openclip.showContent(...)` / `h()` — **removed**: the interactive-canvas bridge no longer
  exists; calling these names surfaces a JS error (`.toast(.error)`).
- `openclip.requireConfiguration({ reason, missing: ["optID"] })` — open config sheet for this action

Deterministic resolution order (`OpenClipJSHost.run`): **JS exception → `.toast(.error)`** (JS throws
never propagate as Swift errors); else `requireConfiguration` → `.openConfiguration`; a `toast`
alone → `.toast`, or coexisting with effects → `.sequence([.toast, …effects])`; effects →
single/`sequence`; function string return → `.text(returnValue)` (implicitly returned text, resolved
per the click's preference); else `.success`.

> Execution runs on a background thread (never the `MainActor`); async scripts are guarded by a
> 30-second watchdog (`Constants.scriptTimeout`, `TimeoutFlag` pattern) — a never-settling promise
> surfaces as an error toast. Note the resolution above: a toast followed by an effect yields a
> sequence of both.

---

## 8. The ActionResult surface & JSON effect shapes

`ActionResult` cases an extension can produce (via JS effects, script JSON, declared `secondary`
outcomes, or kind runtimes):

| Case | Meaning |
| :--- | :--- |
| `.success` | no side effect |
| `.copy(String)` | copy to pasteboard |
| `.cut(String)` | copy + delete selection (delete key) |
| `.paste(String)` | paste text (replaces selection / frontmost app) |
| `.text(String)` | implicitly returned text (JS string return / AppleScript output / shell stdout / text snippet); no delivery decision — the per-click preference resolves it to preview/paste/copy |
| `.openURL(URL)` | open the URL |
| `.showServices(String)` | macOS share picker on the text |
| `.shareService(identifier:, text:)` | invoke a specific macOS sharing service by identifier (e.g. Notes inline popup) |
| `.notify(title:, body:)` | post a notification (best-effort; needs authorization) |
| `.toast(StatusFeedback)` | transient toast; **dismisses the popup by default**, `keepVisible: true` keeps it open |
| `.openConfiguration(ConfigurationRequest)` | hide popup, open the action's config sheet |
| `.sequence([ActionResult])` | run in order; popup hides only if all dismiss |
| `.keyPress(KeyPressSpec)` | post synthetic key event |
| `.runShortcut(name:, input:)` | run a Shortcuts shortcut with input |
| `.none` | no effect |

Dismissal: `.toast` dismisses the popup by default (`keepVisible: true` keeps it open); `.sequence`
dismisses only when non-empty and all items dismiss (a `keepVisible` toast forces it open);
everything else (including `.openConfiguration`) dismisses. `.text` never auto-dismisses (preview
keeps the popup open; paste/copy dismiss via the resolved outcome).

The **companion toast** resolved by delivery (the click's declared `toast`/`secondaryToast`, or the
default "Copied") is a **delivery-side effect** — it is rendered by the floating toast surface and is
*not* an `ActionResult` case, so it has no effect on dismissal. A script-emitted `.toast` suppresses
the companion entirely (one toast per run, §5b).

### 8a. Shell/script JSON protocol (`ShellResultMapper`)

A script command may emit one JSON object on stdout (all fields optional except `type`, and
except `shareService`'s `identifier`, which is required):

```jsonc
{ "type": "paste", "value": "text" }                                  // .paste
{ "type": "copy",  "value": "text" }                                  // .copy
{ "type": "openURL", "value": "https://..." }                         // .openURL
{ "type": "toast", "message": "Done", "style": "success", "keepVisible": true } // .toast — style "success"|"error"|"info"; keepVisible optional (default false)
{ "type": "configure", "reason": "...", "missing": ["opt"] }          // .openConfiguration
{ "type": "shareService", "identifier": "com.apple.Notes.SharingExtension", "value": "text" } // .shareService — identifier REQUIRED
```

Unknown `type` → `.success`. If stdout is **not** valid JSON, the plain text is **implicitly
returned** (`.text`, delivered per the user's per-click preference); empty
stdout → `.success`. A non-zero exit (or hitting the 30 s watchdog) becomes an error status. These
are the *only* script JSON `type` values the runtime accepts. **`"showContent"` is not one of
them** — a `"showContent"` type falls into the unknown branch and maps to `.success`.

**`"shareService"` requires a non-empty `identifier`** — a missing/empty one maps to an **error**
(failure status), never to `.success`. Its `value` is optional: the shared text falls back to
`input` if present, else the empty string.

---

## 9. Complete worked examples

### 9a. Minimal url extension

`~/wikipedia.openclipext/openclip.json`:

```jsonc
{
  "identifier": "com.example.wikipedia",
  "name": "Wikipedia",
  "actions": [
    { "title": "Look up", "icon": "symbol(book)", "type": "url",
      "url": "https://en.wikipedia.org/wiki/Special:Search?search={query}" }
  ]
}
```

Once installed, "Look up" opens Wikipedia for the selected text.

### 9b. Group + options + JS example

`~/case.openclipext/openclip.json`:

```jsonc
{
  "identifier": "com.example.case",
  "name": "Case Tools",
  "options": [
    { "identifier": "tc", "label": "Title-Case Words", "type": "boolean", "default": "true" }
  ],
  "actions": [
    {
      "title": "Case menu", "type": "group", "subActions": [
        { "id": "upper", "title": "UPPERCASE", "type": "javascript",
          "scriptCode": "function action(t){ return t.toUpperCase(); }" },
        { "id": "title", "title": "Title Case", "type": "javascript",
          "scriptCode": "function action(t){ if(openclip.options.tc==='true') return t.replace(/\\w\\S*/g,function(w){return w[0].toUpperCase()+w.slice(1);}); return t; }",
          "requirements": { "requiredOptions": ["tc"] } }
      ]
    }
  ]
}
```

### 9c. Secret option + shell JSON effect

```jsonc
{
  "identifier": "com.example.secret",
  "name": "Secret Echo (example)",
  "options": [ { "identifier": "api", "label": "API key", "type": "secret" } ],
  "actions": [
    { "title": "Ping (JSON)", "type": "shell",
      "scriptCode": "echo '{\"type\":\"toast\",\"message\":\"secret set\",\"style\":\"success\"}'" }
  ]
}
```

The `api` value is stored in the Keychain (never UserDefaults) and would be read in JS as
`openclip.options.api` / `openclip.option('api')`.

---

## 10. Develop / iterate / test workflow

1. **Scaffold or author** the folder. To start from a known-valid template, run
   `./scripts/new_extension.sh <Name> [--type js|group|url] [--with-npm]` — it writes a reverse-DNS
   `openclip.json` (+ `main.js` for js, or a TypeScript + esbuild `src/` package when `--with-npm`)
   into `Extensions/raw/<Name>.openclipext/` and runs the validator before reporting success (an npm
   scaffold is validated post-build — see below). To author by hand:
   `mkdir ~/my-ext.openclipext && nano ~/my-ext.openclipext/openclip.json`
   (plus any `script.sh`/`main.js`/scripts it references, and optional local icon files).
2. **Install** by copying into `~/.openclip/extensions`:
   `./scripts/install_extension.sh ~/my-ext.openclipext`
   (the script runs `cp -R` into `~/.openclip/extensions`; a `.zip` or standalone script file is
   unpacked/copied accordingly if installed through the app's installer). Before copying, directory
   and `.zip` sources are checked against the loader's manifest rules by
   `scripts/validate_extension.sh` — the same rejects (unknown `type`, missing required field or
   payload, bad/capability'd manifest, missing referenced script file, missing `require()` targets,
   npm package missing its built `dist/main.js`) the app applies at load, so
   an invalid package is **rejected here** (exit 1, nothing copied) instead of loading silently.
3. **Reload**: the app scans `~/.openclip/extensions` at **startup** (`ActionCoordinator`
   `loadInitialState` → `ExtensionManager.loadExtensions`), so quit and relaunch OpenClip, or
   trigger a reload from the Preferences → Extensions UI (the in-app install/uninstall paths call
   `loadExtensions` after mutation). A freshly launched app is the reliable check.
4. **Test**: select text anywhere, summon the popup, confirm the action appears and its enablement
   follows §5, then run it and inspect the effect (§8), including whether the popup hides or stays.
5. **Iterate**: edit the folder and relaunch/reload; no build is needed.

**npm / TypeScript bundles** (`--with-npm`): the scaffold writes a `package.json` + `src/` TypeScript
package whose manifest `script` points at `dist/main.js` — the **shipped artifact**. Build contract:
`npm install` once, `npm run build` after **every** edit to `src/`, **then**
`install_extension.sh`. `validate_extension.sh` rejects an npm package with no `dist/main.js` (exit 1,
"run 'npm install && npm run build'") and warns when it is stale versus `package.json`/`src/`.
TypeScript works only through this bundle path — the host loader runs `.js` only (esbuild transpiles
`.ts` to the CJS bundle); the ambient `openclip.*` types live in `src/openclip.d.ts`. Node builtins
are rejected at build time by esbuild's browser platform. See
`docs/developer-guide/extensions-modules.md`.

### Common failure modes

> `install_extension.sh`/`new_extension.sh` now surface most of these **before** the app loads them
> (via `scripts/validate_extension.sh`), so a rejected install is typically caught at install time.
> The load-time behavior below only applies to extensions that were never routed through the scripts
> — or to failures the shell validator can't see (e.g. JS syntax errors, runtime kinds).

- **Bad/invalid manifest = rejected and logged.** A manifest that fails to decode (malformed JSON,
  missing `identifier`/`name`) or fails validation (an unknown `type`, a `keypress`/`shortcut`
  missing its required field, an empty `group`, any `capabilities` entry) is **dropped as a whole**
  — the loader returns an empty action list, the scan continues, and the reason is logged under the
  `extensions` category (`log stream --predicate 'category == "extensions"'`). A typo in a key
  name or malformed JSON therefore looks like "my extension isn't there" — check the log.
- **Missing script file.** A `url`/`scriptCode`-less action that names a `script` file that doesn't
  exist (or is a directory / unreadable) is **not registered** at all, and the drop is logged
  (`factory` category).
- **Wrong `type`.** `type: "script"` with inline `scriptCode` is treated as a shell
  (`shell`/`shellinline`); to get JS you must use `"js"`/`"javascript"` (inline) or an actual
  `.js` file. Unused keys are ignored, not an error — but an **unknown** `type` string rejects the
  package.
- **`requiresSelection` gating.** With no `requirements` the default requires a non-blank selection;
  a selected-empty/app with no selection won't show the action. Set
  `requirements.requiresSelection: false` for always-on actions.
- **Non-zero exit / timeout.** A shell that exits non-zero or exceeds the 30 s watchdog surfaces an
  error status and does not leave the popup spinning.
- **keyPress on a non-QWERTY layout** may type the "wrong" key (ANSI mapping assumption, §3f).

---

## 11. Trust & consent lifecycle

Extensions are **fail-closed**: nothing in a package runs until the user **enables** it once. Each
package is tracked in `SettingsStore` by its `manifest.identifier` under three SettingKeys —
`extension.trust` (state), `extension.trustHashes` (content hash recorded at enable), and
`extension.sources` (`"store"`, `"package"`, or `"developer"`/`"local"`).

Per-package trust states:

- `seen` — detected but never enabled; its actions are gated (registered but not runnable).
- `trusted` — enabled; the package's content hash was recorded at enable time.
- `revoked` — explicitly disabled; stays disabled until re-enabled.

The single consent surface is the **trust model sheet**. How each install path reaches it:

- **Developer / Manual drop** (copy or author a folder in `~/.openclip/extensions`, source `"developer"`) → "New Extension"
  notification → clicking it opens the trust model → Enable → runs.
- **Install File…** (sideloaded archive, source `"package"`) → the trust model opens immediately (no notification) → Enable → runs.
- **Store install** (in-app catalog, source `"store"`) → the store click *is* consent: the package auto-trusts and runs immediately,
  with no trust model and no notification.

**Tamper-watch vs Live Hot-Reload**:
- **Store & Package extensions** (`"store"`, `"package"`): **Strict Tamper-Watch**. A `trusted` package whose files changed
  outside an official update flow is **auto-disabled** — trust flips back to `seen`, an "Extension Disabled" notification fires,
  and its actions are gated as `filesChanged`. Reviewing it in Preferences allows re-enabling.
- **Developer extensions** (`"developer"`, `"local"`): **Live Hot-Reload**. File edits during development are intentional; the
  gate automatically updates the stored SHA-256 fingerprint and hot-reloads the actions without gating, disabling, or sending spam alerts.

**`minOpenClipVersion`** is min-only and decode-only (§2): a package declaring a minimum newer than
the running app still loads but is gated "Needs Update" — its actions don't run until the app is
updated. Absent or malformed → compatible.

**Updates are manual and store-packages-only.** A store package gets a per-package **Update** button
next to Delete plus an **Update All**; there is no auto-update. An update is a fresh store install,
so it re-trusts with the new content hash — except a `revoked` package, which stays revoked.

**Migration**: the first launch after upgrade auto-trusts every package already present (one-time),
so pre-existing extensions keep working with zero action.

> Capability *enforcement* remains future work — consent today is binary (package-level trust), not
> per-capability. JIT permission prompts and gating of `fetch`/`keyPress`/`runShortcut` are not yet
> wired.

---

## 12. Do NOT

- **Do not put AppKit/SwiftUI in Core** — extension *parsing* (`OpenClipSnippetParser`) and model
  types in `Sources/Core/` are pure; keep them free of UI imports.
- **Do not write to `UserDefaults` directly** in extension code paths — Option storage goes through
  `ActionOptionStore`/`SettingKey`; secrets go through the Keychain store.
- **Do not skip the subprocess watchdog** — any new action that spawns a subprocess must terminate
  it past `Constants.scriptTimeout` (30 s). Existing shell/shortcut runtimes already do.
- **Do not `switch action.id`** for presentation decisions — use `action.chrome`, icons, and
  data-driven fields. The `chrome`/`rowStyle`/`popupBehavior`/`source` you may see in the code are
  **computed by the app**, not manifest keys: a manifest has **no** `chrome`, `subtitle`, `badge`,
  `keywords`, `gesturePolicy`, or `after` fields — do not write them (`after` was removed; delivery
  is declared via `secondary`/`toast`/`secondaryToast`, §5b).
- **Do not write a `parentGroupID`** — groups use the id-prefix convention only (§3i); it was
  deliberately deferred.
- **Do not invent JSON effect `type` strings** — the shell protocol accepts only the types in §8a.
- **Do not block inside JS** — the async watchdog kills never-settling promises after 30 s
  (`Constants.scriptTimeout`), but keep scripts fast; `"async": true` is required for any script
  that needs `fetch` or to await a promise.
- **Do not `require` bare or Node-builtin specifiers from a file script** — the host rejects them
  (Node builtins with a "Node builtin" message, other bare names with a "bundle npm libraries with
  esbuild" message); inline `scriptCode` has no `require` at all, and `require` may only reach files
  inside the package directory. See `docs/developer-guide/extensions-modules.md`.
- **Do not use `?key=` for Gemini/auth in URLs**; credentials go in headers, and secrets belong in
  Keychain-backed options, not in a manifest.

---

## 13. Source of truth recap (for confident auditing)

- Manifest model & decoding: `Sources/Core/Extensions/Manifest/ExtensionManifest.swift`,
  `ExtensionActionKind.swift`, `ActionRequirements.swift`; loading in
  `Sources/Core/Extensions/ExtensionManager.swift`.
- Kind→runtime routing + chrome + id rule: `Sources/OpenClip/Platform/Extensions/DefaultActionFactory.swift`.
- JS surface/resolution: `Sources/OpenClip/Platform/Runtimes/OpenClipJSHost.swift`.
- Module resolution & containment: `Sources/OpenClip/Platform/Runtimes/OpenClipModuleLoader.swift`.
- Effect execution: `Sources/OpenClip/Platform/Effects/ActionResultHandler.swift`.
- Result model: `Sources/Core/Actions/ActionResult.swift` (+ `StatusFeedback.swift`,
  `ConfigurationRequest.swift`).
- Delivery model (primary/secondary + per-click toasts): `Sources/Core/Actions/ActionDelivery.swift`,
  `Sources/Core/Actions/ActionResultDelivery.swift`, `Sources/Core/Actions/DeliveryDecoratedAction.swift`.
- AI result card (native SwiftUI): `Sources/OpenClip/UI/Popup/AIResultCardView.swift`.
- Visibility/required options: `Sources/Core/Actions/ActionVisibility.swift`, `ExtensionActionRules.swift`.
- Options storage: `Sources/Core/Settings/ActionOptionStore.swift`, `SettingKey.swift`,
  `Sources/OpenClip/Platform/Extensions/KeychainActionOptionStore.swift`.
- Shell JSON effects + watchdog: `Sources/Core/Extensions/ShellProcessRunner.swift`.