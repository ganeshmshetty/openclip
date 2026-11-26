import XCTest
import AppKit
@testable import Core
@testable import OpenClip

@MainActor
final class ClipBasketManagerTests: XCTestCase {
    @MainActor
    private final class RecordingPaster: ClipBasketPasting {
        var pastedTexts: [String] = []
        var plainTextFlags: [Bool] = []
        var error: Error?

        func paste(_ item: ClipBasketItem, asPlainText: Bool, targetApp: NSRunningApplication?) async throws {
            pastedTexts.append(item.content.plainText ?? "")
            plainTextFlags.append(asPlainText)
            if let error {
                throw error
            }
        }
    }

    private func makeManager(
        store: ClipBasketStore,
        settings: MemorySettingsStore,
        paster: RecordingPaster
    ) -> ClipBasketManager {
        ClipBasketManager(
            store: store,
            panelController: ClipBasketPanelController(settingsStore: settings),
            paster: paster,
            settingsStore: settings
        )
    }

    private func enqueueText(_ texts: [String], into store: ClipBasketStore) {
        for text in texts {
            store.enqueue(ClipBasketItem(content: .text(RichPasteboardPayload(plainText: text))))
        }
    }

    private func waitFor(
        _ description: String,
        timeout: TimeInterval = 2,
        condition: @escaping () -> Bool
    ) async {
        for _ in 0..<Int(timeout * 100) {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for \(description)")
    }

    func testPasteNextPopsTheFrontItem() async {
        let settings = MemorySettingsStore()
        let store = ClipBasketStore(settingsStore: settings)
        let paster = RecordingPaster()
        let manager = makeManager(store: store, settings: settings, paster: paster)
        enqueueText(["a", "b"], into: store)

        manager.pasteNext()
        await waitFor("first item to pasted") { paster.pastedTexts == ["a"] }
        await waitFor("remaining item to stay") { store.items.map(\.content.plainText) == ["b"] }
    }

    func testPasteNextHonorsPlainTextPreference() async {
        let settings = MemorySettingsStore()
        let store = ClipBasketStore(settingsStore: settings)
        store.setPasteAsPlainText(true)
        let paster = RecordingPaster()
        let manager = makeManager(store: store, settings: settings, paster: paster)
        enqueueText(["a"], into: store)

        manager.pasteNext()
        await waitFor("plain-text paste") { paster.plainTextFlags == [true] }
    }

    func testFailedPasteRestoresThePoppedItem() async {
        let settings = MemorySettingsStore()
        let store = ClipBasketStore(settingsStore: settings)
        let paster = RecordingPaster()
        paster.error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Paste failed"])
        let manager = makeManager(store: store, settings: settings, paster: paster)
        enqueueText(["a", "b"], into: store)

        manager.pasteNext()
        await waitFor("item restored after failure") {
            store.items.map(\.content.plainText) == ["a", "b"]
        }
    }

    func testPasteAllJoinsThenClears() async {
        let settings = MemorySettingsStore()
        let store = ClipBasketStore(settingsStore: settings)
        let paster = RecordingPaster()
        let manager = makeManager(store: store, settings: settings, paster: paster)
        enqueueText(["one", "two"], into: store)

        manager.pasteAll()
        await waitFor("joined paste") { paster.pastedTexts == ["one\ntwo"] }
        await waitFor("basket cleared") { store.isEmpty }
    }

    func testEmptyPasteNextKeepsBasketAndDoesNotPaste() async {
        let settings = MemorySettingsStore()
        let store = ClipBasketStore(settingsStore: settings)
        let paster = RecordingPaster()
        let manager = makeManager(store: store, settings: settings, paster: paster)

        manager.pasteNext()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(paster.pastedTexts.isEmpty)
        XCTAssertTrue(store.isEmpty)
    }
}
