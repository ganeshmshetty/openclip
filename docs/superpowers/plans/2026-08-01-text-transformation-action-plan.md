# Text Transformations & Sub-Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement comprehensive text transformation tools (case conversions, line tools, encoding, JSON format) registered as individual togglable sub-actions in Preferences -> Actions and grouped in a dropdown menu in PopupView.

**Architecture:** Define `TransformCase` enum in `Sources/Core/Actions/Builtin/TransformTextAction.swift` supporting 16 transformations. Each transformation registers as an individual built-in action (`builtin.transform.<id>`) disabled by default. Update `PreferencesView` to display sub-action toggles under Transform Text, and update `PopupView` to render a dropdown menu of active transformations.

**Tech Stack:** Swift 6 (strict concurrency) · SwiftUI · Core Actions

## Global Constraints

- Language: Swift 6 strict concurrency — zero warnings.
- All transform sub-actions disabled by default in `ActionRegistry.shared`.
- All 49 existing unit tests + new tests must pass cleanly.
- Commit after each task.

---

## File Structure

- Create: `Sources/Core/Actions/Builtin/TransformTextAction.swift` (`TransformCase` enum + `TransformSubAction` struct + `TransformTextGroupAction` struct)
- Create: `Tests/OpenClipTests/TransformTextActionTests.swift` (Unit tests for all 16 transformations)
- Modify: `Sources/Core/Actions/BuiltinRegistry.swift` (Register all `TransformSubAction` instances)
- Modify: `Sources/Core/Actions/ActionRegistry.swift` (Include all `builtin.transform.*` in default disabled IDs)
- Modify: `Sources/OpenClip/UI/Preferences/PreferencesView.swift` (List transform sub-actions in Actions tab with configuration/toggles)
- Modify: `Sources/OpenClip/UI/Popup/PopupView.swift` (Render dropdown `Menu` of enabled transformations)

---

## Task 1: Implement `TransformCase` & Sub-Actions in Core with Unit Tests

**Files:**
- Create: `Sources/Core/Actions/Builtin/TransformTextAction.swift`
- Create: `Tests/OpenClipTests/TransformTextActionTests.swift`
- Modify: `Sources/Core/Actions/BuiltinRegistry.swift`
- Modify: `Sources/Core/Actions/ActionRegistry.swift`

- [ ] **Step 1: Write failing unit test for `TransformCase` conversions**

Create `Tests/OpenClipTests/TransformTextActionTests.swift`:
```swift
import XCTest
@testable import Core

final class TransformTextActionTests: XCTestCase {
    func testCaseConversions() {
        let text = "hello world example"
        XCTAssertEqual(TransformCase.uppercase.transform(text), "HELLO WORLD EXAMPLE")
        XCTAssertEqual(TransformCase.lowercase.transform(text), "hello world example")
        XCTAssertEqual(TransformCase.titleCase.transform(text), "Hello World Example")
        XCTAssertEqual(TransformCase.camelCase.transform(text), "helloWorldExample")
        XCTAssertEqual(TransformCase.pascalCase.transform(text), "HelloWorldExample")
        XCTAssertEqual(TransformCase.snakeCase.transform(text), "hello_world_example")
        XCTAssertEqual(TransformCase.kebabCase.transform(text), "hello-world-example")
        XCTAssertEqual(TransformCase.constantCase.transform(text), "HELLO_WORLD_EXAMPLE")
    }
    
    func testTextCleaningAndLineTools() {
        XCTAssertEqual(TransformCase.trimWhitespace.transform("   hello world   \n\n"), "hello world")
        XCTAssertEqual(TransformCase.sortLines.transform("banana\napple\ncherry"), "apple\nbanana\ncherry")
        XCTAssertEqual(TransformCase.removeDuplicates.transform("apple\napple\nbanana"), "apple\nbanana")
        XCTAssertEqual(TransformCase.reverseText.transform("hello"), "olleh")
    }
    
    func testEncodingAndJSON() {
        XCTAssertEqual(TransformCase.urlEncode.transform("hello world"), "hello%20world")
        XCTAssertEqual(TransformCase.urlDecode.transform("hello%20world"), "hello world")
        XCTAssertEqual(TransformCase.base64Encode.transform("hello"), "aGVsbG8=")
        XCTAssertEqual(TransformCase.base64Decode.transform("aGVsbG8="), "hello")
        
        let rawJSON = "{\"name\":\"openclip\",\"version\":1}"
        let formatted = TransformCase.formatJSON.transform(rawJSON)
        XCTAssertTrue(formatted.contains("\n"))
        XCTAssertTrue(formatted.contains("\"name\" : \"openclip\"") || formatted.contains("\"name\": \"openclip\""))
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`
Expected: FAIL with "cannot find TransformCase in scope"

