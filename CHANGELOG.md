# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

> Pre-release. OpenClip has not shipped a tagged release yet (the project began in
> July 2026); the entries below summarize the current state of `main`.

### Added

- **Contextual popup bar** — select text in any app and a floating bar appears next to the selection with the actions that fit. The bar anchors to where the mouse is released and never covers the selected text.
- **Action-search palette** — press <kbd>⌥⌘C</kbd> to turn the bar into a fuzzy search field over the *entire* action catalog, including disabled actions. Results are ranked by recency, then bar order.
- **Clipboard fallback** — with no live selection the popup acts on the clipboard contents; Copy/Cut drop out automatically (`chrome.requiresLiveSelection`).
- **Zero-config builtins** — Search, Copy, Cut, Paste, Services, Define, Calculate, Word Completion, and a Transform group (UPPERCASE, lowercase, Title Case, camelCase, Trim Whitespace, Format JSON).
- **Extensions** — a unified `.openclipext` package format (JavaScript, AppleScript, shell, URL templates, key presses, Shortcuts, Services, and group sub-menus) with install from the built-in store or a file/folder, hot-reload of `~/.openclip/extensions`, and uninstall from Preferences.
- **Extension Store** — browse, search, and install extensions from the catalog (`openclip-extensions` submodule) inside Preferences.
- **Canvas content rendering** — actions, AI results, long-press result cards, and previews render inside the popup panel via a content canvas instead of a separate floating panel; canvas extensions can author rich component trees.
- **AI Tools** — run selected text through Apple Intelligence, a local Ollama model, OpenAI, or Claude, or hand the query to your browser. AI presets are first-class, reorderable actions, and the AI Tools bar action opens a scoped palette.
- **Custom action builder** — add web-search URL templates, text snippets, and shell scripts from the GUI without writing a manifest, backed by a 9,000+ SF Symbol picker plus Iconify, Font Awesome, Lucide, and Material Symbols icon search.
- **Deep customization** — drag to reorder the bar, disable actions, override titles and icons, and pick a Classic or Glass theme (Liquid Glass on macOS 26+, frosted material on 14–15) in System, Light, or Dark.
- **App Rules** — scope actions to apps with allow/deny rules, selection regexes, and required options that prompt when missing.
- **Onboarding & permissions** — a 4-step first-launch onboarding and Accessibility permission management with a relaunch helper.
- **Debug tooling** — an in-app debug-log store (ring buffer backed by OSLog) and a `--dump-logs` command-line flag.
- **Start at login** — native `SMAppService` integration in Preferences.

### Changed

- Subprocess actions run under a 30-second watchdog (GCD timer + process-group kill) and read child output via GCD readability handlers, so stuck scripts can't wedge the run loop.
- Text retrieval is Accessibility-only; the clipboard-based `Cmd+C` and menu-copy fallbacks were removed so OpenClip never disturbs the clipboard while monitoring.
- Preferences moved to a Raycast-style `NavigationSplitView` sidebar with a tightened, grouped General tab.
- Group and AI bars open scoped palettes instead of floating panels; the hover "bubble" and the separate AI presets bar were removed.
- The extension system was unified from several ad-hoc formats into a single `.openclipext` manifest package.

### Fixed

- Paste no longer destroys rich text; SearchAction URLs are percent-encoded correctly.
- Extension installs no longer double-nest zips, uninstall matches by manifest identifier, and downloaded packages are checked for Zip-Slip paths.
- Concurrent extension-directory reloads are coalesced.
- Popup and content-canvas shadows no longer clip at the panel edge.
- Search-palette shadow clipping fixed via `.glassEffect(.clear)` + material frost.
- Deterministic snippet action IDs and stale-action unregistration on extension reload.

### Security

- Remote extension installs require HTTPS and validate archives against Zip-Slip traversal.
- AI provider API keys are stored in the Keychain, never in plain preferences.
- Gemini authentication uses the `x-goog-api-key` header only; credentials are never placed in URLs.
- OpenClip reads selections via Accessibility APIs and logs or stores nothing about them; text and extension data stay default-private in logs.

[keep-a-changelog]: https://keepachangelog.com/en/1.1.0/
[SemVer]: https://semver.org/spec/v2.0.0.html