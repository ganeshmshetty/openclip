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
- **Secrets live in SecretStore, not UserDefaults or macOS Keychain.** Sensitive credentials
  (the cloud AI API key and action secret options) use `SecretStore` (`~/.openclip/secrets.json`
  with 0600 POSIX permissions), replacing macOS Keychain to avoid code-signing ACL prompts.
  `AIServiceManager.cloudAPIKey` is `@Published`, backed by `SecretStore` (account `aiCloudAPIKey`);
  do not convert it back to `@AppStorage`. A one-time migration reads the old `UserDefaults`
  `"aiCloudAPIKey"` key, then deletes it.
- **`isAppEnabled` is consolidated** onto `SettingKey.isAppEnabled` — the status bar item and the
  Preferences toggle read/write it through `DefaultSettingsStore`. It means **"Appear
  Automatically"** (its label in both places): it owns the selection monitor's passive auto-show and
  nothing else. It is applied in `MacSelectionMonitor.deliverSelection` (the mouse-release/keyboard
  path) as the global form of the per-app `hotkeyOnly` rule; the explicit **Hold Mouse to Trigger**
  gesture delivers from `handleMouseDown` and is exempt, so off + hold = hold-only mode. The ⌥⌘C
  hotkey is an explicit request and is deliberately *not* gated on it.
  `HotkeyManager.triggerAllowed` gates on the
  real kill switches instead: Pause (`pauseUntilTimestamp`), app exclusion, per-app `disabled`. Builtin store-backed actions
  (`CalculateAction`, `CalendarAction`, `SearchAction`) accept an injected `SettingsStore` via
  `BuiltinRegistry.makeCoreBuiltins(settingsStore:)`.
- **Menu bar visibility is store-backed and reversible.** `SettingKey.showMenuBarIcon` defaults to
  true. `StatusBarController` removes/recreates its `NSStatusItem` immediately when the General-tab
  toggle changes, while reopening the running app presents Preferences so a hidden icon can be
  restored without terminating OpenClip.
- **`ActionConfigSheet` is gone** (dead code — zero presenting call sites; its `useText` keys were
  write-only). Removing it also dropped the only UI that wrote `SettingKey.searchURL` /
  `SettingKey.calculateMode`; the actions still read those keys (defaults apply). Search-engine
  configurability is **restored** via the built-in Search action's preset picker in the Preferences
  edit sheet (`DynamicActionConfigView` — Google / DuckDuckGo / Kagi / Brave / Bing / Ecosia /
  Custom), which writes the option-store key `action.builtin.search.option.url`
  (`SearchEnginePreset` in Core holds the curated catalog); calculate-result-mode still has no
  Preferences surface.
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
  stdin seeded and closed synchronously so a script reading stdin always sees EOF. Both pipe
  accumulators are drained **before** their buffers are read: `waitUntilExit()` returns when the
  direct child exits, so the readability handler can still be behind, or not have run at all. The
  drain is bounded — it waits `grace` (2 s) for EOF, reads what is pending, then closes the handle —
  so it captures output that reached the pipe before that deadline. A descendant that writes after
  the close still loses its output.