- [ ] **Step 3: Implement `TransformTextAction.swift`**

Create `Sources/Core/Actions/Builtin/TransformTextAction.swift`:
```swift
import Foundation

public enum TransformCategory: String, Sendable, CaseIterable {
    case caseConversion = "Case Conversion"
    case textCleaning = "Text Cleaning"
    case developerEncoding = "Developer & Encoding"
}

public enum TransformCase: String, CaseIterable, Sendable, Identifiable {
    case uppercase = "uppercase"
    case lowercase = "lowercase"
    case titleCase = "titleCase"
    case camelCase = "camelCase"
    case pascalCase = "pascalCase"
    case snakeCase = "snakeCase"
    case kebabCase = "kebabCase"
    case constantCase = "constantCase"
    
    case trimWhitespace = "trimWhitespace"
    case sortLines = "sortLines"
    case removeDuplicates = "removeDuplicates"
    case reverseText = "reverseText"
    
    case urlEncode = "urlEncode"
    case urlDecode = "urlDecode"
    case base64Encode = "base64Encode"
    case base64Decode = "base64Decode"
    case formatJSON = "formatJSON"
    
    public var id: String { rawValue }
    
    public var category: TransformCategory {
        switch self {
        case .uppercase, .lowercase, .titleCase, .camelCase, .pascalCase, .snakeCase, .kebabCase, .constantCase:
            return .caseConversion
        case .trimWhitespace, .sortLines, .removeDuplicates, .reverseText:
            return .textCleaning
        case .urlEncode, .urlDecode, .base64Encode, .base64Decode, .formatJSON:
            return .developerEncoding
        }
    }
    
    public var displayName: String {
        switch self {
        case .uppercase: return "UPPERCASE"
        case .lowercase: return "lowercase"
        case .titleCase: return "Title Case"
        case .camelCase: return "camelCase"
        case .pascalCase: return "PascalCase"
        case .snakeCase: return "snake_case"
        case .kebabCase: return "kebab-case"
        case .constantCase: return "CONSTANT_CASE"
        case .trimWhitespace: return "Trim Whitespace"
        case .sortLines: return "Sort Lines (A-Z)"
        case .removeDuplicates: return "Remove Duplicate Lines"
        case .reverseText: return "Reverse Text"
        case .urlEncode: return "URL Encode"
        case .urlDecode: return "URL Decode"
        case .base64Encode: return "Base64 Encode"
        case .base64Decode: return "Base64 Decode"
        case .formatJSON: return "Format JSON"
        }
    }
    
    public func transform(_ text: String) -> String {
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        switch self {
        case .uppercase:
            return text.uppercased()
        case .lowercase:
            return text.lowercased()
        case .titleCase:
            return words.map { $0.capitalized }.joined(separator: " ")
        case .camelCase:
            guard let first = words.first?.lowercased() else { return text }
            let rest = words.dropFirst().map { $0.capitalized }
            return ([first] + rest).joined()
        case .pascalCase:
            return words.map { $0.capitalized }.joined()
        case .snakeCase:
            return words.map { $0.lowercased() }.joined(separator: "_")
        case .kebabCase:
            return words.map { $0.lowercased() }.joined(separator: "-")
        case .constantCase:
            return words.map { $0.uppercased() }.joined(separator: "_")
        case .trimWhitespace:
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .sortLines:
            return text.components(separatedBy: .newlines).sorted().joined(separator: "\n")
        case .removeDuplicates:
            var seen = Set<String>()
            return text.components(separatedBy: .newlines).filter { seen.insert($0).inserted }.joined(separator: "\n")
        case .reverseText:
            return String(text.reversed())
        case .urlEncode:
            return text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        case .urlDecode:
            return text.removingPercentEncoding ?? text
        case .base64Encode:
            return Data(text.utf8).base64EncodedString()
        case .base64Decode:
            guard let data = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let decoded = String(data: data, encoding: .utf8) else { return text }
            return decoded
        case .formatJSON:
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data),
                  let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
                  let prettyString = String(data: prettyData, encoding: .utf8) else { return text }
            return prettyString
        }
    }
}

public struct TransformSubAction: Action {
    public let transformCase: TransformCase
    
    public var id: String { "builtin.transform.\(transformCase.rawValue)" }
    public var title: String { transformCase.displayName }
    public var icon: ActionIcon { .symbol("textformat") }
    
    public init(transformCase: TransformCase) {
        self.transformCase = transformCase
    }
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        return !context.selection.text.isEmpty
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let transformed = transformCase.transform(context.selection.text)
        return .paste(transformed)
    }
}

public struct TransformTextGroupAction: Action {
    public let id = "builtin.transform"
    public let title = "Transform Text"
    public let icon = ActionIcon.symbol("textformat")
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        return !context.selection.text.isEmpty
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        return .none
    }
}
```

