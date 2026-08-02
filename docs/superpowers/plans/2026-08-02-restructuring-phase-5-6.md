# OpenClip Restructuring: Phase 5 & Phase 6 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Phase 5 (Custom Actions Editor & Repository Isolation) and Phase 6 (Composition Root `AppServices` & De-singleton) simultaneously to decouple state management from UI forms and remove global singleton cross-calls in Core domain logic.

**Architecture:**
- **Phase 5 (`CustomActionDraft` & Repository):** Introduce `CustomActionDraft` for draft state validation in custom action editing. Separate `CustomActionRepository` for JSON persistence away from registry mutation.
- **Phase 6 (`AppServices` Composition Root):** Create `AppServices` in `OpenClip/App/` to own instances of `SettingsStore`, `ActionRegistry`, `ActionPresentation`, `ExtensionManager`, and inject them into UI components without Core types relying on `Singleton.shared`.

**Tech Stack:** Swift 5.9, SwiftUI, Combine, AppKit, XCTest

## Global Constraints
- Target macOS 14.0+
- Keep pure domain types (`CustomActionDraft`, `CustomActionRepository`) in `Core` target without AppKit/SwiftUI imports.
- No `Singleton.shared` cross-calls inside `Core` domain methods (dependencies must be injected via `init`).
- UI views receive services via `AppServices` or explicit `init` parameters.

---

### Task 1: `CustomActionDraft` & Isolated `CustomActionRepository`

**Files:**
- Create: `Sources/Core/Actions/Custom/CustomActionDraft.swift`
- Create: `Sources/Core/Actions/Custom/CustomActionRepository.swift`
- Modify: `OpenClip.xcodeproj/project.pbxproj`
- Test: `Tests/OpenClipTests/CustomActionDraftTests.swift`

**Interfaces:**
- Consumes: `CustomAction`, `CustomActionType`
- Produces: `CustomActionDraft`, `CustomActionRepository`

- [ ] **Step 1: Write failing test for `CustomActionDraft`**

Create `Tests/OpenClipTests/CustomActionDraftTests.swift`:
```swift
import XCTest
@testable import Core
@testable import OpenClip

final class CustomActionDraftTests: XCTestCase {
    func testDraftValidationAndConversion() {
        var draft = CustomActionDraft()
        XCTAssertFalse(draft.isValid)

        draft.title = "  "
        XCTAssertFalse(draft.isValid)

        draft.title = "My Action"
        draft.kind = .webSearch
        draft.template = "https://example.com/search?q={query}"
        XCTAssertTrue(draft.isValid)

        let action = draft.toCustomAction(id: "custom.myaction")
        XCTAssertEqual(action?.title, "My Action")
        XCTAssertEqual(action?.id, "custom.myaction")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project OpenClip.xcodeproj -scheme OpenClipTests -only-testing:OpenClipTests/CustomActionDraftTests -destination 'platform=macOS' test | grep -E "error:|FAILED|cannot find"`
Expected: FAIL ("cannot find type 'CustomActionDraft' in scope")

- [ ] **Step 3: Implement `CustomActionDraft` & `CustomActionRepository`**

Create `Sources/Core/Actions/Custom/CustomActionDraft.swift`:
```swift
import Foundation

public struct CustomActionDraft: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case webSearch
        case textSnippet
        case shellScript
    }

    public var title: String
    public var iconName: String
    public var kind: Kind
    public var template: String
    public var replaceSelection: Bool

    public init(
        title: String = "",
        iconName: String = "star",
        kind: Kind = .webSearch,
        template: String = "",
        replaceSelection: Bool = true
    ) {
        self.title = title
        self.iconName = iconName
        self.kind = kind
        self.template = template
        self.replaceSelection = replaceSelection
    }

    public init(action: CustomAction) {
        self.title = action.title
        self.iconName = action.iconName
        switch action.type {
        case .webSearch(let urlTemplate):
            self.kind = .webSearch
            self.template = urlTemplate
            self.replaceSelection = true
        case .textSnippet(let snippet):
            self.kind = .textSnippet
            self.template = snippet
            self.replaceSelection = true
        case .shellScript(let script, let replace):
            self.kind = .shellScript
            self.template = script
            self.replaceSelection = replace
        }
    }

    public var isValid: Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTemplate = template.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedTitle.isEmpty && !trimmedTemplate.isEmpty
    }

    public func toCustomAction(id: String) -> CustomAction? {
        guard isValid else { return nil }
        let type: CustomActionType
        switch kind {
        case .webSearch:
            type = .webSearch(urlTemplate: template.trimmingCharacters(in: .whitespacesAndNewlines))
        case .textSnippet:
            type = .textSnippet(template: template)
        case .shellScript:
            type = .shellScript(script: template, replaceSelection: replaceSelection)
        }
        return CustomAction(
            id: id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            iconName: iconName.isEmpty ? "star" : iconName,
            type: type
        )
    }
}
```

