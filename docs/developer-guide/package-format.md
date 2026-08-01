# Extension Package Format

An OpenClip extension package is a directory ending with `.openclipext` containing a JSON manifest file and any associated script or asset files.

---

## Directory Structure

A standard `.openclipext` bundle contains:

```
MyExtension.openclipext/
├── openclip.json       # Manifest file (or manifest.json / Config.json)
├── main.js             # Primary JavaScript entry point (or .sh / .py / .applescript)
├── icon.png            # (Optional) Custom extension icon
└── README.md           # (Optional) Documentation
```

---

## Manifest File (`openclip.json`)

The manifest file defines the extension metadata, actions, options, and script entry points.

### Minimal Manifest Example

```json
{
  "Identifier": "com.example.uppertext",
  "Name": "Uppercase Converter",
  "Actions": [
    {
      "Title": "UPPERCASE",
      "Icon": "symbol:textformat.characters",
      "Script": "main.js"
    }
  ]
}
```

### Full Manifest Schema

```json
{
  "Identifier": "com.example.translator",
  "Name": "DeepL Translator",
  "Description": "Translate selected text using DeepL API",
  "Author": "OpenClip Developer",
  "Version": "1.0.0",
  "Actions": [
    {
      "Title": "Translate",
      "Icon": "symbol:globe",
      "Script": "main.js",
      "Regular Expression": ".*"
    }
  ],
  "Options": [
    {
      "identifier": "api_key",
      "label": "DeepL API Key",
      "type": "secret",
      "default value": ""
    },
    {
      "identifier": "target_lang",
      "label": "Target Language",
      "type": "multiple",
      "default value": "DE",
      "options": ["DE", "FR", "ES", "IT", "JA", "ZH"]
    }
  ]
}
```

---

## Manifest Properties Reference

### Top-Level Keys

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `Identifier` | String | Yes | Reverse-DNS unique identifier (e.g. `com.example.myext`). |
| `Name` | String | Yes | Display name of the extension. |
| `Actions` | Array | Yes | Array of action objects. |
| `Options` | Array | No | Declarative configuration options array. |

### Action Object Keys

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `Title` | String | No | Button title shown in HUD. Defaults to extension `Name`. |
| `Icon` | String | No | Button icon identifier (e.g. `symbol:sparkles`, `icon.png`, or raw SF Symbol name). |
| `Script` | String | No* | Relative filename of script (`main.js`, `script.sh`, `main.applescript`). |
| `URL` | String | No* | URL template with `{text}` placeholder (for URL actions). |
| `Regular Expression` | String | No | Regex pattern. Action only appears if selection matches this pattern. |

*\* Either `Script` or `URL` must be provided in each action.*

---

## Icon Specification

OpenClip supports 3 formats for action icons:

1. **SF Symbols:** Use the `symbol:` prefix followed by any valid SF Symbol name (e.g. `symbol:magnifyingglass`, `symbol:doc.on.clipboard`, `symbol:terminal`).
2. **Local Image File:** Specify the relative filename of a PNG or SVG icon inside the bundle (e.g. `icon.png`).
3. **Text Label Icon:** If omitted or set to plain text, OpenClip renders a text badge.

---

## Packaging & Distribution

To share your extension:

1. Compress your `.openclipext` folder into a `.zip` archive:
   ```bash
   zip -r MyExtension.openclipext.zip MyExtension.openclipext
   ```
2. Users can drag and drop this `.zip` file into OpenClip Preferences or click **Install Extension…**.
