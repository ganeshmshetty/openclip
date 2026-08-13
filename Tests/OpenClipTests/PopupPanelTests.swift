import XCTest
import AppKit
import SwiftUI
import Core
@testable import OpenClip

@MainActor
final class PopupPanelTests: XCTestCase {
    func testPopupMetricsConstants() {
        // Sentinel: the shared height cap stays 240. Lives here (app target) because popup sizing
        // constants are UI concerns — see PopupMetrics.
        XCTAssertEqual(PopupMetrics.popupMaxHeight, 240)
    }

    func testToastDurationConstant() {
        XCTAssertEqual(PopupMetrics.toastDurationNanoseconds, 500_000_000)
    }

    func testToastFittingSizeIsOneLine() throws {
        let toast = ToastView(feedback: StatusFeedback(message: "Copied to clipboard", style: .success, symbolName: "checkmark"))
        let host = NSHostingView(rootView: toast)
        host.layoutSubtreeIfNeeded()
        let fit = host.fittingSize
        XCTAssertGreaterThan(fit.width, 80, "toast collapsed to zero width")
        XCTAssertLessThan(fit.height, 60, "toast should be a single compact line")
    }

    /// Evidence check: the AI result card's preferred (fitting) size must include the response
    /// body region, not just header + footer. The panel auto-resizes to the hosting view's fitting
    /// size on mode change; if the ScrollView body collapses to zero at fit-time the window stays
    /// ~bar-height and the response never renders.
    func testAICardFittingSizeIncludesResponseBody() throws {
        let card = AIResultCardView(
            payload: AIResultPayload(
                text: (1...20).map { "line \($0) of a long response body" }.joined(separator: "\n"),
                isError: false,
                title: "Summarize"
            ),
            onExit: {},
            onPaste: {},
            onCopy: {}
        )
        let host = NSHostingView(rootView: card)
        host.layoutSubtreeIfNeeded()
        let fit = host.fittingSize
        XCTAssertGreaterThan(fit.height, 130,
                             "card fitting height collapsed to \(fit.height) — response body contributes no height")
    }

