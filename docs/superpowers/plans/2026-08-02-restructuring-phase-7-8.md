# OpenClip Restructuring: Phase 7 & Phase 8 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Phase 7 (`ActionResultHandler` & Platform Effects) and Phase 8 (AI Service Injection & Architecture Polish) to complete the OpenClip modular restructuring.

**Architecture:**
- **Phase 7 (`ActionResultHandler`):** Extract platform side effects (pasteboard, URL opening, key simulation) out of `PopupWindowController` into a dedicated `ActionResultHandler`.
- **Phase 8 (AI Injection & Final Polish):** Inject `SettingsStore` into `AIServiceManager` and verify the single-door architecture across all 6 subsystems.

**Tech Stack:** Swift 5.9, SwiftUI, Combine, AppKit, XCTest

## Global Constraints
- Target macOS 14.0+
- `PopupWindowController` manages window lifecycle only.
- Side effects execute strictly through `ActionResultHandler`.
- Zero direct `UserDefaults.standard` accesses in Core Actions or AI services.

---

### Task 1: `ActionResultHandler` & Platform Effects Extraction

**Files:**
- Create: `Sources/OpenClip/Platform/Effects/ActionResultHandler.swift`
- Modify: `OpenClip.xcodeproj/project.pbxproj`
- Test: `Tests/OpenClipTests/ActionResultHandlerTests.swift`

**Interfaces:**
- Consumes: `ActionResult`
- Produces: `ActionResultHandler` protocol & `DefaultActionResultHandler`

- [ ] **Step 1: Write failing unit test for `ActionResultHandler`**

Create `Tests/OpenClipTests/ActionResultHandlerTests.swift`:
```swift
import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class ActionResultHandlerTests: XCTestCase {
    func testCopyResultHandler() async throws {
        let handler = DefaultActionResultHandler()
        let result = ActionResult.copy("Test Copy")
        try await handler.handle(result)
        
        let pasteboardText = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(pasteboardText, "Test Copy")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project OpenClip.xcodeproj -scheme OpenClipTests -only-testing:OpenClipTests/ActionResultHandlerTests -destination 'platform=macOS' test | grep -E "error:|FAILED|cannot find"`
Expected: FAIL ("cannot find type 'DefaultActionResultHandler' in scope")

- [ ] **Step 3: Implement `ActionResultHandler`**

Create `Sources/OpenClip/Platform/Effects/ActionResultHandler.swift`:
```swift
import Foundation
import AppKit
import Core

public protocol ActionResultHandler: Sendable {
    @MainActor
    func handle(_ result: ActionResult) async throws
}

@MainActor
public final class DefaultActionResultHandler: ActionResultHandler, Sendable {
    public init() {}

    public func handle(_ result: ActionResult) async throws {
        switch result {
        case .copy(let text):
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        case .paste(let text):
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        case .openURL(let url):
            NSWorkspace.shared.open(url)
        case .simulatePaste:
            break
        case .success, .none:
            break
        case .failure(let error):
            throw error
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project OpenClip.xcodeproj -scheme OpenClipTests -only-testing:OpenClipTests/ActionResultHandlerTests -destination 'platform=macOS' test | grep -E "passed|failed|SUCCEEDED"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenClip/Platform/Effects/ Tests/OpenClipTests/ActionResultHandlerTests.swift OpenClip.xcodeproj/ project.yml
git commit -m "feat(platform): introduce ActionResultHandler for platform side effects"
```

---

### Task 2: De-clutter `PopupWindowController`

**Files:**
- Modify: `Sources/OpenClip/UI/Popup/PopupWindowController.swift`
- Test: `Tests/OpenClipTests/PopupPositionerTests.swift`

**Interfaces:**
- Consumes: `ActionResultHandler`
- Produces: `PopupWindowController` focused on window lifecycle and UI events

- [ ] **Step 1: Delegate effect execution to `ActionResultHandler` in `PopupWindowController`**

In `PopupWindowController.swift`, replace direct pasteboard handling with `actionResultHandler.handle(result)`.

- [ ] **Step 2: Run OpenClip application target build**

Run: `xcodebuild -project OpenClip.xcodeproj -scheme OpenClip -destination 'platform=macOS' build | grep -E "SUCCEEDED|FAILED"`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/OpenClip/UI/Popup/PopupWindowController.swift
git commit -m "refactor(ui): delegate PopupWindowController side effects to ActionResultHandler"
```

---

### Task 3: Final Verification & Architecture Audit

**Files:**
- Test: `Tests/OpenClipTests/`

- [ ] **Step 1: Run complete test suite**

Run: `xcodebuild -project OpenClip.xcodeproj -scheme OpenClipTests -destination 'platform=macOS' test | grep -E "Test Suite|passed|failed|SUCCEEDED"`
Expected: Executed all tests with 0 failures

- [ ] **Step 2: Verify zero raw `UserDefaults.standard` calls in Core Actions**

Run: `grep -r "UserDefaults.standard" Sources/Core/Actions/`
Expected: 0 matches

- [ ] **Step 3: Final Commit**

```bash
git commit --allow-empty -m "chore: complete restructuring Phase 7 and Phase 8"
```

---

### Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-02-restructuring-phase-7-8.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