Create `Sources/Core/Actions/Custom/CustomActionRepository.swift`:
```swift
import Foundation

public final class CustomActionRepository: @unchecked Sendable {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("OpenClip", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("custom_actions.json")
        }
    }

    public func load() -> [CustomAction] {
        guard let data = try? Data(contentsOf: fileURL),
              let actions = try? JSONDecoder().decode([CustomAction].self, from: data) else {
            return []
        }
        return actions
    }

    public func save(_ actions: [CustomAction]) {
        if let data = try? JSONEncoder().encode(actions) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project OpenClip.xcodeproj -scheme OpenClipTests -only-testing:OpenClipTests/CustomActionDraftTests -destination 'platform=macOS' test | grep -E "passed|failed|SUCCEEDED"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Actions/Custom/ Tests/OpenClipTests/CustomActionDraftTests.swift OpenClip.xcodeproj/ project.yml
git commit -m "feat(core): introduce CustomActionDraft and CustomActionRepository"
```

---

### Task 2: Composition Root (`AppServices`) & De-singletoning Core

**Files:**
- Create: `Sources/OpenClip/App/AppServices.swift`
- Modify: `Sources/OpenClip/AppDelegate.swift`
- Test: `Tests/OpenClipTests/AppServicesTests.swift`

**Interfaces:**
- Consumes: `SettingsStore`, `ActionRegistry`, `ActionPresentation`, `ExtensionManager`
- Produces: `AppServices` composition root

- [ ] **Step 1: Write unit test for `AppServices`**

Create `Tests/OpenClipTests/AppServicesTests.swift`:
```swift
import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class AppServicesTests: XCTestCase {
    func testAppServicesInitialization() {
        let services = AppServices.shared
        XCTAssertNotNil(services.settingsStore)
        XCTAssertNotNil(services.actionRegistry)
        XCTAssertNotNil(services.actionPresentation)
    }
}
```

- [ ] **Step 2: Implement `AppServices`**

Create `Sources/OpenClip/App/AppServices.swift`:
```swift
import Foundation
import Combine
import Core

@MainActor
public final class AppServices: ObservableObject, Sendable {
    public static let shared = AppServices()

    public let settingsStore: SettingsStore
    public let actionRegistry: ActionRegistry
    public let actionPresentation: ActionPresentation
    public let customizationManager: ActionCustomizationManager

    public init(
        settingsStore: SettingsStore = DefaultSettingsStore.shared,
        actionRegistry: ActionRegistry = .shared,
        actionPresentation: ActionPresentation = .shared,
        customizationManager: ActionCustomizationManager = .shared
    ) {
        self.settingsStore = settingsStore
        self.actionRegistry = actionRegistry
        self.actionPresentation = actionPresentation
        self.customizationManager = customizationManager
    }
}
```

- [ ] **Step 3: Run test to verify it passes**

Run: `xcodebuild -project OpenClip.xcodeproj -scheme OpenClipTests -only-testing:OpenClipTests/AppServicesTests -destination 'platform=macOS' test | grep -E "passed|failed|SUCCEEDED"`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add Sources/OpenClip/App/AppServices.swift Tests/OpenClipTests/AppServicesTests.swift OpenClip.xcodeproj/ project.yml
git commit -m "feat(app): introduce AppServices composition root"
```

---

### Task 3: Final Verification & Integration Checklist

**Files:**
- Test: `Tests/OpenClipTests/`

- [ ] **Step 1: Run complete test suite**

Run: `xcodebuild -project OpenClip.xcodeproj -scheme OpenClipTests -destination 'platform=macOS' test | grep -E "Test Suite|passed|failed|SUCCEEDED"`
Expected: Executed all tests with 0 failures

- [ ] **Step 2: Verify OpenClip Application Build**

Run: `xcodebuild -project OpenClip.xcodeproj -scheme OpenClip -destination 'platform=macOS' build | grep -E "SUCCEEDED|FAILED"`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Final Commit**

```bash
git commit --allow-empty -m "chore: complete restructuring Phase 5 and Phase 6"
```

---

### Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-02-restructuring-phase-5-6.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
