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
  / popup theme still read via `@AppStorage`, but the theme keys (`popupTheme`,
  `popupThemeColor`) now reference `SettingKey` definitions instead of raw literals. Migrating to
  `SettingsStore` is ongoing — **don't add new direct call sites.** (`startAtLogin` was consolidated
  onto `SettingKey.startAtLogin` — `LaunchAtLoginManager` persists through `DefaultSettingsStore`.)
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
- **Delivery is resolved by `ActionResultDelivery`, not per-runtime translation.** Runtimes
  (`OpenClipJSHost.run`, `ShellResultMapper`, kind actions) return only raw results; the paste-vs-copy
  delivery decision (Select → Probe → Toast) is applied downstream from the action's declared
  `Action.delivery` (snapshotted per perform) plus the click intent and the unified paste
  availability. The old `after` translator (the pre-refactor `after` orchestration step and its
  adapter) is **fully removed**. Async JS runs are guarded by the
  `TimeoutFlag` watchdog (30 s, same pattern as `ShellProcessRunner`).

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
  `focusSearchField()` on the next run-loop turn (`PopupWindowController.swift:245`);
  `previousFrontmostApp` is captured once per session (on `show(for:)`/`enterKeyMode`, never
  re-captured mid-session) and re-activated on `exitKeyMode`/`hide`.
- **Search and content modes suspend popup dismissal.** The distance auto-dismiss and the key/scroll
  dismissals in `handleEvent` are skipped while `modeStore.mode == .search` or `.content`
  (`PopupWindowController.swift:591,612,622`), so typing with the mouse elsewhere doesn't close the
  palette, and the AI result card stays open until it is collapsed or the popup hides.
- **The floating bubble panel is gone; content renders inline.** The second `PopupPanel` (and its
  `showBubble`/`hideBubble`/`bubbleBlocksDismiss` machinery) was removed — all action/AI/status
  content renders inside the single panel via `.content` mode (`PopupModeStore`) as a native
  SwiftUI `AIResultCardView`. `StatusBadgeModel` and the old `.info`/`.result`/`.menu` emphasis
  model are gone, and the inline status banner is gone too: every `StatusFeedback` renders as a
  floating toast (`ToastPanelController`) with no queue — a status shows over the card — and
  `showsLoading` actions (manifest `"loading"`) use the early-close spinner toast.
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
- **Popup sizing constants live in the App target.** `PopupMetrics`
  (`Sources/OpenClip/UI/Popup/PopupMetrics.swift`) holds the UI-only values — `searchMaxRows`
  (5), `searchResultRowHeight` (32), `searchPeekRowFraction` (0.5), `popupMaxHeight` (240, the
  shared height cap for the search palette), the AI card bounds (`aiCardMinWidth` 220 /
  `aiCardIdealWidth` 300 / `aiCardMaxWidth` 360 / `aiCardBodyHeight` 120), plus
  placement/dismissal distances. `Core/Selection/Constants.swift` keeps only
  domain/runtime constants (timeouts, key codes, env vars, manifest keys).

## Unused / Latent

- **`ActionContext.modifiers` is currently unused.** No action reads it; `PopupWindowController`
  passes `modifiers: []`. The click intent itself *is* plumbed: `ActionContext.isSecondaryClick` is
  set from
  the captured `pendingClickIntent` by the bar/palette perform paths (right-click always; ⇧-click
  via the `onClickIntent` closure) and read by `DefineAction` to copy a definition headlessly. True
  modifier keys (⌘/⌥) still don't reach actions.
- **Paste delivery is now standardized but has a probe reliance.** Leaf `.paste` results are
  re-decided by `ActionResultDelivery` (App target) per the rule in the dev-guide §5b: a secondary
  click uses the declared `secondary` outcome (else derives `.copy` from a `.paste` primary), and
  the **unified** `PasteAvailability` answer (per-app rules win, AX `PasteAvailabilityProbe` fills
  in) downgrades a chosen `.paste` to `.copy` when it says no; otherwise the requested paste is
  honored. The delivery inputs are snapshotted at perform time — before
  the dismissing `hide()` clears the session context — so `denyPaste` holds even for pastes that
  dismiss the popup, and the AI card's Paste/Copy buttons are explicit requests
  (`performCardEffect`) that carry no delivery context and are never re-decided. The live probe
  (`PasteAvailabilityProbe`) needs
  Accessibility permission and
  walks the target's Edit ▸ Paste AX menu item; without AX it returns "unknown" and delivery falls
  back to copy (safe but means paste never happens for AX-less users). The same unified decision drives
  `modeStore.canPaste`, which hides the card's Paste button and the bar/search Paste + Cut
  (`PasteRequiringAction`) actions on a confirmed cannot-paste; unknown keeps them visible. The
  probe is started by the trigger sites in parallel with selection retrieval and applied before the
  first frame (probe-before-render, nothing cached), so a same-app focus-context change re-probes
  cleanly. The click-intent capture reads
  only ⇧ (not ⌘/⌥) and only sets it on mouse-down; a keyboard-driven run (search palette Enter) uses
  the last left-click intent. Since Task 4, each action's declared `Action.delivery` (a distinct
  secondary outcome + per-click `primaryToast`/`secondaryToast`) is snapshotted alongside the click
  intent and fed into `resolve`, and the returned tuple's toast is rendered directly — the manual
  `isDowngradedToCopy`/`isCopyDefinition` inline toast detection was removed in favor of the resolved
  `.toast`. Only the SwiftUI inline perform path snapshots via the new `onWillPerformAction` closure;
  the completion-button paste path (`PopupView` `onResult(.paste(word))`) still reads the **last**
  `pendingDelivery` (normally nil, since `hide()` clears it) rather than its own snapshot — a prior
  non-dismissing action's declared `primaryToast` could leak onto a completion-word paste; suggested
  fix: clear `pendingDelivery` right after the snapshot in `deliverResult` (single-use per perform).
