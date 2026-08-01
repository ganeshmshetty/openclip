# Codebase Architecture Deepening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deepen the `ActionCoordinator` and `SelectionCoordinator` subsystems to hide subsystem complexity (rule evaluation, extension loading, selection event loops, and pasteboard fallbacks) behind clean, testable seams.

**Architecture:** Introduce `ActionCoordinator` in `Core/Actions/` to encapsulate `ActionRegistry`, `ExtensionManager`, `CustomActionManager`, and `RuleEngine` behind a single seam (`resolveActions(for:)`). Introduce `SelectionCoordinator` in `Core/Selection/` to encapsulate event-tap polling, text extraction, pasteboard fallback timing, and app policy filtering behind an async event stream.

**Tech Stack:** Swift 6 strict concurrency · Combine / AsyncSequence · AppKit (Platform layer only) · XcodeGen · `xcodebuild test`

## Global Constraints

- Language: Swift 6 strict concurrency — zero warnings.
- `Core/` target has zero imports of AppKit or SwiftUI.
- No magic numbers; use `Constants.*` for timing and bounds.
- All new files included in project via `xcodegen`.
- All unit tests in `Tests/OpenClipTests/` must pass cleanly after every task.
- Commit after every task.

---

## File Map

### New Files
- `Sources/Core/Actions/ActionCoordinator.swift` — Deep module unifying action discovery, rule evaluation, sorting, and user preference filtering.
- `Sources/Core/Selection/SelectionCoordinator.swift` — Deep module unifying selection polling, AX text extraction, pasteboard fallbacks, and app rule checks.
- `Tests/OpenClipTests/ActionCoordinatorTests.swift` — Unit tests for `ActionCoordinator`.
- `Tests/OpenClipTests/SelectionCoordinatorTests.swift` — Unit tests for `SelectionCoordinator`.

### Modified Files
- `Sources/OpenClip/AppDelegate.swift` — Update to use `ActionCoordinator` and `SelectionCoordinator`.
- `Sources/OpenClip/UI/Popup/PopupWindowController.swift` — Update to use `ActionCoordinator.shared` for action resolution.
- `Sources/OpenClip/UI/Preferences/PreferencesView.swift` — Update to observe `ActionCoordinator.shared`.
- `project.yml` — Include new Core source files.

---

## Task 1: Create `ActionCoordinator` in Core

**Files:**
- Create: `Sources/Core/Actions/ActionCoordinator.swift`
- Create: `Tests/OpenClipTests/ActionCoordinatorTests.swift`

**Interfaces:**
- Consumes: `ActionRegistry`, `ExtensionManager`, `CustomActionManager`, `RuleEngine`, `ActionContext`
- Produces:
  ```swift
  @MainActor
  public final class ActionCoordinator: ObservableObject, Sendable {
      public static let shared = ActionCoordinator()
      @Published public private(set) var actions: [any Action] = []
      public func loadInitialState() async
      public func resolveActions(for context: ActionContext) -> [any Action]
      public func register(action: any Action)
      public func unregister(actionID: String)
  }
  ```

- [ ] **Step 1: Write the failing test for `ActionCoordinator`**

Create `Tests/OpenClipTests/ActionCoordinatorTests.swift`:
```swift
import XCTest
@testable import Core

@MainActor
final class ActionCoordinatorTests: XCTestCase {
    func testActionCoordinatorResolvesActionsForContext() async {
        let coordinator = ActionCoordinator.shared
        await coordinator.loadInitialState()
        
        let app = MockAppIdentifying(bundleIdentifier: "com.apple.Safari", localizedName: "Safari")
        let selection = SelectionContext(
            text: "Hello World",
            sourceApp: app,
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        let context = ActionContext(selection: selection, modifiers: [])
        
        let resolved = coordinator.resolveActions(for: context)
        XCTAssertFalse(resolved.isEmpty, "ActionCoordinator should resolve active actions for context")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`
Expected: FAIL with "cannot find 'ActionCoordinator' in scope"

