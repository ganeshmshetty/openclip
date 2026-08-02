# OpenClip Restructuring Plan

A clean-slate plan for restructuring the codebase. The current layout was vibe-coded and is treated as a migration source, not a design to preserve. Goal: **change one concept in one place** (locality), with small interfaces and deep modules.

---

## 1. Why restructure

Today, many features require touching 5–15 files because knowledge is duplicated:

| Symptom | Root cause |
|---------|------------|
| Icon/title changes fan out | Two appearance systems (`useText` + overrides), multiple icon renderers, id-based fallbacks |
| Extension format changes fan out | Actions constructed in factory *and* ExtensionManager *and* snippet parser |
| New action config UI fans out | String `configurationViewID` switches instead of data-driven options |
| Prefs/popup special cases | `action.id == "builtin.transform"`, `as? CustomAction`, etc. |
| Hard to test / wire | ~15 singletons calling each other; UserDefaults string keys everywhere |
| God files | `PreferencesView` ~900 lines, `PopupView` ~760, `ExtensionManager` ~425 |

Core idea of the rewrite: **one owner per concept**, thin UI, injectable services.

---

## 2. Target principles

1. **Deep modules** — lots of behavior behind a small interface; callers learn little.
2. **One door** — each concept has one construction path and one presentation path.
3. **Seams where things actually vary** — production + tests (or Mac + fake), not protocols for decoration.
4. **Data over type switches** — options, kinds, chrome described as data/enums; UI doesn’t `if id ==`.
5. **Core vs host stays** — pure domain in Core; AppKit/SwiftUI/JS/AppleScript in the app target.
6. **Replace, don’t layer** — after a module deepens, delete old paths and obsolete tests.

---

## 3. Target architecture

```text
┌─────────────────────────────────────────────────────────────┐
│  App (OpenClip)                                             │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────┐  │
│  │ UI          │  │ Platform     │  │ Runtimes           │  │
│  │ Popup       │  │ AX selection │  │ JS / AppleScript   │  │
│  │ Preferences │  │ Pasteboard   │  │ Process / URL open │  │
│  │ Onboarding  │  │ Hotkey/Menu  │  │ AI providers       │  │
│  └──────┬──────┘  └──────┬───────┘  └─────────┬──────────┘  │
│         │                │                      │             │
│         └────────────────┼──────────────────────┘             │
│                          ▼                                    │
│                   AppServices (composition root)              │
└──────────────────────────┬──────────────────────────────────┘
                           │ depends on
┌──────────────────────────▼──────────────────────────────────┐
│  Core                                                       │
│  ┌────────────┐ ┌─────────────┐ ┌──────────┐ ┌───────────┐ │
│  │ Actions    │ │ Extensions  │ │ Selection│ │ Settings  │ │
│  │ domain     │ │ packages    │ │ + Rules  │ │ store     │ │
│  └────────────┘ └─────────────┘ └──────────┘ └───────────┘ │
└─────────────────────────────────────────────────────────────┘
```

**Composition root:** one place (e.g. `AppDelegate` / `AppServices`) creates managers and injects them. No `X.shared` inside domain logic.

---

## 4. Target module map

### 4.1 Settings

**Module:** `SettingsStore`  
**Interface:** typed get/set for app settings (bool/string/data/list).  
**Owns:** all keys, defaults, migration from old UserDefaults keys.  
**Does not own:** business rules (only storage).

```text
SettingKey enum (or nested keys) — no raw "action.copy.useText" in call sites
```

---

### 4.2 Action domain

**Module:** `Action` (protocol) — keep small:

```text
id, title, icon (defaults only)
isEnabled(context) -> Bool
perform(context) -> ActionResult
options: [ActionOption]          // was ExtensionOption; universal
chrome: ActionChrome             // how UI treats this action
```

**`ActionResult`** — keep as the only effect language (copy/paste/openURL/…). Host has **one** `ActionResultHandler` (today’s popup controller logic, extracted).

**`ActionChrome`** (data, not type checks):

```text
badge: none | script | url | custom | extension
rowStyle: standard | transformGroup
popupBehavior: perform | showTransformMenu | provideCompletions
source: builtin | custom | extension(packageID)
```

**Builtins:** one type (or small set) registered from a single `BuiltinCatalog`. No per-action UserDefaults for appearance.

**Custom actions:** `CustomAction` + `CustomActionRepository` (load/save JSON). Edit via one `CustomActionDraft` + form view.