- **Delivery is resolved by `ActionResultDelivery`, not per-runtime translation.** Runtimes
  (`OpenClipJSHost.run`, `ShellResultMapper`, kind actions) return only raw results; implicitly
  returned text (JS string return, AppleScript output, shell stdout, text snippets) is emitted as
  `.text` and the paste-vs-copy/preview delivery decision (Select → Probe → Toast) is applied
  downstream from the action's author-declared output contract (`output` and `result` in manifest /
  `ActionChrome`), optional user per-action delivery override (`ActionCustomizationManager`),
  the universal secondary-click Clipboard Invariant (secondary click copies; or previews if primary is copy),
  and the unified paste availability. The flawed global settings (`primaryClickBehavior`/
  `secondaryClickBehavior`) are **fully removed**. The old `after` translator (the pre-refactor `after` orchestration step and its
  adapter) is **fully removed**. Synchronous JavaScript (including the top-level synchronous phase
  of async actions) is bounded by JavaScriptCore's VM execution-time limit **only when the run
  carries a budget** (`Request.timeout`), so an explicit timeout unwinds `evaluateScript` and
  releases its sync-evaluation gate slot. Idle promise waiting is bounded by the `TimeoutFlag`
  watchdog under the same budget. Runs with no budget (the default for extension/custom actions)
  have no timer and hold their gate slot until they settle or are cancelled; Swift task cancellation
  remains cooperative.
  A fetch response that arrives after the evaluation ends is discarded (`FetchTaskBox.isEnded`);
  the host does not call the JavaScript VM for it (issue #40). Uncaught exceptions that escape
  native-to-JS callbacks after initial evaluation (issue #48) reject the promise bridge via a
  per-evaluation `exceptionHandler` and surface as `.toast(.error)` without waiting for the idle
  watchdog. This does **not** detect detached unhandled promise rejections, and it does not change
  the retain-cycle residual below. Residual: retain cycles in
  `JSNativeFetch` (`nativeFetchBlock` → `contextBox`/`context`; `jsonBlock` → `JSContextBox`) and
  `PromiseState` (`JSValue?` → `JSValue.context`) keep the finished `JSContext` alive — this is
  **line-cited analysis, not empirically probed**. `PolicySession` does not invalidate its
  `URLSession`. A guarded `CFRunLoopPerformBlock` can still sit on the shared run loop and hold
  those references. Do not break a cycle unless the final release of `JSValue`/`JSContext` is
  guaranteed to land on the JS thread; otherwise an off-thread release becomes a memory-safety
  hazard.
- **Custom Action Groups use canonical IDs with dynamic materialization and strict $\ge 2$ member invariant.**
  User-defined action groups are defined via `ActionGroupDef` (`Sources/Core/Actions/ActionGroupDef.swift`),
  stored as JSON in `SettingKey.actionGroups`. Rather than rewriting action identifiers with virtual ID
  prefixes (e.g. `vgroup.<id>.<actionID>`), grouped actions retain their exact canonical IDs
  (`builtin.copy`, `com.user.ext.action`). `ActionRegistry` dynamically materializes `CustomGroupAction`
  (`Sources/Core/Actions/CustomGroupAction.swift`, conforming to `Action` and `SubActionProviding`)
  group rows, injecting them contiguously before their member actions in `actions`, while `SettingKey.actionOrder`
  strictly stores real, canonical IDs (excluding synthetic group headers and AI presets). `ActionCoordinator`
  manages the full group lifecycle (`createGroup`, `updateGroup`, `ungroup`, `removeFromGroup`, `loadGroupDefs`,
  `pruneOrphans`), automatically enforcing the strict $\ge 2$ member invariant: when members are uninstalled
  or removed, any group dropping below 2 members is immediately dissolved. Availability resolution in
  `ActionRegistry.availableActions(for:)` maps canonical IDs to owning custom groups to hide member actions
  when their parent group is disabled or filtered out.

## Extension JS Module Runtime

- **JS file scripts run in module mode (CommonJS).** A `javascript` action with `"script"` gets
  `require`/`module`/`exports`/`__dirname` and can split across local files; resolution is Node-style
  and contained to the package directory (`OpenClipModuleLoader` + `Constants.isPathSafe`), with
  `../`/symlink escapes, absolute paths, and bare/Node-builtin specifiers rejected. Containment is
  checked on the final symlink-resolved candidate, including the appended `.js` / `index.js`
  (issue #39). Folder installs are **not** scanned for symlinks at install time — only `.zip`
  entries are (`validateZipEntries`) — and `ExtensionPackageHashResolver` skips out-of-package
  symlink targets from the trust hash, so the loader is the last line of defense for file reads.
  Containment verification is bound directly to the open file descriptor via `fcntl(F_GETPATH)`
  before reading, preventing check-then-read races. Inline `scriptCode` actions have no modules
  (byte-identical legacy behavior).
- **Third-party libraries live on the author side, not the host.** npm deps are bundled by the
  author with esbuild (`--platform=browser --target=es2020`) into `dist/main.js`; the host loader is
  **`.js`-only**, so TypeScript works only through the bundle path (`--with-npm` scaffold). Node
  builtins are rejected at build time by the esbuild platform — they can never run.
- **The consent gate has landed; capability *enforcement* remains future work.** Nothing runs until
  a package is enabled (fail-closed trust states `seen`/`trusted`/`revoked` behind a single
  trust-model consent surface), and a tamper-watch auto-disables a trusted package whose content
  hash changed at a later load. Still future: JIT permission prompts, gating `fetch`/`keyPress`/
  `runShortcut`, seeding `ManifestCapabilityGate`, and a JS honesty-scan acting on mismatches.
  Extensions still execute in-process with the app's user context; module containment bounds file
  reads but is not a privilege boundary.

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
  never shoves the popup. For the search palette the pin is one-shot
  (`releasesBottomPinAfterGrowth`): it covers the entry growth only, so the palette's height can
  follow the result count without sliding the field; `exitSearch()` re-arms it for the search→bar
  collapse after restoring the bar's bottom edge (Esc no longer jumps the popup). Both flags are
  cleared by `show(for:)` and `hide()` before intentional placement.
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
  palette, and the result card stays open until it is collapsed or the popup hides.
- **The floating bubble panel is gone; content renders inline.** The second `PopupPanel` (and its
  `showBubble`/`hideBubble`/`bubbleBlocksDismiss` machinery) was removed — all action/AI/status
  content renders inside the single panel via `.content` mode (`PopupModeStore`) as a native
  SwiftUI `ResultCardView`. The card is general, not AI-specific: any text-returning action lands
  there with its customization-resolved icon (`DeliveryContext.actionIcon`, snapshotted by the same
  perform paths as `actionTitle`); AI streaming deliveries pass no icon and keep the sparkles glyph. `StatusBadgeModel` and the old `.info`/`.result`/`.menu` emphasis
  model are gone, and the inline status banner is gone too: every `StatusFeedback` renders as a
  floating toast (`ToastPanelController`) with no queue — a status shows over the card — and
  `showsLoading` actions (manifest `"loading"`) use the early-close spinner toast.
- **Define has a single display picker; popover mode is a system Look Up popover, not inline
  content.** `DefineAction` exposes one `definitionDisplay` picker (`card` default / `popover` /
  `dictionary`), replacing the old `openInDictionaryApp` boolean; a legacy `true` migrates to
  `dictionary` once at launch (`BuiltinRegistry.makeCoreBuiltins` →
  `DefineAction.migrateLegacyDisplayOptionIfNeeded`). `card` resolves in-process and lands in the
  result card like any text result; `dictionary` opens the `x-dictionary:` URL; `popover` returns the
  presenter-owned `ActionResult.showDefinition(word)` case, handled at the effect door by
  `NSView.showDefinition(for:at:)` anchored to the popup's content view. It has no card but is
  kept-open (`dismissesPopup == false`) so the popover keeps its anchor. Caveat: `PopupPanel` is a
  `.nonactivatingPanel`, so whether Look Up renders without an `NSApp.activate()` is unverified.
- **File results preview inline by kind.** `FileOutputKind`
  (`Core/Actions/FileOutputKind.swift`) classifies a `FileOutputPayload` into `image` / `pdf` / `text` /
  `other` from its MIME type, falling back to `UTType` conformance on the filename extension, so
  path-only results (no MIME) classify correctly; `isImage` is now `kind == .image`. `ResultCardView`
  routes on the kind: images keep the aspect-fitted `NSImage`/SVG preview, PDFs embed `PDFKit`'s
  `PDFView`, text-kind files load up to 100 KB and render inline monospace (an unreadable/binary file
  downgrades to `other`), and everything else (audio/video/office/archives/unknown) embeds
  `QLPreviewView` with a filename/size caption. The generic icon + metadata card (`NSWorkspace` icon)
  stays the fallback for a failed image or binary-text load, so a file result is never blank. The
  temporary-output filename map in `ShellProcessRunner.extensionForMimeType` gained the
  generated-document/media MIME types (md, csv, html, xml, yaml, rtf, docx, xlsx, pptx, wav, m4a, mov,
  webm) plus a `UTType` fallback instead of the old closed 11-entry list. ⌘S/⏎ save and ⌘C copies;
  Space no longer opens the Quick Look panel (the key is left to the focused preview) — the generic
  fallback card keeps a click-only **Preview** button. Embedded `PDFView`/`QLPreviewView` previews
  render outside the card's outer `ScrollView` so their own scrolling isn't shadowed, PDF card
  sizing uses page 0's rotated crop box, and an unopenable PDF falls back to the generic card.
  Drag-out is scoped to the filename caption for embedded previews (leaving PDF text selection the
  page area) and stays whole-body for images and text files.
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
  (5), `searchResultRowHeight` (32), `searchPeekRowFraction` (0.5), `popupMaxHeight` (300, the
  shared height cap for the popup panel — lifted per-session via `PopupPanel.heightCap` while the
  result card shows, since a user-resized card may be taller), the AI card bounds
  (`aiCardMinWidth` 220 / `aiCardIdealWidth` 320 / `aiCardMaxWidth` 360 / `aiCardMinHeight` 200 /
  `aiCardMaxHeight` 280 — the max bounds only cap the content-driven default; the card's resize
  handles go up to the screen, see `PopupResizeGeometry`) plus placement/dismissal
  distances. The remembered card size is a popup preference declared in the App
  target (`SettingKey+ResultCard.swift`, next to
  `SettingKey+MenuBar.swift`) because it is pure presentation. `Core/Selection/Constants.swift` keeps only
  domain/runtime constants (timeouts, key codes, env vars, manifest keys).

## AI Providers

- **Apple Intelligence is gated by one availability source.** `AppleIntelligenceAvailability`
  (`Sources/OpenClip/AI/AppleIntelligenceAvailability.swift`) folds the `#available(macOS 26.0, *)`
  floor together with `SystemLanguageModel.default.availability` (`deviceNotEligible`,
  `appleIntelligenceNotEnabled`, `modelNotReady`) into one `Status`, and owns the copy for each. The
  Preferences status row (`AIConfigureForm`) and the provider's runtime errors both read it, so they
  can't disagree about *why* the feature is off. The Apple picker segment is still selectable on
  unsupported machines — it explains rather than disables.
- **The Apple provider uses guided generation, not tag scraping.** `AppleIntelligenceResponse`
  (`@Generable`, in `AppleIntelligenceProvider.swift`) declares `result`/`title`, so the framework
  constrains the model's output; the provider re-emits those fields via
  `AIRequestSupport.taggedResponse` into the `<result>`/`<title>` contract that the palette, result
  card, and save-as-tool flows already parse. `systemPrompt(structuredResult:)` swaps the tag
  instructions for schema-field wording, because asking for tags would make the model embed them
  inside the fields; `taggedResponse` additionally runs values through `stripTagMarkup` for the same
  reason, since the palette's text-shaped prompts still say "inside <title> tags".
- **One name per response.** `<title>` carries the short name for the work — a task heading for the
  answer card, or a reusable action name when saving a palette instruction as an AI tool. Which
  style to produce is the flow's business and lives only in the prompt wording
  (`PaletteAIPrompt.saveToolTaskPrompt`); one generated name serves both the preset title and the
  card heading in the save flow.
- **`tokenCount` is only used as a pre-flight guard.** The provider counts tokens (macOS 26.4+) and
  compares against `contextSize` only when the input exceeds `tokenBudgetCheckThreshold` (2000
  chars), throwing `requestTooLarge` before paying for a doomed generation. Oversized selections are
  **not** auto-routed to another provider.
- **macOS 27 APIs are not yet adopted.** `PrivateCloudComputeLanguageModel`, the new `LanguageModel`
  protocol, and the Vision-backed tools (OCRTool/BarcodeReaderTool) are macOS 27 / Xcode 27 only and
  are absent from the 26.5 SDK this repo builds against, so they cannot be referenced at all
  (`#if canImport(FoundationModels)` is already true on 26.x, so a symbol reference breaks the
  build rather than failing at runtime). Adding Private Cloud Compute and the model-abstraction
  refactor is deferred until the toolchain is upgraded.

## Unused / Latent

- **`ActionContext.modifiers` is currently unused.** No action reads it; `PopupWindowController`
  passes `modifiers: []`. The click intent itself *is* plumbed: `ActionContext.isSecondaryClick` is
  set from
  the run's resolved intent by the bar/sub-bar/palette perform paths (right-click or ⇧-click via
  the bar/sub-bar mouse intent; ⇧⏎ and the ⇧⏎ footer badge via the palette's own `replace` flag,
  passed explicitly through `onWillPerformAction`/`onRunLoadingAction`) and read by `DefineAction`
  to copy a definition headlessly. True modifier keys (⌘/⌥) still don't reach actions.
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
  only ⇧ (not ⌘/⌥); the bar/sub-bar take it from mouse-down, while the palette resolves it itself
  (`replace` for ⇧⏎ / the ⇧⏎ badge, else the captured mouse intent) and passes it explicitly into
  the delivery snapshot, and entering the palette resets `pendingClickIntent` so a keyboard run
  never inherits the right-click that opened a group's scoped palette. Since Task 4, each action's
  declared `Action.delivery` (a distinct
  secondary outcome + per-click `primaryToast`/`secondaryToast`) is snapshotted alongside the click
  intent and fed into `resolve`, and the returned tuple's toast is rendered directly — the manual
  `isDowngradedToCopy`/`isCopyDefinition` inline toast detection was removed in favor of the resolved
  `.toast`. Since Task 8, a script-emitted `.toast` (or any result whose `containsToast` is true)
  suppresses the delivery companion toast entirely — one toast per run — and `keepVisible: true`
  stops a toast's auto-dismiss and keeps the popup open (a `.toast` dismisses by default). Only the
  SwiftUI inline perform path snapshots via the new `onWillPerformAction` closure;
  the completion-button paste path (`PopupView` `onResult(.paste(word))`) routes through
  `deliverResult`, which clears `pendingDelivery` right after its snapshot (single-use per perform),
  so a prior non-dismissing action's declared delivery can never leak onto a completion paste. The
  force-copy probe short-circuit skips the AX walk for a secondary click whose outcome is a copy;
  a declared `.paste` secondary is the exception and still probes, so it is honored when the target
  can paste (and downgrades to copy when it cannot). Implicitly returned text
  (runtimes emit `.text`, never auto-dismissing) is resolved by `ActionResultDelivery.resolve`
  using the action's author output contract (`output` and `result` in manifest / `ActionChrome`),
  optional user per-action delivery override (`ActionCustomizationManager`), the universal secondary-click
  Clipboard Invariant, and unified AX paste availability: a paste outcome probes like any paste
  and downgrades to copy when the target can't paste, a copy outcome delivers a native copy with no toast,
  and a preview outcome keeps the popup open for the card render — dismissal for `.text` is decided by
  the controller's `shouldDismiss`, not `dismissesPopup`. The loading re-show path (`settleLoadingResult`)
  re-creates the popup from the pre-early-close selection snapshot to present the card.
  - **Target application and delivery context snapshotted before perform.** Asynchronous actions snapshot
    the target application, app policy, and declared delivery into an `inFlightDeliveryContext` (or local task
    constant) before performing. If the user switches applications while an asynchronous action is executing,
    `resolveDelivery` detects that the target application is no longer active and safely downgrades `.paste`
    to `.copy` with a "Copied" toast to prevent pasting into the newly focused application.
  - **Re-show binds to the current frontmost app.** The loading-preview re-show
    (`settleLoadingResult`) re-creates the popup from the selection snapshot, but `hide()`
    clears `previousFrontmostApp`, so the re-show re-captures whatever is frontmost at settle
    time — if the user switched apps during a multi-second spinner, dismissal reactivates that
    app. The card's paste probe correctly targets the snapshotted app; only dismissal's
    reactivation is affected.
  - **`.text` inside a `.sequence` is unhandled.** Runtimes emit `.text` only as a lone result
    today, so a `.text` inside a sequence is defensive-only; if the runtime surface ever grows to
    emit `.text` in sequences, the tree-walk needs explicit handling.
- **HotkeyManager.executor pattern** (`HotkeyManager.swift:22`): a latent `Task { @MainActor in`
  inside the shortcut callback could be hardened to an explicit executor; optional.

## Concurrency

- **Residual non-interruptible paths (documented).** Two spots remain that a hostile
  or hung target can make block a background thread:
  (1) `SelectionRetrievalCoordinator.pressEditCopyMenu` starts an AXPress on the dedicated
  `com.openclip.ax-inspect` queue. The `pasteboardCopyTimeout` poll does not stop that press.
  A blocked target can occupy one queue worker until AX returns or
  `AXUIElementSetMessagingTimeout` (`Constants.axReadTimeout`) ends the call.
  The `inspectGate` permit is not held for that duration.
  `pressCopyMenuWithWatchdog` releases the permit at the first of {press returned, `axReadTimeout`},
  same OnceResume race as inspect. The queue is concurrent, so a blocked press does not delay
  later retrieval requests (see below);
  (2) `PasteAvailabilityProbe.editPasteEnabled` walks the menu bar up to an aggregate deadline
  passed through `AXMenuNavigator.findMenuItem`. Each AX message also has a per-call limit of
  `axReadTimeout`. An abandoned walk stops at `pasteProbeTimeout` (or upon completing an in-flight message),
  so workers do not linger for minutes on the queue. The counting gate releases its permit at the deadline
  (issue #37) so subsequent probes are never delayed.
  These paths do not block the main actor.
- **AX inspect is deadline-capped.** `SelectionRetrievalCoordinator.inspectWithWatchdog` races
  `AXElementInspector.inspect` against
  `Constants.axReadTimeout` (0.5 s) via the `OnceResume` once-gate, running the blocking snapshot on
  the dedicated `com.openclip.ax-inspect` queue; an unresponsive app returns
  `nil` to the retrieval chain instead of hanging the popup.
- **Inspect concurrency is bounded, not serialized.** The old single fail-fast `axSlot` made every
  overlapping gesture (rapid re-selection, double-click, hotkey+monitor races) miss entirely and
  stayed occupied until the underlying AX call returned — one heavy page suppressed popups
  process-wide for seconds. Reads now go through a counting gate (`Constants.axMaxConcurrentInspects`,
  currently 4): concurrent reads proceed in parallel, the permit frees when the caller's watchdog
  settles (deadline or completion), and only genuinely saturated bursts skip. Menu-copy presses
  share the same gate. The permit is released at `axReadTimeout`, same as inspect.
- **The `ax-inspect` queue is concurrent, not head-of-line blocking.** All blocking AX work in the
  coordinator (the inspect snapshot and the Edit ▸ Copy AXPress) shares one concurrent
  `com.openclip.ax-inspect` queue: a hung AX call occupies one worker thread but later inspect
  snapshots and presses start on other threads, so a slow or stuck target no longer delays the next
  request's start. Each request still gets its own `axReadTimeout` deadline race.
  `PasteAvailabilityProbe` uses the same design (issue #37): a concurrent
  `com.openclip.ax-probe` queue and a counting gate (`Constants.pasteProbeMaxConcurrent`, 4).
  The side that ends the wait releases the permit at `pasteProbeTimeout`.
  The old `probeSlot` stayed occupied until the blocked AX walk returned.
  That stopped every later probe and changed all paste operations to copy.
- **Subprocess pipe reads are non-blocking (hang fix).** `ShellProcessRunner` previously read stdout/
  stderr with blocking `readToEnd()` tasks and a `Task.sleep` watchdog — both can be starved, so a
  child (or grandchild) holding a pipe open could wedge the cooperative pool and hang the test
  suite indefinitely (observed mid-suite in `ScriptActionTests.testScriptExecution`). The runner now
  uses a GCD timer watchdog + GCD `readabilityHandler` reads + synchronous stdin close. This claim
  covers only the pipe reads: `process.waitUntilExit()` still blocks its detached thread until the
  child exits — bounded only when the invocation carries an explicit `timeout`, which arms the
  watchdog; with none (the default) it runs until the child exits or the caller cancels. At timeout
  the watchdog starts descendant cleanup (the child, the process group when the child is the leader,
  and remaining descendants).
  `waitUntilExit()` waits only for the direct child; descendant SIGKILL is scheduled asynchronously
  and may finish after the wait returns. Descendants come from a `proc_listchildpids` walk of the
  child's own subtree (not a scan of the whole process table), snapshotted with start times before
  `terminate()`. Two limits remain: a probe that reports 0 children is still read once, because a
  spurious 0 would silently drop a descendant; and a grandchild that reparented to launchd before
  the snapshot is unreachable by any pid walk.

## Selection Retrieval

- **The coordinator runs a targeted strategy chain with native AX prioritization.**
  `retrievalMode` picks the entry point; retrieval runs that strategy and its fallbacks
  (native text controls fall back to keyboard copy unless strictly native; web areas cascade
  `ax-web-area → keyboard-copy`). Browsers resolve natively via `AXWebArea` in <1 ms with deep
  ancestor search (depth 25 + window search) and fall back to keyboard copy with a 0.6 s timeout,
  completely removing the legacy `browser-script` AppleScript subprocess churn and permission friction.
- **Web-area settle-retry exhaustion is untested.** The `.axWebArea` retry loop
  (`webAreaSettleMaxRetries` = 6, re-inspecting fresh each attempt) returns `nil` when the text
  never appears, but the exhausted path has no dedicated test — the loop is exercised only through
  fixture snapshots in `SelectionRetrievalCoordinatorTests`.
- **Copy-path clipboard visibility caveat (mostly closed in OpenSelection 0.2.6).** The
  `.menuCopy`/`.keyboardCopy` engine restores the archived items synchronously in the same
  run-loop turn as the capture read (no grace sleep; exposure is microseconds), tagged
  `org.nspasteboard.TransientType` + `AutoGeneratedType` + `ConcealedType` so clipboard managers
  skip it. A residual microsecond race remains for a clipboard manager polling `changeCount`
  between the synthetic copy landing and the restore; `pasteboardRestoreDelay` no longer gates
  the capture path (it only backs the paste-back `SelectionReplacer`).
- **Hold-trigger clipboard fallback is structurally gated, not cursor-gated.** The
  `MacSelectionMonitor` hold task inherits the clipboard only when the press point resolves to
  editable text via `pressIsOverEditableText` (and paste is not denied): an AX hit-test to a text
  control, or the focused editable element's frame covering the press (CodeMirror/Monaco's
  caret-anchored hidden textarea). The earlier I-beam-cursor signal was dropped — browsers render
  an I-beam over *read-only* selectable text, so it re-admitted the fallback over web articles.
  A "shared web area" widening was also rejected: it admitted any read-only page text while an
  input elsewhere held focus, which is the leak the gate exists to prevent. Residual limit: a
  custom-drawn editor exposing no AX text control at all (rare outside terminals, which are
  policy-excluded) will not fall back. The whole probe shares one `axReadTimeout` budget — every
  attribute read is capped and the ancestor walk stops at the same deadline, because it runs on
  the main actor inside the hold task.


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
- **Isolated in-memory test doubles and seams.** Store-backed tests use `MemorySettingsStore`
  rather than writing the real preferences domain, and `SecretActionOptionStoreTests` redirects to a
  temporary file (`SecretStore.setFileURLForTesting`),
  eliminating live system pasteboard/keychain mutation during test runs.
- **Removed slow/flaky/environment-dependent tests:** the Apple Intelligence live-model test
  (`testAppleIntelligenceMatchesPresetPrompts`) made
  real on-device `LanguageModelSession` calls; `DebugLogEndToEndTests` polled `OSLogStore`
  with multi-second sleeps; `ScriptActionTests` duplicated `ScriptActionExecutionTests`; and
  interactive popup panel/toast/search UI tests requiring live window-server positioning were
  trimmed to optimize test execution speed and keep the unit test suite fast and deterministic.
  Core domain logic, validation, action execution, and isolation tests remain fully covered.

## Logging

- **Single `Log` surface is in.** `Sources/Core/Log.swift` owns every `os.Logger` category
  (`settings`, `presentation`, `chrome`, `factory`, `coordinator`, `result-handler`, `shell`, `js`,
  `selection`, `extensions`, `ai`, `permissions`, `icons`, `updates`); all `print()` calls are gone. See
  `docs/logging.md` for the category table and filtering workflow.
- **Level budget is conservative.** Most messages are `.notice`/`.error`; `.debug` is used for
  defensive parses and transient network hiccups (filtered out by default in Console).
- **`chrome` category is reserved but unused** — no popup-window-chrome code logs yet.
- **`RotatingFileLogSink` keeps all non-`Sendable` state on its serial queue**, including
  its `DateFormatter`; its `@unchecked Sendable` depends on that rule (#45).
