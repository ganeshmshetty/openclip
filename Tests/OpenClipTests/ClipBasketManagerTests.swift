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

    @MainActor
    private final class ArmedHotkeyRecorder {
        var values: [Bool] = []
    }

    private func makeManager(
        store: ClipBasketStore,
        settings: MemorySettingsStore,
        paster: RecordingPaster,
        monitor: ClipBasketPasteboardMonitor? = nil,
        armedHotkey: ArmedHotkeyRecorder? = nil
    ) -> ClipBasketManager {
        ClipBasketManager(
            store: store,
            panelController: ClipBasketPanelController(settingsStore: settings),
            paster: paster,
            monitor: monitor ?? ClipBasketPasteboardMonitor(),
            settingsStore: settings,
            setArmedHotkeyEnabled: { enabled in
                armedHotkey?.values.append(enabled)
            }
        )
    }

    private func makeMonitor(pasteboard: NSPasteboard) -> ClipBasketPasteboardMonitor {
        ClipBasketPasteboardMonitor(
            pasteboard: pasteboard,
            accessPolicy: PasteboardAccessPolicy(read: { .allowed }),
            frontmostIdentity: { AppIdentity(bundleIdentifier: "com.example.editor") },
            isExcluded: { _ in false },
            isDisabled: { _ in false }
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

    func testSetArmedPasteTogglesDynamicHotkey() {
        let settings = MemorySettingsStore()
        let store = ClipBasketStore(settingsStore: settings)
        let recorder = ArmedHotkeyRecorder()
        let manager = makeManager(store: store, settings: settings, paster: RecordingPaster(), armedHotkey: recorder)
        enqueueText(["a"], into: store)
        store.setOpen(true)

        manager.setArmedPaste(true)
        XCTAssertEqual(recorder.values, [true])
        XCTAssertTrue(store.isCommandVArmed)

        manager.setArmedPaste(false)
        XCTAssertEqual(recorder.values, [true, false])
        XCTAssertFalse(store.isCommandVArmed)
    }

    func testRemovingLastItemDisarmsHotkey() {
        let settings = MemorySettingsStore()
        let store = ClipBasketStore(settingsStore: settings)
        let recorder = ArmedHotkeyRecorder()
        let manager = makeManager(store: store, settings: settings, paster: RecordingPaster(), armedHotkey: recorder)
        enqueueText(["a"], into: store)
        store.setOpen(true)
        manager.setArmedPaste(true)
        let id = store.items[0].id

        manager.remove(itemID: id)

        XCTAssertTrue(store.isEmpty)
        XCTAssertFalse(store.isCommandVArmed)
        XCTAssertEqual(recorder.values, [true, false])
    }

    func testArmedPasteDisablesHotkeyThenReenablesWhenItemsRemain() async {
        let settings = MemorySettingsStore()
        let store = ClipBasketStore(settingsStore: settings)
        let paster = RecordingPaster()
        let recorder = ArmedHotkeyRecorder()
        let manager = makeManager(store: store, settings: settings, paster: paster, armedHotkey: recorder)
        enqueueText(["a", "b"], into: store)
        store.setOpen(true)
        store.setCommandVArmed(true)

        manager.handleArmedPaste()

        XCTAssertEqual(recorder.values, [false], "the synthetic ⌘V must be guarded immediately")
        await waitFor("armed hotkey re-enabled") { recorder.values == [false, true] }
        XCTAssertEqual(store.items.map(\.content.plainText), ["b"])
    }

    func testArmedPasteLeavesHotkeyDisabledWhenBasketEmpties() async {
        let settings = MemorySettingsStore()
        let store = ClipBasketStore(settingsStore: settings)
        let paster = RecordingPaster()
        let recorder = ArmedHotkeyRecorder()
        let manager = makeManager(store: store, settings: settings, paster: paster, armedHotkey: recorder)
        enqueueText(["a"], into: store)
        store.setOpen(true)
        store.setCommandVArmed(true)

        manager.handleArmedPaste()

        await waitFor("last item pasted") { paster.pastedTexts == ["a"] }
        await waitFor("basket closed") { !store.isOpen }
        XCTAssertEqual(recorder.values, [false])
        XCTAssertFalse(store.isCommandVArmed)
    }

    func testAutoCaptureMonitorRunsOnlyWhileOpenAndEnabled() {
        let settings = MemorySettingsStore()
        let store = ClipBasketStore(settingsStore: settings)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipBasketManager-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let monitor = makeMonitor(pasteboard: pasteboard)
        let manager = makeManager(
            store: store,
            settings: settings,
            paster: RecordingPaster(),
            monitor: monitor
        )

        store.setOpen(true)
        manager.syncMonitor()
        XCTAssertTrue(monitor.isRunning)

        settings.set(.clipBasketAutoCaptureCopies, value: false)
        manager.syncMonitor()
        XCTAssertFalse(monitor.isRunning)

        settings.set(.clipBasketAutoCaptureCopies, value: true)
        store.setOpen(false)
        manager.syncMonitor()
        XCTAssertFalse(monitor.isRunning)
    }

    func testAutoCloseStopsMonitorAndDisarmsHotkey() async {
        let settings = MemorySettingsStore()
        let store = ClipBasketStore(settingsStore: settings)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipBasketManager-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let monitor = makeMonitor(pasteboard: pasteboard)
        let recorder = ArmedHotkeyRecorder()
        let paster = RecordingPaster()
        let manager = makeManager(
            store: store,
            settings: settings,
            paster: paster,
            monitor: monitor,
            armedHotkey: recorder
        )
        enqueueText(["only"], into: store)
        store.setOpen(true)
        store.setCommandVArmed(true)
        manager.syncMonitor()
        manager.syncArmedHotkey()
        XCTAssertTrue(monitor.isRunning)

        manager.pasteNext()

        await waitFor("basket empty and closed") { store.isEmpty && !store.isOpen }
        XCTAssertFalse(monitor.isRunning)
        XCTAssertEqual(recorder.values.last, false)
    }
}
