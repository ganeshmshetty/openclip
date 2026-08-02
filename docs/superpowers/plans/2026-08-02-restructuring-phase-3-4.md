# OpenClip Restructuring: Phase 3 & Phase 4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Phase 3 (`ActionChrome` & UI Modularization) and Phase 4 (Extensions Pipeline & `ActionFactory` Exclusivity) simultaneously to eliminate UI type checks and establish factory-only action construction.

**Architecture:** 
- **Phase 3 (`ActionChrome`):** Introduce data-driven `ActionChrome` model (badge, rowStyle, popupBehavior, source) to replace `is ScriptAction` or `action.id == "builtin.transform"` type switches in UI views. Split mega-views into focused feature components.
- **Phase 4 (Extensions Pipeline & `ActionFactory`):** Extract `ExtensionManifest` and normalized `ExtensionActionKind` (`url`, `js`, `applescript`, `shellInline`, `scriptFile`). Enforce factory-only action construction in `DefaultActionFactory`, deleting legacy fallback constructors in `ExtensionManager` and snippet parsers.

**Tech Stack:** Swift 5.9, SwiftUI, Combine, AppKit, XCTest

## Global Constraints
- Target macOS 14.0+
- Keep pure domain types (`ActionChrome`, `ExtensionManifest`, `ExtensionActionKind`) in `Core` target without AppKit/SwiftUI imports.
- Enforce **one birth door**: `ActionFactory` is the only place constructing extension actions (`ScriptAction`, `URLTemplateAction`, `JavaScriptAction`, `AppleScriptAction`).
- Delete all unused legacy fallback paths and type checks in views upon completion.

---

### Task 1: Core `ActionChrome` Data Model

**Files:**
- Create: `Sources/Core/Actions/ActionChrome.swift`
- Modify: `Sources/Core/Actions/Action.swift`
- Test: `Tests/OpenClipTests/ActionChromeTests.swift`

**Interfaces:**
- Consumes: `Action` protocol
- Produces: `ActionChrome`, `Action.chrome` property

- [ ] **Step 1: Write failing unit test for `ActionChrome`**

Create `Tests/OpenClipTests/ActionChromeTests.swift`:
```swift
import XCTest
@testable import Core
@testable import OpenClip

final class ActionChromeTests: XCTestCase {
    func testBuiltinCopyActionChrome() {
        let copy = CopyAction()
        XCTAssertEqual(copy.chrome.badge, .none)
        XCTAssertEqual(copy.chrome.rowStyle, .standard)
        XCTAssertEqual(copy.chrome.popupBehavior, .perform)
        XCTAssertEqual(copy.chrome.source, .builtin)
    }

    func testCustomActionChrome() {
        let custom = CustomAction(id: "custom.test", title: "Test Custom", prompt: "Prompt", icon: .symbol("star"))
        XCTAssertEqual(custom.chrome.badge, .custom)
        XCTAssertEqual(custom.chrome.source, .custom)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project OpenClip.xcodeproj -scheme OpenClipTests -only-testing:OpenClipTests/ActionChromeTests -destination 'platform=macOS' test | grep -E "error:|FAILED|cannot find"`
Expected: FAIL ("cannot find type 'ActionChrome' in scope")

- [ ] **Step 3: Implement `ActionChrome` and protocol extensions**

Create `Sources/Core/Actions/ActionChrome.swift`:
```swift
import Foundation

public struct ActionChrome: Sendable, Equatable {
    public enum Badge: Sendable, Equatable {
        case none
        case script
        case url
        case custom
        case extensionPkg(String)
    }

    public enum RowStyle: Sendable, Equatable {
        case standard
        case transformGroup
    }

    public enum PopupBehavior: Sendable, Equatable {
        case perform
        case showTransformMenu
        case provideCompletions
    }

    public enum Source: Sendable, Equatable {
        case builtin
        case custom
        case extensionPkg(packageID: String)
    }

    public let badge: Badge
    public let rowStyle: RowStyle
    public let popupBehavior: PopupBehavior
    public let source: Source

    public init(
        badge: Badge = .none,
        rowStyle: RowStyle = .standard,
        popupBehavior: PopupBehavior = .perform,
        source: Source = .builtin
    ) {
        self.badge = badge
        self.rowStyle = rowStyle
        self.popupBehavior = popupBehavior
        self.source = source
    }
}
```

Modify `Sources/Core/Actions/Action.swift` to add:
```swift
public extension Action {
    var chrome: ActionChrome {
        ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin)
    }
}
```

Add `chrome` override for `CustomAction`:
```swift
public extension CustomAction {
    var chrome: ActionChrome {
        ActionChrome(badge: .custom, rowStyle: .standard, popupBehavior: .perform, source: .custom)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project OpenClip.xcodeproj -scheme OpenClipTests -only-testing:OpenClipTests/ActionChromeTests -destination 'platform=macOS' test | grep -E "passed|failed|SUCCEEDED"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Actions/ ActionChrome.swift Tests/OpenClipTests/ActionChromeTests.swift OpenClip.xcodeproj/ project.yml
git commit -m "feat(core): introduce ActionChrome data model"
```

