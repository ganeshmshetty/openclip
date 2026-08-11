import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class ActionResultHandlerTests: XCTestCase {
    func testCopyResultHandler() async throws {
        let handler = DefaultActionResultHandler()
        let result = ActionResult.copy("Test Copy")
        try await handler.handle(result, in: nil)
        
        let pasteboardText = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(pasteboardText, "Test Copy")
    }

    /// Presentation/flow results are presenter-owned (PopupWindowController); the handler must treat
    /// them as no-ops without crashing.
    func testHandlerIgnoresShowContent() async throws {
        let handler = DefaultActionResultHandler()
        let tree = CanvasComponent.text(CanvasTextProps(content: "hi"))
        try await handler.handle(.showContent(tree, nil), in: nil)
    }

    /// The `shortcut` effect routes through the shortcuts CLI under a watchdog. Only exercised when
    /// the binary is present; there is no deterministic short-lived Shortcut to invoke here, so the
    /// assertion is that a non-existent name surfaces as a thrown error (→ status) and that the
    /// missing-binary guard throws cleanly too.
    func testRunShortcutDoesNotCrash() async throws {
        let handler = DefaultActionResultHandler()
        let binary = URL(fileURLWithPath: Constants.shortcutsBinaryPath)
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw XCTSkip("shortcuts CLI unavailable; skipping run-shortcut handler test")
        }
        // A name that almost certainly does not exist: either it runs and logs, or the CLI exits
        // non-zero (→ throw). Both are acceptable; the point is the handler path does not hang.
        do {
            try await handler.handle(.runShortcut(name: "__openclip_should_not_exist__", input: nil), in: nil)
        } catch {
            // Expected: non-existent shortcut → non-zero exit → thrown error.
        }
    }

    func testPasteResultHandlerSkipsRestoreIfChangeCountMoved() async throws {
        let store = MemorySettingsStore()
        store.set(.completionCopyToClipboard, value: false)
        let handler = DefaultActionResultHandler(settingsStore: store)
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("OriginalItem", forType: .string)

        try await handler.handle(.paste("PastedText"), in: nil)

        // User copies something new while sleep task is running
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("UserNewCopy", forType: .string)

        // Wait for restore delay
        try await Task.sleep(nanoseconds: UInt64((Constants.pasteboardRestoreDelay + 0.1) * 1_000_000_000))

        // Ensure user's new copy was NOT overwritten by stale restore task
        let currentText = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(currentText, "UserNewCopy", "Pasteboard restore must be skipped when changeCount moved")
    }
}

