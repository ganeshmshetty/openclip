# Architecture Overview

OpenClip is engineered around a clean target split and single-responsibility architectural boundaries ("Architectural Subsystems"). This design guarantees strict separation between pure domain logic, platform-specific side-effects, dynamic action runtimes, and user interface components.

---

## Target Split

The codebase is split into two primary targets:

```
OpenClip Workspace
├── Core (Framework / Swift Package)
│ ├── Pure domain models (Action, ActionChrome, ActionResult, SelectionContext)
│ ├── Selection detection contracts (TextRetrieving, SelectionMonitoring, SelectionCoordinator)
│ ├── Central action catalog & ordering (ActionRegistry, ActionCoordinator)
│ ├── Strongly-typed settings engine (SettingsStore, SettingKey)
│ ├── Application policy rules (AppRule, RuleEngine)
│ └── Pure snippet & manifest parsing (OpenClipSnippetParser, ExtensionManifest)
│
└── OpenClip (macOS Application Target)
 ├── AppKit floating panels & SwiftUI UI (PopupPanel, PopupView, PreferencesView)
 ├── Action execution runtimes (JavaScriptAction, AppleScriptAction)
 ├── Platform side-effect handler (ActionResultHandler)
 ├── Action factory implementation (DefaultActionFactory)
 ├── macOS selection monitor (MacSelectionMonitor, MacTextRetriever)
 └── App Composition Root (AppServices, AppDelegate)
```

### Core Target Constraints
- **Zero AppKit / SwiftUI UI dependencies** in `Sources/Core/Actions/` or `Sources/Core/Settings/`.
- **Pure Swift Types**: Value types, protocols, and decoupled services.
- **Dependency Injection**: Core components requiring settings accept a `SettingsStore` instance during initialization (defaulting to `DefaultSettingsStore.shared`).

---

## Core Architectural Subsystems

OpenClip enforces a single entry point for each cross-cutting concern. Bypassing these single-responsibility interfaces is strictly prohibited.

```mermaid
graph TD
 UI[UI Surface / PopupView] -->|1. Action Presentation| AP[ActionPresentation]
 UI -->|2. Action Chrome Policy| AC[ActionChrome]
 ACoord[ActionCoordinator] -->|6. Action Coordinator & Composition| AR[ActionRegistry]
 AF[DefaultActionFactory] -->|4. Action Factory| Action[Action Instance]
 Action -->|5. Action Result Handler| ARH[ActionResultHandler]
 Core[Domain Models & Actions] -->|1. Settings Subsystem| SS[SettingsStore]
```

### 1. Settings Subsystem — [`SettingsStore`](file:///Users/ganesh/dev/openclip/Sources/Core/Settings/SettingsStore.swift)
- **Responsibility**: Centralized persistence and retrieval of application settings.
- **Mechanism**: Operates via strongly-typed [`SettingKey<T>`](file:///Users/ganesh/dev/openclip/Sources/Core/Settings/SettingKey.swift) instances.
- **Strict Rule**: Zero direct `UserDefaults.standard` calls anywhere in `Sources/`. All access goes through `SettingsStore` in Core via dependency injection or `DefaultSettingsStore.shared` in the App target.

### 2. Action Presentation — [`ActionPresentation`](file:///Users/ganesh/dev/openclip/Sources/Core/Actions/ActionPresentation.swift)
- **Responsibility**: Resolves display titles and icons for specific UI surfaces (`.popup` or `.table`).
- **Mechanism**: `ActionPresentation.shared.presented(action, surface:)` queries user customizations via `ActionCustomizationManager` and falls back to action defaults.
- **Strict Rule**: UI code never computes display icons using type checks or string matches. Preferences table icons delegate to `ConfigurableAction.preferenceIconName`.

### 3. Action Chrome Policy — [`ActionChrome`](file:///Users/ganesh/dev/openclip/Sources/Core/Actions/ActionChrome.swift)
- **Responsibility**: Exposes UI policy metadata for actions without logic coupling.
- **Metadata**:
 - `badge`: `.none`, `.script`, `.url`, `.custom`, `.extensionPkg(String)`
 - `rowStyle`: `.standard`, `.transformGroup`
 - `popupBehavior`: `.perform`, `.showTransformMenu`, `.provideCompletions`
 - `source`: `.builtin`, `.custom`, `.extensionPkg(packageID: String)`
- **Strict Rule**: Views must inspect `action.chrome.badge` or `action.chrome.source` instead of checking `if action is ScriptAction` or matching `action.id`.

### 4. Action Factory — [`DefaultActionFactory`](file:///Users/ganesh/dev/openclip/Sources/OpenClip/Platform/Extensions/DefaultActionFactory.swift)
- **Responsibility**: Instantiating executable `Action` objects from extension manifest JSON metadata or parsed script snippet headers.
- **Mechanism**: Implements the `ActionFactory` protocol in the App target where JavaScript, AppleScript, and process runtimes are available.

### 5. Action Result Handler — [`ActionResultHandler`](file:///Users/ganesh/dev/openclip/Sources/OpenClip/Platform/Effects/ActionResultHandler.swift)
- **Responsibility**: Executing platform side-effects returned by actions (such as copying text, pasting into active apps, opening URLs, or showing system sharing services).
- **Strict Rule**: `PopupWindowController` manages window presentation and event filtering, delegating all result execution side-effects to `ActionResultHandler`.

### 6. Action Coordinator & Composition — [`ActionCoordinator`](file:///Users/ganesh/dev/openclip/Sources/Core/Actions/ActionCoordinator.swift)
- **Responsibility**: Orchestrates initial state loading, registers builtins, and connects custom actions and extensions to the central `ActionRegistry`.
- **Strict Rule**: `CustomActionManager` and `ExtensionManager` do not couple directly to singletons; they register/unregister actions through `ActionRegistry` via `ActionCoordinator`.

---

## Key Design Guidelines

1. **Accept dependencies, don't create them**: Core types accept `SettingsStore` in `init(settingsStore:)` with default fallback.
2. **No `ActionRegistry.shared` inside domain managers**: Domain managers use explicit callbacks or registration functions invoked by `ActionCoordinator`.
3. **No `switch action.id` string matching in UI**: Display formatting relies on `ConfigurableAction.preferenceIconName` and `ActionChrome`.
4. **Transform Policy Centralization**: `TransformCase.defaultDisabledActionIDs` controls default-on and default-off text case transformation actions.
5. **Pure Snippet Parsing**: `OpenClipSnippetParser` is a pure string parser with no UI or `@MainActor` ties.
6. **Pure Layout Math**: `PopupPositioner` is a pure static struct for computing panel coordinates and edge clamping.
