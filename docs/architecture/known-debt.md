# Known Debt & Current-State Realities

This file holds OpenClip's **current-state notes** — the places where the code has not yet
reached the target architecture. These change more often than the hard rules, so they are
tracked here rather than in `AGENTS.md`. Keep this file current when you touch any of these
areas; stale debt notes are worse than none.

---

## Settings Migration (UserDefaults → SettingsStore)

- The typed settings abstraction is `SettingsStore` + `SettingKey<T>` (see `Sources/Core/Settings/`).
  New settings code must route through it.
- **AI-config `@AppStorage` surface remains** (`AIServiceManager` keys), and `completionCopyToClipboard`
  / `startAtLogin` / popup theme still read via `@AppStorage`, but the theme keys (`popupTheme`,
  `popupThemeColor`) now reference `SettingKey` definitions instead of raw literals. Migrating to
  `SettingsStore` is ongoing — **don't add new direct call sites.**
- **Secrets live in the Keychain, not UserDefaults.** Sensitive credentials (the cloud AI API key)
  must use `KeychainStore` (generic-password `SecItem` wrapper, `kSecAttrAccessibleAfterFirstUnlock`).
  `AIServiceManager.cloudAPIKey` is `@Published`, backed by `KeychainStore` (account `aiCloudAPIKey`);
  do not convert it back to `@AppStorage`. A one-time migration reads the old `UserDefaults`
  `"aiCloudAPIKey"` key, then deletes it.
- **`isAppEnabled` is consolidated** onto `SettingKey.isAppEnabled` — status bar, hotkey gate, and
  the Preferences toggle all read/write through `DefaultSettingsStore`. Builtin store-backed actions
  (`CalculateAction`, `CalendarAction`, `SearchAction`) accept an injected `SettingsStore` via
  `BuiltinRegistry.makeCoreBuiltins(settingsStore:)`.
