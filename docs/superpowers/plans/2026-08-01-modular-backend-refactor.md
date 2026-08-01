# Modular Backend Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix four architectural friction points so adding a new builtin action or extension requires touching exactly one file, not four.

**Architecture:** Introduce `ConfigurableAction` + `WordCompletionProviding` protocols; move AppKit-free builtins to `Core/Actions/Builtin/`; add `BuiltinRegistry`; make Preferences data-driven.

**Tech Stack:** Swift 6 strict concurrency · SwiftUI · AppKit (platform layer only) · XcodeGen

## Global Constraints
- Swift 6 strict concurrency — zero warnings
- `Core/` target: zero imports of AppKit or SwiftUI
- All new files included in project via `xcodegen`
- All 39+ tests must pass after every task
- Commit after every task

---

## Task 1: Add protocols to Core

**Files:**
- Create: `Sources/Core/Actions/ConfigurableAction.swift`
- Create: `Sources/Core/Actions/WordCompletionProviding.swift`
- Test: `Tests/OpenClipTests/ProtocolConformanceTests.swift`

Create these two protocol files:

```swift
// ConfigurableAction.swift
import Foundation
public protocol ConfigurableAction: Action {
    var configurationViewID: String { get }
    var preferenceIconName: String { get }
}
```

```swift
// WordCompletionProviding.swift
import Foundation
public protocol WordCompletionProviding: Action {
    @MainActor
    func fetchCompletions(for text: String) -> [String]
}
```

Tests:
```swift
import XCTest
@testable import Core
final class ProtocolConformanceTests: XCTestCase {
    func testConfigurableActionProtocolExists() {
        let _: (any ConfigurableAction).Type = (any ConfigurableAction).self
        XCTAssertTrue(true)
    }
    func testWordCompletionProvidingProtocolExists() {
        let _: (any WordCompletionProviding).Type = (any WordCompletionProviding).self
        XCTAssertTrue(true)
    }
}
```

Run `xcodegen` then `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`. Commit.

---

## Task 2: Move AppKit-free builtins to Core/Actions/Builtin/

