# AGENTS.md — Authoring & Packaging OpenClip Extensions (Manifest v2)

This file is the single source of truth for writing a **v2 manifest** OpenClip extension by hand.
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
  // validation log line (e.g. "Loaded extension manifest <id> (v1.0.1, schema 2, ...)").
  "version": "1.0.0",

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
Recognized inputs for each kind:

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
  "after": "copy-result",              // see §5b
  "stayVisible": true,                 // see §5b (alias "stay-visible")
  "requirements": { /* ... */ },       // see §5
  "options": [ /* per-action option overrides, see §4 */ ]
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
handler. A non-empty string the script returns becomes `.copy`. Errors become `.failure` (shown as
an error status).

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
stdout is interpreted per §8 (JSON effects, plain-text paste, or empty-text success).

### 3e. textsnippet

```jsonc
{
  "title": "Wrap in blockquote",
  "type": "textsnippet",
  "scriptCode": "> {text}"
}
```

Holds a template in `scriptCode`; `{text}`/`{query}` etc. are substituted (unencoded) and the result
is pasted, replacing the selection.

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
groups are not flattened in v1 (a sub-action of kind `group` is skipped). The group row itself is
structural only — running it returns `.none`. The group row is registered by the factory's
`createActions` (the registry/loader path); the single-action seam treats a bare group as
schema-only (produces nothing).

### 3j. Sub-menu relevance & preview (`menuRelevance`, `menuPreview`)

Any action — most usefully a sub-action inside a `group` — may declare two optional keys that
dress up how it appears in the group's sub-menu:

```jsonc
{
  "id": "upper",
  "title": "UPPERCASE",
  "type": "url",
  "url": "https://example.com/?q={text}",
  "menuRelevance": "\\S",                     // optional regex: only list when the selection matches
  "menuPreview": "{text} → {matched}"         // optional placeholder template shown as the row subtitle
}
```

- **`menuRelevance`** (regex): when present, the sub-action is listed in the sub-menu only if the
  selected text (trimmed, case-insensitive, dot-matches-newlines) matches. Absent → always listed.
  A malformed pattern never hides the action (defensive). This is a *menu-time* filter only — it
  does not affect `requirements`-based visibility or the popup bar.
- **`menuPreview`** (placeholder template): rendered with `TextPlaceholderEngine`
  (`{text}`/`{query}`/`{matched}`/`{captureN}`/`{bundleID}`) and shown as the sub-menu row's
  one-line subtitle. Absent → no subtitle.

The builtin **Transform** group is the reference: its four case-conversion sub-actions
(UPPERCASE, lowercase, Title Case, camelCase) self-filter to no-ops and preview the transformed
result. The factory wraps any action declaring these keys in a passive decorator that forwards the
original action's identity and behavior — registry sorting, disable, and perform are unaffected.

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

### 5b. `after` and `stayVisible`

`after` (`ActionAfterBehavior`, applied by `ActionResultAdapter`):

- `copy-result` — a paste/copy outcome becomes `.copy`.
- `paste-result` — a copy/paste outcome becomes `.paste`.
- `show-result` — a copy/paste outcome is rendered as a content canvas with Paste/Copy footer actions.
- `none` — collapse any result to success.
- `default` — unchanged. (Runtime presentations — content canvas/status/configuration/keyPress/shortcut/
  sequence/keepVisible — always pass through regardless of `after`.)

`stayVisible: true` wraps the (normalized) result in `.keepVisible` so the popup **stays open**
when it would otherwise dismiss. This is also how a plain-text script keeps the menu up after a
paste.

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
  `openclip.input.app.bundleID`, `openclip.input.app.name`
- `openclip.options` — `{ optionID: stringValue }` resolved through the option store
- `openclip.option(id)` — functional form returning the same value string

Entry points: the code is wrapped in an IIFE; if you define `action(selection, options)` or
`main(selection, options)` it is called with the selection and options dict; otherwise the top-level
code runs. A returned non-null string maps to `.copy`.

