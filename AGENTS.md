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

## 3. Core Architectural Subsystems

OpenClip enforces a strict single-responsibility architecture across these core subsystems:

1. **Settings Subsystem — [`SettingsStore`](file:///Users/ganesh/dev/openclip/Sources/Core/Settings/SettingsStore.swift)**
   - The typed settings abstraction is `SettingsStore` + [`SettingKey<T>`](file:///Users/ganesh/dev/openclip/Sources/Core/Settings/SettingKey.swift). New settings code should route through this.
   - **Current reality:** `UserDefaults.standard` is still used directly in ~13 App-target call sites (`AppDelegate` ×2, `StatusBarController` ×4, `JavaScriptAction` ×1, `AIServiceManager` ×2, `OnboardingView` ×1, `LaunchAtLoginManager` ×3). Migrating these to `SettingKey`/`DefaultSettingsStore` is an ongoing effort — don't add new direct `UserDefaults.standard` calls.
   - **Secrets live in the Keychain, not UserDefaults.** Sensitive credentials (e.g. the cloud AI API key) must use [`KeychainStore`](file:///Users/ganesh/dev/openclip/Sources/OpenClip/Platform/KeychainStore.swift) (generic-password `SecItem` wrapper, `kSecAttrAccessibleAfterFirstUnlock`). `AIServiceManager.cloudAPIKey` is a `@Published` var backed by `KeychainStore` (account `aiCloudAPIKey`); do not convert it back to `@AppStorage`. A one-time legacy migration reads the old `UserDefaults` `"aiCloudAPIKey"` key and then deletes it.
   - **Builtin actions** (`CalculateAction`, `CalendarAction`, `SearchAction`) currently read `DefaultSettingsStore.shared` directly (they do not accept an injected `SettingsStore` today).
   - **Dynamic action option keys** (`JavaScriptAction`, `AppleScriptAction`): the target pattern is `SettingKey<String>("action.<id>.option.<identifier>", defaultValue:)` via `SettingsStore`. Today `JavaScriptAction` reads option values via `UserDefaults.standard.string(forKey:)` (migration target).

2. **Action Presentation — [`ActionPresentation`](file:///Users/ganesh/dev/openclip/Sources/Core/Actions/ActionPresentation.swift)**
   - All action icon symbols, labels, and display modes for UI surfaces (`.popup`, `.table`) are generated via `ActionPresentation.shared.presented(action, surface:)`.
   - Rendered using [`ActionIconView`](file:///Users/ganesh/dev/openclip/Sources/OpenClip/UI/Icons/ActionIconView.swift).
   - **Constraint:** `ActionCustomizationManager.tableIcon()` resolves icons via `ConfigurableAction.preferenceIconName` — never add `switch action.id` string-matching blocks. (Note: there is currently one legacy `switch action.id` fallback block in `tableIcon` at `ActionCustomizationManager.swift:101`; treat it as debt, not a pattern.)

3. **Action Chrome Policy — [`ActionChrome`](file:///Users/ganesh/dev/openclip/Sources/Core/Actions/ActionChrome.swift)**
   - Exposes UI policy metadata (`badge`, `rowStyle`, `popupBehavior`, `source`).
   - **Constraint:** UI views (e.g. `PreferencesView`) must use data-driven `switch action.chrome.badge` instead of fragile `if action is ScriptAction` type checks or `switch action.id` string matches.

4. **Action Factory — [`DefaultActionFactory`](file:///Users/ganesh/dev/openclip/Sources/OpenClip/Platform/Extensions/DefaultActionFactory.swift)**
   - Action objects derived from extension manifests or script snippets are instantiated exclusively via `ActionFactory`.

5. **Action Result Handler — [`ActionResultHandler`](file:///Users/ganesh/dev/openclip/Sources/OpenClip/Platform/Effects/ActionResultHandler.swift)**
   - Executes platform side-effects (`.copy`, `.paste`, `.cut`, `.openURL`, `.showServices`) using `NSPasteboard`, `NSWorkspace`, and `CGEvent` key simulation.
   - **Constraint:** `PopupWindowController` is strictly responsible for window lifecycle and positioning; all execution side-effects route through `ActionResultHandler`.

6. **Action Coordinator & Composition — [`ActionCoordinator`](file:///Users/ganesh/dev/openclip/Sources/Core/Actions/ActionCoordinator.swift) + [`AppServices`](file:///Users/ganesh/dev/openclip/Sources/OpenClip/App/AppServices.swift)**
   - `ActionCoordinator.loadInitialState()` is the single place that wires `CustomActionManager` and `ExtensionManager` to the `ActionRegistry`.
   - **Current reality:** the `onRegister`/`onUnregister` callback seam described in `docs/architecture/action-coordinator.md` does NOT exist. `CustomActionManager` and `ExtensionManager` currently call `ActionRegistry.shared` directly (`CustomActionManager.swift:34,44,50`; `ExtensionManager.swift:125,129,199`). Implementing the callback seam is planned, not done — don't claim otherwise in new code or docs.
   - `AppServices` owns the UI-facing service singletons (`SettingsStore`, `ActionRegistry`, `ActionPresentation`, `ActionCustomizationManager`).

---

## 4. Key Design Rules (enforced, not suggestions)

- **Accept dependencies, don't create them.** Core types that need settings accept `SettingsStore` in `init` with a default of `DefaultSettingsStore.shared`. Tests can inject a fake store. (Note: builtin actions currently read `DefaultSettingsStore.shared` directly — see §3.1.)
- **No `ActionRegistry.shared` in Core domain modules.** Only `ActionCoordinator` touches the registry directly. `CustomActionManager` and `ExtensionManager` use `onRegister`/`onUnregister` callbacks. (Note: this callback seam is NOT yet implemented — both managers currently call `ActionRegistry.shared` directly. See §3.6.)
- **No `switch action.id` string matching in presentation code.** Use `ConfigurableAction.preferenceIconName`, `action.chrome.badge`, or `action.icon`. (One legacy block remains in `ActionCustomizationManager.tableIcon`.)
- **Transform policy lives on `TransformCase`.** The set of default-on/off transform actions is `TransformCase.defaultDisabledActionIDs` — do not duplicate this in `ActionRegistry` or any other type. (Note: `TransformCase.defaultDisabledActionIDs` does NOT exist yet; the policy is currently hardcoded in `ActionRegistry.availableActions`. See §3.6.)
- **`OpenClipSnippetParser` is a pure text parser** — no `@MainActor`, no UI dependencies. (Note: it is currently annotated `@MainActor`; removing that is planned, not done.)
- **Subprocess actions must have a timeout watchdog.** `ScriptAction` and `CustomAction.shellScript` launch `Process` and terminate it if it exceeds `Constants.scriptTimeout` (30 s) so a hanging script never leaves the popup spinning. Any new action that spawns a subprocess must follow the same pattern.
- **Swift 6 strict concurrency: continuation guard boxes must be `@unchecked Sendable` classes.** The "resume exactly once" flag inside a `withCheckedThrowingContinuation` cannot be a captured mutable local (`var didResume`) when the resumer is called from a `@Sendable` closure (e.g. `Process.terminationHandler`) — that fails `SWIFT_STRICT_CONCURRENCY: complete`. Use a small lock-guarded helper class (see `OnceGate` in `CustomAction.swift`).
- **`ActionContext.modifiers` is currently unused.** No action reads it; `PopupWindowController` passes `modifiers: []`. Don't build new logic that assumes modifier keys reach actions without wiring it up first.
- **Gemini auth uses the `x-goog-api-key` header, not a URL query.** `CloudAPIProvider` sets the key on every request (`processGemini` and `fetchGeminiModels`). Don't reintroduce `?key=` in the URL — it leaks credentials into logs.

---

## 5. Codebase Directory Structure

```text
Sources/
├── Core/                                     # Domain Logic (Pure Swift Target)
│   ├── Actions/
│   │   ├── Action.swift                      # Action protocol
│   │   ├── ActionChrome.swift                # UI metadata policy enum
│   │   ├── ActionContext.swift               # Action resolution context
│   │   ├── ActionCoordinator.swift           # Action execution coordinator & composition root (wires managers to registry)
│   │   ├── ActionCustomizationManager.swift  # User action overrides (title/icon); delegates I/O to SettingsStore
│   │   ├── ActionPresentation.swift          # Presentation styling generator
│   │   ├── ActionRegistry.swift              # Storage, ordering, and transform default-on/off policy
│   │   ├── ActionResult.swift                # Action result value types
│   │   ├── Builtin/                          # Core builtin actions (Copy, Cut, Paste, etc.)
│   │   │   └── TransformTextAction.swift     # TransformCase enum & transform implementations (default-on/off policy lives in ActionRegistry)
│   │   ├── BuiltinRegistry.swift             # Default builtin actions catalog
│   │   ├── ConfigurableAction.swift          # Configurable action protocol (preferenceIconName)
│   │   ├── Custom/                           # Custom action draft & I/O seam
│   │   │   ├── CustomActionDraft.swift       # Value-type DTO for form editing
│   │   │   └── CustomActionRepository.swift  # I/O seam for custom_actions.json (currently unused; CustomActionManager does its own I/O)
│   │   ├── CustomAction.swift                # Custom action domain model
│   │   ├── CustomActionManager.swift         # Manages custom action list; does its own file I/O; calls ActionRegistry.shared directly
│   │   ├── ExtensionOption.swift             # Extension option models
│   │   ├── ModifierFlags.swift               # Keyboard modifier flags
│   │   ├── URLTemplateAction.swift           # Web search / URL template action
│   │   └── WordCompletionProviding.swift     # Completion provider protocol
│   ├── Extensions/
│   │   ├── ActionFactory.swift               # Action factory protocol
│   │   ├── ExtensionManager.swift            # Extension loader; calls ActionRegistry.shared directly
│   │   ├── ExtensionsAPIClient.swift         # Remote store API client
│   │   ├── ExtensionsModels.swift            # Store models & DTOs
│   │   ├── Manifest/                         # Extension manifest structures
│   │   │   ├── ExtensionActionKind.swift     # Normalized extension kind enum
│   │   │   └── ExtensionManifest.swift       # Extension manifest decoder
│   │   ├── OpenClipSnippetParser.swift       # Standalone snippet header parser (currently @MainActor); body mode ends only at `#` header keys, `//` lines stay body
│   │   └── ScriptAction.swift                # Executable script action
│   ├── Rules/                                # App-specific policy rules
│   │   ├── AppRule.swift                     # AppPolicyContext (5 active fields) + AppRule Codable model
│   │   └── RuleEngine.swift
│   ├── Selection/                            # Text selection & monitoring models
│   │   ├── AppFilter.swift
│   │   ├── AppIdentifying.swift
│   │   ├── Constants.swift                   # Timing thresholds, key codes, settings keys, scriptTimeout
│   │   ├── SelectionContext.swift
│   │   ├── SelectionCoordinator.swift
│   │   ├── SelectionMonitoring.swift
│   │   └── TextRetrieving.swift
│   ├── Settings/                             # Settings subsystem
│   │   ├── SettingKey.swift                  # Strongly-typed setting keys
│   │   └── SettingsStore.swift               # Central SettingsStore protocol + DefaultSettingsStore adapter
│   └── Utils/
│       └── TextPlaceholderEngine.swift       # Dynamic text template engine
└── OpenClip/                                 # App Target (macOS App / AppKit / SwiftUI)
    ├── AI/                                   # AI Assistant & Providers
    │   ├── AIProvider.swift
    │   ├── AIServiceManager.swift            # cloudAPIKey is Keychain-backed (@Published), other prefs via @AppStorage
    │   └── Providers/                        # Apple Intelligence, Cloud, Ollama, BrowserRedirect
    ├── Actions/                              # Runtime actions requiring AppKit/JavaScript
    │   ├── AppleScriptAction.swift
    │   └── JavaScriptAction.swift            # Reads action options via UserDefaults.standard directly (migration target: SettingKey)
    ├── App/
    │   └── AppServices.swift                 # UI-facing composition root
    ├── AppDelegate.swift                     # Reads isAppEnabled / hasCompletedOnboarding via UserDefaults.standard
    ├── OpenClipApp.swift                     # SwiftUI App Entrypoint
    ├── Platform/                             # macOS Platform Services
    │   ├── BuiltinActions/                   # AppKit platform actions (Services, Finder)
    │   ├── Effects/
    │   │   └── ActionResultHandler.swift     # Platform side-effects handler
    │   ├── Extensions/
    │   │   ├── DefaultActionFactory.swift    # ActionFactory implementation
    │   │   ├── OpenClipSnippetParser+DefaultFactory.swift
    │   │   └── RemoteExtensionInstaller.swift
    │   ├── HotkeyManager.swift               # Global shortcut manager
    │   ├── InstalledAppsScanner.swift        # App scanner
    │   ├── KeychainStore.swift               # Generic-password SecItem wrapper for sensitive credentials (AI API key)
    │   ├── LaunchAtLoginManager.swift        # Login item manager
    │   ├── MacSelectionMonitor.swift         # Global accessibility monitor
    │   ├── MacTextRetriever.swift            # AX selection read + Safari JS; grabPasteboard apps use Cmd+C fallback
    │   └── PermissionManager.swift           # Accessibility permission manager
    ├── StatusBarController.swift             # Reads/writes isAppEnabled via UserDefaults.standard
    └── UI/                                   # User Interface (SwiftUI & AppKit Panels)
        ├── AI/                               # AI result overlay
        ├── Icons/
        │   └── ActionIconView.swift          # Dynamic icon renderer
        ├── Onboarding/                       # First launch onboarding
        ├── Popup/                            # Floating popup panel
        │   ├── PopupPanel.swift              # NSPanel subclass
        │   ├── PopupPositioner.swift         # Frame math & screen clamping (pure static, no singletons)
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

## 6. Instructions & Constraints for AI Agents

1. **Run `xcodegen generate` after file changes:** Always regenerate the Xcode project whenever adding or removing `.swift` files in `Sources/` or `Tests/`.
2. **Preserve modular boundaries:** Do not import `AppKit` or `SwiftUI` into `Sources/Core/Actions/` or `Sources/Core/Settings/`.
3. **No direct `UserDefaults` anywhere:** Use `SettingsStore`/`SettingKey` in Core (via injection); use `DefaultSettingsStore.shared.get/set` in App target code. Never call `UserDefaults.standard` directly. (Existing ~13 App-target call sites are known debt — see §3.1; don't add new ones.)
4. **No hidden singleton wiring in Core:** `CustomActionManager` and `ExtensionManager` use `onRegister`/`onUnregister` callbacks — do not add `ActionRegistry.shared` calls inside these types. Wire callbacks in `ActionCoordinator.loadInitialState()`. (Note: the callback seam is not implemented yet — both managers still call `ActionRegistry.shared` directly. See §3.6.)
5. **Data-driven UI:** Use `action.chrome` enums and `ConfigurableAction.preferenceIconName` instead of Swift type checks (`is ScriptAction`) or `switch action.id` string matches in any UI or presentation code.
6. **Transform policy on `TransformCase`:** Default-on/off transform sub-actions are defined in `TransformCase.defaultDisabledActionIDs` — do not duplicate or move this to the registry. (Note: `TransformCase.defaultDisabledActionIDs` does not exist yet; the policy is currently hardcoded in `ActionRegistry.availableActions`. See §3.6.)
7. **Maintain file-level comments:** When editing any Swift file, ensure the top-level doc comment block (`// FileName.swift ...`) is updated if the file's responsibilities or architectural role change.
8. **Always verify:** Run `xcodebuild` build and unit test verification commands before declaring completion of any task.
