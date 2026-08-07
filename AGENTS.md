# AGENTS.md — OpenClip AI Developer & Agent Guide

> **Note for AI Agents:**
> This file is loaded into every session, so it stays lean: essential commands, the hard
> design rules, and pointers to detail. Pull in a linked doc only when your task touches
> that area. See §6 for how to keep this file current.

---

## 1. Project Overview

**OpenClip** is a lightweight macOS (14.0+) floating popup utility in Swift. It reads selected
text, presents contextual actions (copy/cut/paste, definitions, web search, scripts, extensions),
and runs platform side-effects. A ⌥⌘C hotkey toggles the popup bar into an **action-search palette**
that filters the full action catalog (enabled and disabled) without leaving the popup.

- **Core** (Swift Package): pure domain models, actions, rules, selection logic, settings,
  manifest parsers. No `AppKit`/`SwiftUI`.
- **OpenClip** (App): AppKit panels, SwiftUI views, platform side-effect handlers, AI providers,
  composition root.
- **OpenClipTests** (XCTest): unit + integration for both targets.

---

## 2. Essential Commands

Prefer `scripts/` over raw `xcodebuild`/`xcodegen`:

| Task | Command |
| :--- | :--- |
| Regenerate Xcode project after adding/deleting Swift files (MANDATORY) | `xcodegen generate` |
| Build (Debug) + launch | `./scripts/dev_run.sh` |
| Build (Release) + package `build/OpenClip.zip` | `./scripts/package_app.sh` |
| Full test suite (can hang; wrap in a timeout) | `timeout -k 10 60 ./scripts/test.sh` |
| Single test class | `./scripts/test.sh SettingsStoreTests` |
| Clean DerivedData + build artifacts | `./scripts/clean.sh` |
| Install a local extension/snippet into `~/.openclip/extensions` | `./scripts/install_extension.sh <path>` |
| Quick compile gate (before the full suite) | `timeout -k 5 60 xcodebuild -project OpenClip.xcodeproj -scheme OpenClip -destination 'platform=macOS' build` |

---

## 3. Where the Detail Lives

OpenClip enforces strict single-responsibility subsystems. Read what's relevant before editing:

- **Architecture & the six subsystems** (settings, presentation, chrome policy, factory,
  result handler, coordinator) — `docs/architecture/overview.md`
- **Known debt / current-state realities** (UserDefaults → `SettingsStore` migration, singleton
  wiring, latent issues) — `docs/architecture/known-debt.md`
- **Annotated directory tree** — `docs/architecture/directory-structure.md`
- **Popup panel internals** (never-key window, hover state, positioning, preview isolation,
  content canvas + hover preview strip + status banner, action-search palette + panel-growth
  anchoring) — `docs/architecture/popup-window.md`
- **Text selection & retrieval** (incl. clipboard fallback) — `docs/architecture/text-selection.md`
- **Action-search palette** (search catalog/matcher, popup mode state machine, scoped key
  exception) — `Sources/Core/Actions/ActionSearch.swift`, `Sources/OpenClip/UI/Popup/PopupSearchView.swift`

---

## 4. Hard Design Rules (enforced, not suggestions)

These change behavior — keep them.

- **Accept dependencies, don't create them.** Core types needing settings accept `SettingsStore`
  in `init` (default `DefaultSettingsStore.shared`); tests inject a fake store.
- **No `ActionRegistry.shared` in Core domain.** Only `ActionCoordinator` touches the registry
  directly. `ExtensionManager` reports via `onRegister`/`onUnregister` callbacks wired in
  `ActionCoordinator.loadInitialState()`. The JSON manifest is the only canonical action
  definition: Add/Edit sheets write manifest packages via `CustomActionManifestWriter`, and
  `custom_actions.json`/`CustomActionManager` are retired.
- **No `switch action.id` string matching in presentation.** Use `ConfigurableAction.preferenceIconName`,
  `action.chrome.badge`, `action.icon`. (One legacy block in `ActionCustomizationManager.tableIcon`.)
- **`OpenClipSnippetParser` is a pure text parser** — no `@MainActor`/UI. (Currently `@MainActor`; removal planned.)
- **Subprocess actions need a timeout watchdog** — terminate if past `Constants.scriptTimeout` (30 s).
  Any new action that spawns a subprocess must follow. The JS runtime uses the same `TimeoutFlag`
  pattern (flag + pump-loop check; `JSVirtualMachine.invalidate()` no longer exists in modern SDKs).
- **Never `Self.<static>` inside a `Task.detached` closure** — it trips a Swift 6 region-based
  isolation checker bug (`"pattern that the region-based isolation checker does not understand how
  to check"`). Reference the type by name (`OpenClipJSHost.execute(...)`). See `docs/runtimes/javascript.md`.
