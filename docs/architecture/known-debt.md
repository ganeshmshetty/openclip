# Known Debt & Current-State Realities

This file holds OpenClip's **current-state notes** — the places where the code has not yet
reached the target architecture. These change more often than the hard rules, so they are
tracked here rather than in `AGENTS.md`. Keep this file current when you touch any of these
areas; stale debt notes are worse than none.

---

## Settings Migration (UserDefaults → SettingsStore)

- The typed settings abstraction is `SettingsStore` + `SettingKey<T>` (see `Sources/Core/Settings/`).
  New settings code must route through it.
- **Current reality:** `UserDefaults.standard` is still called directly in ~12 App-target call
  sites: `AppDelegate` ×2, `StatusBarController` ×4, `AIServiceManager` ×2, `OnboardingView` ×1,
  `LaunchAtLoginManager` ×3. Migrating these is ongoing — **don't add new ones.**
- **Secrets live in the Keychain, not UserDefaults.** Sensitive credentials (the cloud AI API key)
  must use `KeychainStore` (generic-password `SecItem` wrapper, `kSecAttrAccessibleAfterFirstUnlock`).
  `AIServiceManager.cloudAPIKey` is `@Published`, backed by `KeychainStore` (account `aiCloudAPIKey`);
  do not convert it back to `@AppStorage`. A one-time migration reads the old `UserDefaults`
  `"aiCloudAPIKey"` key, then deletes it.
- **Builtin actions** (`CalculateAction`, `CalendarAction`, `SearchAction`) read
  `DefaultSettingsStore.shared` directly — they don't accept an injected `SettingsStore` today.
- **Dynamic action option keys** (`JavaScriptAction`, `AppleScriptAction`): the target pattern is
  `SettingKey<String>("action.<id>.option.<identifier>", defaultValue:)` via `SettingsStore`. The JS
  path already reads through the injected `optionStore` (`OpenClipJSHost` reads options read-only via
  `ActionOptionReading`); `AppleScriptAction` does not consume options today.

## Action Seams Already Implemented

- **Coordinator composition is done.** `ActionCoordinator.loadInitialState()` wires `ExtensionManager`
  to the registry via `onRegister`/`onUnregister`; the manager never calls `ActionRegistry.shared`
  directly. GUI-authored actions persist as manifest packages (via `CustomActionManifestWriter`);
  `custom_actions.json`/`CustomActionManager` are retired.
- **Shell runtimes share one executor.** `ScriptAction` script files and `CustomAction.shellScript`
  both run through `ShellProcessRunner` (one watchdog; `TimeoutFlag`/`OnceGate` live in
  `ShellProcessRunner.swift`) and translate stdout JSON via `ShellResultMapper`; `NSUserNotification`
  is gone (`.notify` is handled by the effect door via `UNUserNotificationCenter`).
- **`ActionResultAdapter.apply` is the single after/stayVisible translator.** Runtimes return raw
  results; each extension runtime's `perform` applies `rules.after`/`rules.stayVisible` via the
  adapter. `OpenClipJSHost.run` returns only raw results; async JS runs are guarded by the
  `TimeoutFlag` watchdog (30 s, same pattern as `ShellProcessRunner`).

## Presentation / Rule Holes

- **One legacy `switch action.id` fallback** remains in `ActionCustomizationManager.tableIcon()`
  (~`ActionCustomizationManager.swift:101`). Treat it as debt, not a pattern — don't add more.
- **`OpenClipSnippetParser` is annotated `@MainActor`** (it should be a pure text parser). Removing
  that is planned, not done.

## Action-Search Palette & Popup Growth

- **Content-driven panel growth has no controller callback.** The `NSHostingView` auto-resizes the
  panel window top-anchored when its SwiftUI content grows (e.g. entering search mode);
  `onPreferenceChange`/`onContentSizeChange` never fires for this and `sizingOptions` has no effect.
  The only reliable hook is `PopupPanel.setFrame` (`PopupPanel.swift:42`): when
  `pinBottomEdgeOnResize` is set it keeps the bottom edge fixed so results-above-the-field growth
  never shoves the popup. The pin stays active through the search→bar collapse (Esc no longer jumps
  the popup) and is cleared by `show(for:)` (`PopupWindowController.swift:69`) and `hide()`
  (`:464`) before intentional placement.
- **Search mode is the scoped key exception to the never-key rule.** `PopupPanel.allowsKey`
  enables `canBecomeKey` only in search mode (`PopupPanel.swift:15,34`). A `@FocusState`-in-onAppear
  request is silently dropped on macOS, so focus is forced via `focusSearchField()` on the next
  run-loop turn (`PopupWindowController.swift:161`); `previousFrontmostApp` is captured on
  `enterSearch` (`:145`) and re-activated on `exitSearch`/`hide`.
- **Search mode suspends popup dismissal.** The distance auto-dismiss and the key/scroll dismissals
  in `handleEvent` are skipped while `modeStore.mode == .search` (`PopupWindowController.swift:544,564,572`),
  so typing with the mouse elsewhere doesn't close the palette.
- **The floating bubble panel is gone; content renders inline.** The second `PopupPanel` (and its
  `showBubble`/`hideBubble`/`bubbleBlocksDismiss` machinery) was removed — all action/AI/hover/status
  content renders inside the single panel via `.content` mode (`PopupModeStore`) + `PopupContentView`.
  `PopupContentView` still renders `.info` emphasis for JS-emitted info cards; `StatusBadgeModel`
  remains a shared singleton (the canvas corner-badge path).
- **`MathEvaluator` replaced crash-prone `NSExpression`.** `CalculateAction` used to run
  `NSExpression(format:)`, which throws an **uncaught Objective-C exception** on malformed selection
  text like `+` or `1+` (crash). The pure-Swift `MathEvaluator` (`Sources/Core/Actions/MathEvaluator.swift`)
  returns nil (never traps) and properly supports `%` modulo. Regression coverage in
  `Tests/OpenClipTests/CalculateActionTests.swift`.
- **Search rows render icons strictly `[icon | text]`.** A `.text` icon in the icon column would
  duplicate the title, so `PopupSearchView.rowIcon` falls back to `ConfigurableAction.preferenceIconName`
  (`PopupSearchView.swift:214`); Iconify-format symbols (`prefix:name`) render via `AnyIconView`
  matching the bar (`:230`).
- **Search sizing constants:** `Constants.searchMaxHeight` (176), `searchMaxRows` (3),
  `searchResultRowHeight` (32) — `Sources/Core/Selection/Constants.swift:23`.

## Unused / Latent

- **`ActionContext.modifiers` is currently unused.** No action reads it; `PopupWindowController`
  passes `modifiers: []`. Don't build logic that assumes modifier keys reach actions.
- **HotkeyManager.executor pattern** (`HotkeyManager.swift:22`): a latent `Task { @MainActor in`
  inside the shortcut callback could be hardened to an explicit executor; optional.