# Implementation Plan: JS-Decided Menu Rows & Flattened Transform Extension

| Field | Value |
| :--- | :--- |
| **Title** | JS-Decided Menu Rows & Flattened Transform Extension |
| **Date** | 2026-08-04 |
| **Status** | Draft / Ready for Implementation |
| **Repo** | `/Users/ganesh/dev/openclip` |

---

## Objective

Let a JS extension action **decide at runtime how it appears in the popup bar / sub-menu** (whether shown and its one-line description), then ship the builtin Transform as a bundled, flattened (non-group) extension that uses it. Overcomes the two regressions that pure-declarative extensions would impose: exact no-op smart-filtering and a live, author-authored row description.

Does NOT change the generic sub-menu machinery: group-based extensions keep using it; Transform simply stops being a group.

---

## Key Decisions

1. **JS decides relevance + description itself** — the app does NOT infer relevance from `output != selection`.
2. **Author surface:** `openclip.menuShow(true/false)` (visibility) + `openclip.menuSubtitle("text")` (row/info text).
3. **Automatic for ALL JS actions and sub-actions** — no manifest opt-in flag required.
4. **Re-seed the transform extension every launch** so it is effectively always present (like a builtin).
5. **Transform is flattened:** 4 standalone JS actions (uppercase/lowercase/TitleCase/camelCase), group row removed.

---

## Capability Design

- Core protocol `MenuRowProviding: Action`:
  `func menuRow(for context: ActionContext) async -> MenuRow?`
- `MenuRow { visible: Bool; subtitle: String? }` (`Sendable`; Core, no `AppKit`/`SwiftUI`).
- **Semantics:** A conforming action computes its row by running its own JS. `visible=false` hides it (bar or sub-menu); `subtitle` is the dynamic row text (author-defined, freeform). Safe default when the action isn't `MenuRowProviding`, or compute returns `nil` (missing required option / JS exception) or no `menuShow`/`menuSubtitle` is called: `visible=true, subtitle=nil`.
- Non-conforming actions keep the existing declarative path: `RelevanceProviding` (regex) + `PreviewProviding` (template).

---

## Tasks

### Task 1: Core Capability & Renderers (App: PopupView)
- Add `Sources/Core/Actions/MenuRowProviding.swift` (protocol + `MenuRow`).
- `PopupView.menuBubble` (`PopupView.swift`): for a `MenuRowProviding` sub-action, `await menuRow(for:)` → skip row if `visible == false`; subtitle = `subtitle`; else existing path.
- Bar visibility: drop a non-group `MenuRowProviding` action from `displayActions` (async filter pass when the popup builds) when `visible == false`.
- **Tests:** Fake `MenuRowProviding` hidden/shown by `visible`, subtitle = author string; bar-drop mirror test.

### Task 2: JS Compute Mode (App)
- `OpenClipJSHost`: compute path returns `(visible, subtitle)` from new `menuShow`/`menuSubtitle` setters, discarding all side effects; defaults `true/nil`; `nil` on missing required option or JS exception.
- `JavaScriptAction` conforms to `MenuRowProviding` (already `@MainActor`).
- **Tests:** Capture; missing-required-option → `nil`; exception/side-effect-only → default.

### Task 3: Transform as a Bundled Flat Extension
- Bundled package `com.openclip.transform` (`openclip.json`), 4 standalone JS actions, no group: uppercase, lowercase, TitleCase, camelCase. Each JS: computes its conversion, calls `menuShow(<its own no-op/has-word check>)` + `menuSubtitle("→ <converted>")`, and `openclip.paste(...)` on perform; mimic Swift case semantics (word-splitting for TitleCase/camelCase).
- IDs `com.openclip.transform.{uppercase|lowercase|titleCase|camelCase}`.
- **Tests:** Golden-style test: flat set of 4 actions (no group row); no-op cases hide (already-caps hides UPPERCASE, single lowercase word hides camelCase, etc.).

### Task 4: Ship-by-Default (Re-Seed Each Launch)
- Bundle the package in app Resources; copy into `~/.openclip/extensions/` before `loadExtensions()` each launch (`ActionCoordinator.loadInitialState` / `AppDelegate`).
- Integration test for clean launch re-seeding.

### Task 5: Remove Native Transform
- Delete `Sources/Core/Actions/Builtin/TransformTextAction.swift` (`TransformCase`/`TransformSubAction`/`TransformTextGroupAction`); drop from `BuiltinRegistry.makeCoreBuiltins()`.
- `ActionRegistry.availableActions`: remove `TransformCase.defaultDisabledActionIDs` + `isTransformGroupEnabled` special-case; enable/disable via standard `disabledPackages`.
- `PreferencesView.swift`: remove the bespoke transform section.
- Re-point `PopupGesturePolicyTests`/`BuiltinRegistryTests`; replace `TransformRelevanceTests`/`TransformTextActionTests` with T3 JS parity tests.

### Task 6: Documentation & Agent Rules
- Replace `AGENTS.md` hard rules 4 & 6 (`TransformCase` policy / chrome-in-Core) with the `MenuRowProviding` + `menuShow`/`menuSubtitle` authoring rule.
- Update `docs/architecture/{overview,directory-structure,action-coordinator}`.

---

## Verification Plan

1. `xcodegen generate`
2. Quick gated build: `timeout -k 5 60 xcodebuild -project OpenClip.xcodeproj -scheme OpenClip -destination 'platform=macOS' build`
3. Full test suite: `./scripts/test.sh`
4. Manual verification via `./scripts/dev_run.sh`:
   - Lowercase selection → bar shows UPPERCASE/TitleCase/camelCase with live converted subtitles, lowercase hidden.
   - Relaunch → transform re-seeded.
   - Group-based extension still renders its sub-menu.