- **Swift 6 strict concurrency: continuation resume-once flags must be `@unchecked Sendable` classes**
  (see `TimeoutFlag`/`OnceGate` in `Sources/Core/Extensions/ShellProcessRunner.swift`), not captured
  mutable locals.
- **`ActionContext.modifiers` is unused.** Don't build logic assuming modifier keys reach actions.
- **AI presets are registered Actions with chrome source `.ai`** (`AIAction`, synced by `AIActionSync`).
  They appear in the action-search palette and Preferences → Actions but are excluded from the popup
  bar (`ActionRegistry.availableActions`) — the bar's AI entry is the reorderable `builtin.aiTools`
  action (`AIToolsAction`, chrome `launchesAI`), which renders as a normal paginated bar row and
  routes its click into a **scoped AI-presets palette** (`onEnteredScopedSearch`), never `perform`.
  The palette routes `.ai` selections through `onRunAI` → `runAIPreset` (AI card), never `perform`.
  Enable/disable is single-sourced to `AIActionPreset.isEnabled`; the Actions-tab toggle shares it.
  `AIToolsAction`'s enable state is single-sourced to `isAIEnabled`, shared by the AI-tab and
  Actions-tab toggles; `launchesAI` actions are excluded from `searchCatalog`.
- **Group sub-actions open a scoped palette, not a floating panel.** Extension groups (`GroupAction` + registry
  entries id-prefixed `\(groupID).\\(subID)`) render as normal bar
  rows (`chrome.popupBehavior == .showSubActions` → `gesturePolicy.singleClick == .openSubActions`);
  a click calls `PopupWindowController.enterScopedSearch(for:)`, which resolves children via the Core
  `SubActionResolver` over `searchCatalog` and enters the palette with `modeStore.scope =
  SearchScope(parent:children:)`. `PopupSearchView` scopes results to those children, swaps the field's
  leading icon to the parent's, and its Esc path (`onExitScope`) drops the scope back to the bar. No
  hover sub-menu; membership is `SubActionProviding`-driven (`SubAction.swift`), never id switches.
- **Content renders in the single popup canvas, never a floating panel.** Actions, AI results,
  long-press result cards, hover previews (inline `PopupPreviewStrip`), and status (inline auto-dismiss
  banner / canvas corner badge) all render inside the one `PopupPanel`. `PopupContentView` is the only
  content renderer. Content mode (`.content` on `PopupModeStore`) is **not** a key-window exception —
  the panel stays non-key and Esc is observed by the global event monitor (observation-only).
- **Gemini auth via the `x-goog-api-key` header only** — never `?key=` in the URL (leaks credentials).
- **Glass stays apart from the color themes.** `PopupThemeSelector` has two rows: theme category
  (Classic | Glass) then appearance (System/Light/Dark). Storage: `popupTheme` ("classic"/"glass"),
  `popupThemeColor` (shared appearance "system"/"light"/"dark" — one value for both themes). A pinned
  appearance forces the popup's `colorScheme` via `PopupThemeModel.effectiveScheme` so the material *and*
  `.primary`/`.secondary` content flip together — that's the fix for near-white glass over a white
  background. The force is scoped with `.environment(\.colorScheme, ...)` on the popup content only,
  so it never changes the surrounding Preferences window (preview-only).
- **Liquid Glass is macOS 26+ only** — `.ultraThinMaterial` fallback on macOS 14-15. Every glass
  surface keeps an `#available(macOS 26, *)` branch. Don't stack a dimmer under a glass card.
- **`glassEffect(.regular)` casts an elevation shadow that scales with surface size** — it clips on
  large surfaces (e.g. the search palette) even with 16pt padding, while the small bar is fine.
  `GlassEffectContainer` does NOT fix it. The pattern that does: `.ultraThinMaterial` background +
  `.clipShape` + `.glassEffect(.clear)` + `.compositingGroup()` then the SwiftUI `.shadow`.
  `.clear` keeps the glass sheen but skips the frost/elevation layer (the material supplies frost).
- **Standard windows unless a chrome-less card is the goal.** Preferences = stock chrome
  (`.titled`/`.fullSizeContentView`/`.hiddenTitleBar`) + `.glassSurface` content; the system provides
  shadow/corners/resize. A `.borderless` transparent window re-draws all of it manually.
- **Onboarding is a solid card, not a glass surface.** Transparent `borderless` window; `OnboardingView`
  draws a `windowBackgroundColor` rounded rect + border + SwiftUI shadow in a ~32pt inset container.
- **Popup/bubble shadows render inside the panel.** Keep ≥16pt SwiftUI padding around bar/canvas
  content (12pt info cards); shadows clip at the panel edge otherwise. Never re-enable
  window/panel `hasShadow`.
