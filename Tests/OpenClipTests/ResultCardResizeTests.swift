import XCTest
import AppKit
import SwiftUI
import Core
@testable import OpenClip

/// The result card can be pulled larger or smaller by its right edge, bottom edge and corner grip,
/// its top-left corner staying put, and the size it settles on is the size the next card opens at.
@MainActor
final class ResultCardResizeTests: XCTestCase {

    private let ring = 2 * PopupMetrics.popupShadowInset
    private let cardMin = CGSize(width: PopupMetrics.aiCardMinWidth, height: PopupMetrics.aiCardMinHeight)
    /// A panel wrapping the default 320 × 280 card, placed high enough that growing downward
    /// stays clear of the dock on any screen.
    private let cardPanelFrame = NSRect(x: 100, y: 400, width: 320 + 2 * PopupMetrics.popupShadowInset,
                                        height: 280 + 2 * PopupMetrics.popupShadowInset)

    /// Stands in for the SwiftUI hosting view: reports whatever frame it was given as its fitting
    /// size, so the controller's fit-to-content pass on card entry leaves the test panel's frame
    /// alone (an empty content view would report zero and shrink the panel to the fallback size).
    private final class FixedFittingSizeView: NSView {
        override var fittingSize: NSSize { frame.size }
    }

    private func makeController(settings: MemorySettingsStore = MemorySettingsStore()) -> PopupWindowController {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(
            resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard),
            settingsStore: settings
        )
        let panel = PopupPanel()
        panel.contentView = FixedFittingSizeView(frame: NSRect(origin: .zero, size: cardPanelFrame.size))
        panel.setFrame(cardPanelFrame, display: false)
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

    private func showCard(_ controller: PopupWindowController) {
        controller.showResultCard(text: "Hey, how are you doing?", isError: false, title: "Proofread", session: controller.aiSessionID)
        XCTAssertEqual(controller.modeStore.mode, .content)
    }

    // MARK: - Geometry

    func testCornerDragFollowsTheCursorFromAFixedTopLeftCorner() throws {
        let controller = makeController()
        defer { controller.hide() }
        let panel = try XCTUnwrap(controller.panel)
        showCard(controller)
        XCTAssertNil(controller.modeStore.resultCardSize, "a never-resized card sizes itself from its content")

        controller.handleResize(.bottomRight, phase: .began, mouseLocation: CGPoint(x: 450, y: 410))
        controller.handleResize(.bottomRight, phase: .changed, mouseLocation: CGPoint(x: 490, y: 380))
        let size = try XCTUnwrap(controller.modeStore.resultCardSize)
        XCTAssertEqual(size.width, 320 + 40, accuracy: 0.5)
        XCTAssertEqual(size.height, 280 + 30, accuracy: 0.5, "dragging the bottom edge down (screen y decreasing) grows the card")
        XCTAssertEqual(panel.frame.minX, cardPanelFrame.minX, accuracy: 0.5, "the left edge never moves")
        XCTAssertEqual(panel.frame.maxY, cardPanelFrame.maxY, accuracy: 0.5, "the top edge never moves")
        XCTAssertEqual(panel.frame.width, size.width + ring, accuracy: 0.5)
        XCTAssertEqual(panel.frame.height, size.height + ring, accuracy: 0.5)

        controller.handleResize(.bottomRight, phase: .changed, mouseLocation: CGPoint(x: 510, y: 380))
        XCTAssertEqual(controller.modeStore.resultCardSize?.width ?? 0, 320 + 60, accuracy: 0.5,
                       "sizes must stay absolute, not accumulate per update")

        controller.handleResize(.bottomRight, phase: .ended, mouseLocation: CGPoint(x: 510, y: 380))
        XCTAssertFalse(panel.isUserDragging)
        // A stale anchor must not resize the card after the drag ended.
        controller.handleResize(.bottomRight, phase: .changed, mouseLocation: CGPoint(x: 900, y: 100))
        XCTAssertEqual(controller.modeStore.resultCardSize?.width ?? 0, 320 + 60, accuracy: 0.5)
    }

