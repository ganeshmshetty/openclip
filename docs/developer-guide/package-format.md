# Extension package format (`.openclipext`)

> Authoritative reference: the current manifest schema, all action kinds, options,
> requirements, groups, and the runtime result surface are documented in
> [`Extensions/AGENTS.md`](../../Extensions/AGENTS.md). This page is a summary and may lag it.

OpenClip extension packages are directory bundles (suffixed with `.openclipext` or plain directories) containing a manifest JSON file (`manifest.json`, `openclip.json`, or `Config.json`) along with supporting script files and local asset icons.

## Package directory structure

```text
my-extension.openclipext/
├── manifest.json
├── main.js # Action script file (JavaScript, AppleScript, or Executable)
├── icon.png
└── README.md
```

## Installation

- **Finder Double-Click**: `.openclipext` bundles are registered macOS document packages owned by OpenClip (`com.openclip.extension`). Double-clicking a `.openclipext` package (or `.openclipext.zip` archive) opens a confirmation dialog in OpenClip with package metadata, installs the package directly into `~/.openclip/extensions`, and marks it trusted.
- **Extension Store**: Deep links (`openclip://install?id=...&url=...`) download and install verified releases.
- **Manual / CLI**: Drop folders into `~/.openclip/extensions` or run `./Extensions/scripts/install.sh <path>`.

## Manifest JSON schema (`ExtensionMetadata`)

OpenClip decodes extension metadata via [`ExtensionMetadata`](../../Sources/Core/Extensions/ExtensionManager.swift). For backward compatibility, the decoder accepts both modern camelCase keys and legacy capitalized or singular keys.

### Complete example `manifest.json`

```json
{
 "identifier": "com.example.jsonformatter",
 "name": "JSON & Text Utilities",
 "actions": [
 {
 "id": "com.example.jsonformatter.prettify",
 "title": "Prettify JSON",
 "icon": "symbol:doc.plaintext",
 "type": "javascript",
 "script": "main.js"
 },
 {
 "id": "com.example.jsonformatter.docs",
 "title": "Search JSON Docs",
 "icon": "symbol:magnifyingglass",
 "url": "https://developer.mozilla.org/en-US/search?q={query}"
 }
 ],
 "options": [
 {
 "identifier": "indent_spaces",
 "label": "Indentation Spaces",
 "type": "string",
 "default": "2"
 }
 ]
}
```

## Manifest fields reference

### Top-level metadata (`ExtensionMetadata`)

| Field | Type | Legacy Alias | Description |
| :--- | :--- | :--- | :--- |
| `identifier` | String | `id`, `Identifier` | Unique package identifier (e.g. `com.user.ext`). |
| `name` | String / Object | `Name` | Display name of the extension package. Plain string or localized dictionary (e.g. `{"en": "Word Tools", "zh-Hans": "字词工具"}`). |
| `description` | String / Object | `Description` | Optional package summary. Plain string or localized dictionary. |
| `actions` | Array / Object | `action`, `Actions` | List of action definitions (or single action object). |
| `options` | Array | `Options` | Optional array of user-configurable settings. |
| `keywords` | Array / String | - | Optional search keywords for the package actions in the action-search palette. |
| `version` | String | - | Declared package version; recorded in the validation log line, not used for loading. |
| `capabilities` | Array | - | Declared runtime capabilities. The known set is empty on day one, so any non-empty value rejects the manifest. Reserved. |
| `output` | String | - | Optional default output contract kind (`"text"`, `"color"`, `"file"`, `"none"`, `"dynamic"`) inherited by actions in the package. |
| `result` | String | - | Optional default delivery recommendation (`"preview"`, `"paste"`, `"copy"`, `"paste-or-copy"`, `"open"`, `"save"`) inherited by actions. |
| `presentation` | String | - | Optional default card format for text results: `"plain"`, `"markdown"`, `"code"`, or `"diff"`. Inherited by actions; defaults to `"plain"`. |

Manifests are validated on load (`ManifestValidator`): unknown action kinds, missing required
fields (`keyPress`/`shortcutName`/`subActions`/executable payload), and any declared capability
reject the package, which is then logged (category `extensions`) rather than silently skipped. See
[`docs/architecture/extensions.md`](../architecture/extensions.md).

