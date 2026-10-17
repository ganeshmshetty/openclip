import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class ActionResultHandlerTests: XCTestCase {
    @MainActor
    private final class RecordingPoster: KeyboardEventPosting {
        var keys: [CGKeyCode] = []
        var onPost: (() -> Void)?
        func postKey(keyCode: CGKeyCode, flags: CGEventFlags) {
            keys.append(keyCode)
            onPost?()
        }
    }

    private final class SourceApp: NSRunningApplication {
        override var processIdentifier: pid_t { 99999 }
        override var bundleIdentifier: String? { "md.obsidian" }
    }

    func testCopyPlaysSoundOnlyWhenEnabled() async throws {
        let board = NSPasteboard(name: .init("OpenClipCopySound-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let store = MemorySettingsStore()
        var played: [CopySound] = []
        let handler = DefaultActionResultHandler(
            settingsStore: store, keyboardPoster: RecordingPoster(), pasteboard: board,
            copySoundPlayer: { played.append($0) }
        )
        try await handler.handle(.copy("one"), in: nil)
        XCTAssertTrue(played.isEmpty, "Sound is off by default")
        store.set(.playCopySound, value: true)
        store.set(.copySoundName, value: "thock")
        try await handler.handle(.copy("two"), in: nil)
        XCTAssertEqual(played, [.thock])
        XCTAssertEqual(board.string(forType: .string), "two")
    }

    func testCapturePickerRefusalIsNotReportedAsChangedSource() async throws {
        let board = NSPasteboard(name: .init("OpenClipNativeCopy-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.setString("Original", forType: .string)
        let source = SourceApp()
        let poster = RecordingPoster()
        let handler = DefaultActionResultHandler(
            settingsStore: MemorySettingsStore(), keyboardPoster: poster, pasteboard: board,
            pasteboardRestoreDelay: 0.01, appActivator: { _ in }, targetActiveChecker: { _ in true },
            frontmostPID: { 99999 }, copyOverlayPresent: { true }
        )
        do {
            try await handler.handle(.copySelection(SelectionContext(text: "Text", sourceApp: AppIdentity(source))),
                                     in: nil, targetApp: source)
            XCTFail("A capture picker must block Copy")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Finish the screen capture before copying.")
        }
        XCTAssertTrue(poster.keys.isEmpty)
        XCTAssertEqual(board.string(forType: .string), "Original")
    }

    func testLiveCopyPostsNativeCommandAndLeavesSourceFormatsIntact() async throws {
        let board = NSPasteboard(name: .init("OpenClipNativeCopy-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.setString("Old clipboard", forType: .string)
        let source = SourceApp()
        let poster = RecordingPoster()
        let custom = NSPasteboard.PasteboardType("com.test.obsidian-table")
        var copiedCount = 0
        poster.onPost = {
            let item = NSPasteboardItem()
            item.setString("**Bold**", forType: .string)
            item.setString("<b>Bold</b>", forType: .html)
            item.setData(Data([1, 2, 3]), forType: custom)
            board.clearContents()
            board.writeObjects([item])
            copiedCount = board.changeCount
        }
        let handler = DefaultActionResultHandler(
            settingsStore: MemorySettingsStore(), keyboardPoster: poster, pasteboard: board,
            pasteboardRestoreDelay: 0.01, appActivator: { _ in }, targetActiveChecker: { _ in true },
            frontmostPID: { 99999 }
        )
        let selection = SelectionContext(text: "AX plain text", sourceApp: AppIdentity(source), selectionGeneration: 12)
        try await handler.handle(.copySelection(selection), in: nil, targetApp: source,
                                 isSelectionCurrent: { $0.selectionGeneration == 12 })
        XCTAssertEqual(poster.keys, [Constants.copyVirtualKey])
        XCTAssertEqual(board.changeCount, copiedCount)
        XCTAssertEqual(board.data(forType: custom), Data([1, 2, 3]))
        XCTAssertEqual(board.string(forType: .html), "<b>Bold</b>")
        XCTAssertEqual(board.string(forType: .string), "**Bold**")
    }

    func testLiveCopyRejectsSelectionChangedDuringActivation() async throws {
        let board = NSPasteboard(name: .init("OpenClipNativeCopy-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.setString("Original", forType: .string)
        let source = SourceApp()
        let poster = RecordingPoster()
        var current = true
        let handler = DefaultActionResultHandler(
            settingsStore: MemorySettingsStore(), keyboardPoster: poster, pasteboard: board,
            pasteboardRestoreDelay: 0.01, appActivator: { _ in },
            targetActiveChecker: { _ in current = false; return true }, frontmostPID: { 99999 }
        )
        let selection = SelectionContext(text: "Old selection", sourceApp: AppIdentity(source))
        do {
            try await handler.handle(.copySelection(selection), in: nil, targetApp: source,
                                     isSelectionCurrent: { _ in current })
            XCTFail("A stale selection must not trigger Copy")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The source selection is no longer available.")
        }
        XCTAssertTrue(poster.keys.isEmpty)
        XCTAssertEqual(board.string(forType: .string), "Original")
    }

    func testLiveCopyRefusesDifferentForegroundApplicationWithoutActivatingSource() async throws {
        let board = NSPasteboard(name: .init("OpenClipNativeCopy-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.setString("Original", forType: .string)
        let poster = RecordingPoster()
        var activated = false
        let handler = DefaultActionResultHandler(
            settingsStore: MemorySettingsStore(), keyboardPoster: poster, pasteboard: board,
            pasteboardRestoreDelay: 0.01, appActivator: { _ in activated = true },
            targetActiveChecker: { _ in true }, frontmostPID: { 88888 }
        )
        let source = SourceApp()
        do {
            try await handler.handle(.copySelection(SelectionContext(text: "Text", sourceApp: AppIdentity(source))),
                                     in: nil, targetApp: source)
            XCTFail("Copy must not switch back to an unrelated app")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The source selection is no longer available.")
        }
        XCTAssertFalse(activated)
        XCTAssertTrue(poster.keys.isEmpty)
        XCTAssertEqual(board.string(forType: .string), "Original")
    }

    private func makeHandler(settingsStore: SettingsStore = MemorySettingsStore(),
                             pasteboard: NSPasteboard = .general,
                             dictionaryLookup: @escaping DefaultActionResultHandler.DictionaryLookup = { _ in nil },
                             pasteboardRestoreDelay: TimeInterval = 0.01) -> DefaultActionResultHandler {
        DefaultActionResultHandler(settingsStore: settingsStore, keyboardPoster: RecordingPoster(),
                                   pasteboard: pasteboard, dictionaryLookup: dictionaryLookup,
                                   pasteboardRestoreDelay: pasteboardRestoreDelay,
                                   appActivator: { _ in }, targetActiveChecker: { _ in true })
    }

    func testCopyResultHandler() async throws {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let handler = makeHandler(pasteboard: isolatedPasteboard)
        let result = ActionResult.copy("Test Copy")
        try await handler.handle(result, in: nil)
        
        let pasteboardText = isolatedPasteboard.string(forType: .string)
        XCTAssertEqual(pasteboardText, "Test Copy")
    }

    func testCopyDefinitionHandlerWritesLookupToPasteboard() async throws {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let handler = makeHandler(
            pasteboard: isolatedPasteboard,
            dictionaryLookup: { word in "The definition of \(word)." }
        )
        try await handler.handle(.copyDefinition("epiphany"), in: nil)

        XCTAssertEqual(isolatedPasteboard.string(forType: .string), "The definition of epiphany.")
    }

    func testCopyDefinitionHandlerThrowsWhenLookupEmpty() async throws {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let handler = makeHandler(
            pasteboard: isolatedPasteboard,
            dictionaryLookup: { _ in nil }
        )

        do {
            try await handler.handle(.copyDefinition("zzznotaword"), in: nil)
            XCTFail("Expected empty definition lookup to throw")
        } catch {
        }
        XCTAssertNil(isolatedPasteboard.string(forType: .string))
    }

    /// Skipped without the shortcuts CLI; a missing shortcut must throw rather than hang.
    func testRunShortcutDoesNotCrash() async throws {
        let handler = makeHandler()
        let binary = URL(fileURLWithPath: Constants.shortcutsBinaryPath)
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw XCTSkip("shortcuts CLI unavailable; skipping run-shortcut handler test")
        }
        // Either the CLI runs it or exits non-zero; both are fine as long as nothing hangs.
        do {
            try await handler.handle(.runShortcut(name: "__openclip_should_not_exist__", input: nil), in: nil)
        } catch {
        }
    }

    func testPasteResultHandlerSkipsRestoreIfChangeCountMoved() async throws {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let store = MemorySettingsStore()
        store.set(.completionCopyToClipboard, value: false)
        let testDelay: TimeInterval = 0.05
        let handler = makeHandler(settingsStore: store, pasteboard: isolatedPasteboard, pasteboardRestoreDelay: testDelay)
        
        isolatedPasteboard.clearContents()
        isolatedPasteboard.setString("OriginalItem", forType: .string)

        try await handler.handle(.paste("PastedText"), in: nil)

        // User copies something new while sleep task is running
        isolatedPasteboard.clearContents()
        isolatedPasteboard.setString("UserNewCopy", forType: .string)

        try await Task.sleep(nanoseconds: UInt64((testDelay + 0.05) * 1_000_000_000))

        // Ensure user's new copy was NOT overwritten by stale restore task
        let currentText = isolatedPasteboard.string(forType: .string)
        XCTAssertEqual(currentText, "UserNewCopy", "Pasteboard restore must be skipped when changeCount moved")
    }

    func testCopyContentHandlerWritesMultiTypePasteboard() async throws {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let handler = makeHandler(pasteboard: isolatedPasteboard)
        let payload = RichPasteboardPayload(plainText: "Plain copy", rtf: "{\\rtf1 RTF copy}", html: "<b>HTML copy</b>")
        try await handler.handle(.copyContent(payload), in: nil)

        XCTAssertEqual(isolatedPasteboard.string(forType: .string), "Plain copy")
        XCTAssertEqual(isolatedPasteboard.string(forType: .html), "<b>HTML copy</b>")
        XCTAssertEqual(isolatedPasteboard.string(forType: .rtf), "{\\rtf1 RTF copy}")
    }

    func testCopyContentHandlerWritesRawFlavorsVerbatim() async throws {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let handler = makeHandler(pasteboard: isolatedPasteboard)
        let proprietaryType = "com.apple.notes.richtext"
        let proprietaryData = Data([0x00, 0x01, 0xFE, 0xFF])
        let payload = RichPasteboardPayload(
            plainText: "Checklist",
            flavors: [
                RichPasteboardFlavor(type: "public.utf8-plain-text", data: Data("Checklist".utf8)),
                RichPasteboardFlavor(type: proprietaryType, data: proprietaryData)
            ]
        )
        try await handler.handle(.copyContent(payload), in: nil)

        XCTAssertEqual(isolatedPasteboard.data(forType: NSPasteboard.PasteboardType(proprietaryType)), proprietaryData)
        XCTAssertEqual(isolatedPasteboard.string(forType: .string), "Checklist")
    }

    func testPasteContentHandlerWritesMultiTypePasteboard() async throws {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let store = MemorySettingsStore()
        store.set(.completionCopyToClipboard, value: true)
        let handler = makeHandler(settingsStore: store, pasteboard: isolatedPasteboard)
        let payload = RichPasteboardPayload(plainText: "Plain paste", rtf: "{\\rtf1 RTF paste}", html: "<i>HTML paste</i>")
        try await handler.handle(.pasteContent(payload), in: nil)

        XCTAssertEqual(isolatedPasteboard.string(forType: .string), "Plain paste")
        XCTAssertEqual(isolatedPasteboard.string(forType: .html), "<i>HTML paste</i>")
        XCTAssertEqual(isolatedPasteboard.string(forType: .rtf), "{\\rtf1 RTF paste}")
        XCTAssertNotNil(isolatedPasteboard.data(forType: PasteboardSnapshot.transientType))
        XCTAssertNotNil(isolatedPasteboard.data(forType: PasteboardSnapshot.autoGeneratedType))
    }

    func testPasteResultHandlerTagsTransientMarkers() async throws {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let store = MemorySettingsStore()
        store.set(.completionCopyToClipboard, value: true)
        let handler = makeHandler(settingsStore: store, pasteboard: isolatedPasteboard)
        try await handler.handle(.paste("TransientPaste"), in: nil)

        XCTAssertEqual(isolatedPasteboard.string(forType: .string), "TransientPaste")
        XCTAssertNotNil(isolatedPasteboard.data(forType: PasteboardSnapshot.transientType))
        XCTAssertNotNil(isolatedPasteboard.data(forType: PasteboardSnapshot.autoGeneratedType))
    }

    func testPasteResultHandlerPassesTargetAppToOpenSelection() async throws {
        let board = NSPasteboard(name: .init("OpenClipTest-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let poster = RecordingPoster()
        let app = NSRunningApplication.current
        var activatedPID: pid_t?
        var checkedPID: pid_t?
        let handler = DefaultActionResultHandler(keyboardPoster: poster, pasteboard: board,
            pasteboardRestoreDelay: 0,
            appActivator: { activatedPID = $0.processIdentifier },
            targetActiveChecker: { checkedPID = $0.processIdentifier; return true })
        try await handler.handle(.paste("TargetAppText"), in: nil, targetApp: app)
        XCTAssertEqual(activatedPID, app.processIdentifier)
        XCTAssertEqual(checkedPID, app.processIdentifier)
        XCTAssertEqual(poster.keys, [Constants.vVirtualKey])
    }

    func testFailedActivationDoesNotWriteClipboardOrPostPaste() async {
        let board = NSPasteboard(name: .init("OpenClipTest-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.setString("original", forType: .string)
        let poster = RecordingPoster()
        let handler = DefaultActionResultHandler(keyboardPoster: poster, pasteboard: board,
            pasteboardRestoreDelay: 0, appActivator: { _ in }, targetActiveChecker: { _ in false })
        do {
            try await handler.handle(.paste("payload"), in: nil, targetApp: .current)
            XCTFail("Expected activation failure")
        } catch { }
        XCTAssertTrue(poster.keys.isEmpty)
        XCTAssertEqual(board.string(forType: .string), "original")
    }

    func testExplicitCopyCancelsPendingRestoreAndClearsCoordinatorSession() async throws {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let store = MemorySettingsStore()
        store.set(.completionCopyToClipboard, value: false)
        let testDelay: TimeInterval = 0.2
        let handler = makeHandler(settingsStore: store, pasteboard: isolatedPasteboard, pasteboardRestoreDelay: testDelay)

        isolatedPasteboard.clearContents()
        isolatedPasteboard.setString("BaselineClipboard", forType: .string)

        let pasteTask = Task { @MainActor in
            try await handler.handle(.paste("PastedText"), in: nil)
        }

        // Let the paste acquire its session before the explicit copy.
        try await Task.sleep(nanoseconds: 20_000_000)

        // User explicitly copies before the restore delay expires:
        try await handler.handle(.copy("ExplicitUserCopy"), in: nil)

        _ = await pasteTask.result

        XCTAssertEqual(isolatedPasteboard.string(forType: .string), "ExplicitUserCopy")
    }

    func testRapidSuccessivePastesInheritBaselineAndRestoreOriginal() async throws {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let store = MemorySettingsStore()
        store.set(.completionCopyToClipboard, value: false)
        let testDelay: TimeInterval = 0.1
        let handler = makeHandler(settingsStore: store, pasteboard: isolatedPasteboard, pasteboardRestoreDelay: testDelay)

        isolatedPasteboard.clearContents()
        isolatedPasteboard.setString("OriginalBaseline", forType: .string)

        let payload1 = RichPasteboardPayload(plainText: "Temp 1")
        let payload2 = RichPasteboardPayload(plainText: "Temp 2")

        let task1 = Task { @MainActor in
            try await handler.handle(.pasteContent(payload1), in: nil)
        }

        // Let task1 begin and set the dirty state first.
        try await Task.sleep(nanoseconds: 20_000_000)

        let task2 = Task { @MainActor in
            try await handler.handle(.pasteContent(payload2), in: nil)
        }

        _ = await task1.result
        _ = await task2.result

        XCTAssertEqual(isolatedPasteboard.string(forType: .string), "OriginalBaseline")
    }
}

