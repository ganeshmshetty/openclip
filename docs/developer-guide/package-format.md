# Extension Package Format (`.openclipext`)

> **Authoritative reference:** the current manifest schema, all action kinds, options,
> requirements, groups, and the runtime result surface are documented in
> [`Extensions/AGENTS.md`](../../Extensions/AGENTS.md). This page is a summary and may lag it.

OpenClip extension packages are directory bundles (suffixed with `.openclipext` or plain directories) containing a manifest JSON file (`manifest.json`, `openclip.json`, or `Config.json`) along with supporting script files and local asset icons.

---

## Package Directory Structure

```text
my-extension.openclipext/
├── manifest.json # Required: Extension manifest definition
├── main.js # Action script file (JavaScript, AppleScript, or Executable)
├── icon.png # Optional: Local action icon image
└── README.md # Optional: Documentation
```

---

## Manifest JSON Schema (`ExtensionMetadata`)

OpenClip decodes extension metadata via [`ExtensionMetadata`](../../Sources/Core/Extensions/ExtensionManager.swift). To ensure backward compatibility, the decoder supports both modern camelCase keys and legacy capitalized/singular keys.

### Complete Example `manifest.json`

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

---

## Manifest Fields Reference

### Top-Level Metadata (`ExtensionMetadata`)

| Field | Type | Legacy Alias | Description |
| :--- | :--- | :--- | :--- |
| `identifier` | String | `id`, `Identifier` | Unique package identifier (e.g. `com.user.ext`). |
| `name` | String / Object | `Name` | Display name of the extension package. Plain string or localized dictionary (e.g. `{"en": "Word Tools", "zh-Hans": "字词工具"}`). |
| `description` | String / Object | `Description` | Optional package summary. Plain string or localized dictionary. |
| `actions` | Array / Object | `action`, `Actions` | List of action definitions (or single action object). |
| `options` | Array | `Options` | Optional array of user-configurable settings. |
| `keywords` | Array / String | — | Optional search keywords for the package actions in the action-search palette. |
| `version` | String | — | Declared package version; recorded in the validation log line, not used for loading. |
| `capabilities` | Array | — | Declared runtime capabilities. The known set is **empty** on day one, so any non-empty value rejects the manifest. Reserved. |

Manifests are **validated** on load (`ManifestValidator`): unknown action kinds, missing required
fields (`keyPress`/`shortcutName`/`subActions`/executable payload), and any declared capability
reject the package, which is then logged (category `extensions`) rather than silently skipped. See
[`docs/architecture/extensions.md`](../architecture/extensions.md).

### Action Object (`ExtensionActionMetadata`)

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
| `secondary` | Object | Optional. Secondary-click (right-click/⇧-click) outcome: `{ "type": "copy" | "paste" | "openURL" | "toast" | "success" | "none", "value"?, "message"? }`. **Non-JS kinds only** — rejected on `javascript` (JS authors branch on `openclip.input.isSecondaryClick` in-script instead). |
| `toast` | Object | Optional. Primary-click companion toast `{ "message": string | object, "style"?: "success" | "error" | "info" }` (default style `success`). Valid on all kinds. Message can be localized dictionary. |
| `secondaryToast` | Object | Optional. Secondary-click companion toast (same shape as `toast`). Valid on all kinds. Dash alias: `secondary-toast`. |

The `secondary`/`toast`/`secondaryToast` keys map onto the per-action `Action.delivery` (see
[`Extensions/AGENTS.md` §5b](../../Extensions/AGENTS.md)); the delivery decision (Select → Probe →
Toast) then applies the probe and resolves the companion toast.

### `type: "canvas"` (removed)

The former interactive-canvas kind `"canvas"` was removed; a `type: "canvas"` manifest is rejected
at load (`unknownActionKind("canvas")`).

---

## Options Schema (`ExtensionOptionMetadata`)

Extensions can expose user preferences rendered in the Preferences window under **Dynamic Action Configuration**.

| Field | Type | Legacy Alias | Description |
| :--- | :--- | :--- | :--- |
| `identifier` | String | `id`, `Identifier` | Option key used when reading configuration. |
| `label` | String / Object | `Label` | User-facing title in the Preferences panel. Plain string or localized dictionary. |
| `type` | String | `Type` | Input control type: `"string"`, `"boolean"`, `"multiple"` (picker; see `options`), `"secret"` (SecretStore-backed). |
| `default` | String | `Default` | Default value if unspecified by the user. |
| `options` | Array | `Options` | Candidate choices for `type: "multiple"`. |

### Option Storage & Retrieval
- Non-secret option values are saved through [`SettingsStore`](../../Sources/Core/Settings/SettingsStore.swift) using typed setting key strings: `SettingKey<String>("action.<id>.option.<identifier>", defaultValue:)`.
- `type: "secret"` option values live in `SecretStore` (`~/.openclip/secrets.json` with POSIX 0600 permissions), never `SettingsStore`/UserDefaults — resolved via [`SecretActionOptionStore`](../../Sources/OpenClip/Platform/Extensions/SecretActionOptionStore.swift).
- Direct `UserDefaults.standard` access is discouraged and should not be added in new code. The JavaScript runtime reads options through the injected `ActionOptionReading` store (`OpenClipJSHost`), not `UserDefaults`.