- [ ] **Step 4: Register in `BuiltinRegistry` & `ActionRegistry`**

In `BuiltinRegistry.swift`:
```swift
public static func makeCoreBuiltins() -> [any Action] {
    var actions: [any Action] = [
        SearchAction(),
        CopyAction(),
        CutAction(),
        PasteAction(),
        DefineAction(),
        CalculateAction(),
        TransformTextGroupAction()
    ]
    for transformCase in TransformCase.allCases {
        actions.append(TransformSubAction(transformCase: transformCase))
    }
    return actions
}
```

In `ActionRegistry.swift`:
```swift
private let defaultDisabledIDs: Set<String> = [
    "builtin.transform"
].union(TransformCase.allCases.map { "builtin.transform.\($0.rawValue)" })
```

- [ ] **Step 5: Run unit tests to verify pass**

Run: `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`
Expected: PASS (50 tests passing).

- [ ] **Step 6: Commit Task 1**

```bash
git add Sources/Core/Actions/Builtin/TransformTextAction.swift Sources/Core/Actions/BuiltinRegistry.swift Sources/Core/Actions/ActionRegistry.swift Tests/OpenClipTests/TransformTextActionTests.swift project.yml
git commit -m "feat(core): implement TransformCase enum, TransformSubAction, and group action"
```

---

## Task 2: Update Preferences & Popup UI Handoff

**Files:**
- Modify: `Sources/OpenClip/UI/Preferences/PreferencesView.swift`
- Modify: `Sources/OpenClip/UI/Popup/PopupView.swift`

- [ ] **Step 1: Update `PreferencesView.swift` to list transform sub-actions**

In `PreferencesView.swift` (`ActionsTab`), group transform sub-actions cleanly so users can toggle individual text transformation tools (e.g. UPPERCASE, camelCase, JSON Format) ON/OFF in Preferences.

- [ ] **Step 2: Update `PopupView.swift` to render `Menu` for enabled sub-actions**

In `PopupView.swift`:
If `action is TransformTextGroupAction` or `action.id == "builtin.transform"`:
Check which `TransformSubAction`s are active/enabled in `actions`, and render a native `Menu` with categories or direct items:
```swift
if action.id == "builtin.transform" {
    Menu {
        ForEach(TransformCategory.allCases, id: \.rawValue) { cat in
            let catCases = TransformCase.allCases.filter { $0.category == cat }
            Menu(cat.rawValue) {
                ForEach(catCases) { tCase in
                    Button(tCase.displayName) {
                        let res = tCase.transform(context.selection.text)
                        onResult(.paste(res))
                    }
                }
            }
        }
    } label: {
        buttonLabel
    }
    .menuStyle(.borderlessButton)
}
```

- [ ] **Step 3: Run full unit test suite**

Run: `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`
Expected: PASS with zero errors.

- [ ] **Step 4: Build and launch dev app**

Run: `./scripts/dev_run.sh`
Expected: App launches cleanly. Enabling sub-actions in Preferences -> Actions shows them in the Transform Text dropdown menu!

- [ ] **Step 5: Commit Task 2**

```bash
git add Sources/OpenClip/UI/Preferences/PreferencesView.swift Sources/OpenClip/UI/Popup/PopupView.swift docs/superpowers/plans/2026-08-01-text-transformation-action-plan.md
git commit -m "feat(ui): display transform sub-actions in Preferences and render dropdown Menu in PopupView"
```
