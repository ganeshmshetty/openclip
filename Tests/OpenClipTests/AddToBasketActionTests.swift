import XCTest
@testable import Core

@MainActor
final class AddToBasketActionTests: XCTestCase {
    private func context(
        text: String,
        modifiers: ModifierFlags = [],
        isClipboardFallback: Bool = false
    ) -> ActionContext {
        ActionContext(
            selection: SelectionContext(
                text: text,
                sourceApp: AppIdentity(bundleIdentifier: "com.example.editor", localizedName: "Editor"),
                isClipboardFallback: isClipboardFallback
            ),
            modifiers: modifiers
        )
    }

    func testPrimaryClickEnqueuesOneItem() async throws {
        let store = ClipBasketStore(settingsStore: MemorySettingsStore())
        let action = AddToBasketAction(store: store)

        _ = try await action.perform(context(text: "line one\nline two"))

        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store.items.first?.content.plainText, "line one\nline two")
        XCTAssertEqual(store.items.first?.sourceApp?.bundleIdentifier, "com.example.editor")
    }

    func testOptionClickSplitsLines() async throws {
        let store = ClipBasketStore(settingsStore: MemorySettingsStore())
        let action = AddToBasketAction(store: store)

        _ = try await action.perform(context(text: "alpha\nbeta\n\ngamma", modifiers: .option))

        XCTAssertEqual(store.items.map(\.content.plainText), ["alpha", "beta", "gamma"])
    }

    func testRichPayloadIsPreserved() async throws {
        let store = ClipBasketStore(settingsStore: MemorySettingsStore())
        let action = AddToBasketAction(store: store)
        let rich = ActionContext(selection: SelectionContext(
            text: "bold",
            html: "<b>bold</b>",
            rtf: "{\\rtf1 bold}"
        ))

        _ = try await action.perform(rich)

        guard case .text(let payload) = store.items.first?.content else {
            return XCTFail("Expected a text item")
        }
        XCTAssertEqual(payload.plainText, "bold")
        XCTAssertEqual(payload.html, "<b>bold</b>")
        XCTAssertEqual(payload.rtf, "{\\rtf1 bold}")
    }

    func testDisabledForClipboardFallbackAndEmptySelection() {
        let store = ClipBasketStore(settingsStore: MemorySettingsStore())
        let action = AddToBasketAction(store: store)

        XCTAssertFalse(action.isEnabled(for: context(text: "clipboard text", isClipboardFallback: true)))
        XCTAssertFalse(action.isEnabled(for: context(text: "")))
        XCTAssertTrue(action.isEnabled(for: context(text: "live selection")))
    }
}