**Async mode (`"async": true`)** — the entry function may return a `Promise`; the host awaits it and
a rejected promise surfaces as `.showStatus(.error)`. A script with no entry point (top-level side
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
- `openclip.showStatus(message, style)` — style `"success"`|`"error"`|`"info"` (else `"info"`)
- `openclip.showContent(tree, { size })` — renders the given `h()` element tree as an inline
  interactive canvas on the popup (`.content` mode). The optional `{ size: { width, height } }`
  declares the canvas size once. See §7a for the full canvas authoring contract.
- `openclip.keepVisible()` — wraps the resolved result so the popup stays open
- `openclip.requireConfiguration({ reason, missing: ["optID"] })` — open config sheet for this action

Deterministic resolution order (`OpenClipJSHost.run`): **JS exception → `.showStatus(error)`** (JS
throws never propagate as Swift errors); else `requireConfiguration` → `openConfiguration`;
`showContent` → `.showContent(CanvasComponent, CanvasHeader?)`; `showStatus` with no other effects
→ `showStatus`; effects → single/`sequence`; function string return → `copy`; else `success`.
`keepVisible()` wraps the final result unconditionally. Inside a canvas session (§7a) `showContent`
never resolves to a result — it *replaces* the session's mounted tree (declaring the canvas size)
for the next re-render, and effects never dismiss.

> Execution runs on a background thread (never the `MainActor`); async scripts are guarded by a
> 30-second watchdog (`Constants.scriptTimeout`, `TimeoutFlag` pattern) — a never-settling promise
> surfaces as an error status. Note the resolution above: `showStatus` followed by an effect yields
> the effect, not the status.

---

## 7a. Interactive canvases (`type: "canvas"`)

A canvas is a **JS-only** action kind: `"type": "canvas"` with `scriptCode` (required — validation
rejects a canvas without it) holding the canvas script;
`"async": true` is optional — it enables `openclip.fetch` in handlers (below). `ui()` and
mount-time rendering are synchronous, so a promise returned from `ui()` at mount or during a
re-render is rejected immediately (`asyncNotSupported`); the 30 s watchdog applies only to async
handler dispatches whose promise never settles (e.g. an `openclip.fetch` that never resolves).
There is no `output` key — a canvas never "returns" text; it *renders*.

### Script contract

```js
const initialState = { count: 0 };   // optional; app-owned state seeds the session

function ui(state, input) {          // REQUIRED — the only required export
  return h('stack', {}, [
    h('text', { content: 'Count: ' + state.count }),
    h('button', { title: '+1', handler: 'increment' }),
  ]);
}

const handlers = {                   // optional; named handlers receive (state, event, input)
  increment(state, event, input) { return { ...state, count: state.count + 1 }; },
  deliver(state, event, input)   { openclip.paste(event.value); return state; }
};
```

- `ui(state, input)` is the **only required export**; it must return an `h()` element object (an
  array return is wrapped in a vertical `stack`). It is called at mount (`ui(initialState, input)`)
  and re-called after every handler (`ui(newState, input)`).
- `handlers[name](state, event, input)` is optional. `state` is a **fresh JSON object** each call
  (never the same object you returned); the handler returns the **new state** — not a new tree. The
  render tree is produced by `ui(newState, input)` *after* the handler runs. `event` is
  `{ kind, targetID, value, handler }` where `kind` is `"tap"` (button/listItem/link/toggle
  activation), `"change"` (a committed value: a `textField` blur or submit, or a `toggle` flip —
  never a per-keystroke event), or `"submit"` (a `textField` Enter).
- A node whose `handler` is an **object** (`{ type: "paste", text: "..." }`) is a leaf effect
  (H2) and never dispatches; a bare string `handler` names a `handlers` entry.

### `h(type, props, children)` — component reference

`h` returns `{ type, props, children }` element objects. The 11 component types:

| type | props |
| :--- | :--- |
| `stack` | `orientation` (`"vertical"`/`"horizontal"`), `spacing`, `id` |
| `divider` | `id` |
| `spacer` | `minLength`, `id` |
| `text` | `content`, `style` (`"title"`/`"body"`/`"caption"`/`"monospaced"`), `color` (`"primary"`/`"secondary"`/`"accent"`), `selectable`, `id` |
| `icon` | `symbol` \| `iconify` \| `local` \| `url`, `size`, `id` |
| `image` | `url` \| `local`, `cornerRadius`, `id` |
| `button` | `title`, `icon`, `style` (`"accent"`/`"plain"`), `disabled`, `handler`, `id` |
| `list` / `listItem` | `listItem`: `icon`, `title`, `subtitle`, `badge`, `disabled`, `handler`, `id` |
| `textField` | `id` (**required**), `value`, `placeholder`, `onSubmit`, `onChange` |
| `toggle` | `id` (**required**), `value`, `disabled`, `onToggle` |
| `link` | `title`, `url` |

Unknown types, missing required `id`s, and invalid link URLs drop the node (recovery is lenient
per node); only structural violations — too many nodes/depth, too many list items, an over-long
`text`, or a non-object root — reject the whole canvas with an error status.

### The `openclip` bridge inside a canvas

Read-only context: `openclip.input.text`, `openclip.input.matchedText` (both the selection),
`openclip.options` / `openclip.option(id)` (resolved option values). Leaf effects
(`paste`/`copy`/`cut`/`keyPress`/`runShortcut`/`openURL`/`showServices`/`notify`) are collected on
each evaluation and run **without dismissing** — a canvas never hides the popup on its own.
`keepVisible()` is a **no-op** inside a canvas (effects never dismiss). `showStatus(message, style)`
surfaces on the **bar banner after collapse**, never inside the canvas. `showContent(tree, { size })`
declares the canvas size **once** — `{ size: { width, height } }` clamped to the 220–360 width
column and `Constants.popupMaxHeight` tall — and replaces the mounted tree for the next re-render.

With `"async": true`, handlers may call `openclip.fetch(url, options)` — the same contract
as JS actions: `options` = `{ method, headers, body }` (default GET); the response is
`{ status, ok, text() → Promise<string>, json() → Promise<any> }`; network errors reject the
handler's promise (surfaced as an error status), and a request that never settles is killed
by the 30 s watchdog (in-flight tasks are cancelled). `ui()` stays synchronous — use fetch in
handlers, never in `ui`/at mount; mount-time async rendering is not supported.

### State model

- A `textField` commits on **submit (Enter) or blur**, never per keystroke; the committed value
  fires the field's `onChange` handler as a `change` event (Enter fires `onSubmit` as a `submit`
  event first).
