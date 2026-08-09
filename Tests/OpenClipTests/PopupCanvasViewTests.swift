import XCTest
import AppKit
import SwiftUI
@testable import OpenClip
@testable import Core

/// Fake action for hosting PopupView (bar rows need at least one action).
private struct CanvasTestAction: Action {
    let id = "test.canvas"
    var title: String { "Test" }
    var icon: ActionIcon { .symbol("gearshape") }
    var chrome: ActionChrome { ActionChrome(source: .builtin) }
    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .success }
}

@MainActor
final class PopupCanvasViewTests: XCTestCase {

    private func makeContext() -> ActionContext {
        ActionContext(
            selection: SelectionContext(
                text: "hi",
                sourceApp: AppIdentity(NSRunningApplication.current),
                cursorPosition: .zero,
                selectionBounds: nil,
                timestamp: Date(),
                appPolicy: .default
            )
        )
    }

    /// Hosts PopupView and returns its fitting size. The size-change preference callback doesn't
    /// fire reliably outside a live window, so measure the hosting view directly.
    private func measuredSize(store: PopupModeStore) -> CGSize {
        let view = PopupView(
            actions: [CanvasTestAction()],
            context: makeContext(),
            modeStore: store,
            onResult: { _ in }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        hosting.setFrameSize(hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize
    }

    func testPreviewStripGrowsContentHeight() {
        let store = PopupModeStore()
        let bar = measuredSize(store: store)

        store.preview = .text(CanvasTextProps(content: "2 + 2 = 4", style: .caption))
        let expanded = measuredSize(store: store)

        XCTAssertGreaterThan(expanded.height, bar.height, "preview strip should grow the popup")
    }

    func testStatusBannerGrowsContentHeight() {
        let store = PopupModeStore()
        let bar = measuredSize(store: store)

        store.statusBanner = StatusFeedback(message: "Copied", style: .success)
        let expanded = measuredSize(store: store)

        XCTAssertGreaterThan(expanded.height, bar.height, "status banner should grow the popup")
    }
}