- **HotkeyManager.executor pattern** (`HotkeyManager.swift:22`): a latent `Task { @MainActor in`
  inside the shortcut callback could be hardened to an explicit executor; optional.

## Concurrency

- **Residual non-interruptible paths (documented).** Two spots remain that a hostile
  or hung target can make block a background thread:
  (1) `SelectionRetrievalCoordinator.pressEditCopyMenu` fires an AXPress on the dedicated
  `com.openclip.ax-inspect` queue that the `pasteboardCopyTimeout` poll does not kill — the press
  is uncancellable and may pin a queue worker thread against a hung target until the AX call
  returns (never bounded by the copy timeout). The queue is concurrent, so a stuck press no longer
  head-of-line-blocks later retrieval requests (see below);
  (2) an async-mode
  JS script with a top-level *synchronous* infinite loop blocks inside `evaluateScript`, which the
  watchdog pump loop never reaches (the sync-evaluation gate covers only `isAsync == false`).
  Neither path is main-actor-blocking.
- **AX inspect is deadline-capped.** `SelectionRetrievalCoordinator.inspectWithWatchdog` races
  `AXElementInspector.inspect` against
  `Constants.axReadTimeout` (0.5 s) via the `OnceResume` once-gate, running the blocking snapshot on
  the dedicated `com.openclip.ax-inspect` queue; an unresponsive app returns
  `nil` to the retrieval chain instead of hanging the popup.
- **The `ax-inspect` queue is concurrent, not head-of-line blocking.** All blocking AX work in the
  coordinator (the inspect snapshot and the Edit ▸ Copy AXPress) shares one concurrent
  `com.openclip.ax-inspect` queue: a hung AX call occupies one worker thread but later inspect
  snapshots and presses start on other threads, so a slow or stuck target no longer delays the next
  request's start. Each request still gets its own `axReadTimeout` deadline race.
  (`PasteAvailabilityProbe` deliberately keeps its own `ax-probe` queue plus a
  probe-slot gate so a stalled probe never spawns extra blocked workers.)
- **Subprocess pipe reads are non-blocking (hang fix).** `ShellProcessRunner` previously read stdout/
  stderr with blocking `readToEnd()` tasks and a `Task.sleep` watchdog — both can be starved, so a
  child (or grandchild) holding a pipe open could wedge the cooperative pool and hang the test
  suite indefinitely (observed mid-suite in `ScriptActionTests.testScriptExecution`). The runner now
  uses a GCD timer watchdog + GCD `readabilityHandler` reads + synchronous stdin close. This claim
  covers only the pipe reads: `process.waitUntilExit()` still blocks its detached thread until the
  child exits — bounded at `Constants.scriptTimeout`, when the watchdog kills the child and the wait
  returns.

## Selection Retrieval

- **The coordinator runs a single canonical strategy chain, not per-mode switch routing.**
  `retrievalMode` picks the entry point; retrieval then runs that strategy and every strategy below
  it in the chain (`ax-text-control → browser-script → ax-web-area → menu-copy → keyboard-copy`).
  An app with no rule starts at the top (auto). This mirrors SelectedTextKit's `.auto` model and
  removes the old `requireSelectionBeforeCopy` pre-gate — the copy engine decides whether a
  selection existed by observing the clipboard change. The chain is unit-tested with fixture
  targets, but the live per-app ordering is not exercised by an integration test.
- **Web-area settle-retry exhaustion is untested.** The `.axWebArea` retry loop
  (`webAreaSettleMaxRetries` = 6, re-inspecting fresh each attempt) returns `nil` when the text
  never appears, but the exhausted path has no dedicated test — the loop is exercised only through
  fixture snapshots in `SelectionRetrievalCoordinatorTests`. The `browser-script` fallback onto
  `AXWebAreaStrategy` is likewise covered by coordinator unit tests, not a live browser.
- **`browser-script` runs the osascript subprocess twice.** Each retrieval fires two AppleScript
  runs (selection text, then page URL) over Apple Events — up to 2 × `browserScriptTimeout` worst
  case. A single combined script would halve the automation round-trips but was left as two
  separately bounded runs for simplicity.
- **Copy-path clipboard visibility caveat.** The `.menuCopy`/`.keyboardCopy` engine leaves the
  captured selection on the general pasteboard for up to `pasteboardRestoreDelay` (0.8 s) before
  restoring the archived items. The restore is tagged `org.nspasteboard.TransientType` +
  `org.nspasteboard.AutoGeneratedType` so clipboard managers skip it, but anything that reads the
  pasteboard in that window (a live clipboard-manager UI, or another app polling `changeCount`) can
  observe the copied text.

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
- **Removed slow/flaky/environment-dependent tests:** the Apple Intelligence live-model test
  (`testAppleIntelligenceMatchesPresetPrompts`) made
  real on-device `LanguageModelSession` calls; `DebugLogEndToEndTests` polled `OSLogStore`
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