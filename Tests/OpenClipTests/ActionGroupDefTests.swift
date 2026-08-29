import XCTest
@testable import Core

final class ActionGroupDefTests: XCTestCase {
    private func createMockContext(with text: String) -> ActionContext {
        let selection = SelectionContext(
            text: text,
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        return ActionContext(selection: selection, modifiers: [])
    }

    func testRoundTripSerialization() throws {
        let def = ActionGroupDef(
            id: "vgroup.test",
            title: "My Group",
            iconName: "folder",
            memberActionIDs: ["builtin.copy", "builtin.paste"]
        )
        let data = try ActionGroupDef.encode([def])
        let decoded = try ActionGroupDef.decode(from: data)
        XCTAssertEqual(decoded, [def])
    }

    func testDecodeOrEmpty() throws {
        let def = ActionGroupDef(
            id: "vgroup.test",
            title: "My Group",
            iconName: "folder",
            memberActionIDs: ["builtin.copy"]
        )
        let data = try ActionGroupDef.encode([def])
        XCTAssertEqual(ActionGroupDef.decodeOrEmpty(from: data), [def])
        XCTAssertEqual(ActionGroupDef.decodeOrEmpty(from: Data()), [])
        XCTAssertEqual(ActionGroupDef.decodeOrEmpty(from: nil), [])
        XCTAssertEqual(ActionGroupDef.decodeOrEmpty(from: "invalid json".data(using: .utf8)), [])
    }

    func testCustomGroupActionResolvesSubActionsFromCatalogByCanonicalIDPreservingCatalogOrder() {
        let action1 = DummyAction(id: "builtin.copy", title: "Copy")
        let action2 = DummyAction(id: "builtin.paste", title: "Paste")
        let action3 = DummyAction(id: "builtin.cut", title: "Cut")
        // Catalog order is: copy, paste, cut
        let catalog: [any Action] = [action1, action2, action3]

        // memberActionIDs defined in reverse order: paste, copy
        let group = CustomGroupAction(
            id: "vgroup.test",
            title: "Clipboard",
            iconName: "doc.on.clipboard",
            memberActionIDs: ["builtin.paste", "builtin.copy", "nonexistent.action"]
        )

        let resolved = group.subActions(in: catalog)
        // Subactions should follow catalog ordering: copy, paste
        XCTAssertEqual(resolved.map(\.id), ["builtin.copy", "builtin.paste"])
    }

    @MainActor
    func testCustomGroupActionPropertiesAndBehavior() async throws {
        let group = CustomGroupAction(
            id: "vgroup.test",
            title: "Clipboard",
            iconName: "doc.on.clipboard",
            memberActionIDs: ["builtin.copy", "builtin.paste"]
        )

        XCTAssertEqual(group.id, "vgroup.test")
        XCTAssertEqual(group.title, "Clipboard")
        XCTAssertEqual(group.icon, .symbol("doc.on.clipboard"))
        XCTAssertEqual(group.chrome.rowStyle, .actionGroup)
        XCTAssertEqual(group.chrome.popupBehavior, .showSubActions)
        XCTAssertEqual(group.chrome.source, .builtin)
        XCTAssertEqual(group.chrome.badge, .none)
        XCTAssertEqual(group.memberActionIDs, ["builtin.copy", "builtin.paste"])

        let nonEmptyContext = createMockContext(with: "hello")
        let emptyContext = createMockContext(with: "   \n\t  ")

        XCTAssertTrue(group.isEnabled(for: nonEmptyContext))
        XCTAssertFalse(group.isEnabled(for: emptyContext))
        XCTAssertNil(group.matchInfo(for: nonEmptyContext))

        let result = try await group.perform(nonEmptyContext)
        if case .none = result {
            // expected
        } else {
            XCTFail("Expected .none result, got \(result)")
        }
    }
}

private struct DummyAction: Action, Sendable {
    let id: String
    let title: String
    var icon: ActionIcon { .symbol("star") }
    var chrome: ActionChrome { ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin) }
    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .none }
}
