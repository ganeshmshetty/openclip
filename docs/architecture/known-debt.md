# Known Debt & Current-State Realities

This file holds OpenClip's **current-state notes** — the places where the code has not yet
reached the target architecture. These change more often than the hard rules, so they are
tracked here rather than in `AGENTS.md`. Keep this file current when you touch any of these
areas; stale debt notes are worse than none.

---

## Settings Migration (UserDefaults → SettingsStore)

- The typed settings abstraction is `SettingsStore` + `SettingKey<T>` (see `Sources/Core/Settings/`).
  New settings code must route through it.
- **Current reality:** `UserDefaults.standard` is still called directly in ~13 App-target call
  sites: `AppDelegate` ×2, `StatusBarController` ×4, `JavaScriptAction` ×1, `AIServiceManager` ×2,
  `OnboardingView` ×1, `LaunchAtLoginManager` ×3. Migrating these is ongoing — **don't add new ones.**
- **Secrets live in the Keychain, not UserDefaults.** Sensitive credentials (the cloud AI API key)
  must use `KeychainStore` (generic-password `SecItem` wrapper, `kSecAttrAccessibleAfterFirstUnlock`).
  `AIServiceManager.cloudAPIKey` is `@Published`, backed by `KeychainStore` (account `aiCloudAPIKey`);
  do not convert it back to `@AppStorage`. A one-time migration reads the old `UserDefaults`
  `"aiCloudAPIKey"` key, then deletes it.
- **Builtin actions** (`CalculateAction`, `CalendarAction`, `SearchAction`) read
  `DefaultSettingsStore.shared` directly — they don't accept an injected `SettingsStore` today.
- **Dynamic action option keys** (`JavaScriptAction`, `AppleScriptAction`): the target pattern is
  `SettingKey<String>("action.<id>.option.<identifier>", defaultValue:)` via `SettingsStore`. Today
  `JavaScriptAction` reads option values via `UserDefaults.standard.string(forKey:)` (migration target).

## Action Seams Already Implemented

- **Coordinator composition is done.** `ActionCoordinator.loadInitialState()` wires `ExtensionManager`
  to the registry via `onRegister`/`onUnregister`; the manager never calls `ActionRegistry.shared`
  directly. GUI-authored actions persist as manifest packages (via `CustomActionManifestWriter`);
  `custom_actions.json`/`CustomActionManager` are retired.

## Presentation / Rule Holes

- **One legacy `switch action.id` fallback** remains in `ActionCustomizationManager.tableIcon()`
  (~`ActionCustomizationManager.swift:101`). Treat it as debt, not a pattern — don't add more.
- **`OpenClipSnippetParser` is annotated `@MainActor`** (it should be a pure text parser). Removing
  that is planned, not done.

## Unused / Latent

- **`ActionContext.modifiers` is currently unused.** No action reads it; `PopupWindowController`
  passes `modifiers: []`. Don't build logic that assumes modifier keys reach actions.
- **HotkeyManager.executor pattern** (`HotkeyManager.swift:22`): a latent `Task { @MainActor in`
  inside the shortcut callback could be hardened to an explicit executor; optional.