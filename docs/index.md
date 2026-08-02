# OpenClip Technical Documentation

Welcome to the **OpenClip** technical documentation hub. OpenClip is a lightweight, high-performance macOS floating popup utility written in Swift (macOS 14.0+). It intercepts selected text across any application, presents contextual text manipulation actions (copy, cut, paste, definition lookups, web searches, custom scripts, and extensions), and executes platform side-effects seamlessly.

---

## Quick Start Guide

### Prerequisites
- macOS 14.0 (Sonoma) or later
- Xcode 15.0+ (for building from source)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Building & Running

1. **Clone the Repository:**
 ```bash
 git clone https://github.com/openclip/openclip.git
 cd openclip
 ```

2. **Generate Xcode Project:**
 > **Note:** Run `xcodegen generate` whenever adding or removing `.swift` files.
 ```bash
 xcodegen generate
 ```

3. **Build the Application:**
 ```bash
 xcodebuild -project OpenClip.xcodeproj -scheme OpenClip -destination 'platform=macOS' build | tail -n 10
 ```

4. **Run Unit Tests:**
 ```bash
 xcodebuild -project OpenClip.xcodeproj -scheme OpenClipTests -destination 'platform=macOS' test | grep -E "Test Suite|passed|failed|SUCCEEDED"
 ```

5. **Grant Accessibility Permissions:**
 OpenClip relies on macOS Accessibility APIs to detect text selections without modifying system clipboard contents during monitoring. Grant permission in **System Settings > Privacy & Security > Accessibility**.

---

## Documentation Table of Contents

### System Architecture
- [Architecture Overview](architecture/overview.md) — Module target split (`Core` vs `OpenClip` App) and the Core Architectural Subsystems.
- [Action Coordinator & Registry](architecture/action-coordinator.md) — Central wiring, callback mechanics, and ordering policy.
- [Text Selection Subsystem](architecture/text-selection.md) — AX monitoring, `MacTextRetriever`, and non-destructive selection handling.
- [Popup Panel & Positioning Math](architecture/popup-window.md) — `PopupPanel`, static layout math in `PopupPositioner`, and window lifecycle management.

### Developer Guide
- [Extending OpenClip Overview](developer-guide/overview.md) — Extension architecture and custom action integration.
- [Extension Package Format](developer-guide/package-format.md) — `.openclipext` bundle structure, `manifest.json` schema, and options definitions.
- [Standalone Snippet Parsing](developer-guide/snippets.md) — Pure header parsing via `OpenClipSnippetParser`.

### Action Execution Runtimes
- [AppleScript Runtime](runtimes/applescript.md) — `AppleScriptAction` execution, variable injection, and output handling.
- [JavaScript Runtime](runtimes/javascript.md) — `JavaScriptAction` under JavaScriptCore, the `openclip` bridge, and option keys via `SettingKey`.
- [URL Templates Engine](runtimes/url-templates.md) — Parameterized search links using `URLTemplateAction` and `TextPlaceholderEngine`.
- [Shell & Executable Scripts](runtimes/zsh-python.md) — Process execution, environment variables (`OPENCLIP_TEXT`, `OPENCLIP_OPTION_*`), and JSON/text stdout parsing.

### User Guide
- [Installation & Onboarding](user-guide/installation.md) — Installing OpenClip, Accessibility permissions setup, and first-launch workflow.
- [Preferences & Customization](user-guide/preferences.md) — Customizing action titles, table icons, ordering, and AI provider setup.
- [Managing Extensions & Custom Actions](user-guide/managing-extensions.md) — Installing remote and local extensions and script snippet actions.
- [App-Specific Policy Rules](user-guide/app-rules.md) — Configuring application-level overrides via `AppRule` and `rules.json`.

---

## Core Architectural Principles

OpenClip enforces a strict single-responsibility architecture divided across **Core Architectural Subsystems**:
1. **Settings Subsystem** — [`SettingsStore`](file:///Users/ganesh/dev/openclip/Sources/Core/Settings/SettingsStore.swift) (Typed `SettingKey` access; a few legacy `UserDefaults.standard` sites remain in the App target).
2. **Action Presentation** — [`ActionPresentation`](file:///Users/ganesh/dev/openclip/Sources/Core/Actions/ActionPresentation.swift) (Surface-tailored icon and title resolution).
3. **Action Chrome Policy** — [`ActionChrome`](file:///Users/ganesh/dev/openclip/Sources/Core/Actions/ActionChrome.swift) (UI policy metadata without type checking).
4. **Action Factory** — [`DefaultActionFactory`](file:///Users/ganesh/dev/openclip/Sources/OpenClip/Platform/Extensions/DefaultActionFactory.swift) (Action creation from manifests/snippets).
5. **Action Result Handler** — [`ActionResultHandler`](file:///Users/ganesh/dev/openclip/Sources/OpenClip/Platform/Effects/ActionResultHandler.swift) (Platform side-effects, pasteboard, and key events).
6. **Action Coordinator & Composition** — [`ActionCoordinator`](file:///Users/ganesh/dev/openclip/Sources/Core/Actions/ActionCoordinator.swift) (Composition root; managers register with `ActionRegistry` directly today).