### Action object (`ExtensionActionMetadata`)

| Field | Type | Description |
| :--- | :--- | :--- |
| `id` | String | Unique action identifier. If omitted, generated as `<manifest.id>.action.<index>`. |
| `title` | String / Object | Display title presented in UI surfaces. Plain string or localized dictionary (e.g. `{"en": "Count", "zh-Hans": "统计"}`). |
| `icon` | String | Icon definition. Accepts `symbol:sf_symbol_name`, local filename (`icon.png`), or URL. |
| `type` | String | Runtime kind (case-insensitive): `"url"` (default when absent), `"javascript"` (`"js"`), `"applescript"`, `"shell"` (`"shellinline"`), `"script"` (`"scriptfile"`), `"textSnippet"` (`"snippet"`/`"text"`), `"webSearch"` (`"web"`/`"search"`), `"keyPress"` (`"keys"`), `"service"` (`"servicemenu"`), `"shortcut"` (`"keyboardshortcut"`), `"group"` (`"subactions"`). **Unknown values reject the manifest** at load. |
| `script` | String | Path to script file relative to extension directory (defaults to `main.js`). |
| `scriptCode` | String | Inline script code string (used when code is embedded directly in manifest/snippet). |
| `async` | Boolean | Optional. For `type: "javascript"` only: runs the script asynchronously, enabling a `fetch()` polyfill and awaiting the entry function's returned promise. Default `false` (legacy synchronous mode). |
| `url` | String | URL template pattern string with `{query}` or `{text}` placeholders. |
| `regex` | String | Optional regular expression pattern to gate action visibility. |
| `keywords` | Array / String | Optional search keywords for the action palette (e.g. `["stats", "length", "字数"]`). |
| `loading` | Boolean | Optional. Closes popup immediately and shows a spinner toast until the action returns. |
| `loadingMessage` | String / Object | Optional text for loading spinner toast. Plain string or localized dictionary. |
| `keyPress` | String | Key-press spec like `"command+shift+o"` (for `type: "keyPress"`). |
| `shortcutName` | String | Name of a macOS Shortcut to run (for `type: "shortcut"`). |
| `serviceName` | String | Reserved for the macOS Services menu (for `type: "service"`). |
| `subActions` | Array | Sub-action objects for `type: "group"`; rendered as a sub-menu with IDs `<groupID>.<subID>`. |
| `output` | String | Optional declared output kind: `"text"`, `"color"`, `"file"`, `"none"`, `"dynamic"`. Inherits package-level `output` if omitted, or falls back to inference sniffing for legacy extensions. |
| `result` | String | Optional recommended delivery: `"preview"` (result card), `"paste"`, `"copy"`, `"paste-or-copy"`, `"open"`, `"save"`. Defaults to package-level default or kind defaults (`paste-or-copy` for text, `preview` for file). |
| `presentation` | String | Optional card format for text results: `"plain"`, `"markdown"`, `"code"`, or `"diff"`. Overrides the package default; defaults to `"plain"`. Set it on each sub-action of a group, not on the structural group row. |
| `secondary` | Object | Optional. Secondary-click (right-click/⇧-click) outcome: `{ "type": "copy" | "paste" | "openURL" | "toast" | "success" | "none", "value"?, "message"? }`. **Non-JS kinds only**, rejected on `javascript` (JS authors branch on `openclip.input.isSecondaryClick` in-script instead). |
| `toast` | Object | Optional. Primary-click companion toast `{ "message": string | object, "style"?: "success" | "error" | "info" }` (default style `success`). Valid on all kinds. Message can be localized dictionary. |
| `secondaryToast` | Object | Optional. Secondary-click companion toast (same shape as `toast`). Valid on all kinds. Dash alias: `secondary-toast`. |
| `requirements.content` | Array | Non-empty list of `url`, `email`, `date`, `path`, `phone`, `address`; any detected type passes and supplies `openclip.input.detected`. A narrowing requirement makes the action contextual by default; `contextual` overrides. Requires 1.9.0. |
| `requirements.input` | String | Input contract: `optional`, `text` (default), `liveSelection`, or `editableSelection`. Legacy `requiresSelection`/`requires-selection` maps `true` to `text` and `false` to `optional`; do not combine legacy and new keys. `liveSelection` and `editableSelection` are narrowing requirements for contextual promotion; `text` and `optional` are not. |
| `requirements.requiresPasteTarget` | Boolean | Optional destination gate. `true` requires a confirmed Paste-capable target and is a narrowing requirement for contextual promotion; `false` or omission means no paste target is required, not that paste is forbidden. Dash alias: `requires-paste-target`. |
| `requirements.predicate` | String | Optional package-relative `.js` file (64 KiB max) exporting one pure `(input) => boolean` function. ANDed after every other gate; fail-open on error/timeout; may `require` package-local helpers. Requires a `minOpenClipVersion` for the release that ships predicate support. |
| `contextual` | Boolean | Optional contextual-promotion override. `true` promotes even without requirements; `false` prevents promotion even with requirements; absent uses the uniform narrowing-requirement rule. User settings override this value. |