    func testEdgeHandlesResizeOnlyTheirOwnDimension() throws {
        let controller = makeController()
        defer { controller.hide() }
        showCard(controller)

        controller.handleResize(.right, phase: .began, mouseLocation: CGPoint(x: 450, y: 500))
        controller.handleResize(.right, phase: .changed, mouseLocation: CGPoint(x: 500, y: 450))
        var size = try XCTUnwrap(controller.modeStore.resultCardSize)
        XCTAssertEqual(size.width, 370, accuracy: 0.5)
        XCTAssertEqual(size.height, 280, accuracy: 0.5, "the right edge never changes the height")
        controller.handleResize(.right, phase: .ended, mouseLocation: CGPoint(x: 500, y: 450))

        controller.handleResize(.bottom, phase: .began, mouseLocation: CGPoint(x: 300, y: 410))
        controller.handleResize(.bottom, phase: .changed, mouseLocation: CGPoint(x: 350, y: 390))
        size = try XCTUnwrap(controller.modeStore.resultCardSize)
        XCTAssertEqual(size.width, 370, accuracy: 0.5, "the bottom edge never changes the width")
        XCTAssertEqual(size.height, 300, accuracy: 0.5, "a second resize starts from the first one's result")
        controller.handleResize(.bottom, phase: .ended, mouseLocation: CGPoint(x: 350, y: 390))
    }

    func testResizeNeverShrinksBelowTheMinimumCard() throws {
        let controller = makeController()
        defer { controller.hide() }
        let panel = try XCTUnwrap(controller.panel)
        showCard(controller)

        controller.handleResize(.bottomRight, phase: .began, mouseLocation: CGPoint(x: 450, y: 410))
        controller.handleResize(.bottomRight, phase: .changed, mouseLocation: CGPoint(x: 50, y: 900))
        let size = try XCTUnwrap(controller.modeStore.resultCardSize)
        XCTAssertEqual(size.width, PopupMetrics.aiCardMinWidth, accuracy: 0.5)
        XCTAssertEqual(size.height, PopupMetrics.aiCardMinHeight, accuracy: 0.5)
        XCTAssertEqual(panel.frame.maxY, cardPanelFrame.maxY, accuracy: 0.5, "shrinking keeps the top edge too")
        controller.handleResize(.bottomRight, phase: .ended, mouseLocation: CGPoint(x: 50, y: 900))
    }

    func testResizeIsIgnoredOutsideContentMode() {
        let controller = makeController()
        defer { controller.hide() }
        controller.handleResize(.bottomRight, phase: .began, mouseLocation: CGPoint(x: 450, y: 410))
        controller.handleResize(.bottomRight, phase: .changed, mouseLocation: CGPoint(x: 490, y: 380))
        XCTAssertNil(controller.modeStore.resultCardSize, "the bar has no card to resize")
    }

    // MARK: - Pure geometry

    func testProposedSizeUsesAbsoluteCursorTravel() {
        let anchor = CGSize(width: 320, height: 280)
        let from = CGPoint(x: 500, y: 500)
        let corner = PopupResizeGeometry.size(from: anchor, edge: .bottomRight, anchorMouse: from, mouse: CGPoint(x: 530, y: 480))
        XCTAssertEqual(corner, CGSize(width: 350, height: 300))
        let right = PopupResizeGeometry.size(from: anchor, edge: .right, anchorMouse: from, mouse: CGPoint(x: 530, y: 480))
        XCTAssertEqual(right, CGSize(width: 350, height: 280))
        let bottom = PopupResizeGeometry.size(from: anchor, edge: .bottom, anchorMouse: from, mouse: CGPoint(x: 530, y: 480))
        XCTAssertEqual(bottom, CGSize(width: 320, height: 300))
    }