    /// The panel must actually GROW to fit the card when the AI result is shown (content mode),
    /// not stay at bar height. If the resize path starves the ScrollView body, the user sees only
    /// the header (title + back) and footer (Copy/Paste) with no response text.
    func testAICardResizesPanelToIncludeBody() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownPanel(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 150))
        defer { controller.hide() }
        let panel = try visiblePanel()

        pump(0.3)
        let barFrame = panel.frame
        XCTAssertGreaterThan(barFrame.height, 0)

        controller.modeStore.aiResult = AIResultPayload(
            text: (1...20).map { "line \($0) of a long response body" }.joined(separator: "\n"),
            isError: false,
            title: "Summarize"
        )
        controller.modeStore.mode = .content

        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline {
            if panel.frame.height > barFrame.height + 100 { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
        XCTAssertGreaterThan(panel.frame.height, barFrame.height + 100,
                             "panel stayed at bar height \(barFrame.height); card body starved, final \(panel.frame.height)")
    }

    /// Paste availability is probed by the trigger site before selection retrieval and handed to
    /// show(for:pasteAvailable:) — a confirmed cannot-paste must land on `modeStore.canPaste ==
    /// false` synchronously so the card hides its Paste button and the bar/search hide Paste + Cut
    /// on the first frame (no async flash).
    func testPasteAvailabilityGatesBarAndCardSynchronously() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(
            resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard),
            pasteProbe: AICardFixedProbe(result: false)
        )
        let context = SelectionContext(
            text: "hello",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 150),
            timestamp: Date(),
            appPolicy: .default
        )
        controller.show(for: context, pasteAvailable: false)
        defer { controller.hide() }

        XCTAssertEqual(controller.modeStore.canPaste, false,
                       "confirmed cannot-paste must gate Paste/Cut from the first frame")
    }

    /// Paste and Cut require a paste-capable target; Copy does not. The bar/search hide exactly the
    /// `PasteRequiringAction` set when the probe reports cannot-paste.
    func testPasteAndCutArePasteRequiringActions() {
        XCTAssertTrue(PasteAction() is any PasteRequiringAction)
        XCTAssertTrue(CutAction() is any PasteRequiringAction)
        XCTAssertFalse(CopyAction() is any PasteRequiringAction)
    }

    /// Paste availability tracks the target app's focus context, so it must never be cached per
    /// app: a re-show in the same app applies the freshly-probed value each time.
    func testPasteAvailabilityIsNotCachedAcrossShows() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(
            resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard),
            pasteProbe: AICardFixedProbe(result: false)
        )
        let context = SelectionContext(
            text: "hello",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 150),
            timestamp: Date(),
            appPolicy: .default
        )

        controller.show(for: context, pasteAvailable: false)
        XCTAssertEqual(controller.modeStore.canPaste, false)
        controller.hide()

        controller.show(for: context, pasteAvailable: true)
        XCTAssertEqual(controller.modeStore.canPaste, true,
                       "a focus-context change in the same app must apply the fresh probe result")
        controller.hide()
    }

    /// preparePasteProbe runs the injected probe and resolves to its result, so the trigger sites
    /// can await it after selection retrieval and hand it to show without blocking the bar.
    func testPreparePasteProbeResolvesToProbeResult() async {
        let controller = PopupWindowController(pasteProbe: AICardFixedProbe(result: true))
        let probe = controller.preparePasteProbe(for: nil, policy: .default)
        let value = await probe.value
        XCTAssertEqual(value, true)
    }

    func testCanBecomeKeyFollowsAllowsKey() {
        let panel = PopupPanel()
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        panel.allowsKey = true
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.canBecomeMain)
        panel.allowsKey = false
        XCTAssertFalse(panel.canBecomeKey)
    }

    /// Returns the popup panel after show(for:) has mounted it.
    private func shownPanel(for cursor: CGPoint) throws -> PopupWindowController {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard))
        let context = SelectionContext(
            text: "hello world",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: cursor,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.show(for: context)
        return controller
    }

    /// The visible popup panel for the most recent show; filters out hidden panels left by earlier
    /// tests in the same process (NSApp.windows includes hidden windows).
    private func visiblePanel() throws -> PopupPanel {
        guard let panel = NSApp.windows.first(where: { $0 is PopupPanel && $0.isVisible }) as? PopupPanel else {
            throw XCTSkip("popup panel did not appear")
        }
        return panel
    }

    private func pump(_ duration: TimeInterval = 2.0) {
        RunLoop.current.run(until: Date().addingTimeInterval(duration))
    }

    /// Deterministic paste-availability fake (never blocks, ignores the app argument).
    private struct AICardFixedProbe: PasteAvailabilityProbing {
        let result: Bool?

        func canPaste(in app: NSRunningApplication?, policy: AppPolicyContext) async -> Bool? {
            result
        }
    }

    /// Polls until the panel height settles at a value strictly greater than the bar height (i.e.
    /// the search palette has rendered and resized the panel), or the timeout elapses.
    private func waitForSearchResize(_ panel: PopupPanel, barHeight: CGFloat, timeout: TimeInterval = 3.0) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if panel.frame.height > barHeight + 1 { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
    }

    /// Polls until the panel shrinks back to the bar height (search palette collapsed), or the
    /// timeout elapses.
    private func waitForSearchCollapse(_ panel: PopupPanel, barHeight: CGFloat, timeout: TimeInterval = 3.0) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if panel.frame.height <= barHeight + 1 { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
    }

    /// Results below the field (popup near top of screen): entering search mode must keep the
    /// panel's TOP edge fixed and grow downward so the field doesn't jump.
    func testSearchModeKeepsTopEdgeFixedForResultsBelow() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownPanel(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }
        let panel = try visiblePanel()

        pump(0.3)
        let barFrame = panel.frame
        XCTAssertGreaterThan(barFrame.height, 0)

        controller.enterSearch()
        waitForSearchResize(panel, barHeight: barFrame.height)
        let searchFrame = panel.frame

        XCTAssertGreaterThan(searchFrame.height, barFrame.height)
        XCTAssertEqual(searchFrame.maxY, barFrame.maxY, accuracy: 1.0,
                       "popup top edge moved by \(searchFrame.maxY - barFrame.maxY)pt entering search mode")
    }

    /// Results ABOVE the field (popup near screen bottom): palette is [results, field], so the field
    /// sits at the palette bottom. The panel must anchor its BOTTOM edge and grow upward, keeping the
    /// field where the bar was.
    func testSearchModeKeepsBottomEdgeFixedForResultsAbove() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownPanel(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 150))
        defer { controller.hide() }
        let panel = try visiblePanel()

        pump(0.3)
        let barFrame = panel.frame
        XCTAssertGreaterThan(barFrame.height, 0)

        controller.enterSearch()
        waitForSearchResize(panel, barHeight: barFrame.height)
        let searchFrame = panel.frame

        XCTAssertGreaterThan(searchFrame.height, barFrame.height)
        XCTAssertEqual(searchFrame.minY, barFrame.minY, accuracy: 1.0,
                       "popup bottom edge moved by \(searchFrame.minY - barFrame.minY)pt entering search mode")
    }

    /// A fresh show near the bottom of the screen (card above the cursor) must arm the bottom-edge
    /// pin immediately: a card-above popup renders its content above the bar, so content-driven
    /// growth has to push up, not shove the bar down off the cursor. Previously only enterSearch()
    /// armed the pin, so the first above-bar render after opening the popup was mis-anchored.
    func testShowArmsBottomEdgePinForResultsAbove() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownPanel(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 150))
        defer { controller.hide() }
        let panel = try visiblePanel()

        XCTAssertTrue(panel.pinBottomEdgeOnResize,
                      "bottom-edge pin should be armed for a card-above popup")
    }

    /// Entering search swaps the (variable-width) actions bar for the fixed 280pt palette. The
    /// hosting view auto-resizes the panel top-anchored, preserving origin.x, so without horizontal
    /// re-anchoring the popup's center would drift off the cursor. The bar's center must stay fixed.
    func testSearchModeKeepsHorizontalCenterFixed() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let cursor = CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200)
        let controller = try shownPanel(for: cursor)
        defer { controller.hide() }
        let panel = try visiblePanel()

        pump(0.3)
        let barCenter = panel.frame.midX
        XCTAssertGreaterThan(barCenter, 0)

        controller.enterSearch()
        waitForSearchResize(panel, barHeight: panel.frame.height)
        let searchCenter = panel.frame.midX

        XCTAssertEqual(searchCenter, barCenter, accuracy: 1.0,
                       "popup center moved \(searchCenter - barCenter)pt entering search mode")
    }

    /// Exiting search (Escape) must return the bar to the field's spot, not jump it to the palette
    /// top. Results-above case: the field sat at the palette bottom, so the bar's bottom edge must
    /// equal the original bar's bottom edge.
    func testExitingSearchReturnsBarToOriginalPositionForResultsAbove() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownPanel(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.minY + 150))
        defer { controller.hide() }
        let panel = try visiblePanel()

        pump(0.3)
        let barFrame = panel.frame

        controller.enterSearch()
        waitForSearchResize(panel, barHeight: barFrame.height)
        controller.exitSearch()
        waitForSearchCollapse(panel, barHeight: barFrame.height)

        XCTAssertEqual(panel.frame.minY, barFrame.minY, accuracy: 1.0,
                       "bar bottom edge moved by \(panel.frame.minY - barFrame.minY)pt exiting search mode")
    }

    /// The search field must become the first responder once the panel is key, so typing lands in
    /// the field (not the panel). Exercises both the direct (hotkey-equivalent) entry and a second
    /// entry after exit to catch re-entry timing.
    func testSearchModeMakesPanelKeyAndFieldFirstResponder() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let controller = try shownPanel(for: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200))
        defer { controller.hide() }
        let panel = try visiblePanel()

        pump(0.3)
        controller.enterSearch()
        pump(0.5)

        XCTAssertTrue(panel.isKeyWindow, "panel should be key in search mode")
        let isTextInput = (panel.firstResponder is NSTextView) || (panel.firstResponder is NSTextField)
        XCTAssertTrue(isTextInput,
                      "search field should be first responder, got \(String(describing: panel.firstResponder))")

        // Exit and re-enter search: focus must be re-acquired.
        controller.exitSearch()
        pump(0.2)
        XCTAssertFalse(panel.canBecomeKey, "exit must restore the never-key invariant")

        controller.enterSearch()
        pump(0.5)
        let isTextInputAgain = (panel.firstResponder is NSTextView) || (panel.firstResponder is NSTextField)
        XCTAssertTrue(isTextInputAgain,
                      "search field should be first responder after re-entry, got \(String(describing: panel.firstResponder))")
    }

    func testSetFramePreservesTopEdgeWhenPinBottomEdgeOnResizeIsFalse() {
        let panel = PopupPanel()
        panel.pinBottomEdgeOnResize = false

        // Initial frame setup
        let initialFrame = NSRect(x: 100, y: 500, width: 200, height: 100)
        panel.setFrame(initialFrame, display: false)
        XCTAssertEqual(panel.frame.maxY, 600)

        // Path 1: Top-anchored height change (height 250 is clamped to PopupMetrics.popupMaxHeight = 240, requested maxY is 600)
        let heightOnlyChange = NSRect(x: 100, y: 350, width: 200, height: 250)
        panel.setFrame(heightOnlyChange, display: false)
        XCTAssertEqual(panel.frame.maxY, 600, "Height-only change must preserve requested top edge (maxY)")
        XCTAssertEqual(panel.frame.height, PopupMetrics.popupMaxHeight)
        XCTAssertEqual(panel.frame.origin.y, 600 - PopupMetrics.popupMaxHeight)

        // Path 2: Repositioning to a new cursor location must respect the new requested origin.y
        let repositionFrame = NSRect(x: 80, y: 100, width: 200, height: 100)
        panel.setFrame(repositionFrame, display: false)
        XCTAssertEqual(panel.frame.origin.y, 100, "Repositioning must place the panel at the requested origin.y")
    }
}
