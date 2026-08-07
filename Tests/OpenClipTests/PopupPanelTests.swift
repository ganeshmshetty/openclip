import XCTest
import AppKit
import Core
@testable import OpenClip

@MainActor
final class PopupPanelTests: XCTestCase {
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
        let controller = PopupWindowController()
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
    /// pin immediately: the hover preview strip renders above the bar, so its growth has to push up,
    /// not shove the bar down off the cursor. Previously only enterSearch() armed the pin, so the
    /// first hover preview after opening the popup was mis-anchored.
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
}