- A `toggle` commits the **already-flipped** value — the renderer flips it before the handler runs,
  so `handlers` read post-flip state.

### Example: interactive counter + textField form

```js
const initialState = { count: 0, name: '' };

const handlers = {
  increment(state)            { return { ...state, count: state.count + 1 }; },
  updateName(state, event)    { return { ...state, name: event.value }; },
  greet(state, event, input)  { openclip.notify('Hi ' + state.name, input); return state; }
};

function ui(state, input) {
  return h('stack', { spacing: 8 }, [
    h('text', { content: 'Count: ' + state.count, style: 'title' }),
    h('button', { title: '+1', handler: 'increment' }),
    h('textField', { id: 'name', value: state.name, placeholder: 'Your name',
                     onChange: 'updateName' }),
    h('button', { title: 'Greet', handler: 'greet', style: 'accent' }),
  ]);
}
```

### Behavior contract

- **Esc collapses** the canvas to the bar (SwiftUI `.onKeyPress` on the canvas root/fields) —
  click-outside and app deactivation **hide** the popup.
- A mount/parse/watchdog **failure rejects the canvas**: the session is dropped, the panel
  collapses to the bar, and the error surfaces as a status on the bar banner.

---

## 8. The ActionResult surface & JSON effect shapes

`ActionResult` cases an extension can produce (via JS effects, script JSON, declarative
`after`/`stayVisible`, or kind runtimes):