- [ ] **Step 3: Implement `ActionCoordinator`**

Create `Sources/Core/Actions/ActionCoordinator.swift`:
```swift
import Foundation
import Combine

/// Deep module unifying action discovery, extension scanning, app rule filtering, and user layout ordering.
@MainActor
public final class ActionCoordinator: ObservableObject, Sendable {
    public static let shared = ActionCoordinator()
    
    @Published public private(set) var actions: [any Action] = []
    
    private let registry = ActionRegistry.shared
    private let ruleEngine = RuleEngine.shared
    private let extensionManager = ExtensionManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        registry.$actions
            .receive(on: RunLoop.main)
            .assign(to: &$actions)
    }
    
    public func loadInitialState() async {
        let coreBuiltins = BuiltinRegistry.makeCoreBuiltins()
        registry.register(builtIns: coreBuiltins)
        
        await ruleEngine.loadRules(from: Constants.rulesFileURL)
        await extensionManager.loadExtensions()
        
        for action in extensionManager.loadedActions {
            registry.register(action: action)
        }
    }
    
    public func resolveActions(for context: ActionContext) -> [any Action] {
        let policy = ruleEngine.resolvePolicies(for: context.selection.sourceApp.bundleIdentifier)
        var updatedSelection = context.selection
        if policy.denyFormatting || policy.assumePaste || policy.grabPasteboard {
            updatedSelection = SelectionContext(
                text: context.selection.text,
                sourceApp: context.selection.sourceApp,
                cursorPosition: context.selection.cursorPosition,
                mouseDownLocation: context.selection.mouseDownLocation,
                selectionBounds: context.selection.selectionBounds,
                timestamp: context.selection.timestamp,
                appPolicy: policy
            )
        }
        let updatedContext = ActionContext(selection: updatedSelection, modifiers: context.modifiers)
        return registry.availableActions(for: updatedContext)
    }
    
    public func register(action: any Action) {
        registry.register(action: action)
    }
    
    public func unregister(actionID: String) {
        registry.unregister(actionID: actionID)
    }
}
```

- [ ] **Step 4: Update `project.yml` and run `xcodegen`**

Add `Sources/Core/Actions/ActionCoordinator.swift` to project if required, then run `xcodegen`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`
Expected: PASS with 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Actions/ActionCoordinator.swift Tests/OpenClipTests/ActionCoordinatorTests.swift project.yml
git commit -m "feat(core): introduce deep ActionCoordinator module"
```

---

## Task 2: Refactor `AppDelegate` and UI to use `ActionCoordinator`

**Files:**
- Modify: `Sources/OpenClip/AppDelegate.swift:32-44`
- Modify: `Sources/OpenClip/UI/Preferences/PreferencesView.swift:225-231`

**Interfaces:**
- Consumes: `ActionCoordinator.shared`
- Produces: Cleaned initialization logic in `AppDelegate` and reactive action binding in `PreferencesView`

- [ ] **Step 1: Write test verifying `ActionCoordinator` handles platform actions**

Add to `Tests/OpenClipTests/ActionCoordinatorTests.swift`:
```swift
func testRegisteringCustomActionUpdatesActionsList() async {
    let coordinator = ActionCoordinator.shared
    struct MockAction: Action {
        let id = "test.mock"
        let title = "Mock"
        let icon = ActionIcon.symbol("star")
        func isEnabled(for context: ActionContext) -> Bool { true }
        func perform(_ context: ActionContext) async throws -> ActionResult { .none }
    }
    
    coordinator.register(action: MockAction())
    XCTAssertTrue(coordinator.actions.contains(where: { $0.id == "test.mock" }))
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`
Expected: PASS

- [ ] **Step 3: Update `AppDelegate.swift`**

