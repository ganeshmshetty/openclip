# Known Debt & Current-State Realities

This file holds OpenClip's **current-state notes** — the places where the code has not yet
reached the target architecture. These change more often than the hard rules, so they are
tracked here rather than in `AGENTS.md`. Keep this file current when you touch any of these
areas; stale debt notes are worse than none.

---

## Settings Migration (UserDefaults → SettingsStore)

- The typed settings abstraction is `SettingsStore` + `SettingKey<T>` (see `Sources/Core/Settings/`).
  New settings code must route through it.
- **Current reality:** `UserDefaults.standard` is still called directly in ~8 App-target call
  sites: `AppDelegate` ×1 (onboarding flag), `AIServiceManager` ×2 (keychain migration),
  `OnboardingView` ×1, `LaunchAtLoginManager` ×4 (startAtLogin fallback + persistence). Plus the
  AI-config/theme `@AppStorage` surface (`AIServiceManager`, `ActionConfigSheet`, popup theme,
  `completionCopyToClipboard`, `startAtLogin`). Migrating these is ongoing — **don't add new ones.**
- **Secrets live in the Keychain, not UserDefaults.** Sensitive credentials (the cloud AI API key)
  must use `KeychainStore` (generic-password `SecItem` wrapper, `kSecAttrAccessibleAfterFirstUnlock`).
  `AIServiceManager.cloudAPIKey` is `@Published`, backed by `KeychainStore` (account `aiCloudAPIKey`);
  do not convert it back to `@AppStorage`. A one-time migration reads the old `UserDefaults`
  `"aiCloudAPIKey"` key, then deletes it.
- **`isAppEnabled` is consolidated** onto `SettingKey.isAppEnabled` — status bar, hotkey gate, and
  the Preferences toggle all read/write through `DefaultSettingsStore`. Builtin store-backed actions
  (`CalculateAction`, `CalendarAction`, `SearchAction`) accept an injected `SettingsStore` via
  `BuiltinRegistry.makeCoreBuiltins(settingsStore:)`.
- **`ActionConfigSheet` still binds raw keys** (`@AppStorage("action.search.url")`,
  `@AppStorage("action.calculate.mode")`, `"action.calculate.useText"`) that duplicate `SettingKey`
  names. Functionally consistent (same underlying keys), but the config sheets are a Phase-5
  consolidation target.
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
  is gone (`.notify` is handled by the effect door via `UNUserNotificationCenter`). AppleScript
  joins the same executor via `AppleScriptRunner` (osascript subprocess), so no code runs
  `NSAppleScript` in-process anymore.
- **`ActionResultAdapter.apply` is the single after/stayVisible translator.** Runtimes return raw
  results; each extension runtime's `perform` applies `rules.after`/`rules.stayVisible` via the
  adapter. `OpenClipJSHost.run` returns only raw results; async JS runs are guarded by the
  `TimeoutFlag` watchdog (30 s, same pattern as `ShellProcessRunner`).

## Presentation / Rule Holes

- **One legacy `switch action.id` fallback** remains in `ActionCustomizationManager.tableIcon()`
  (~`ActionCustomizationManager.swift:101`). Treat it as debt, not a pattern — don't add more.

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
- **Search sizing constants:** `Constants.searchMaxRows` (5), `searchResultRowHeight` (32),
  `searchPeekRowFraction` (0.5), `searchMaxHeight` (240) —
  `Sources/Core/Selection/Constants.swift:23`.

## Unused / Latent

- **`ActionContext.modifiers` is currently unused.** No action reads it; `PopupWindowController`
  passes `modifiers: []`. Don't build logic that assumes modifier keys reach actions.
- **HotkeyManager.executor pattern** (`HotkeyManager.swift:22`): a latent `Task { @MainActor in`
  inside the shortcut callback could be hardened to an explicit executor; optional.

## Concurrency

- **Residual non-interruptible paths (documented, bounded).** Three spots remain that a hostile
  or hung target can make block a cooperative-pool thread for up to `Constants.scriptTimeout`:
  (1) `MacTextRetriever.strategyAXMenuCopy` fires an unstructured `Task.detached` AXPress that the
  0.15 s pasteboard poll does not kill — the detached task finishes on its own; (2) an async-mode
  JS script with a top-level *synchronous* infinite loop blocks inside `evaluateScript`, which the
  watchdog pump loop never reaches (the sync-evaluation gate covers only `isAsync == false`);
  (3) `withMutedAlertVolume`'s volume-restore is fire-and-forget (deliberate — it must not block
  the Cmd+C return). All three are bounded (a leaked thread is eventually reaped), never
  main-actor-blocking.
- **AX direct read is deadline-capped.** `strategyAXDirect` races against
  `Constants.axReadTimeout` (0.5 s) via the `OnceResume` once-gate; an unresponsive app returns
  `nil` to the retrieval chain instead of hanging the popup.

## Test Isolation

- **Shared reset for the app singletons:** `Tests/OpenClipTests/TestIsolation.swift` centralizes
  `TestIsolation.reset()` — clears `ActionRegistry.shared`, `ActionCustomizationManager.shared`,
  `RuleEngine.shared`, and `ExtensionManager.shared` (loaded actions, `onRegister`/`onUnregister`
  callbacks, and factory). The singleton-touching test classes call it in `setUp()`, so the suite is
  order-independent. `ActionCoordinator.shared` needs no explicit reset: it mirrors the registry's
  `@Published` state, which `ActionRegistry.reset()` clears.
- **Tests must wire what they read.** A test that expects loaded extensions to land in the shared
  registry must set `ExtensionManager.shared.onRegister` itself (see
  `GoldenExtensionPlatformTests.setUp`) rather than relying on wiring left behind by an earlier
  test class. Keep using `TestIsolation.reset()` rather than cross-class state.
- **Store-backed behavior tests via `MemorySettingsStore`.** The shared in-memory test double
  (`Tests/OpenClipTests/MemorySettingsStore.swift`) replaces `UserDefaults.standard` mutation in
  `CalculateActionTests`, `ActionRegistryTests`, `GoldenExtensionPlatformTests`, and
  `ActionCustomizationTests`. Prefer it (or `DefaultSettingsStore(userDefaults: suiteName)`) over
  writing the real preferences domain.
- **Deliberate live-integration tests remain (documented):** `TextRetrieverTests` writes the real
  system clipboard (restores afterward; no pasteboard seam exists), `KeychainActionOptionStoreTests`
  hits the real macOS Keychain (UUID-unique accounts, deleted in tearDown), and
  `ScriptAction*Tests`/`ActionResultHandlerTests` spawn real subprocesses in temp dirs. These are
  bounded, self-restoring integration checks — leave them unless a real seam is added.

## Logging

- **Single `Log` surface is in.** `Sources/Core/Log.swift` owns every `os.Logger` category
  (`settings`, `presentation`, `chrome`, `factory`, `coordinator`, `result-handler`, `shell`, `js`,
  `selection`, `extensions`, `ai`, `permissions`, `icons`); all `print()` calls are gone. See
  `docs/logging.md` for the category table and filtering workflow.
- **Level budget is conservative.** Most messages are `.notice`/`.error`; `.debug` is used for
  defensive parses and transient network hiccups (filtered out by default in Console).
- **`chrome` category is reserved but unused** — no popup-window-chrome code logs yet.