| Case | Meaning |
| :--- | :--- |
| `.success` | no side effect |
| `.copy(String)` | copy to pasteboard |
| `.cut(String)` | copy + delete selection (delete key) |
| `.paste(String)` | paste text (replaces selection / frontmost app) |
| `.openURL(URL)` | open the URL |
| `.showServices(String)` | macOS share picker on the text |
| `.shareService(identifier:, text:)` | invoke a specific macOS sharing service by identifier (e.g. Notes inline popup) |
| `.notify(title:, body:)` | post a notification (best-effort; needs authorization) |
| `.showContent(CanvasComponent, CanvasHeader?)` | render an interactive canvas tree; **keeps popup open** |
| `.showStatus(StatusFeedback)` | transient status; **keeps popup open** |
| `.openConfiguration(ConfigurationRequest)` | hide popup, open the action's config sheet |
| `.keepVisible(ActionResult)` | perform inner result but never dismiss |
| `.sequence([ActionResult])` | run in order; popup hides only if all dismiss |
| `.keyPress(KeyPressSpec)` | post synthetic key event |
| `.runShortcut(name:, input:)` | run a Shortcuts shortcut with input |
| `.none` | no effect |

Dismissal: `.showContent`/`.showStatus`/`.keepVisible` keep the popup open; `.sequence` dismisses
only when non-empty and all items dismiss; everything else (including `.openConfiguration`)
dismisses.

### 8a. Shell/script JSON protocol (`ShellResultMapper`)