`text` accepts nonblank selection, clipboard, or OCR text. `liveSelection` requires text from the
current live selection. `editableSelection` additionally requires confirmed editability of that
selection; unknown editability fails closed. Paste destination support is independent from input
source, so clipboard-derived transformations can still be pasted into a confirmed destination.
Older OpenClip releases ignore unknown manifest keys; do not publish catalog packages that rely on
these gates until an enforcing release exists. The current source version 1.7.3 is not a confirmed
compatibility floor, so `minOpenClipVersion` must wait for that release's version to be established.

### Result presentation

`presentation` only changes how the preview card renders a text result. Copy, Paste, and Drag always
use the text itself. Declare it on the action or package, or return it with a typed text result:

```js
return { type: "text", value: markdown, presentation: "markdown" };
```

```json
{ "type": "text", "value": "print(1)", "presentation": "code" }
```

`diff` compares the original selection with the result. When the texts are too large or not
meaningfully similar, the card falls back to plain text and hides the diff toggle. Unknown values
fall back to `plain`.

Manifest-level `presentation` is ignored by older releases, which show plain text. A typed text
result with `presentation` is only understood by releases that support the key; gate it with
`minOpenClipVersion` once that release is known.

### Contextual promotion

A parsed action is contextual by default when it declares a **narrowing** requirement: `apps`,
`content`, `regex`/`regexNegated`, `predicate`, `requiresPasteTarget`, `input: "liveSelection"` or
`"editableSelection"`, a legacy top-level `regex`, or `menuRelevance`.

`input: "optional"`, explicit `input: "text"`, and `requiredOptions` on their own do not narrow when
the action appears, so they do not promote it. If a narrowing requirement is also present, the
action is contextual.

`contextual: true` forces promotion; `contextual: false` prevents it. The user's global contextual
toggle and per-action disable still win. Within the contextual tier, the user's action order remains
authoritative; there is no author ranking.

`requirements.predicate` points at a package-relative `.js` file. The file must be a CommonJS module
exporting one function. It receives a read-only `input` object with `text`, `app`, `source`,
`editable`, `pasteTarget`, `matchedText`, `captures`, and `detected` arrays, and may `require`
package-local helpers. The predicate file's own directory is the `require` base. Helpers run with
no `openclip.*` bridge, so they must be pure. The file is limited to 64 KiB. It has a 5 ms budget;
errors and timeouts leave the action visible. The predicate runs only after the cheap gates pass.
The module is ordinary CommonJS, so authors can test it in Node with a plain fixture object. The
manifest must declare a `minOpenClipVersion` for the release that ships predicate support.

The `secondary`/`toast`/`secondaryToast` keys map onto the per-action `Action.delivery` (see
[`Extensions/AGENTS.md` §5b](../../Extensions/AGENTS.md)); the delivery decision (Select → Probe →
Toast) then applies the probe and resolves the companion toast.

### Extension output contract and delivery resolution

