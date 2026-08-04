# Extension Package Format (`.openclipext`)

> **Authoritative reference:** the current (v2) manifest schema, all action kinds, options,
> requirements, groups, and the runtime result surface are documented in
> [`docs/developer-guide/AGENTS.md`](./AGENTS.md). This page is a summary and may lag it.

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
| `name` | String | `Name` | Display name of the extension package. |
| `actions` | Array / Object | `action`, `Actions` | List of action definitions (or single action object). |
| `options` | Array | `Options` | Optional array of user-configurable settings. |

### Action Object (`ExtensionActionMetadata`)

| Field | Type | Description |
| :--- | :--- | :--- |
| `id` | String | Unique action identifier. If omitted, generated as `<manifest.id>.action.<index>`. |
| `title` | String | Display title presented in UI surfaces. |
| `icon` | String | Icon definition. Accepts `symbol:sf_symbol_name`, local filename (`icon.png`), or URL. |
| `type` | String | Runtime kind (case-insensitive): `"url"` (default), `"javascript"` (`"js"`), `"applescript"`, `"shell"` (`"shellinline"`), `"script"` (`"scriptfile"`), `"textSnippet"` (`"snippet"`/`"text"`), `"webSearch"` (`"web"`/`"search"`), `"keyPress"` (`"keys"`), `"service"` (`"servicemenu"`), `"shortcut"` (`"keyboardshortcut"`), `"group"` (`"subactions"`). Unknown values default to `"url"`. |
| `script` | String | Path to script file relative to extension directory (defaults to `main.js`). |
| `scriptCode` | String | Inline script code string (used when code is embedded directly in manifest/snippet). |
| `url` | String | URL template pattern string with `{query}` or `{text}` placeholders. |
| `regex` | String | Optional regular expression pattern to gate action visibility. |
| `keyPress` | String | Key-press spec like `"command+shift+o"` (for `type: "keyPress"`). |
| `shortcutName` | String | Name of a macOS Shortcut to run (for `type: "shortcut"`). |
| `serviceName` | String | Reserved for the macOS Services menu (for `type: "service"`). |
| `subActions` | Array | Sub-action objects for `type: "group"`; rendered as a sub-menu with IDs `<groupID>.<subID>`. |

---

## Options Schema (`ExtensionOptionMetadata`)

Extensions can expose user preferences rendered in the Preferences window under **Dynamic Action Configuration**.

| Field | Type | Legacy Alias | Description |
| :--- | :--- | :--- | :--- |
| `identifier` | String | `id`, `Identifier` | Option key used when reading configuration. |
| `label` | String | `Label` | User-facing title in the Preferences panel. |
| `type` | String | `Type` | Input control type: `"string"`, `"boolean"`, `"multiple"` (picker; see `options`), `"secret"` (Keychain-backed). |
| `default` | String | `Default` | Default value if unspecified by the user. |
| `options` | Array | `Options` | Candidate choices for `type: "multiple"`. |

### Option Storage & Retrieval
- Non-secret option values are saved through [`SettingsStore`](../../Sources/Core/Settings/SettingsStore.swift) using typed setting key strings: `SettingKey<String>("action.<id>.option.<identifier>", defaultValue:)`.
- `type: "secret"` option values live in the **Keychain**, never `SettingsStore`/UserDefaults — resolved via [`KeychainActionOptionStore`](../../Sources/OpenClip/Platform/Extensions/KeychainActionOptionStore.swift) (Keychain account from `ActionOptionKey.keychainAccount(actionID:optionID:)`).
- Direct `UserDefaults.standard` access is discouraged and should not be added in new code. The JavaScript runtime reads options through the injected `ActionOptionReading` store (`OpenClipJSHost`), not `UserDefaults`.