    /// Growing from a fixed top-left corner, the panel (card + shadow ring) must stay inside the
    /// screen by the popup padding; the card minimum wins when even that does not fit.
    func testClampKeepsThePanelInsideTheScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let clamped = PopupResizeGeometry.clamp(CGSize(width: 2000, height: 2000), minSize: cardMin,
                                                panelTopLeft: CGPoint(x: 1000, y: 500), screenBounds: screen)
        XCTAssertEqual(clamped.width, 1440 - PopupMetrics.popupPadding - 1000 - ring, accuracy: 0.5)
        XCTAssertEqual(clamped.height, 500 - PopupMetrics.popupPadding - ring, accuracy: 0.5)

        let cornered = PopupResizeGeometry.clamp(CGSize(width: 2000, height: 2000), minSize: cardMin,
                                                 panelTopLeft: CGPoint(x: 1430, y: 20), screenBounds: screen)
        XCTAssertEqual(cornered, CGSize(width: PopupMetrics.aiCardMinWidth, height: PopupMetrics.aiCardMinHeight))
    }

    func testARememberedSizeIsFittedToTheScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let fitted = PopupResizeGeometry.fit(CGSize(width: 5000, height: 5000), minSize: cardMin, in: screen)
        XCTAssertEqual(fitted.width, 1440 - 2 * PopupMetrics.popupPadding - ring, accuracy: 0.5)
        XCTAssertEqual(fitted.height, 900 - 2 * PopupMetrics.popupPadding - ring, accuracy: 0.5)
        XCTAssertEqual(PopupResizeGeometry.fit(CGSize(width: 10, height: 10), minSize: cardMin, in: screen),
                       CGSize(width: PopupMetrics.aiCardMinWidth, height: PopupMetrics.aiCardMinHeight))
        XCTAssertEqual(PopupResizeGeometry.fit(CGSize(width: 500, height: 400), minSize: cardMin, in: screen),
                       CGSize(width: 500, height: 400), "a size that fits is left alone")
    }

    // MARK: - Remembering the size

    func testResizeEndRemembersTheSize() throws {
        let settings = MemorySettingsStore()
        let controller = makeController(settings: settings)
        defer { controller.hide() }
        showCard(controller)

        controller.handleResize(.bottomRight, phase: .began, mouseLocation: CGPoint(x: 450, y: 410))
        controller.handleResize(.bottomRight, phase: .changed, mouseLocation: CGPoint(x: 490, y: 380))
        XCTAssertEqual(settings.get(SettingKey.resultCardWidth), 0, "nothing is written mid-drag")
        controller.handleResize(.bottomRight, phase: .ended, mouseLocation: CGPoint(x: 490, y: 380))
        XCTAssertEqual(settings.get(SettingKey.resultCardWidth), 360, accuracy: 0.5)
        XCTAssertEqual(settings.get(SettingKey.resultCardHeight), 310, accuracy: 0.5)
    }

    func testTheNextCardOpensAtTheRememberedSize() throws {
        let settings = MemorySettingsStore()
        settings.set(SettingKey.resultCardWidth, value: 500)
        settings.set(SettingKey.resultCardHeight, value: 400)
        let controller = makeController(settings: settings)
        defer { controller.hide() }
        showCard(controller)
        XCTAssertEqual(controller.modeStore.resultCardSize, CGSize(width: 500, height: 400))
        XCTAssertGreaterThan(try XCTUnwrap(controller.panel).heightCap, PopupMetrics.popupMaxHeight,
                             "the shared bar/palette height cap must not clip a tall card")
    }

    func testAnUnsetSizeLeavesTheCardContentDriven() {
        let controller = makeController()
        defer { controller.hide() }
        showCard(controller)
        XCTAssertNil(controller.modeStore.resultCardSize)
    }

    func testLeavingTheCardForgetsTheLiveSizeButKeepsThePreference() throws {
        let settings = MemorySettingsStore()
        let controller = makeController(settings: settings)
        defer { controller.hide() }
        let panel = try XCTUnwrap(controller.panel)
        showCard(controller)
        controller.handleResize(.bottomRight, phase: .began, mouseLocation: CGPoint(x: 450, y: 410))
        controller.handleResize(.bottomRight, phase: .changed, mouseLocation: CGPoint(x: 490, y: 380))
        controller.handleResize(.bottomRight, phase: .ended, mouseLocation: CGPoint(x: 490, y: 380))

        controller.exitContent()
        XCTAssertNil(controller.modeStore.resultCardSize)
        XCTAssertEqual(panel.heightCap, PopupMetrics.popupMaxHeight, "the bar gets its cap back")
        XCTAssertEqual(settings.get(SettingKey.resultCardWidth), 360, accuracy: 0.5)

        showCard(controller)
        XCTAssertEqual(controller.modeStore.resultCardSize, CGSize(width: 360, height: 310),
                       "the next card opens at the size the last one was left at")
    }

    func testResizingDoesNotPinTheCardLikeADragDoes() {
        let controller = makeController()
        defer { controller.hide() }
        showCard(controller)
        controller.handleResize(.bottomRight, phase: .began, mouseLocation: CGPoint(x: 450, y: 410))
        controller.handleResize(.bottomRight, phase: .changed, mouseLocation: CGPoint(x: 490, y: 380))
        controller.handleResize(.bottomRight, phase: .ended, mouseLocation: CGPoint(x: 490, y: 380))
        XCTAssertFalse(controller.cardIsModal, "only moving the card aside pins it against outside clicks")
    }

    // MARK: - Panel

    func testPanelHeightCapCanBeLiftedForTheCard() {
        let panel = PopupPanel()
        panel.setFrame(NSRect(x: 100, y: 100, width: 300, height: 500), display: false)
        XCTAssertEqual(panel.frame.height, PopupMetrics.popupMaxHeight, "the bar/palette cap applies by default")

        panel.heightCap = 900
        panel.setFrame(NSRect(x: 100, y: 100, width: 300, height: 500), display: false)
        XCTAssertEqual(panel.frame.height, 500, accuracy: 0.5)
    }

    // MARK: - View

    /// A remembered size wins over the content-driven measurement in both dimensions.
    func testPreferredSizeOverridesTheContentDrivenSize() {
        let card = ResultCardView(
            payload: ResultCardPayload(text: "Hi.", isError: false, title: "Proofread"),
            canPaste: true,
            preferredSize: CGSize(width: 500, height: 420),
            onExit: {}, onPaste: {}, onCopy: {}
        ).environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: AnyView(card))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.width, 500, accuracy: 1.0)
        XCTAssertEqual(host.fittingSize.height, 420, accuracy: 1.0)
    }

    /// The corner grip must actually receive the drag through SwiftUI's gesture system (the same
    /// hit-testing pitfall as the header drag: an AppKit handle would never see the mouseDown).
    func testCornerGripGestureReachesTheCard() throws {
        final class Recorder { var events: [(PopupResizeEdge, ResultCardDragPhase)] = [] }
        let recorder = Recorder()
        let card = ResultCardView(
            payload: ResultCardPayload(text: "Hey, how are you doing?", isError: false, title: "Proofread", original: "hey how are you doing"),
            canPaste: true,
            onExit: {}, onPaste: {}, onCopy: {},
            onResize: { recorder.events.append(($0, $1)) }
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

        // Window coordinates are bottom-left origin: the grip sits in the bottom-right corner.
        let start = NSPoint(x: panel.frame.width - 6, y: 6)
        try send(.leftMouseDown, start)
        for step in 1...5 {
            try send(.leftMouseDragged, NSPoint(x: start.x + CGFloat(step) * 8, y: start.y - CGFloat(step) * 4))
        }
        try send(.leftMouseUp, NSPoint(x: start.x + 40, y: start.y - 20))

        let phases = recorder.events.map(\.1)
        XCTAssertTrue(phases.contains(.began), "corner drag never reached the card: \(phases)")
        XCTAssertTrue(phases.contains(.changed), "resize updates never reached the card: \(phases)")
        XCTAssertTrue(phases.contains(.ended), "resize end never reported: \(phases)")
        XCTAssertTrue(recorder.events.allSatisfy { $0.0 == .bottomRight }, "the grip reports the corner handle")
    }
}