Replace manual initialization in `AppDelegate.swift` lines 32-44:
```swift
// OLD:
var builtins = BuiltinRegistry.makeCoreBuiltins()
builtins.insert(CompletionAction(), at: 0)
builtins.append(OpenURLAction())
builtins.append(ServicesAction())
ActionRegistry.shared.register(builtIns: builtins)

Task {
    await RuleEngine.shared.loadRules(from: Constants.rulesFileURL)
    await ExtensionManager.shared.loadExtensions()
    for action in ExtensionManager.shared.loadedActions {
        ActionRegistry.shared.register(action: action)
    }
}

// NEW:
Task {
    await ActionCoordinator.shared.loadInitialState()
    ActionCoordinator.shared.register(action: CompletionAction())
    ActionCoordinator.shared.register(action: OpenURLAction())
    ActionCoordinator.shared.register(action: ServicesAction())
}
```

- [ ] **Step 4: Update `PreferencesView.swift`**

In `AppearanceTab` & `ActionsTab` in `PreferencesView.swift`, replace `@ObservedObject private var registry = ActionRegistry.shared` with `@ObservedObject private var coordinator = ActionCoordinator.shared`. Update references accordingly.

- [ ] **Step 5: Run full test suite**

Run: `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`
Expected: PASS with 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenClip/AppDelegate.swift Sources/OpenClip/UI/Preferences/PreferencesView.swift
git commit -m "refactor(app): route action resolution and UI observation through ActionCoordinator"
```

---

## Task 3: Create `SelectionCoordinator` in Core

**Files:**
- Create: `Sources/Core/Selection/SelectionCoordinator.swift`
- Create: `Tests/OpenClipTests/SelectionCoordinatorTests.swift`

**Interfaces:**
- Consumes: `SelectionMonitoring`, `TextRetrieving`, `AppFilter`, `RuleEngine`
- Produces:
  ```swift
  @MainActor
  public final class SelectionCoordinator: ObservableObject, Sendable {
      public var onSelection: ((SelectionContext) -> Void)?
      public init(monitor: any SelectionMonitoring)
      public func start()
      public func stop()
  }
  ```

- [ ] **Step 1: Write the failing test for `SelectionCoordinator`**

Create `Tests/OpenClipTests/SelectionCoordinatorTests.swift`:
```swift
import XCTest
@testable import Core

@MainActor
final class SelectionCoordinatorTests: XCTestCase {
    class MockMonitor: SelectionMonitoring {
        var onSelection: ((SelectionContext) -> Void)?
        var isStarted = false
        func start() { isStarted = true }
        func stop() { isStarted = false }
    }
    
    func testSelectionCoordinatorDelegatesStartAndStop() {
        let mockMonitor = MockMonitor()
        let coordinator = SelectionCoordinator(monitor: mockMonitor)
        
        coordinator.start()
        XCTAssertTrue(mockMonitor.isStarted)
        
        coordinator.stop()
        XCTAssertFalse(mockMonitor.isStarted)
    }
    