**Registry:** `ActionRegistry` — register, order, enable/disable, `available(for: context)`.  
**Coordinator:** `ActionCoordinator` — startup load sequence only (builtins → custom → extensions → rules). Thin.

---

### 4.3 Action presentation (critical)

**Module:** `ActionPresentation`

**Interface:**

```text
presented(action, surface: popup | table) -> (title, icon)
setOverride(actionID, title?, icon?)
reset(actionID)
```

**Owns:**

- Override storage
- Migration from old `useText` / preference icons
- Table vs popup policy

**UI:** single `ActionIconView(icon:size:)` for symbol / Iconify / url / local / text.

**Delete after migration:**

- `preferenceIconName`
- `action.*.useText` reads in each builtin
- `tableIcon` switch on `builtin.copy` / etc.
- Duplicate icon switches in Popup and Preferences

---

### 4.4 Extensions

Treat as a **package pipeline**, not one god class.

| Module | Responsibility |
|--------|----------------|
| `ExtensionManifest` | Decode `openclip.json` (+ legacy keys) → structured package |
| `ExtensionActionKind` | Normalized enum: url / js / applescript / shellInline / scriptFile |
| `ActionFactory` | **Only** place metadata → `Action` |
| `ExtensionInstaller` | Copy/unzip/remove under `~/.openclip/extensions` |
| `ExtensionLoader` | Scan disk → manifest → factory → `[Action]` + package records |
| `InstalledExtension` | package id, path, action IDs |
| `ExtensionsCatalogAPI` | Remote list (DTO + HTTP) |
| `RemoteExtensionInstaller` | HTTPS download → local installer |

**Hard rule:** loaders and snippet parser never construct `URLTemplateAction` / `ScriptAction` / etc. Factory only.

**Snippet parser:** `String → ExtensionManifest/ActionMetadata` only, then factory.

**Shell:** make two kinds explicit (`shellInline` vs `scriptFile`) so authors and code don’t confuse `CustomAction` shell with `ScriptAction` files.

---

### 4.5 Selection & rules

Keep direction; clean edges.

| Module | Notes |
|--------|--------|
| `SelectionMonitoring` | Port; Mac adapter in app |
| `TextRetrieving` | Port; `MacTextRetriever` stays deep in app |
| `AppFilter` | Static denylist |
| `RuleEngine` | Policies from defaults + user rules file |
| `SelectionCoordinator` | Monitor → context → callback |

No UserDefaults or registry calls inside retriever.

---

### 4.6 AI

Already relatively clean. Keep:

- `AIProvider` protocol
- Adapters: Apple / Ollama / Cloud / Browser
- `AIServiceManager` as settings + provider factory (inject `SettingsStore`)
- Shared `AIRequestSupport` for HTTP/sanitize

Optional later: split `CloudAPIProvider` by vendor behind one cloud adapter — not blocking.

---

### 4.7 UI structure (by feature, not one mega-view)

```text
UI/
  App/
    StatusBar, Onboarding, DeepLinks
  Popup/
    PopupWindowController   // lifecycle + monitors
    ActionResultHandler     // side effects
    PopupBarView            // main bar composition
    ActionButtonsView
    CompletionBarView
    AIBarView
    ActionIconView          // shared with prefs
  Preferences/
    PreferencesShell        // tab chrome only
    Tabs/General, Appearance, Actions, Rules, AI, Store, About
    Actions/ActionRow, TransformGroupRow, EditActionSheet
    Shared/ActionAppearanceFields, CustomActionForm, IconPicker
  Icons/
    UnifiedIconProvider, AnyIconView / ActionIconView, cache
```

**Rule:** Preferences tabs and popup bars consume `ActionPresentation` + `ActionChrome`; they do not re-implement icon policy or `is ScriptAction` badges.

---

### 4.8 Platform / runtimes (app target)

```text
Platform/
  Selection/ MacSelectionMonitor, MacTextRetriever, PermissionManager
  Input/ HotkeyManager, LaunchAtLogin
  Effects/ Pasteboard, KeySimulation   // used by ActionResultHandler
  Extensions/ DefaultActionFactory, RemoteExtensionInstaller
Runtimes/
  JavaScriptAction, AppleScriptAction
BuiltinPlatform/
  Completion, OpenURL, Services, RevealInFinder
```

Core builtins that need no AppKit stay in Core; AppKit builtins register from app at startup via coordinator.

---

## 5. Target source tree (suggested)

