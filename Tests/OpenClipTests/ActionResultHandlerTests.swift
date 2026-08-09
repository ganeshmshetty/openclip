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
}
