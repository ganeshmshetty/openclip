import XCTest
@testable import Core

@MainActor
final class ClipBasketStoreTests: XCTestCase {
    private func makeStore() -> (ClipBasketStore, MemorySettingsStore) {
        let settings = MemorySettingsStore()
        return (ClipBasketStore(settingsStore: settings), settings)
    }

    func testPreferencesLoadFromSettings() {
        let (_, settings) = makeStore()
        settings.set(.clipBasketOrder, value: ClipBasketOrder.lifo.rawValue)
        settings.set(.clipBasketPasteAsPlainText, value: true)
        settings.set(.clipBasketJoinFormat, value: ClipBasketJoinFormat.comma.rawValue)

        let store = ClipBasketStore(settingsStore: settings)
        XCTAssertEqual(store.order, .lifo)
        XCTAssertTrue(store.pasteAsPlainText)
        XCTAssertEqual(store.joinFormat, .comma)
    }

    func testPreferenceChangesPersist() {
        let (store, settings) = makeStore()
        store.reverse()
        store.setPasteAsPlainText(true)
        store.setJoinFormat(.numberedList)

        XCTAssertEqual(settings.get(.clipBasketOrder), ClipBasketOrder.lifo.rawValue)
        XCTAssertTrue(settings.get(.clipBasketPasteAsPlainText))
        XCTAssertEqual(settings.get(.clipBasketJoinFormat), ClipBasketJoinFormat.numberedList.rawValue)
    }

    func testItemsStayInMemoryOnly() {
        let (store, settings) = makeStore()
        store.enqueue(ClipBasketItem(content: .text(RichPasteboardPayload(plainText: "secret"))))

        XCTAssertEqual(store.count, 1)
        XCTAssertNil(settings.rawObject(forKey: "clipBasket.items"))
    }

    func testUndoAfterDelivery() {
        let (store, _) = makeStore()
        store.enqueue(ClipBasketItem(content: .text(RichPasteboardPayload(plainText: "a"))))
        store.enqueue(ClipBasketItem(content: .text(RichPasteboardPayload(plainText: "b"))))

        XCTAssertEqual(store.popNext()?.content.plainText, "a")
        XCTAssertEqual(store.undo()?.content.plainText, "a")
        XCTAssertEqual(store.items.map(\.content.plainText), ["a", "b"])
    }
}