- **`ActionConfigSheet` is gone** (dead code — zero presenting call sites; its `useText` keys were
  write-only). Removing it also dropped the only UI that wrote `SettingKey.searchURL` /
  `SettingKey.calculateMode`; the actions still read those keys (defaults apply), so a future
  Preferences surface for search-engine / calculate-result-mode would restore configurability.
  `ConfigurableAction` keeps only `preferenceIconName` (used by `tableIcon`/`rowIcon` icon fallback).
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
  `NSAppleScript` in-process anymore. Since the hang fix, the watchdog is a **GCD timer** (immune
  to Swift-concurrency-pool starvation) and pipe output is read via GCD `readabilityHandler` (never
  a blocking `readToEnd()`, so a stuck child can't permanently consume a cooperative thread), with
  stdin seeded and closed synchronously so a script reading stdin always sees EOF.
- **`ActionResultAdapter.apply` is the single after/stayVisible translator.** Runtimes return raw
  results; each extension runtime's `perform` applies `rules.after`/`rules.stayVisible` via the
  adapter. `OpenClipJSHost.run` returns only raw results; async JS runs are guarded by the
  `TimeoutFlag` watchdog (30 s, same pattern as `ShellProcessRunner`).
- **Canvas `fetch()` ships with a live-load gap.** `"async": true` canvas actions get
  `openclip.fetch` in handlers via the shared `JSNativeFetch` bridge
  (`Sources/OpenClip/Platform/Runtimes/JSNativeFetch.swift`, used by both `OpenClipJSHost` and
  `JavaScriptCanvasEngine`). The canvas `isAsync` flag — previously stored but never read —
  now gates dispatch-time fetch installation. Deferred: mount-time async rendering (async
  `ui()` / a `beforeMount` hook) and a busy indicator for in-flight handler fetches; `ui()`
  must stay synchronous.

## Presentation / Rule Holes

- **No `switch action.id` fallback remains.** `ActionCustomizationManager.tableIcon()` resolves via
  `ConfigurableAction.preferenceIconName` — the legacy block is gone. Keep it that way: never add
  id-string switches in presentation.

## Action-Search Palette & Popup Growth

- **Content-driven panel growth has no controller callback.** The `NSHostingView` auto-resizes the
  panel window top-anchored when its SwiftUI content grows (e.g. entering search mode);
  `onPreferenceChange`/`onContentSizeChange` never fires for this and `sizingOptions` has no effect.
  The only reliable hook is `PopupPanel.setFrame` (`PopupPanel.swift:42`): when
  `pinBottomEdgeOnResize` is set it keeps the bottom edge fixed so results-above-the-field growth
  never shoves the popup. The pin stays active through the search→bar collapse (Esc no longer jumps
  the popup) and is cleared by `show(for:)` (`PopupWindowController.swift:69`) and `hide()`
  (`:464`) before intentional placement.
- **Search and content modes are the two key exceptions to the never-key rule.** `PopupPanel.allowsKey`
  enables `canBecomeKey`/`canBecomeMain` in both modes (`PopupPanel.swift:19`), routed through the
  same `enterKeyMode()`/`exitKeyMode()` primitives (`PopupWindowController.swift:196,206`). A
  `@FocusState`-in-onAppear request is silently dropped on macOS, so search forces focus via
  `focusSearchField()` on the next run-loop turn (`PopupWindowController.swift:245`) and the canvas
  focuses its first interactive component via `canvasSessionController.requestFocus`;
  `previousFrontmostApp` is captured once per session (on `show(for:)`/`enterKeyMode`, never
  re-captured mid-session) and re-activated on `exitKeyMode`/`hide`.
- **Search and content modes suspend popup dismissal.** The distance auto-dismiss and the key/scroll
  dismissals in `handleEvent` are skipped while `modeStore.mode == .search` or `.content`
  (`PopupWindowController.swift:591,612,622`), so typing with the mouse elsewhere doesn't close the
  palette, and a canvas stays open until it is collapsed or the popup hides.
- **The floating bubble panel is gone; content renders inline.** The second `PopupPanel` (and its
  `showBubble`/`hideBubble`/`bubbleBlocksDismiss` machinery) was removed — all action/AI/status
  content renders inside the single panel via `.content` mode (`PopupModeStore`) + `CanvasSessionView`
  (the interactive canvas renderer), and hover previews render in the inline `PopupPreviewStrip`.
  `StatusBadgeModel` and the old `.info`/`.result`/`.menu` emphasis model are gone; a status emitted
  while a canvas is open is **queued** (`pendingStatus`) and flushed onto the bar banner when the
  canvas collapses (`exitContent()` → `flushPendingStatus()`).
- **`MathEvaluator` replaced crash-prone `NSExpression`.** `CalculateAction` used to run
  `NSExpression(format:)`, which throws an **uncaught Objective-C exception** on malformed selection
  text like `+` or `1+` (crash). The pure-Swift `MathEvaluator` (`Sources/Core/Actions/MathEvaluator.swift`)
  returns nil (never traps) and properly supports `%` modulo. Regression coverage in
  `Tests/OpenClipTests/CalculateActionTests.swift`.
- **Search rows render icons strictly `[icon | text]`.** A `.text` icon in the icon column would
  duplicate the title, so `PopupSearchView.rowIcon` falls back to `ConfigurableAction.preferenceIconName`; all four
  `ActionIcon` cases render through the shared `ActionIconView` (`Sources/OpenClip/UI/Icons/ActionIconView.swift`),
  including Iconify-format symbols (`prefix:name`). The popup bar keeps its own `iconView(for:)`
  (`PopupView.swift`) because text icons there need natural width + horizontal padding, not a fixed frame.
- **Popup sizing constants:** `Constants.searchMaxRows` (5), `searchResultRowHeight` (32),
  `searchPeekRowFraction` (0.5), `Constants.popupMaxHeight` (240, the shared height cap for the
  search palette and the canvas body) — `Sources/Core/Selection/Constants.swift:23`.

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
- **Subprocess pipe reads are non-blocking (hang fix).** `ShellProcessRunner` previously read stdout/
  stderr with blocking `readToEnd()` tasks and a `Task.sleep` watchdog — both can be starved, so a
  child (or grandchild) holding a pipe open could wedge the cooperative pool and hang the test
  suite indefinitely (observed mid-suite in `ScriptActionTests.testScriptExecution`). The runner now
  uses a GCD timer watchdog + GCD `readabilityHandler` reads + synchronous stdin close. This claim
  covers only the pipe reads: `process.waitUntilExit()` still blocks its detached thread until the
  child exits — bounded at `Constants.scriptTimeout`, when the watchdog kills the child and the wait
  returns.

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
  `ScriptActionExecutionTests`/`ActionResultHandlerTests` spawn real subprocesses in temp dirs. These are
  bounded, self-restoring integration checks — leave them unless a real seam is added.
- **Removed slow/flaky/environment-dependent tests:** the Apple Intelligence live-model tests
  (`testAppleIntelligenceMatchesPresetPrompts`, `AIActionTests.testPerformReturnsContentTree`) made
  real on-device `LanguageModelSession` calls; `CanvasEffectDeliveryTests` gated on real app
  activation under xcodebuild (intermittent failures); `DebugLogEndToEndTests` polled `OSLogStore`
  with multi-second sleeps; and `ScriptActionTests` duplicated `ScriptActionExecutionTests` (its
  stdin-reading test was the observed hang point). Core validation tests for those paths remain
  (pure validation, no live model/activation).

## Logging

- **Single `Log` surface is in.** `Sources/Core/Log.swift` owns every `os.Logger` category
  (`settings`, `presentation`, `chrome`, `factory`, `coordinator`, `result-handler`, `shell`, `js`,
  `selection`, `extensions`, `ai`, `permissions`, `icons`); all `print()` calls are gone. See
  `docs/logging.md` for the category table and filtering workflow.
- **Level budget is conservative.** Most messages are `.notice`/`.error`; `.debug` is used for
  defensive parses and transient network hiccups (filtered out by default in Console).
- **`chrome` category is reserved but unused** — no popup-window-chrome code logs yet.