Move SearchAction, CopyAction, CutAction, PasteAction, DefineAction, CalculateAction from `Sources/OpenClip/Platform/BuiltinActions/` to `Sources/Core/Actions/Builtin/`. Each must:
- Drop `import Core` (they ARE Core now)
- Drop `#if canImport(AppKit)` (they don't use AppKit)
- Adopt `ConfigurableAction` (add `configurationViewID` and `preferenceIconName`)
- `import Foundation` only

CompletionAction and ServicesAction stay in Platform/BuiltinActions/ (they use AppKit).

Example for SearchAction:
```swift
// Sources/Core/Actions/Builtin/SearchAction.swift
import Foundation
public struct SearchAction: ConfigurableAction {
    public let id = "builtin.search"
    public let title = "Search"
    public let icon = ActionIcon.symbol("magnifyingglass")
    public let configurationViewID = "builtin.search"
    public let preferenceIconName = "magnifyingglass"
    public init() {}
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        let text = context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasURLPrefix = text.hasPrefix("http://") || text.hasPrefix("https://") || text.hasPrefix("www.")
        return !hasURLPrefix && !text.isEmpty
    }
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let query = context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let template = UserDefaults.standard.string(forKey: "action.search.url") ?? ""
        if !template.isEmpty, template.contains("{query}"),
           let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: template.replacingOccurrences(of: "{query}", with: encodedQuery)) {
            return .openURL(url)
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/search"
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        if let url = components.url { return .openURL(url) }
        return .failure(NSError(domain: Constants.actionErrorDomain, code: Constants.actionErrorCode, userInfo: nil))
    }
}
```

Follow same pattern for the other 5 (CopyAction, CutAction, PasteAction, DefineAction, CalculateAction). For CalculateAction, copy the full body from the existing `Platform/BuiltinActions/CalculateAction.swift` and add `configurationViewID = "builtin.calculate"` and `preferenceIconName = "equal.circle"`.

After creating all 6 new files, delete the old ones:
```bash
rm Sources/OpenClip/Platform/BuiltinActions/SearchAction.swift
rm Sources/OpenClip/Platform/BuiltinActions/CopyAction.swift
rm Sources/OpenClip/Platform/BuiltinActions/CutAction.swift
rm Sources/OpenClip/Platform/BuiltinActions/PasteAction.swift
rm Sources/OpenClip/Platform/BuiltinActions/DefineAction.swift
rm Sources/OpenClip/Platform/BuiltinActions/CalculateAction.swift
```

Run `xcodegen` then full test suite. Commit.

---

## Task 3: Add BuiltinRegistry; simplify AppDelegate

Create `Sources/Core/Actions/BuiltinRegistry.swift`:
```swift
import Foundation
/// Core (AppKit-free) builtin actions. AppDelegate appends platform-specific ones.
public enum BuiltinRegistry {
    @MainActor
    public static func makeCoreBuiltins() -> [any Action] {
        [
            SearchAction(),
            DefineAction(),
            CopyAction(),
            CutAction(),
            PasteAction(),
            CalculateAction(),
        ]
    }
}
```

Update AppDelegate to replace the hard-coded list:
```swift
var builtins = BuiltinRegistry.makeCoreBuiltins()
builtins.insert(CompletionAction(), at: 0)
builtins.append(OpenURLAction())
builtins.append(ServicesAction())
ActionRegistry.shared.register(builtIns: builtins)
```

Tests (`Tests/OpenClipTests/BuiltinRegistryTests.swift`):
```swift
import XCTest
@testable import Core
@MainActor
final class BuiltinRegistryTests: XCTestCase {
    func testMakeCoreBuiltinsReturnsExpectedCount() {
        XCTAssertEqual(BuiltinRegistry.makeCoreBuiltins().count, 6)
    }
    func testAllCoreBuiltinIdsAreUnique() {
        let ids = BuiltinRegistry.makeCoreBuiltins().map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }
    func testExpectedIdsPresent() {
        let ids = Set(BuiltinRegistry.makeCoreBuiltins().map(\.id))
        XCTAssertTrue(ids.contains("builtin.search"))
        XCTAssertTrue(ids.contains("builtin.define"))
        XCTAssertTrue(ids.contains("builtin.copy"))
        XCTAssertTrue(ids.contains("builtin.cut"))
        XCTAssertTrue(ids.contains("builtin.paste"))
        XCTAssertTrue(ids.contains("builtin.calculate"))
    }
}
```

Run `xcodegen` then full test suite. Commit.

---

## Task 4: CompletionAction adopts WordCompletionProviding; fix PopupView

In `CompletionAction.swift`, change `Action` to `WordCompletionProviding`:
```swift
public struct CompletionAction: WordCompletionProviding {
```
The existing `fetchCompletions(for:)` already satisfies the protocol.

In `PopupView.swift`, replace `availableCompletions`:
```swift
private var availableCompletions: [String] {
    guard let provider = actions.first(where: { $0 is any WordCompletionProviding }) as? any WordCompletionProviding,
          provider.isEnabled(for: context) else { return [] }
    return provider.fetchCompletions(for: context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines))
}
```

Run full test suite. Commit.

---

## Task 5: Make Preferences data-driven via ConfigurableAction

In `PreferencesView.swift` (ActionRowView struct, ~line 333):

Replace:
```swift
var isConfigurable: Bool {
    ["builtin.search", "builtin.define", "builtin.copy", "builtin.cut", "builtin.paste", "builtin.calculate"].contains(action.id)
}
private var displayIcon: ActionIcon {
    switch action.id {
    case "builtin.copy": return .symbol("doc.on.doc")
    case "builtin.cut": return .symbol("scissors")
    case "builtin.paste": return .symbol("clipboard")
    case "builtin.calculate": return .symbol("equal.circle")
    case "builtin.define": return .symbol("book")
    case "builtin.completion": return .symbol("text.badge.plus")
    default: return action.icon
    }
}
```
With:
```swift
private var configurableAction: (any ConfigurableAction)? {
    action as? any ConfigurableAction
}
private var displayIcon: ActionIcon {
    if let configurable = configurableAction {
        return .symbol(configurable.preferenceIconName)
    }
    return action.icon
}
```

In the body, replace `if isConfigurable {` with `if let configurable = configurableAction {`, and change:
```swift
ActionConfigSheet(actionID: action.id)
```
to:
```swift
ActionConfigSheet(configurationViewID: configurable.configurationViewID)
```

In `ActionConfigSheet.swift`, rename parameter from `actionID` to `configurationViewID` and update all references inside `body`.

Run full test suite. Commit.
