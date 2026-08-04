# Managing Extensions & Custom Actions

OpenClip allows users to install community extensions and create custom search or script actions directly from the application interface or terminal.

---

## Extension Store & Remote Installation

OpenClip features a built-in Extension Store browser in **Preferences > Extension Store**.

```
Preferences > Extension Store
├── Browse official & community extensions
├── View extension details, actions, and author metadata
└── Click 'Install' to download and activate extensions instantly
```

### How Remote Installation Works
1. `ExtensionsAPIClient` fetches the published extensions catalog.
2. `RemoteExtensionInstaller` downloads the extension archive `.zip` or `.openclipext` bundle.
3. [`ExtensionManager.installExtension(from:)`](../../Sources/Core/Extensions/ExtensionManager.swift) extracts and verifies the extension in `~/.openclip/extensions/`.
4. `ExtensionManager` reloads the extensions catalog and registers new actions with `ActionRegistry`.

---

## Manual Installation of Extensions & Scripts

You can manually install extensions or standalone script files by placing them directly into your local extensions directory:

```bash
~/.openclip/extensions/
```

### Installation File Types
- **Extension Bundles (`.openclipext`)**: Folders containing `manifest.json` and code files.
- **Zip Archives (`.zip`)**: Compressed extension packages automatically unzipped by `ExtensionManager`.
- **Standalone Scripts (`.sh`, `.py`, `.js`, `.applescript`)**: Single script files with comment header metadata.

---

## Creating Custom Actions in GUI

You can create custom web search links or inline shell scripts without writing extension manifests:

1. Open **Preferences > Actions**.
2. Click **+ Add Custom Action**.
3. Choose the action type:
 - **URL Template**: Enter a title, SF Symbol icon, and URL string (e.g. `https://google.com/search?q={query}`).
 - **Shell Script**: Enter a script command or inline snippet (e.g. `tr '[:lower:]' '[:upper:]'`).
4. Click **Save**.

### Storage & Persistence
- Custom actions created in the GUI are written as single-action manifest packages by
  [`CustomActionManifestWriter`](../../Sources/OpenClip/Platform/Extensions/CustomActionManifestWriter.swift):
  `~/Library/Application Support` is not used; the package lives at
  `~/.openclip/extensions/<id>/openclip.json` and loads through the same extension scan as installed
  extensions. (`custom_actions.json` and `CustomActionManager` are retired.)