```text
Sources/
  Core/
    Actions/
      Action.swift              # protocol + ActionIcon + ActionResult + ActionChrome
      ActionContext.swift
      ActionRegistry.swift
      ActionCoordinator.swift
      ActionPresentation.swift  # overrides + resolve
      ActionOption.swift
      Builtin/
        BuiltinCatalog.swift    # registers all core builtins
        CopyAction.swift        # thin; no appearance UD
        ...
      Custom/
        CustomAction.swift
        CustomActionRepository.swift
        CustomActionDraft.swift
    Extensions/
      Manifest/
        ExtensionManifest.swift
        ExtensionActionKind.swift
      ActionFactory.swift       # protocol only in Core
      ExtensionInstaller.swift
      ExtensionLoader.swift
      InstalledExtension.swift
      SnippetParser.swift       # text → manifest only
      ScriptAction.swift        # or move file-script executor here
      Catalog/
        ExtensionsAPIClient.swift
        ExtensionItem.swift
    Selection/
      ...
    Rules/
      ...
    Settings/
      SettingsStore.swift
      SettingKey.swift
    Util/
      TextPlaceholderEngine.swift

  OpenClip/
    App/
      OpenClipApp.swift
      AppDelegate.swift
      AppServices.swift         # composition root
      StatusBarController.swift
    Platform/...
    Runtimes/
      DefaultActionFactory.swift
      JavaScriptAction.swift
      AppleScriptAction.swift
    UI/...
```

Exact file names can flex; **module boundaries above matter more than filenames**.

---

## 6. Dependency rules

```text
UI            → AppServices / protocols, not concrete disk/HTTP details
AppServices   → constructs Core + Platform
Core Actions  → SettingsStore protocol, not UserDefaults directly (ideal)
Core Ext load → ActionFactory protocol only
Runtimes      → Core Action types
Platform AX   → Core Selection ports

Forbidden:
  Core → SwiftUI / AppKit (except if you deliberately collapse targets later)
  ExtensionLoader → JavaScriptAction concrete type
  PopupView → UserDefaults for action appearance
  Builtin action → hard-coded preference icon strings for table
```

---

## 7. Phased migration plan

Do not big-bang rewrite. Each phase leaves the app shippable. After each phase: delete dead code and narrow tests to the new interface.

### Phase 0 — Inventory & freeze rules (½–1 day)

- List all UserDefaults keys and singleton graph (already largely known).
- Agree: **no new** `useText` keys, **no new** construct paths outside factory, **no new** icon switches in views.
- Add this file as the source of truth for PRs.

### Phase 1 — SettingsStore (1–2 days)

- Introduce `SettingsStore` + `SettingKey`.
- Route new code through it; migrate hot keys (action order, disabled IDs, appearance, AI).
- Keep a compatibility layer reading old keys once.

**Done when:** grep for `UserDefaults.standard` in Actions/ is near zero.

### Phase 2 — Action presentation (2–4 days) — **highest user-visible leverage**

- Finish single `ActionPresentation` module.
- One `ActionIconView`.
- Migrate `useText` → overrides; remove per-builtin appearance logic.
- Remove `preferenceIconName` and id switches in table icons.
- Tests only through `presented(_:surface:)`.

**Done when:** changing Copy’s default icon or label is one catalog/presentation change; popup and prefs match.

### Phase 3 — Action chrome & UI consumption (2–3 days)

- Add `ActionChrome` (or equivalent) on actions / catalog.
- Popup/Preferences use chrome for transform group, badges, delete affordance.
- Remove `action.id == "builtin.transform"` and most `is ScriptAction` checks.
- Split `PreferencesView` / `PopupView` along feature files **after** chrome exists (so splits follow seams).

**Done when:** adding a new “menu-style” action doesn’t edit Popup and Prefs with special cases.

### Phase 4 — Extensions pipeline (3–5 days)

- Extract manifest types from `ExtensionManager`.
- **Factory-only construction**; delete fallbacks in manager + snippet parser.
- `InstalledExtension` package identity; uninstall by package or documented action policy.
- Normalize `ExtensionActionKind`.
- Clarify shell inline vs script file.
- Remote store stays thin adapters.

**Done when:** `URLTemplateAction(` / `ScriptAction(` / `JavaScriptAction(` construction only in `DefaultActionFactory` (and tests).

### Phase 5 — Custom actions editor (1–2 days)