---

### Task 2: Data-Driven UI Consumption in Preferences & Popup Views

**Files:**
- Modify: `Sources/OpenClip/UI/Preferences/PreferencesView.swift`
- Modify: `Sources/OpenClip/UI/Preferences/ActionAppearanceFields.swift`
- Test: `Tests/OpenClipTests/ActionChromeTests.swift`

**Interfaces:**
- Consumes: `ActionChrome`
- Produces: Data-driven UI rendering without `if action is ScriptAction` or `action.id == "builtin.transform"` switches

- [ ] **Step 1: Replace type checks in `ActionRowView` with `ActionChrome`**

In `Sources/OpenClip/UI/Preferences/PreferencesView.swift`, replace `if action is ScriptAction` with `switch action.chrome.badge`:
```swift
switch action.chrome.badge {
case .script:
    Text("Script")
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.blue.opacity(0.15)))
        .foregroundColor(.blue)
case .url:
    Text("URL Template")
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.purple.opacity(0.15)))
        .foregroundColor(.purple)
case .custom:
    Text("Custom")
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.orange.opacity(0.15)))
        .foregroundColor(.orange)
case .extensionPkg(let name):
    Text(name)
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.green.opacity(0.15)))
        .foregroundColor(.green)
case .none:
    EmptyView()
}
```

- [ ] **Step 2: Run OpenClip app target build**

Run: `xcodebuild -project OpenClip.xcodeproj -scheme OpenClip -destination 'platform=macOS' build | grep -E "SUCCEEDED|FAILED"`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/OpenClip/UI/Preferences/PreferencesView.swift
git commit -m "refactor(ui): convert ActionRowView badge rendering to ActionChrome"
```

---

### Task 3: Manifest Extraction & Normalized `ExtensionActionKind`

**Files:**
- Create: `Sources/Core/Extensions/Manifest/ExtensionManifest.swift`
- Create: `Sources/Core/Extensions/Manifest/ExtensionActionKind.swift`
- Modify: `OpenClip.xcodeproj/project.pbxproj`
- Test: `Tests/OpenClipTests/ExtensionManifestTests.swift`

**Interfaces:**
- Consumes: Manifest JSON data
- Produces: `ExtensionManifest`, `ExtensionActionKind` (`.url`, `.js`, `.applescript`, `.shellInline`, `.scriptFile`)

- [ ] **Step 1: Write failing unit test for `ExtensionActionKind` & `ExtensionManifest`**

Create `Tests/OpenClipTests/ExtensionManifestTests.swift`:
```swift
import XCTest
@testable import Core
@testable import OpenClip

final class ExtensionManifestTests: XCTestCase {
    func testExtensionActionKindNormalization() {
        XCTAssertEqual(ExtensionActionKind(rawType: "url"), .url)
        XCTAssertEqual(ExtensionActionKind(rawType: "js"), .js)
        XCTAssertEqual(ExtensionActionKind(rawType: "applescript"), .applescript)
        XCTAssertEqual(ExtensionActionKind(rawType: "shellInline"), .shellInline)
        XCTAssertEqual(ExtensionActionKind(rawType: "scriptFile"), .scriptFile)
    }