- **`PopupPreview` is a static visual, never a live registry snapshot.** Fixed canonical actions
  (Search/Copy/Cut/Paste/Services) + `alwaysShowAISparkles: true`; passes its own `PopupHoverState()`
  and `isStatic: true` so it never touches the real popup's hover state. Don't reconnect to the registry.
- **Hover state = one shared singleton + an opt-in static mode.** Real popup uses
  `PopupHoverState.shared`; any other `PopupView` gets its own `hoverState:` + `isStatic: true`
  (early-return in `updateHoveredTarget`/`useLocalHoverFallback`). Views must hold `hoverState` as
  an unobserved stored property and subscribe only via `.onReceive(hoverState.$location)` — never
  `@ObservedObject`, because `location` publishes on every mouse move and observing the whole
  object re-evaluates the entire body tree per move.
- **Content-driven panel growth re-anchors in `PopupPanel.setFrame`.** The hosting view auto-resizes
  the panel top-anchored with no controller callback (`onContentSizeChange`/`sizingOptions` have no
  effect on this auto-resize); `pinBottomEdgeOnResize` keeps the bottom edge fixed so search results
  above the field don't shove the popup off the cursor, and `recenterXOnResize` keeps the horizontal
  center fixed so a narrower search palette / shorter pagination page doesn't drift the bar off the
  cursor. `show(for:)`/`hide()` clear both — don't work around the auto-resize with preference keys or
  resize callbacks.
- **Shortcut with no selection falls back to the clipboard.** `HotkeyManager` reads the pasteboard
  and sets `isClipboardFallback`; the full catalog then acts on the clipboard text except Copy/Cut,
  which `ActionChrome.requiresLiveSelection` + the registry gate drop (no live selection).

---

## 5. Instructions & Constraints

1. **Regenerate after file changes:** `xcodegen generate` whenever adding/removing `.swift` in
   `Sources/` or `Tests/`.
2. **Keep module boundaries:** never `import AppKit`/`SwiftUI` in `Sources/Core/Actions/` or
   `Sources/Core/Settings/`.
3. **No direct `UserDefaults.standard`** — use `SettingKey`/`SettingsStore` (Core) or
   `DefaultSettingsStore.shared` only in App target code. Don't add new direct call sites.
4. **No hidden singleton wiring in Core:** managers use `onRegister`/`onUnregister` callbacks,
   never `ActionRegistry.shared` directly.
5. **Data-driven UI:** use `action.chrome`, `ConfigurableAction.preferenceIconName`,
   `Action.gesturePolicy` — never Swift type checks (`is ScriptAction`) or `switch action.id`.
6. **Update file-level doc comments** when a file's responsibilities change.
7. **Test isolation:** any test class touching the app singletons (`ActionRegistry.shared`,
   `RuleEngine.shared`, `ExtensionManager.shared`, `ActionCustomizationManager.shared`) must call
   `TestIsolation.reset()` (in `Tests/OpenClipTests/TestIsolation.swift`) from `setUp()`, and must
   wire any shared state it reads (e.g. `ExtensionManager.shared.onRegister`) itself rather than
   relying on leaks from an earlier test class. `ActionCoordinator.shared` needs no reset (it
   mirrors the registry's `@Published` state).
8. **Always verify:** quick build gate first, then the full suite once at the end. The suite can
   hang in automated sessions, so wrap it in a 60 s timeout (`timeout -k 10 60 ./scripts/test.sh`).
9. **Popup must never be key — except the scoped action-search exception.** `PopupPanel.allowsKey`
   enables key status only in search mode, with focus forced via `focusSearchField()` on the next
   run-loop turn (a `@FocusState`-in-onAppear request is silently dropped on macOS); on exit/hide,
   `previousFrontmostApp` is re-activated. No other `canBecomeKey`/`canBecomeMain`/`makeKey()`;
   keyboard dismissal runs through the global (AX) event monitor only — observation-only, so
   keystrokes stay in the source app.

---

## 6. Keeping This File Alive (soft)

This file loads on every session, so keep it lean and true:

- **Prune.** A line is worth keeping only if the agent would otherwise do the wrong thing. Remove
  rules that are obsolete, too vague, or now second nature.
- **Push detail down.** Stable/debt content and "current-state" notes belong in `docs/` (linked
  above), not inline here. Prefer links + `file:line` pointers over pasted content.
- **Refresh cadence (not a hard rule).** After a meaningful batch of edits — roughly every ~15–20
  file changes, a finished feature, or a new convention — take a minute to refresh this file and
  the docs it points to if they'd otherwise drift. It's living documentation, so updating it in the
  same change you land is ideal; this isn't a blocker, just a habit. Same spirit applies to
  `docs/architecture/known-debt.md`, which drifts fastest.