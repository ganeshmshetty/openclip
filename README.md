# OpenClip

A lightweight, native macOS clipboard action engine. Highlight any text in any app, and instantly run actions — search the web, transform text, run scripts, or open URLs — all from a lightweight popup HUD.

## Features

- **Instant popup HUD** — appears on text selection, disappears on dismiss, zero friction
- **4 native runtimes** — JavaScript (JavaScriptCore), AppleScript, Shell/Python, and URL templates
- **Extension system** — install `.openclipext` packages or drop single-file snippets
- **Built-in actions** — Copy, Cut, Paste, Search, Define, Calculate, Transform Text, and more
- **Declarative options UI** — extensions can expose configurable fields natively in Preferences
- **Rules engine** — scope actions to specific apps or text patterns with regex support
- **Extension Store** — browse and install community extensions from the web or inside the app
- **Auto-update** — powered by Sparkle

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 16+ (to build from source)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (to regenerate the project file)

## Getting Started

```bash
git clone https://github.com/ganeshmshetty/openclip.git
cd openclip
xcodegen generate
open OpenClip.xcodeproj
```

Build and run the `OpenClip` scheme in Xcode. Grant Accessibility permissions when prompted.

## Creating Extensions

### Single-file snippet

The fastest way to create an action. Drop a script anywhere in `~/.openclip/extensions/`:

```bash
# title: Search GitHub
# icon: magnifyingglass
# url: https://github.com/search?q={text}
```

Supports `{text}` and `{query}` placeholders. Works with `.js`, `.sh`, `.py`, and `.applescript` files.

### Package format (`.openclipext`)

For more complex extensions, create a folder ending in `.openclipext` with an `openclip.json` manifest:

```
MyExtension.openclipext/
├── openclip.json
└── main.js          # or main.sh / main.applescript
```

**`openclip.json`** (singular action):
```json
{
  "identifier": "com.example.myextension",
  "name": "My Extension",
  "action": {
    "title": "Do Something",
    "icon": "star",
    "script": "main.js"
  }
}
```

> [!TIP]
> Both `"action"` (singular object) and `"actions"` (array) are supported in the manifest.

### Install an extension

- **From Preferences → Actions tab** — click the install button and select the `.openclipext` folder
- **From the Extension Store** — click "Install" on any extension card inside the app or at [web-opal-five-90.vercel.app/extensions](https://web-opal-five-90.vercel.app/extensions)
- **Manually** — copy the `.openclipext` folder into `~/.openclip/extensions/`

## Project Structure

```
Sources/
├── Core/              # Pure Swift/Foundation — no AppKit or JSC deps
│   ├── Actions/       # Action protocol, builtins, registry, coordinator
│   ├── Extensions/    # ExtensionManager, manifest decoding, API client
│   ├── Rules/         # RuleEngine for app/regex scoping
│   ├── Selection/     # Text selection, pasteboard, constants
│   └── Utils/         # TextPlaceholderEngine and shared utilities
└── OpenClip/          # AppKit host layer
    ├── Platform/      # DefaultActionFactory, installers, hotkey manager
    └── UI/            # Popup HUD, Preferences, onboarding views
Extensions/            # Bundled extension packages
Tests/                 # Unit and integration tests
web/                   # Next.js website & Extension Store (deployed on Vercel)
docs/                  # Developer documentation
```

> [!NOTE]
> `Sources/Core` is intentionally kept dependency-free (no AppKit, no JavaScriptCore). All platform-specific runtimes live in `Sources/OpenClip/Platform/`.

## Extension Runtimes

| File extension | Runtime | Placeholder |
|---|---|---|
| `.js` | JavaScriptCore | `{text}` / `{query}` |
| `.applescript` | AppleScript | `OPENCLIP_TEXT` env var |
| `.sh` / `.py` | Shell / Python | `OPENCLIP_TEXT` env var |
| URL template | Native (no script) | `{text}` / `{query}` |

## Web & Extension Store

The Extension Store is a Next.js app deployed on Vercel. It auto-discovers extensions from the `Extensions/` directory in this repo via the GitHub API — no manual entries needed.

- **Website:** [web-opal-five-90.vercel.app](https://web-opal-five-90.vercel.app)
- **Extensions API:** `/api/v1/extensions?q=&category=&page=&limit=`
- **Deep-link install:** `openclip://install?id=<id>&name=<name>&url=<url>`

To add a new extension to the store, create an `.openclipext` package in `Extensions/` and push to `master`. It appears on the website and inside the app within 60 seconds.

## Dependencies

| Package | Purpose |
|---|---|
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | Global hotkey registration |
| [Defaults](https://github.com/sindresorhus/Defaults) | Type-safe `UserDefaults` |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | Auto-update |