OpenClip uses an author output contract (`output` and `result`) for extensions:
- **`output` (`text` | `color` | `file` | `none` | `dynamic`)**: Declares what type of output the action produces. Non-output actions (`url`, `keyPress`, `shortcut`, `service`) default to `none`.
- **`result` (`preview` | `paste` | `copy` | `paste-or-copy` | `open` | `save`)**: Declares the author's recommended default outcome. Text actions default to `paste-or-copy`; file actions default to `preview`; color actions support `preview` only and fall back to it with a validation warning.
- **User Customization**: Users can override the delivery mode per-action in Settings (`Show in card`, `Paste`, `Copy`).
- **Clipboard Invariant**: Secondary click (right-click or ⇧-click) always copies the result to the clipboard (or displays a preview card if the primary click was copy), unless the action explicitly declares a custom `secondary` outcome. If the user set the action to **Show in card**, a secondary click on a text result shows the card too. A color never enters automatic copy/paste delivery on any route, including force-copy; its card offers explicit Copy of the hex and Save of the hex text.

### Typed inline results

Synchronous JavaScript actions with `inline: true` can return typed preview values:

```js
return "144";                              // shorthand text
return { type: "text", value: "144" };
return { type: "color", value: "#FF8800" };
return null;                               // no applicable result
```

- The structured type must match the declared `output` (`text` or `color`); a mismatch produces no preview.
- An emoji is an ordinary text value: it renders in the row and pastes/copies verbatim.
- Text keeps the existing Paste/Copy/Show delivery matrix. Color renders a swatch and canonical hex with automatic Show-only delivery; the card offers explicit Copy and Save.
- `displayOnly: true` requires `inline: true` on a synchronous JavaScript action, and requires `minOpenClipVersion` `1.10.0` or newer. The item stays visible, searchable, and accessible, but mouse, footer, Enter/Shift-Enter, Command-digit, and bound-hotkey routes do nothing and record no execution.
- Automatic preview runs in a restricted environment: clipboard, fetch, file, URL, notification, keypress, subprocess, and configuration APIs are removed before top-level code or `require`d modules execute. A script that needs those effects must not declare `inline`.
- Extension-author documentation, validator rules, and catalog examples remain authoritative in the separate `openclip-extensions` repository (`Extensions/AGENTS.md`).

### Native file output results

Actions implemented in JavaScript (`openclip.file`, `openclip.copyFile`, `openclip.saveFile`) or executable scripts (JSON `{"type": "file" | "copyFile" | "saveFile", ...}` or auto-detected regular file paths on stdout) can produce native file results. When returning a file, OpenClip renders an interactive file preview card in the popup panel (supporting inline image/SVG previews, system file icons, metadata inspection, drag-and-drop into other apps, and Open/Copy/Save shortcuts) or triggers direct clipboard copy / disk saving.

### `type: "canvas"` (removed)

The former interactive-canvas kind `"canvas"` was removed; a `type: "canvas"` manifest is rejected
at load (`unknownActionKind("canvas")`).

## Options schema (`ExtensionOptionMetadata`)

Extensions can expose user preferences rendered in the Preferences window under **Dynamic Action Configuration**.

| Field | Type | Legacy Alias | Description |
| :--- | :--- | :--- | :--- |
| `identifier` | String | `id`, `Identifier` | Option key used when reading configuration. |
| `label` | String / Object | `Label` | User-facing title in the Preferences panel. Plain string or localized dictionary. |
| `type` | String | `Type` | Input control type: `"string"`, `"boolean"`, `"multiple"` (picker; see `options`), `"secret"` (SecretStore-backed). |
| `default` | String | `Default` | Default value if unspecified by the user. |
| `options` | Array | `Options` | Candidate choices for `type: "multiple"`. |

### Option storage and retrieval
- Non-secret option values are saved through [`SettingsStore`](../../Sources/Core/Settings/SettingsStore.swift) using typed setting key strings: `SettingKey<String>("action.<id>.option.<identifier>", defaultValue:)`.
- `type: "secret"` option values live in `SecretStore` (`~/.openclip/secrets.json` with POSIX 0600 permissions), never `SettingsStore`/UserDefaults, resolved via [`SecretActionOptionStore`](../../Sources/OpenClip/Platform/Extensions/SecretActionOptionStore.swift).
- Direct `UserDefaults.standard` access is discouraged and should not be added in new code. The JavaScript runtime reads options through the injected `ActionOptionReading` store (`OpenClipJSHost`), not `UserDefaults`.

Native result shapes and migration from retired `requirements.expression` are documented in [native content requirements](native-content-requirements.md).
