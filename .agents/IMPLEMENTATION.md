# Agent Prompt: Implement OpenClip (Clean-Room Build)

## Your Role
You are the **Implementation Team** in a clean-room engineering project.
You will build **OpenClip** — an open-source macOS text-selection utility — from scratch in Swift.

## The Chinese Wall Rule — CRITICAL
You are the clean side. You must NEVER look at:
- `~/dev/openclip/reference/` (binary analysis artifacts)
- `~/dev/openclip/SPEC_AGENT_PROMPT.md` (the analysis prompt)
- Any decompiled or disassembled output

You may ONLY read:
- `~/dev/openclip/spec/` (the functional spec folder)
- Apple's official documentation
- Open-source MIT/Apache licensed libraries listed below

If the spec is ambiguous, use your own design judgment. Do NOT go back to the binary.

---

## Tech Stack (Mandatory)

| Layer | Choice | Reason |
|---|---|---|
| Language | Swift 6 (strict concurrency) | Modern, safe, no legacy ObjC baggage |
| UI Framework | SwiftUI + AppKit interop | SwiftUI for views, NSPanel for popup window |
| Persistence | SwiftData (macOS 14+) | Modern replacement for CoreData |
| Hotkeys | [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | MIT, modern, SwiftUI-native |
| Defaults | [Defaults](https://github.com/sindresorhus/Defaults) | MIT, type-safe UserDefaults wrapper |
| JS Runtime | JavaScriptCore (system, no install) | Already on every Mac |
| Auto-update | [Sparkle 2](https://sparkle-project.org/) | MIT, industry standard |
| Networking | URLSession (system) | No external dependency needed |
| Package manager | Swift Package Manager only | No CocoaPods/Carthage |
| Min macOS | macOS 14 Sonoma | Required for SwiftData |
| App type | Non-sandboxed, Agent app (LSUIElement) | Required for Accessibility API |

---

## Project Structure to Create

```
~/dev/openclip/
├── OpenClip.xcodeproj  (or Package.swift if CLI-first)
└── Sources/
    └── OpenClip/
        ├── App/
        │   ├── OpenClipApp.swift          ← @main, NSApplicationDelegate
        │   ├── AppDelegate.swift
        │   └── Info.plist
        │
        ├── Core/                          ← No UI, no AppKit. Pure logic.
        │   ├── Selection/
        │   │   ├── SelectionMonitor.swift     ← Global mouse event watcher
        │   │   ├── TextRetriever.swift        ← AX + fallback strategies
        │   │   ├── SelectionContext.swift     ← Value type: text, app, position
        │   │   └── AppFilter.swift            ← Excluded app logic
        │   │
        │   ├── Actions/
        │   │   ├── Action.swift               ← Protocol definition
        │   │   ├── ActionContext.swift        ← Input passed to every action
        │   │   ├── ActionResult.swift         ← Output from every action
        │   │   ├── ActionRegistry.swift       ← Registers all known actions
        │   │   └── Builtin/
        │   │       ├── CopyAction.swift
        │   │       ├── CutAction.swift
        │   │       ├── PasteAction.swift
        │   │       ├── SearchAction.swift
        │   │       ├── OpenURLAction.swift
        │   │       └── ServicesAction.swift
        │   │
        │   ├── Extensions/
        │   │   ├── Extension.swift            ← Extension value type
        │   │   ├── ExtensionLoader.swift      ← Loads .openclipext packages
        │   │   ├── ExtensionRegistry.swift    ← Tracks installed extensions
        │   │   ├── ExtensionValidator.swift   ← Signature + schema check
        │   │   └── ExtensionConfig.swift      ← Decoded config schema
        │   │
        │   ├── JavaScript/
        │   │   ├── JSRuntime.swift            ← JavaScriptCore wrapper
        │   │   ├── JSActionBridge.swift       ← Exposes action API to JS
        │   │   └── JSXHRBridge.swift          ← XHR for JS extensions
        │   │
        │   ├── Rules/
        │   │   ├── Rule.swift                 ← Rule value type
        │   │   ├── RuleEvaluator.swift        ← Matches rules to context
        │   │   └── RuleCondition.swift        ← App, URL, text conditions
        │   │
        │   └── Persistence/
        │       ├── AppStore.swift             ← SwiftData container setup
        │       ├── LayoutStore.swift          ← Action order/grouping
        │       └── SyncCoordinator.swift      ← iCloud / CloudKit sync
        │
        ├── UI/
        │   ├── Popup/
        │   │   ├── PopupWindowController.swift  ← NSPanel lifecycle
        │   │   ├── PopupPanel.swift              ← NSPanel subclass
        │   │   ├── PopupView.swift               ← SwiftUI root view
        │   │   ├── ActionButton.swift            ← Individual button
        │   │   └── PopupPositioner.swift         ← Where to show popup
        │   │
        │   ├── Preferences/
        │   │   ├── PreferencesWindowController.swift
        │   │   ├── GeneralPane.swift
        │   │   ├── AppearancePane.swift
        │   │   ├── ActionsPane.swift
        │   │   ├── ExtensionsPane.swift
        │   │   ├── ShortcutsPane.swift
        │   │   └── AboutPane.swift
        │   │
        │   ├── StatusItem/
        │   │   └── StatusBarController.swift    ← Menu bar icon + menu
        │   │
        │   └── Icons/
        │       ├── IconResolver.swift           ← SF Symbol / custom / URL
        │       └── IconPickerView.swift
        │
        ├── Platform/
        │   ├── AccessibilityPermission.swift    ← AXIsProcessTrusted wrapper
        │   ├── LoginItemManager.swift           ← ServiceManagement wrapper
        │   ├── HotkeyManager.swift              ← KeyboardShortcuts wrapper
        │   └── PasteboardHelper.swift           ← NSPasteboard utilities
        │
        └── Resources/
            ├── Assets.xcassets
            └── Localizable.xcstrings
```

---

## Implementation Order (Build in This Sequence)

### Phase 1 — Skeleton (Day 1)
Read: `spec/01_executive_summary.md`, `spec/02_system_architecture.md`, `spec/03_permissions.md`

Tasks:
1. Create the Xcode project as a non-sandboxed macOS agent app (`LSUIElement = YES`)
2. Set up Swift Package Manager with all dependencies
3. Write `AppDelegate.swift` — empty but wired correctly
4. Request Accessibility permission on first launch with explanation
5. Create `StatusBarController` — menu bar icon that does nothing yet
6. Confirm app runs without crashing and appears in menu bar

Deliverable: App launches, shows menu bar icon, prompts for Accessibility permission.

---

### Phase 2 — Core Selection Engine (Days 2–3)
Read: `spec/04_text_selection.md` (most important — read fully before writing any code)

Tasks:
1. `SelectionContext.swift` — define the value type first:
   ```swift
   struct SelectionContext {
       let text: String
       let sourceApp: NSRunningApplication
       let cursorPosition: CGPoint
       let timestamp: Date
   }
   ```
2. `AppFilter.swift` — excluded apps list from spec, wildcard bundle ID matching
3. `TextRetriever.swift` — implement 3 strategies in order:
   - Strategy 1: `AXUIElementCreateSystemWide()` → `kAXFocusedUIElementAttribute` → `kAXSelectedTextAttribute`
   - Strategy 2: Simulate Cmd+C, read `NSPasteboard.general`, restore previous contents
   - Strategy 3: AppleScript `tell application X to get selection`
4. `SelectionMonitor.swift` — global `NSEvent.addGlobalMonitorForEvents([.leftMouseUp])` observer,
   debounce using the timing thresholds in the spec, call TextRetriever on each trigger

Deliverable: On mouse-up after selecting text, `SelectionContext` is printed to console.

---

### Phase 3 — Popup Window (Days 4–5)
Read: `spec/05_popup_window.md`, `spec/06_action_system.md`

Tasks:
1. `PopupPanel.swift` — subclass NSPanel:
   ```swift
   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView]
   level: .floating
   collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary]
   backgroundColor: .clear
   isOpaque: false
   ```
2. `PopupPositioner.swift` — calculate frame from cursor position + screen bounds
3. `PopupView.swift` — SwiftUI view inside an `NSHostingView`, horizontal button row
4. `ActionButton.swift` — icon + optional title, hover state, click handler
5. Dismiss logic: mouse moved beyond threshold, Escape key, click outside, new selection
6. Wire `SelectionMonitor` → `PopupWindowController` → show/hide panel

Deliverable: Selecting text anywhere shows a floating popup with placeholder buttons.

---

### Phase 4 — Built-in Actions (Day 6)
Read: `spec/06_action_system.md`

Tasks:
1. Define `Action` protocol:
   ```swift
   protocol Action {
       var id: String { get }
       var title: String { get }
       var icon: ActionIcon { get }
       var isEnabled: (ActionContext) -> Bool { get }
       func perform(_ context: ActionContext) async throws -> ActionResult
   }
   ```
2. Define `ActionContext` and `ActionResult` structs per spec
3. Implement all built-in actions: Copy, Cut, Paste, Search, Open URL, Services
4. `ActionRegistry.swift` — registers built-ins, later extended by extensions

Deliverable: Popup shows real Copy/Cut/Paste buttons that work.

---

### Phase 5 — Extension System (Days 7–9)
Read: `spec/07_extension_system.md`, `spec/08_javascript_runtime.md`, `spec/GLOSSARY.md`

Tasks:
1. Define `.openclipext` package format and `ExtensionConfig` Codable schema
2. `ExtensionLoader.swift` — scan folder, decode config, validate
3. `ExtensionValidator.swift` — signature check + schema validation + user trust prompt
4. `ExtensionRegistry.swift` — holds loaded extensions, exposes as `[any Action]`
5. JS extension type:
   - `JSRuntime.swift` — create JSContext, inject `openclip` object
   - `JSActionBridge.swift` — expose `openclip.selectedText`, `openclip.pasteText()`, etc.
   - `JSXHRBridge.swift` — expose synchronous-style XHR for network requests
6. Shell script extension type — `Process` runner, stdin = selected text
7. AppleScript extension type — `NSAppleScript` runner

Deliverable: Install a test `.openclipext` and have it appear as an action button.

---

### Phase 6 — Rules Engine (Day 10)
Read: `spec/09_app_rules.md`

Tasks:
1. `RuleCondition` enum: `.app(bundleID)`, `.urlPattern(regex)`, `.textPattern(regex)`, `.always`
2. `Rule` struct: condition + list of action IDs to enable/disable
3. `RuleEvaluator` — given a `SelectionContext`, return which actions are visible
4. Hook into action filtering before popup shows

Deliverable: Different apps show different action sets.

---

### Phase 7 — Preferences UI (Days 11–13)
Read: `spec/11_preferences_ui.md`, `spec/10_persistence_and_sync.md`, `spec/12_keyboard_shortcuts.md`

Tasks:
1. Set up SwiftData schema — persist action layout, extension list, rules, settings
2. `PreferencesWindowController` — tabbed settings window
3. Each pane: General, Appearance, Actions (drag-to-reorder), Extensions, Shortcuts, About
4. `HotkeyManager` — global shortcut to manually trigger popup using KeyboardShortcuts library
5. `LoginItemManager` — launch at login via `SMAppService`
6. iCloud sync via CloudKit (if spec requires it)

Deliverable: Preferences window with working settings that persist across launches.

---

### Phase 8 — Polish (Days 14–15)
Read: `spec/13_icon_system.md`, `spec/17_localization.md`, `spec/19_macos_integration.md`

Tasks:
1. SF Symbol icon support in action buttons
2. URL scheme handler (`openclip://`) per spec
3. Drag-and-drop extension installation
4. `.openclipext` / `.opencliplicense` file association
5. macOS Services registration
6. Localization for all languages in spec
7. Sparkle auto-update integration

---

## Coding Standards

### Swift 6 Concurrency
- All `SelectionMonitor` callbacks on `@MainActor`
- `TextRetriever` strategies run on background `Task`, marshal result to main actor
- `JSRuntime` operations on a dedicated serial `Actor`
- No `DispatchQueue` — use `async/await` and `actor` exclusively

### Protocol-First Design
- Every subsystem boundary is a protocol (e.g., `TextRetrieving`, `ActionPerforming`)
- Concrete types are internal — only protocols cross module boundaries
- This makes every subsystem independently testable and replaceable

### Error Handling
- Never `fatalError` in production paths
- All Accessibility API errors must degrade gracefully (show nothing, log to console)
- All extension errors must be isolated — one broken extension must not crash the app

### Testing
- Unit test every `Core/` type (no AppKit dependency in Core)
- Integration test: mock `SelectionMonitor` → verify popup shows correct actions
- No UI tests required for MVP

### No Magic Numbers
- All timing constants in a single `Constants.swift` with named properties
- All values come from what the spec documents as observable behavior

---

## Dependencies (Package.swift)

```swift
dependencies: [
    .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    .package(url: "https://github.com/sindresorhus/Defaults", from: "8.0.0"),
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
]
```

---

## What NOT to Build (MVP Scope)
These are in the spec but defer to v2:
- CloudKit sync (use local-only SwiftData for now)
- StoreKit purchase flow (open source = free, no license system)
- Icon server HTTP endpoint (load icons from bundle/SF Symbols only)
- Beta update channel

---

## Quality Bar

Before considering a phase done:
- [ ] All code compiles with zero warnings under Swift 6 strict concurrency
- [ ] No force-unwraps (`!`) except where guaranteed by construction (document why)
- [ ] Every public type has a doc comment (1 line minimum)
- [ ] Accessibility permission missing → graceful degradation, not crash
- [ ] `Core/` has zero imports of AppKit or SwiftUI
- [ ] Running on both Apple Silicon and Intel (universal binary)

---

## Agentic Self-Check

After completing each phase, before moving to the next:
1. Run the app and manually test the phase's deliverable
2. Search your code for any string that looks like it came from the binary (`Pop`, `NM`, `pilotmoon`) — these are red flags indicating the Chinese Wall was violated
3. Confirm you only imported from `spec/` and Apple docs
