# AGENTS.md — OpenClip AI Developer & Agent Guide

> **Note for AI Assistant Agents (Antigravity, Claude Code, Codex, Copilot, Gemini CLI):**
> Read this file to understand the architecture, build workflows, and strict code guidelines for the OpenClip project.

---

## 1. Project Overview

**OpenClip** is a lightweight, high-performance macOS floating popup utility written in Swift (macOS 14.0+). It intercepts selected text, presents contextual text manipulation actions (copy, cut, paste, definition lookups, web searches, scripts, extensions), and executes platform side-effects seamlessly.

- **Targets:**
  - `Core` (Framework / Swift Package): Pure domain models, actions, rules, selection logic, settings, and extension manifest parsers.
  - `OpenClip` (macOS App): AppKit floating panels (`PopupPanel`), SwiftUI views, platform side-effect handlers, AI providers, and composition root.
  - `OpenClipTests` (XCTest Suite): Unit and integration tests for Core and OpenClip targets.

---

## 2. Essential Commands

### Project Generation (MANDATORY after adding/deleting Swift files)
```bash
xcodegen generate
```

### Building the App
```bash
xcodebuild -project OpenClip.xcodeproj -scheme OpenClip -destination 'platform=macOS' build | tail -n 10
```

### Running Tests
```bash
# Run full test suite with filtered output
xcodebuild -project OpenClip.xcodeproj -scheme OpenClipTests -destination 'platform=macOS' test | grep -E "Test Suite|passed|failed|SUCCEEDED"

# Run a specific test class
xcodebuild -project OpenClip.xcodeproj -scheme OpenClipTests -only-testing:OpenClipTests/SettingsStoreTests -destination 'platform=macOS' test
```

---

## 3. The 6 Architectural Single-Door Principles

OpenClip enforces a strict single-responsibility architecture. Do NOT layer or bypass these single doors:

1. **The Settings Door — [`SettingsStore`](file:///Users/ganesh/dev/openclip/Sources/Core/Settings/SettingsStore.swift)**
   - All settings read/write operations must go through `SettingsStore` using typed [`SettingKey<T>`](file:///Users/ganesh/dev/openclip/Sources/Core/Settings/SettingKey.swift).
   - **Constraint:** Zero direct `UserDefaults.standard` calls in `Sources/Core/Actions/`.

2. **The Look Door — [`ActionPresentation`](file:///Users/ganesh/dev/openclip/Sources/Core/Actions/ActionPresentation.swift)**
   - All action icon symbols, labels, and display modes for UI surfaces (`.table`, `.popup`, `.editor`) are generated via `ActionPresentation.shared.presented(action, surface:)`.
   - Rendered using [`ActionIconView`](file:///Users/ganesh/dev/openclip/Sources/OpenClip/UI/Icons/ActionIconView.swift).

3. **The Chrome Door — [`ActionChrome`](file:///Users/ganesh/dev/openclip/Sources/Core/Actions/ActionChrome.swift)**
   - Exposes UI policy metadata (`badge`, `rowStyle`, `popupBehavior`, `source`).
   - **Constraint:** UI views (e.g. `PreferencesView`) must use data-driven `switch action.chrome.badge` instead of fragile `if action is ScriptAction` type checks.

4. **The Birth Door — `DefaultActionFactory`**
   - Action objects derived from extension manifests or script snippets are instantiated exclusively via `ActionFactory`.

5. **The Effect Door — [`ActionResultHandler`](file:///Users/ganesh/dev/openclip/Sources/OpenClip/Platform/Effects/ActionResultHandler.swift)**
   - Executes platform side-effects (`.copy`, `.paste`, `.cut`, `.openURL`, `.showServices`) using `NSPasteboard`, `NSWorkspace`, and `CGEvent` key simulation.
   - **Constraint:** `PopupWindowController` is strictly responsible for window lifecycle and positioning; all execution side-effects route through `ActionResultHandler`.

6. **The Wiring Door — [`AppServices`](file:///Users/ganesh/dev/openclip/Sources/OpenClip/App/AppServices.swift)**
   - Central composition root that owns single service instances (`SettingsStore`, `ActionRegistry`, `ActionPresentation`, `ActionCustomizationManager`).

---

## 4. Accurate Codebase Directory Structure

```text
Sources/
├── Core/                                     # Domain Logic (Pure Swift Target)
│   ├── Actions/
│   │   ├── Action.swift                      # Action protocol
│   │   ├── ActionChrome.swift                # UI metadata policy enum
│   │   ├── ActionContext.swift               # Action resolution context
│   │   ├── ActionCoordinator.swift           # Action execution coordinator
│   │   ├── ActionCustomizationManager.swift  # User action customization & ordering
│   │   ├── ActionPresentation.swift          # Look & styling generator
│   │   ├── ActionRegistry.swift              # Central action registry
│   │   ├── ActionResult.swift                # Action result value types
│   │   ├── Builtin/                          # Core builtin actions (Copy, Cut, Paste, etc.)
│   │   ├── BuiltinRegistry.swift             # Default builtin actions catalog
│   │   ├── ConfigurableAction.swift          # Configurable action protocol
│   │   ├── Custom/                           # Custom action draft & repository
│   │   │   ├── CustomActionDraft.swift
│   │   │   └── CustomActionRepository.swift
│   │   ├── CustomAction.swift                # Custom action domain model
│   │   ├── CustomActionManager.swift         # Custom action manager
│   │   ├── ExtensionOption.swift             # Extension option models
│   │   ├── ModifierFlags.swift               # Keyboard modifier flags
│   │   ├── URLTemplateAction.swift           # Web search / URL template action
│   │   └── WordCompletionProviding.swift     # Completion provider protocol
│   ├── Extensions/
│   │   ├── ActionFactory.swift               # Action factory protocol
│   │   ├── ExtensionManager.swift            # Extension loader & catalog
│   │   ├── ExtensionsAPIClient.swift         # Remote store API client
│   │   ├── ExtensionsModels.swift            # Store models & DTOs
│   │   ├── Manifest/                         # Extension manifest structures
│   │   │   ├── ExtensionActionKind.swift     # Normalized extension kind enum
│   │   │   └── ExtensionManifest.swift       # Extension manifest decoder
│   │   ├── OpenClipSnippetParser.swift       # Standalone snippet header parser
│   │   └── ScriptAction.swift                # Executable script action
│   ├── Rules/                                # App-specific policy rules
│   │   ├── AppRule.swift
│   │   └── RuleEngine.swift
│   ├── Selection/                            # Text selection & monitoring models
│   │   ├── AppFilter.swift
│   │   ├── AppIdentifying.swift
│   │   ├── Constants.swift
│   │   ├── SelectionContext.swift
│   │   ├── SelectionCoordinator.swift
│   │   ├── SelectionMonitoring.swift
│   │   └── TextRetrieving.swift
│   ├── Settings/                             # Settings subsystem
│   │   ├── SettingKey.swift                  # Strongly-typed setting keys
│   │   └── SettingsStore.swift               # Central SettingsStore
│   └── Utils/
│       └── TextPlaceholderEngine.swift       # Dynamic text template engine
└── OpenClip/                                 # App Target (macOS App / AppKit / SwiftUI)
    ├── AI/                                   # AI Assistant & Providers
    │   ├── AIProvider.swift
    │   ├── AIServiceManager.swift
    │   └── Providers/                        # Apple Intelligence, Cloud, Ollama, etc.
    ├── Actions/                              # Runtime actions requiring AppKit/JavaScript
    │   ├── AppleScriptAction.swift
    │   └── JavaScriptAction.swift
    ├── App/
    │   └── AppServices.swift                 # Composition root
    ├── AppDelegate.swift                     # macOS App Delegate
    ├── OpenClipApp.swift                     # SwiftUI App Entrypoint
    ├── Platform/                             # macOS Platform Services
    │   ├── BuiltinActions/                   # AppKit platform actions (Services, Finder)
    │   ├── Effects/
    │   │   └── ActionResultHandler.swift     # Platform side-effects handler
    │   ├── Extensions/
    │   │   ├── DefaultActionFactory.swift    # Factory implementation
    │   │   ├── OpenClipSnippetParser+DefaultFactory.swift
    │   │   └── RemoteExtensionInstaller.swift
    │   ├── HotkeyManager.swift               # Global shortcut manager
    │   ├── InstalledAppsScanner.swift        # App scanner
    │   ├── LaunchAtLoginManager.swift        # Login item manager
    │   ├── MacSelectionMonitor.swift         # Global accessibility monitor
    │   ├── MacTextRetriever.swift            # AX / Pasteboard text retriever
    │   └── PermissionManager.swift           # Accessibility permission manager
    └── UI/                                   # User Interface (SwiftUI & AppKit Panels)
        ├── AI/                               # AI result overlay
        ├── Icons/
        │   └── ActionIconView.swift          # Dynamic icon renderer
        ├── Onboarding/                       # First launch onboarding
        ├── Popup/                            # Floating popup panel
        │   ├── PopupPanel.swift              # NSPanel subclass
        │   ├── PopupPositioner.swift         # Frame math & screen clamping
        │   ├── PopupView.swift               # SwiftUI popup bar
        │   └── PopupWindowController.swift   # Window lifecycle manager
        └── Preferences/                      # Settings & preferences views
            ├── ActionAppearanceFields.swift
            ├── AddCustomActionSheet.swift
            ├── DynamicActionConfigView.swift
            ├── EditActionSheet.swift
            ├── ExtensionsStoreView.swift
            └── PreferencesView.swift
```

---

## 5. Instructions & Constraints for AI Agents

1. **Run `xcodegen generate` after file changes:** Always regenerate the Xcode project whenever adding or removing `.swift` files in `Sources/` or `Tests/`.
2. **Preserve modular boundaries:** Do not import `AppKit` or `SwiftUI` into `Sources/Core/Actions/` or `Sources/Core/Settings/`.
3. **No direct `UserDefaults` in Core:** Always use `SettingsStore` and `SettingKey`.
4. **Data-driven UI:** Use `action.chrome` enums instead of Swift type checks (`is ScriptAction`) in UI code.
5. **Always verify:** Run `xcodebuild` build and unit test verification commands before declaring completion of any task.
