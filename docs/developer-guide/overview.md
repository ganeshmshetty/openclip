# Extending OpenClip Overview

> **Start here:** the self-contained authoring guide is [`Extensions/AGENTS.md`](../../Extensions/AGENTS.md)
> (manifest schema, all action kinds, options/requirements, groups, and the result surface).
> This page is a high-level orientation.

OpenClip provides a pluggable extension architecture that allows developers and power users to create custom text manipulation tools, integrate third-party APIs, and automate macOS workflows.

---

## Extension Capabilities

You can extend OpenClip in three distinct ways:

```
Extending OpenClip
├── 1. Custom Actions (GUI-configured)
│ ├── Web URL search templates
│ └── Inline shell scripts (bash, zsh, python, node)
│
├── 2. Standalone Script Snippets (Header Metadata)
│ ├── Single file scripts (.sh, .py, .js, .applescript)
│ └── Header comments declaring title, icon, and options
│
└── 3. OpenClip Extension Packages (.openclipext)
 ├── Directory containing manifest.json / openclip.json
 ├── Support for JavaScript (JSContext), AppleScript (NSAppleScript), and Executables
 └── Custom options UI schema (strings, booleans, dropdowns)
```

---

## Action Types at a Glance

| Action Type | Runtime Engine | Typical Use Cases |
| :--- | :--- | :--- |
| **URL Template** | `URLTemplateAction` | Web searches, documentation lookup, deep links |
| **JavaScript** | `JavaScriptAction` (JavaScriptCore) | Fast string transformations, JSON formatting, web API calls |
| **AppleScript** | `AppleScriptAction` (NSAppleScript) | macOS app automation (Finder, Safari, Notes, Mail) |
| **Executable Script** | `ScriptAction` / Shell `CustomAction` | Python, Node.js, Ruby, Zsh scripts accessing CLI utilities |
| **Key Press** | `KeyPressAction` (`type: "keyPress"`) | Synthetic key events (e.g. `"command+shift+v"`) into the frontmost app |
| **Shortcut** | `ShortcutAction` (`type: "shortcut"`) | Run a macOS Shortcut via `/usr/bin/shortcuts` |
| **Service** | `NamedServiceAction` (`type: "service"`) | Show the macOS Services menu |
| **Group** | `GroupAction` (`type: "group"` + `subActions`) | A menu row that reveals a sub-menu of actions |

---

## Extension Directory Locations

OpenClip automatically scans the following directory for extensions and script files at launch:

```text
~/.openclip/extensions/
├── my-extension.openclipext/
│ ├── manifest.json
│ ├── main.js
│ └── icon.png
├── currency-converter.py
└── format-sql.sh
```

---

## Architectural Integration Seam

Extending OpenClip does not require modifying Core framework code:
1. When extensions are placed in `~/.openclip/extensions/`, [`ExtensionManager`](../../Sources/Core/Extensions/ExtensionManager.swift) automatically parses manifests and snippets.
2. Extension metadata is passed to [`DefaultActionFactory`](../../Sources/OpenClip/Platform/Extensions/DefaultActionFactory.swift) (the **Action Factory**).
3. Derived action instances are registered with [`ActionRegistry`](../../Sources/Core/Actions/ActionRegistry.swift) through [`ActionCoordinator`](../../Sources/Core/Actions/ActionCoordinator.swift).