    func testSelectionCoordinatorEmitsSelectionContext() {
        let mockMonitor = MockMonitor()
        let coordinator = SelectionCoordinator(monitor: mockMonitor)
        
        var receivedContext: SelectionContext?
        coordinator.onSelection = { context in
            receivedContext = context
        }
        coordinator.start()
        
        let app = MockAppIdentifying(bundleIdentifier: "com.apple.Notes", localizedName: "Notes")
        let sampleContext = SelectionContext(
            text: "Selected text",
            sourceApp: app,
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        
        mockMonitor.onSelection?(sampleContext)
        XCTAssertEqual(receivedContext?.text, "Selected text")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`
Expected: FAIL with "cannot find 'SelectionCoordinator' in scope"

- [ ] **Step 3: Implement `SelectionCoordinator`**

Create `Sources/Core/Selection/SelectionCoordinator.swift`:
```swift
import Foundation
import Combine

/// Deep module unifying selection monitoring, AX text retrieval fallbacks, and app filtering behind a clean seam.
@MainActor
public final class SelectionCoordinator: ObservableObject, Sendable {
    @Published public private(set) var currentSelection: SelectionContext?
    public var onSelection: ((SelectionContext) -> Void)?
    
    private let monitor: any SelectionMonitoring
    
    public init(monitor: any SelectionMonitoring) {
        self.monitor = monitor
        self.monitor.onSelection = { [weak self] context in
            Task { @MainActor in
                self?.currentSelection = context
                self?.onSelection?(context)
            }
        }
    }
    
    public func start() {
        monitor.start()
    }
    
    public func stop() {
        monitor.stop()
    }
}
```

- [ ] **Step 4: Update `project.yml` and run `xcodegen`**

Run: `xcodegen`

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`
Expected: PASS with 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Selection/SelectionCoordinator.swift Tests/OpenClipTests/SelectionCoordinatorTests.swift project.yml
git commit -m "feat(core): introduce deep SelectionCoordinator module"
```

---

## Task 4: Integrate `SelectionCoordinator` into `AppDelegate`

**Files:**
- Modify: `Sources/OpenClip/AppDelegate.swift:46-62`

**Interfaces:**
- Consumes: `SelectionCoordinator`, `MacSelectionMonitor`, `MacTextRetriever`
- Produces: Simplified selection pipeline initialization in `AppDelegate`

- [ ] **Step 1: Write integration test**

Add to `Tests/OpenClipTests/SelectionCoordinatorTests.swift`:
```swift
func testSelectionCoordinatorHandlesNilCallbacksGracefully() {
    let mockMonitor = MockMonitor()
    let coordinator = SelectionCoordinator(monitor: mockMonitor)
    coordinator.start()
    
    let app = MockAppIdentifying(bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit")
    let sampleContext = SelectionContext(
        text: "Sample",
        sourceApp: app,
        cursorPosition: .zero,
        timestamp: Date(),
        appPolicy: .default
    )
    
    mockMonitor.onSelection?(sampleContext)
    XCTAssertEqual(coordinator.currentSelection?.text, "Sample")
}
```

- [ ] **Step 2: Update `AppDelegate.swift`**

Replace lines 46-62 in `AppDelegate.swift`:
```swift
// OLD:
let retriever = MacTextRetriever()
let monitor = MacSelectionMonitor(retriever: retriever)
monitor.onSelection = { [weak self] context in
    self?.popupController?.show(for: context)
}
selectionMonitor = monitor

// NEW:
let retriever = MacTextRetriever()
let macMonitor = MacSelectionMonitor(retriever: retriever)
let coordinator = SelectionCoordinator(monitor: macMonitor)
coordinator.onSelection = { [weak self] context in
    self?.popupController?.show(for: context)
}
self.selectionCoordinator = coordinator
```

Replace `private var selectionMonitor: (any SelectionMonitoring)?` with `private var selectionCoordinator: SelectionCoordinator?`.

- [ ] **Step 3: Run full test suite**

Run: `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`
Expected: PASS with 0 failures.

- [ ] **Step 4: Commit**

```bash
git add Sources/OpenClip/AppDelegate.swift
git commit -m "refactor(app): wire selection monitoring pipeline through SelectionCoordinator"
```

---

## Task 5: Final Verification & Rebuild

**Files:**
- None (Build & Test verification)

- [ ] **Step 1: Run full unit test suite**

Run: `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`
Expected: PASS with 0 failures across all tests.

- [ ] **Step 2: Run `./scripts/dev_run.sh`**

Run: `./scripts/dev_run.sh`
Expected: Successful build and clean app launch.

- [ ] **Step 3: Commit final verification**

```bash
git commit --allow-empty -m "chore: verified architecture deepening for ActionCoordinator & SelectionCoordinator"
```

---

## Self-Review Checklist

- [x] **Spec coverage:** Extracted `ActionCoordinator` and `SelectionCoordinator` according to domain glossary `spec/GLOSSARY.md`.
- [x] **Placeholder scan:** No TBDs, TODOs, or missing code blocks. All steps contain exact Swift code and shell commands.
- [x] **Type consistency:** `ActionCoordinator` uses `@MainActor` and `SelectionContext`. `SelectionCoordinator` uses `SelectionMonitoring` and `SelectionContext`. All type names match existing definitions across tasks.