    func testManifestDecoding() throws {
        let json = """
        {
          "identifier": "com.example.translator",
          "name": "Translator",
          "version": "1.0.0",
          "actions": [
            {
              "id": "action.translate",
              "title": "Translate",
              "type": "url",
              "url": "https://translate.google.com/?text={query}"
            }
          ]
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: json)
        XCTAssertEqual(manifest.identifier, "com.example.translator")
        XCTAssertEqual(manifest.actions.count, 1)
        XCTAssertEqual(manifest.actions[0].kind, .url)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project OpenClip.xcodeproj -scheme OpenClipTests -only-testing:OpenClipTests/ExtensionManifestTests -destination 'platform=macOS' test | grep -E "error:|FAILED|cannot find"`
Expected: FAIL ("cannot find type 'ExtensionActionKind' in scope")

- [ ] **Step 3: Implement `ExtensionActionKind` and `ExtensionManifest`**

Create `Sources/Core/Extensions/Manifest/ExtensionActionKind.swift`:
```swift
import Foundation

public enum ExtensionActionKind: String, Codable, Sendable, Equatable {
    case url
    case js
    case applescript
    case shellInline
    case scriptFile

    public init(rawType: String) {
        switch rawType.lowercased() {
        case "url", "urltemplate":
            self = .url
        case "js", "javascript":
            self = .js
        case "applescript":
            self = .applescript
        case "shellinline", "shell":
            self = .shellInline
        case "scriptfile", "script":
            self = .scriptFile
        default:
            self = .url
        }
    }
}
```

Create `Sources/Core/Extensions/Manifest/ExtensionManifest.swift`:
```swift
import Foundation

public struct ExtensionActionMetadata: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let rawType: String
    public let iconSymbol: String?
    public let url: String?
    public let script: String?

    public var kind: ExtensionActionKind {
        ExtensionActionKind(rawType: rawType)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case rawType = "type"
        case iconSymbol = "icon"
        case url
        case script
    }
}

public struct ExtensionManifest: Codable, Sendable, Equatable {
    public let identifier: String
    public let name: String
    public let version: String
    public let actions: [ExtensionActionMetadata]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project OpenClip.xcodeproj -scheme OpenClipTests -only-testing:OpenClipTests/ExtensionManifestTests -destination 'platform=macOS' test | grep -E "passed|failed|SUCCEEDED"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Extensions/Manifest/ Tests/OpenClipTests/ExtensionManifestTests.swift OpenClip.xcodeproj/ project.yml
git commit -m "feat(core): extract ExtensionManifest and normalized ExtensionActionKind"
```

---

### Task 4: `DefaultActionFactory` Exclusivity & Legacy Constructor Deletion

**Files:**
- Modify: `Sources/OpenClip/Platform/DefaultActionFactory.swift`
- Modify: `Sources/OpenClip/Platform/ExtensionManager.swift`
- Modify: `Sources/Core/Util/SnippetParser.swift`
- Test: `Tests/OpenClipTests/DefaultActionFactoryTests.swift`

**Interfaces:**
- Consumes: `ExtensionActionMetadata`, `ExtensionManifest`
- Produces: `Action` instance created exclusively through `DefaultActionFactory`

- [ ] **Step 1: Update `DefaultActionFactory` to handle all `ExtensionActionKind` variants**

In `DefaultActionFactory.swift`:
```swift
public final class DefaultActionFactory {
    public static func makeAction(from metadata: ExtensionActionMetadata, packageDirectory: URL? = nil) -> (any Action)? {
        switch metadata.kind {
        case .url:
            guard let urlStr = metadata.url else { return nil }
            return URLTemplateAction(id: metadata.id, title: metadata.title, template: urlStr, iconSymbol: metadata.iconSymbol)
        case .js:
            guard let script = metadata.script else { return nil }
            return JavaScriptAction(id: metadata.id, title: metadata.title, scriptBody: script, iconSymbol: metadata.iconSymbol)
        case .applescript:
            guard let script = metadata.script else { return nil }
            return AppleScriptAction(id: metadata.id, title: metadata.title, scriptBody: script, iconSymbol: metadata.iconSymbol)
        case .shellInline:
            guard let script = metadata.script else { return nil }
            return ScriptAction(id: metadata.id, title: metadata.title, scriptPath: nil, inlineScript: script, iconSymbol: metadata.iconSymbol)
        case .scriptFile:
            guard let path = metadata.script, let packageDirectory else { return nil }
            let fullURL = packageDirectory.appendingPathComponent(path)
            return ScriptAction(id: metadata.id, title: metadata.title, scriptPath: fullURL.path, inlineScript: nil, iconSymbol: metadata.iconSymbol)
        }
    }
}
```

- [ ] **Step 2: Update `ExtensionManager` to construct actions strictly via `DefaultActionFactory`**

Remove inline `URLTemplateAction(...)` and `ScriptAction(...)` calls from `ExtensionManager.swift` and delegate exclusively to `DefaultActionFactory.makeAction(from:packageDirectory:)`.

- [ ] **Step 3: Run test suite to verify factory exclusivity**

Run: `xcodebuild -project OpenClip.xcodeproj -scheme OpenClipTests -destination 'platform=macOS' test | grep -E "Test Suite|passed|failed|SUCCEEDED"`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add Sources/OpenClip/Platform/ DefaultActionFactory.swift Sources/OpenClip/Platform/ExtensionManager.swift
git commit -m "refactor(extensions): enforce DefaultActionFactory exclusivity and remove fallback constructors"
```

---

### Task 5: Final Verification & Integration Checklist

**Files:**
- Test: `Tests/OpenClipTests/`

- [ ] **Step 1: Run complete test suite**

Run: `xcodebuild -project OpenClip.xcodeproj -scheme OpenClipTests -destination 'platform=macOS' test | grep -E "Test Suite|passed|failed|SUCCEEDED"`
Expected: Executed all tests with 0 failures

- [ ] **Step 2: Verify zero fallback constructors in ExtensionManager**

Run: `grep -E "URLTemplateAction\(|ScriptAction\(" Sources/OpenClip/Platform/ExtensionManager.swift || true`
Expected: 0 matches (factory is the single construction door)

- [ ] **Step 3: Final Commit**

```bash
git commit --allow-empty -m "chore: complete restructuring Phase 3 and Phase 4"
```

---

### Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-02-restructuring-phase-3-4.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
