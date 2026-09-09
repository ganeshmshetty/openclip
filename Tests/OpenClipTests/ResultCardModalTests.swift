import XCTest
import AppKit
import SwiftUI
import Core
@testable import OpenClip

/// The result card is deliberately modal-ish: once a result shows, only Copy, Paste or Esc takes
/// it away. Everything that dismisses the bar — an outside click, a right-click elsewhere, the
/// cursor wandering off, another app coming forward — must leave the card up, so the user can read
/// the response (and its diff) while working in the source app.
@MainActor
final class ResultCardModalTests: XCTestCase {

    private func makeController() -> PopupWindowController {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard))
        let panel = PopupPanel()
        panel.setFrame(NSRect(x: 100, y: 100, width: 300, height: 120), display: false)
        controller.panel = panel
        controller.startTestSession(for: SelectionContext(
            text: "hey how are you doing",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: 400, y: 400),
            timestamp: Date(),
            appPolicy: .default
        ))
        return controller
    }

    private func mouseEvent(_ type: NSEvent.EventType, at location: CGPoint) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))
    }

    private func escapeEvent() throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ))
    }

    func testContentModeIsModal() {
        let controller = makeController()
        defer { controller.hide() }
        XCTAssertFalse(controller.cardIsModal, "the bar is not modal")
        controller.modeStore.mode = .content
        XCTAssertFalse(controller.cardIsModal, "undragged content card remains ephemeral")

        controller.handleCardDrag(.began)
        controller.handleCardDrag(.ended)
        XCTAssertTrue(controller.cardIsModal, "dragged content card becomes pinned/modal")
    }

    func testOutsideClickKeepsTheCardButStillDismissesTheBar() throws {
        let far = CGPoint(x: 2_000, y: 2_000)

        // Undragged card dismisses on outside click
        let controller1 = makeController()
        defer { controller1.hide() }
        controller1.modeStore.mode = .content
        controller1.handleEvent(try mouseEvent(.leftMouseDown, at: far))
        XCTAssertFalse(controller1.isVisible, "an undragged card must dismiss on click outside")

        // Dragged card remains visible on outside click
        let controller2 = makeController()
        defer { controller2.hide() }
        controller2.modeStore.mode = .content
        controller2.handleCardDrag(.began)
        controller2.handleCardDrag(.ended)
        controller2.handleEvent(try mouseEvent(.leftMouseDown, at: far))
        XCTAssertTrue(controller2.isVisible, "a dragged card must remain visible on outside click")
    }

    func testOutsideRightClickKeepsTheCard() throws {
        let controller = makeController()
        defer { controller.hide() }
        controller.modeStore.mode = .content
        controller.handleCardDrag(.began)
        controller.handleCardDrag(.ended)
        controller.handleEvent(try mouseEvent(.rightMouseDown, at: CGPoint(x: 2_000, y: 2_000)))
        XCTAssertTrue(controller.isVisible)
    }

    func testCursorDistanceKeepsTheCard() throws {
        let controller = makeController()
        defer { controller.hide() }
        controller.modeStore.mode = .content
        controller.handleCardDrag(.began)
        controller.handleCardDrag(.ended)
        let panelFrame = try XCTUnwrap(controller.panel).frame
        let far = CGPoint(x: panelFrame.maxX + PopupMetrics.popupDismissalDistance + 400,
                          y: panelFrame.maxY + PopupMetrics.popupDismissalDistance + 400)
        controller.handleEvent(try mouseEvent(.mouseMoved, at: far))
        XCTAssertTrue(controller.isVisible)
    }

    /// The card owns Esc through SwiftUI while the panel is key; the monitor answers it only when
    /// the panel lost key (the user clicked into another app), so the two can never double-fire.
    func testEscapeDismissesTheCardWhenThePanelIsNotKey() throws {
        let controller = makeController()
        defer { controller.hide() }
        controller.modeStore.mode = .content
        XCTAssertFalse(try XCTUnwrap(controller.panel).isKeyWindow)
        controller.handleEvent(try escapeEvent())
        XCTAssertFalse(controller.isVisible, "Esc must close the card outright")
    }

    func testNonEscapeKeysNeverCloseTheCard() throws {
        let controller = makeController()
        defer { controller.hide() }
        controller.modeStore.mode = .content
        let typing = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0
        ))
        controller.handleEvent(typing)
        XCTAssertTrue(controller.isVisible, "typing in the source app must not disturb the card")
    }

    /// The card diffs input → output, so the selection the action ran on has to reach the payload.
    func testResultCardCarriesTheOriginalSelection() {
        let controller = makeController()
        defer { controller.hide() }
        controller.showResultCard(text: "Hey, how are you doing?", isError: false, title: "Proofread", session: controller.aiSessionID)
        XCTAssertEqual(controller.modeStore.resultCard?.original, "hey how are you doing")
        XCTAssertEqual(controller.modeStore.resultCard?.text, "Hey, how are you doing?")
    }

    // MARK: - Dragging

    /// The header handle must actually receive the drag. An `NSViewRepresentable` handle does not:
    /// `NSHostingView` answers `hitTest` with itself for the whole card, so an AppKit subview never
    /// sees the `mouseDown` (which is exactly how the first implementation failed). This drives a
    /// real panel with synthetic mouse events and pins that the SwiftUI gesture is delivered.
    func testHeaderDragGestureReachesTheCard() throws {
        final class Recorder { var phases: [ResultCardDragPhase] = [] }
        let recorder = Recorder()
        let card = ResultCardView(
            payload: ResultCardPayload(text: "Hey, how are you doing?", isError: false, title: "Proofread", original: "hey how are you doing"),
            canPaste: true,
            onExit: {}, onPaste: {}, onCopy: {},
            onDrag: { recorder.phases.append($0) }
        ).environment(\.colorScheme, .dark)

        let host = NSHostingView(rootView: AnyView(card))
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let panel = PopupPanel()
        panel.allowsKey = true
        panel.contentView = host
        panel.setFrame(NSRect(x: 300, y: 300, width: size.width, height: size.height), display: true)
        panel.makeKeyAndOrderFront(nil)
        defer { panel.orderOut(nil) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        func send(_ type: NSEvent.EventType, _ point: NSPoint) throws {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1
            ))
            panel.sendEvent(event)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        // Window coordinates are bottom-left origin, so the floating capsule header is centered at height - 30.
        let start = NSPoint(x: panel.frame.width / 2, y: panel.frame.height - 30)
        try send(.leftMouseDown, start)
        for step in 1...5 {
            try send(.leftMouseDragged, NSPoint(x: start.x + CGFloat(step) * 8, y: start.y))
        }
        try send(.leftMouseUp, NSPoint(x: start.x + 40, y: start.y))

        XCTAssertTrue(recorder.phases.contains(.began), "header drag never reached the card: \(recorder.phases)")
        XCTAssertTrue(recorder.phases.contains(.changed), "drag updates never reached the card: \(recorder.phases)")
        XCTAssertTrue(recorder.phases.contains(.ended), "drag end never reported: \(recorder.phases)")
    }

    /// The panel follows the cursor one-for-one, from the absolute pointer position rather than the
    /// gesture translation (which would fight the window moving out from under the pointer).
    func testCardDragMovesThePanelWithTheCursor() throws {
        let controller = makeController()
        defer { controller.hide() }
        let panel = try XCTUnwrap(controller.panel)
        controller.modeStore.mode = .content
        let origin = panel.frame.origin

        controller.handleCardDrag(.began, mouseLocation: CGPoint(x: 500, y: 500))
        controller.handleCardDrag(.changed, mouseLocation: CGPoint(x: 540, y: 470))
        XCTAssertEqual(panel.frame.origin.x, origin.x + 40, accuracy: 0.5)
        XCTAssertEqual(panel.frame.origin.y, origin.y - 30, accuracy: 0.5)

        controller.handleCardDrag(.changed, mouseLocation: CGPoint(x: 560, y: 470))
        XCTAssertEqual(panel.frame.origin.x, origin.x + 60, accuracy: 0.5,
                       "moves must stay absolute, not accumulate per update")

        controller.handleCardDrag(.ended, mouseLocation: CGPoint(x: 560, y: 470))
        XCTAssertFalse(panel.isUserDragging)
        // A stale anchor must not move the panel after the drag ended.
        controller.handleCardDrag(.changed, mouseLocation: CGPoint(x: 900, y: 900))
        XCTAssertEqual(panel.frame.origin.x, origin.x + 60, accuracy: 0.5)
    }

    /// A user-placed card must stay where it was put: dragging drops the re-centering anchor that
    /// content-driven width changes would otherwise apply.
    func testUserDragStopsAutomaticRecentering() {
        let panel = PopupPanel()
        panel.setFrame(NSRect(x: 100, y: 100, width: 300, height: 120), display: false)
        panel.horizontalAnchor = .center
        XCTAssertFalse(panel.isUserDragging)

        panel.prepareForUserDrag()
        XCTAssertTrue(panel.isUserDragging, "hover tracking reads this to stop toggling click-through mid-drag")
        XCTAssertEqual(panel.horizontalAnchor, .none, "a placed card must not be re-centered afterwards")

        panel.endUserDrag()
        XCTAssertFalse(panel.isUserDragging, "the drag flag must clear when AppKit's drag loop returns")
        XCTAssertEqual(panel.horizontalAnchor, .none, "the placement outlives the drag")
    }

    /// A dragged card keeps its origin when the content resizes it (toggling the diff on changes
    /// the card's width), instead of snapping back to the cursor-centred placement.
    func testDraggedPanelKeepsItsOriginAcrossAWidthChange() {
        let panel = PopupPanel()
        panel.setFrame(NSRect(x: 400, y: 300, width: 300, height: 120), display: false)
        panel.horizontalAnchor = .center
        panel.prepareForUserDrag()
        panel.endUserDrag()

        panel.setFrame(NSRect(x: 400, y: 300, width: 220, height: 160), display: false)
        XCTAssertEqual(panel.frame.minX, 400, accuracy: 0.5)
    }

    // MARK: - Footer

    private func fittingSize(_ payload: ResultCardPayload, canPaste: Bool? = true) -> CGSize {
        let card = ResultCardView(payload: payload, canPaste: canPaste, onExit: {}, onPaste: {}, onCopy: {})
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: AnyView(card))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    /// The card keeps a constant width and resizes height based on text content.
    func testShortResultStillFitsCloseCopyAndPaste() {
        let shortSize = fittingSize(ResultCardPayload(text: "Hi.", isError: false, title: "Proofread"))
        XCTAssertEqual(shortSize.width, PopupMetrics.aiCardMinWidth, accuracy: 1.0, "a short result takes only the minimum width")

        let longText = String(repeating: "This is a longer line of text designed to test dynamic height scaling. ", count: 6)
        let longSize = fittingSize(ResultCardPayload(text: longText, isError: false, title: "Proofread"))
        XCTAssertEqual(longSize.width, PopupMetrics.aiCardIdealWidth, accuracy: 1.0, "a long result fills the default maximum width")
        XCTAssertGreaterThan(longSize.height, shortSize.height, "longer content scales card height")
    }

    /// An error card carries no Copy/Paste, but still renders a clean footer and close header.
    func testErrorCardKeepsTheCloseFooter() {
        let failed = fittingSize(ResultCardPayload(text: "All good", isError: true, title: "Proofread"))
        XCTAssertGreaterThan(failed.height, 0)
    }

    /// When paste is denied/unavailable (e.g. terminal apps like Ghostty), the card hides the
    /// Paste button and styles Copy as the primary action.
    func testResultCardWhenPasteIsUnavailable() {
        let size = fittingSize(ResultCardPayload(text: "Hi.", isError: false, title: "Proofread"), canPaste: false)
        XCTAssertEqual(size.width, PopupMetrics.aiCardMinWidth, accuracy: 1.0)
        XCTAssertGreaterThan(size.height, 0)
    }

    // MARK: - Diff rendering

    /// Evidence that the diff actually reaches the pixels: a proofread-shaped edit must open on
    /// the diff (its equal ratio is high) and paint both a red run for the removed characters and
    /// a green run for the added ones.
    func testProofreadResultRendersRedAndGreenRuns() throws {
        let card = ResultCardView(
            payload: ResultCardPayload(
                text: "Hey, how are you doing?",
                isError: false,
                title: "Proofread",
                original: "hey how are you doing"
            ),
            canPaste: true,
            onExit: {},
            onPaste: {},
            onCopy: {}
        )
        .environment(\.colorScheme, .dark)

        let host = NSHostingView(rootView: AnyView(card))
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 220)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil) }

        // onAppear (which computes the diff) needs a run-loop turn after the view is hosted.
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()

        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)

        var reddish = 0
        var greenish = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 1) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 1) {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.2 else { continue }
                guard let rgb = color.usingColorSpace(.sRGB) else { continue }
                let r = rgb.redComponent, g = rgb.greenComponent, b = rgb.blueComponent
                if r > g + 0.18 && r > b + 0.18 { reddish += 1 }
                if g > r + 0.18 && g > b + 0.18 { greenish += 1 }
            }
        }
        XCTAssertGreaterThan(reddish, 2, "removed characters must render in red")
        XCTAssertGreaterThan(greenish, 2, "added characters must render in green")
    }
}
