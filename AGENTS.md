# AGENTS.md — OpenClip AI Developer & Agent Guide

> **Note for AI Agents:**
> This file is loaded into every session, so it stays lean: essential commands, the hard
> design rules, and pointers to detail. Pull in a linked doc only when your task touches
> that area. See §6 for how to keep this file current.

---

## 1. Project Overview

**OpenClip** is a lightweight macOS (14.0+) floating popup utility in Swift. It reads selected
text, presents contextual actions (copy/cut/paste, definitions, web search, scripts, extensions),
and runs platform side-effects.

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
| Full test suite | `./scripts/test.sh` |
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
- **Popup panel internals** (never-key window, hover state, positioning, preview isolation) —
  `docs/architecture/popup-window.md`
- **Text selection & retrieval** (incl. clipboard fallback) — `docs/architecture/text-selection.md`

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
- **Transform on/off policy lives on `TransformCase.defaultDisabledActionIDs`**, not the registry;
  menu relevance filtering in `TransformCase.isRelevant(for:)`.
- **`OpenClipSnippetParser` is a pure text parser** — no `@MainActor`/UI. (Currently `@MainActor`; removal planned.)
- **Subprocess actions need a timeout watchdog** — terminate if past `Constants.scriptTimeout` (30 s).
  Any new action that spawns a subprocess must follow.
- **Swift 6 strict concurrency: continuation resume-once flags must be `@unchecked Sendable` classes**
  (see `OnceGate` in `CustomAction.swift`), not captured mutable locals.
- **`ActionContext.modifiers` is unused.** Don't build logic assuming modifier keys reach actions.
- **Gemini auth via the `x-goog-api-key` header only** — never `?key=` in the URL (leaks credentials).
- **Glass stays apart from the color themes.** `PopupThemeSelector` groups System/Light/Dark vs Glass;
  storage `popupTheme` + `popupThemeColor`. No flat 4-option picker or separate Glass switch.
- **Liquid Glass is macOS 26+ only** — `.ultraThinMaterial` fallback on macOS 14-15. Every glass
  surface keeps an `#available(macOS 26, *)` branch. Don't stack a dimmer under a glass card.
- **Standard windows unless a chrome-less card is the goal.** Preferences = stock chrome
  (`.titled`/`.fullSizeContentView`/`.hiddenTitleBar`) + `.glassSurface` content; the system provides
  shadow/corners/resize. A `.borderless` transparent window re-draws all of it manually.
- **Onboarding is a solid card, not a glass surface.** Transparent `borderless` window; `OnboardingView`
  draws a `windowBackgroundColor` rounded rect + border + SwiftUI shadow in a ~32pt inset container.
- **Popup/bubble shadows render inside the panel.** Keep ≥16pt SwiftUI padding around bar/bubble
  content (12pt info bubbles); shadows clip at the panel edge otherwise. Never re-enable
  window/panel `hasShadow`.
- **`PopupPreview` is a static visual, never a live registry snapshot.** Fixed canonical actions
  (Search/Copy/Cut/Paste/Services) + `alwaysShowAISparkles: true`; passes its own `PopupHoverState()`
  and `isStatic: true` so it never touches the real popup's hover state. Don't reconnect to the registry.
- **Hover state = one shared singleton + an opt-in static mode.** Real popup observes
  `PopupHoverState.shared`; any other `PopupView` gets its own `hoverState:` + `isStatic: true`
  (early-return in `updateHoveredTarget`/`useLocalHoverFallback`).
- **Shortcut with no selection falls back to the clipboard.** `HotkeyManager` reads the pasteboard
  and sets `isClipboardFallback`; the popup then shows Paste + AI only.

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
6. **`TransformCase` owns transform policy & relevance** — don't duplicate it elsewhere.
7. **Update file-level doc comments** when a file's responsibilities change.
8. **Always verify:** quick build gate first, then the full suite once at the end. The suite can
   hang in automated sessions, so prefer the gated build (`timeout -k 5 60 … build`).
9. **Popup must never be key.** No `canBecomeKey`/`canBecomeMain`/`makeKey()`; keyboard dismissal
   runs through the global (AX) event monitor only — observation-only, so keystrokes stay in the
   source app.

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