- Single `CustomActionDraft` + `CustomActionForm` for Add and Edit.
- Repository isolated from registry (registry notified by coordinator/services).

### Phase 6 — Composition root & de-singleton (2–4 days)

- `AppServices` owns instances; pass into UI via environment or explicit init.
- Domain types take dependencies in `init` (registry, presentation, settings, loader).
- Keep `shared` only as a temporary app-level accessor if needed; remove from Core types.

**Done when:** Core tests construct graph without touching global state.

### Phase 7 — ActionResultHandler & platform effects (1–2 days)

- Extract pasteboard/key simulation from popup controller into `ActionResultHandler`.
- Popup controller = window lifecycle only.

### Phase 8 — AI / polish (optional)

- Inject settings into AI manager.
- Trim Cloud provider if it becomes painful.
- Docs: replace old architecture pages with this model.

---

## 8. What to delete (end state)

| Remove | Replaced by |
|--------|-------------|
| Dual appearance (`useText` + ad hoc overrides) | `ActionPresentation` |
| `ConfigurableAction.preferenceIconName` | default `icon` + presentation |
| `ActionConfigSheet` id switches for text toggles | appearance sheet + options |
| ExtensionManager fallback constructors | `ActionFactory` only |
| Snippet parse → concrete Action fallback | snippet → metadata → factory |
| Popup/Prefs private icon switches | `ActionIconView` |
| Type checks for badges/delete | `ActionChrome.source` |
| Scattered UserDefaults string keys | `SettingsStore` |
| Cross-singleton calls in Core | injected deps |

---

## 9. Testing strategy

| Area | Test surface |
|------|----------------|
| Presentation | `presented(action, surface)` |
| Registry | `available(for:)` with fake settings |
| Factory | metadata fixtures → action → `perform` → `ActionResult` |
| Loader | temp directory packages → action IDs + package records |
| Snippet | string → metadata (not full Action) |
| Rules | `resolvePolicies` |
| Result handler | given result, assert pasteboard/URL effects with fakes |
| UI | light smoke; logic not in views |

Delete tests that only exist to pin old shallow helpers once the deep interface is covered.

---

## 10. Non-goals (for this restructure)

- Rewriting selection AX heuristics unless they block seams
- Redesigning extension *author* format from scratch (normalize loaders first; schema evolution later)
- Micro-protocol for every builtin
- Merging Core and App into one target
- Full DI framework — manual composition root is enough

---

## 11. Success metrics

1. **Locality:** “Change action default icon” → ≤2 files (catalog + maybe asset).  
2. **Locality:** “Add extension action kind” → manifest kind + factory case + runtime (± test).  
3. **Locality:** “Change popup icon rendering” → `ActionIconView` only.  
4. **Grep health:** one construction site for extension actions; one presentation resolver; one settings access pattern.  
5. **File size:** no SwiftUI file >> ~300–400 lines without a clear subview split.  
6. **Tests:** Core domain tests run without launching NSApp where possible.

---

## 12. Suggested PR sequence (Graphite/stack friendly)

1. `settings: introduce SettingsStore + migrate keys`  
2. `actions: ActionPresentation + ActionIconView; remove useText paths`  
3. `actions: ActionChrome; declutter popup/prefs special cases`  
4. `ui: split PreferencesView / PopupView along features`  
5. `extensions: manifest extract + factory-only load`  
6. `extensions: InstalledExtension + installer/loader split`  
7. `custom: shared CustomActionForm`  
8. `app: AppServices composition root; drop Core singletons`  
9. `platform: ActionResultHandler extract`

Each PR should end gre greppable-cleaner than it started (delete dead paths in the same PR).

---

## 13. Immediate next step

Start **Phase 1 + Phase 2** (Settings + Presentation). They unblock almost every other cleanup and match the pain of multi-file icon/title work already in flight.

Extensions factory exclusivity (Phase 4) is the second priority if you are actively changing package format; otherwise finish presentation first so UI stops moving under you.

---

## 14. One-page cheat sheet

```text
ONE settings door     → SettingsStore
ONE look door         → ActionPresentation + ActionIconView
ONE birth door        → ActionFactory (extensions/snippets)
ONE effect door       → ActionResult → ActionResultHandler
ONE chrome door       → ActionChrome (UI policy)
ONE wiring door       → AppServices

UI is thin. Core is deep. Platform is adapters.
```

This document is the restructuring plan. Implement against it; update phases only when the target modules change, not when temporary vibe paths reappear.