A script command may emit one JSON object on stdout (all fields optional except `type`, and
except `shareService`'s `identifier`, which is required):

```jsonc
{ "type": "paste", "value": "text" }                                  // .paste
{ "type": "copy",  "value": "text" }                                  // .copy
{ "type": "openURL", "value": "https://..." }                         // .openURL
{ "type": "status", "message": "Done", "style": "success" }           // "success"|"error"|"info"
{ "type": "keepVisible", "effect": { "type": "paste", "value": "x" } }// .keepVisible(recursive)
{ "type": "configure", "reason": "...", "missing": ["opt"] }          // .openConfiguration
{ "type": "shareService", "identifier": "com.apple.Notes.SharingExtension", "value": "text" } // .shareService — identifier REQUIRED
```

Unknown `type` → `.success`. If stdout is **not** valid JSON, the plain text is **pasted**; empty
stdout → `.success`. A non-zero exit (or hitting the 30 s watchdog) becomes an error status. These
are the *only* script JSON `type` values the runtime accepts. **`"showContent"` is not one of
them** — a shell script cannot render a canvas, so a `"showContent"` type falls into the unknown
branch and maps to `.success` (canvas rendering is JS-only, §7a).

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
      "scriptCode": "echo '{\"type\":\"status\",\"message\":\"secret set\",\"style\":\"success\"}'" }
  ]
}
```

The `api` value is stored in the Keychain (never UserDefaults) and would be read in JS as
`openclip.options.api` / `openclip.option('api')`.

---

## 10. Develop / iterate / test workflow

1. **Scaffold or author** the folder. To start from a known-valid template, run
   `./scripts/new_extension.sh <Name> [--type canvas|js|group|url]` — it writes a reverse-DNS
   `openclip.json` (+ `main.js` for canvas/js) into `Extensions/raw/<Name>.openclipext/` and runs
   the validator before reporting success. To author by hand:
   `mkdir ~/my-ext.openclipext && nano ~/my-ext.openclipext/openclip.json`
   (plus any `script.sh`/`main.js`/scripts it references, and optional local icon files).
2. **Install** by copying into `~/.openclip/extensions`:
   `./scripts/install_extension.sh ~/my-ext.openclipext`
   (the script runs `cp -R` into `~/.openclip/extensions`; a `.zip` or standalone script file is
   unpacked/copied accordingly if installed through the app's installer). Before copying, directory
   and `.zip` sources are checked against the loader's manifest rules by
   `scripts/validate_extension.sh` — the same rejects (unknown `type`, missing required field or
   payload, bad/capability'd manifest, missing referenced script file) the app applies at load, so
   an invalid package is **rejected here** (exit 1, nothing copied) instead of loading silently.
3. **Reload**: the app scans `~/.openclip/extensions` at **startup** (`ActionCoordinator`
   `loadInitialState` → `ExtensionManager.loadExtensions`), so quit and relaunch OpenClip, or
   trigger a reload from the Preferences → Extensions UI (the in-app install/uninstall paths call
   `loadExtensions` after mutation). A freshly launched app is the reliable check.
4. **Test**: select text anywhere, summon the popup, confirm the action appears and its enablement
   follows §5, then run it and inspect the effect (§8), including whether the popup hides or stays.
5. **Iterate**: edit the folder and relaunch/reload; no build is needed.

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

## 11. Do NOT

- **Do not put AppKit/SwiftUI in Core** — extension *parsing* (`OpenClipSnippetParser`) and model
  types in `Sources/Core/` are pure; keep them free of UI imports.
- **Do not write to `UserDefaults` directly** in extension code paths — Option storage goes through
  `ActionOptionStore`/`SettingKey`; secrets go through the Keychain store.
- **Do not skip the subprocess watchdog** — any new action that spawns a subprocess must terminate
  it past `Constants.scriptTimeout` (30 s). Existing shell/shortcut runtimes already do.
- **Do not `switch action.id`** for presentation decisions — use `action.chrome`, icons, and
  data-driven fields. The `chrome`/`rowStyle`/`popupBehavior`/`source` you may see in the code are
  **computed by the app**, not manifest keys: a manifest has **no** `chrome`, `subtitle`, `badge`,
  `keywords`, or `gesturePolicy` fields — do not write them.
- **Do not write a `parentGroupID`** — groups use the id-prefix convention only (§3i); it was
  deliberately deferred.
- **Do not invent JSON effect `type` strings** — the shell protocol accepts only the types in §8a.
- **Do not block inside JS** — the async watchdog kills never-settling promises after 30 s
  (`Constants.scriptTimeout`), but keep scripts fast; `"async": true` is required for any script
  that needs `fetch` or to await a promise.
- **Do not use `?key=` for Gemini/auth in URLs**; credentials go in headers, and secrets belong in
  Keychain-backed options, not in a manifest.

---

## 12. Source of truth recap (for confident auditing)

- Manifest model & decoding: `Sources/Core/Extensions/Manifest/ExtensionManifest.swift`,
  `ExtensionActionKind.swift`, `ActionRequirements.swift`; loading in
  `Sources/Core/Extensions/ExtensionManager.swift`.
- Kind→runtime routing + chrome + id rule: `Sources/OpenClip/Platform/Extensions/DefaultActionFactory.swift`.
- JS surface/resolution: `Sources/OpenClip/Platform/Runtimes/OpenClipJSHost.swift`.
- Effect execution: `Sources/OpenClip/Platform/Effects/ActionResultHandler.swift`.
- Result model: `Sources/Core/Actions/ActionResult.swift` (+ `ActionResultAdapter.swift`,
  `StatusFeedback.swift`, `ConfigurationRequest.swift`).
- Canvas component model + limits: `Sources/Core/Canvas/` (`CanvasComponent.swift`,
  `CanvasElementParser.swift`, `CanvasLimits.swift`, `CanvasScripting.swift`).
- Canvas engine + JS bridge + manifest kind: `Sources/OpenClip/Platform/Runtimes/JavaScriptCanvasEngine.swift`,
  `Sources/OpenClip/Platform/Runtimes/CanvasScriptBox.swift`, `Sources/OpenClip/Platform/Runtimes/JavaScriptCanvasAction.swift`.
- Canvas renderer/session: `Sources/OpenClip/UI/Popup/CanvasSession*.swift`.
- Visibility/required options: `Sources/Core/Actions/ActionVisibility.swift`, `ExtensionActionRules.swift`.
- Options storage: `Sources/Core/Settings/ActionOptionStore.swift`, `SettingKey.swift`,
  `Sources/OpenClip/Platform/Extensions/KeychainActionOptionStore.swift`.
- Shell JSON effects + watchdog: `Sources/Core/Extensions/ShellProcessRunner.swift`.