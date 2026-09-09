import XCTest
import AppKit
import SwiftUI
import Core
@testable import OpenClip

/// The action-search palette resizes exactly like the result card — right edge, bottom edge and
/// corner grip, top-left corner fixed — under its own floor and its own remembered size, on both
/// entry paths (from the bar and directly by the hotkey).
@MainActor
final class SearchPaletteResizeTests: XCTestCase {

    private let ring = 2 * PopupMetrics.popupShadowInset
    private let paletteMin = CGSize(width: PopupMetrics.searchPaletteMinWidth, height: PopupMetrics.searchPaletteMinHeight)
    private let defaultWidth = PopupMetrics.searchPanelContentWidth
    private let defaultHeight = PopupSearchView.defaultHeight
    /// A panel wrapping the default palette, placed high enough that growing downward stays
    /// clear of the dock on any screen.
    private var palettePanelFrame: NSRect {
        NSRect(x: 100, y: 400, width: defaultWidth + ring, height: defaultHeight + ring)
    }

    /// Stands in for the SwiftUI hosting view: reports whatever frame it was given as its fitting
    /// size, so content-driven fits leave the test panel's frame alone.
    private final class FixedFittingSizeView: NSView {
        override var fittingSize: NSSize { frame.size }
    }

    private func makeContext(cursor: CGPoint = CGPoint(x: 400, y: 400)) -> SelectionContext {
        SelectionContext(
            text: "hey how are you doing",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: cursor,
            timestamp: Date(),
            appPolicy: .default
        )
    }

    /// A controller with a visible test panel (`enterSearch` requires one) that is already in a
    /// session, but without the full `show(for:)` placement.
    private func makeController(settings: MemorySettingsStore = MemorySettingsStore()) -> PopupWindowController {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(
            resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard),
            settingsStore: settings
        )
        let panel = PopupPanel()
        panel.contentView = FixedFittingSizeView(frame: NSRect(origin: .zero, size: palettePanelFrame.size))
        panel.setFrame(palettePanelFrame, display: false)
        panel.orderFrontRegardless()
        controller.panel = panel
        controller.startTestSession(for: makeContext())
        return controller
    }

    // MARK: - Geometry

    func testCornerDragResizesThePaletteFromItsFixedTopLeftCorner() throws {
        let controller = makeController()
        defer { controller.hide() }
        let panel = try XCTUnwrap(controller.panel)
        controller.enterSearch()
        XCTAssertEqual(controller.modeStore.mode, .search)
        XCTAssertNil(controller.modeStore.searchPaletteSize, "a never-resized palette keeps its default column")

        controller.handleResize(.bottomRight, phase: .began, mouseLocation: CGPoint(x: 430, y: 410))
        controller.handleResize(.bottomRight, phase: .changed, mouseLocation: CGPoint(x: 470, y: 380))
        let size = try XCTUnwrap(controller.modeStore.searchPaletteSize)
        XCTAssertEqual(size.width, defaultWidth + 40, accuracy: 0.5)
        XCTAssertEqual(size.height, defaultHeight + 30, accuracy: 0.5)
        XCTAssertEqual(panel.frame.minX, palettePanelFrame.minX, accuracy: 0.5, "the left edge never moves")
        XCTAssertEqual(panel.frame.maxY, palettePanelFrame.maxY, accuracy: 0.5, "the top edge (the field) never moves")
        XCTAssertEqual(panel.frame.size.width, size.width + ring, accuracy: 0.5)
        XCTAssertEqual(panel.frame.size.height, size.height + ring, accuracy: 0.5)
        XCTAssertNil(controller.modeStore.resultCardSize, "the card's size is untouched")

        controller.handleResize(.bottomRight, phase: .ended, mouseLocation: CGPoint(x: 470, y: 380))
        XCTAssertFalse(panel.isUserDragging)
    }

    func testResizeNeverShrinksBelowTheMinimumPalette() throws {
        let controller = makeController()
        defer { controller.hide() }
        controller.enterSearch()
        controller.handleResize(.bottomRight, phase: .began, mouseLocation: CGPoint(x: 430, y: 410))
        controller.handleResize(.bottomRight, phase: .changed, mouseLocation: CGPoint(x: 50, y: 900))
        XCTAssertEqual(controller.modeStore.searchPaletteSize, paletteMin)
        controller.handleResize(.bottomRight, phase: .ended, mouseLocation: CGPoint(x: 50, y: 900))
    }

    // MARK: - Remembering the size

    func testResizeEndRemembersTheSizeUnderThePaletteKeys() throws {
        let settings = MemorySettingsStore()
        let controller = makeController(settings: settings)
        defer { controller.hide() }
        controller.enterSearch()
        controller.handleResize(.right, phase: .began, mouseLocation: CGPoint(x: 430, y: 500))
        controller.handleResize(.right, phase: .changed, mouseLocation: CGPoint(x: 480, y: 500))
        XCTAssertEqual(settings.get(SettingKey.searchPaletteWidth), 0, "nothing is written mid-drag")
        controller.handleResize(.right, phase: .ended, mouseLocation: CGPoint(x: 480, y: 500))
        XCTAssertEqual(settings.get(SettingKey.searchPaletteWidth), defaultWidth + 50, accuracy: 0.5)
        XCTAssertEqual(settings.get(SettingKey.searchPaletteHeight), defaultHeight, accuracy: 0.5)
        XCTAssertEqual(settings.get(SettingKey.resultCardWidth), 0, "the palette never writes the card's keys")
    }

    func testTheNextPaletteOpensAtTheRememberedSizeAndTheCapIsLifted() throws {
        let settings = MemorySettingsStore()
        settings.set(SettingKey.searchPaletteWidth, value: 480)
        settings.set(SettingKey.searchPaletteHeight, value: 360)
        let controller = makeController(settings: settings)
        defer { controller.hide() }
        let panel = try XCTUnwrap(controller.panel)

        controller.enterSearch()
        XCTAssertEqual(controller.modeStore.searchPaletteSize, CGSize(width: 480, height: 360))
        XCTAssertGreaterThan(panel.heightCap, PopupMetrics.popupMaxHeight, "the shared cap must not clip a tall palette")

        controller.exitSearch()
        XCTAssertNil(controller.modeStore.searchPaletteSize, "the live size goes with the palette")
        XCTAssertEqual(panel.heightCap, PopupMetrics.popupMaxHeight, "the bar gets its cap back")

        controller.enterSearch()
        XCTAssertEqual(controller.modeStore.searchPaletteSize, CGSize(width: 480, height: 360),
                       "the preference outlives the session")
    }

    func testAScopeHopKeepsTheInSessionSize() throws {
        let controller = makeController()
        defer { controller.hide() }
        controller.enterSearch()
        controller.handleResize(.bottom, phase: .began, mouseLocation: CGPoint(x: 300, y: 410))
        controller.handleResize(.bottom, phase: .changed, mouseLocation: CGPoint(x: 300, y: 350))
        controller.handleResize(.bottom, phase: .ended, mouseLocation: CGPoint(x: 300, y: 350))
        let resized = try XCTUnwrap(controller.modeStore.searchPaletteSize)

        struct GroupStub: Action {
            let id = "test.group"
            let title = "Group"
            let icon = ActionIcon.symbol("folder")
            func isEnabled(for context: ActionContext) -> Bool { true }
            func perform(_ context: ActionContext) async throws -> ActionResult { .none }
        }
        controller.enterSearch(with: SearchScope(parent: GroupStub(), children: []))
        XCTAssertEqual(controller.modeStore.searchPaletteSize, resized, "hopping into a scope is not a fresh entry")
    }

    /// The hotkey path builds the palette without `enterSearch()`, so the remembered size must be
    /// in place before the first frame — the panel is placed at the remembered width right away.
    func testDirectSearchSessionOpensAtTheRememberedSize() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let settings = MemorySettingsStore()
        settings.set(SettingKey.searchPaletteWidth, value: 480)
        settings.set(SettingKey.searchPaletteHeight, value: 360)
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let controller = PopupWindowController(
            resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard),
            settingsStore: settings
        )
        defer { controller.hide() }
        controller.show(for: makeContext(cursor: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)), initialMode: .search)
        let panel = try XCTUnwrap(controller.panel)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        XCTAssertEqual(controller.modeStore.searchPaletteSize, CGSize(width: 480, height: 360))
        XCTAssertEqual(panel.frame.width, 480 + ring, accuracy: 1.0, "placed at the remembered width, not the default column")
        XCTAssertEqual(panel.frame.height, 360 + ring, accuracy: 1.0, "taller than the shared cap, so the cap was lifted")
        let bounds = screen.visibleFrame
        XCTAssertTrue(bounds.insetBy(dx: -1, dy: -1).contains(panel.frame), "a remembered palette must stay on screen: \(panel.frame) vs \(bounds)")
    }

    // MARK: - View

    private func makePalette(preferredSize: CGSize? = nil,
                             onResize: @escaping @MainActor (PopupResizeEdge, ResultCardDragPhase) -> Void = { _, _ in }) -> some View {
        let context = ActionContext(selection: makeContext())
        return PopupSearchView(
            catalog: [],
            context: context,
            preferredSize: preferredSize,
            onResize: onResize,
            onResult: { _ in },
            onExit: {}
        )
        .environment(\.colorScheme, .dark)
    }

    func testPreferredSizeOverridesThePaletteDefaultSize() {
        let host = NSHostingView(rootView: AnyView(makePalette()))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.width, defaultWidth, accuracy: 1.0)
        XCTAssertEqual(host.fittingSize.height, defaultHeight, accuracy: 1.0)

        let resized = NSHostingView(rootView: AnyView(makePalette(preferredSize: CGSize(width: 480, height: 360))))
        resized.layoutSubtreeIfNeeded()
        XCTAssertEqual(resized.fittingSize.width, 480, accuracy: 1.0)
        XCTAssertEqual(resized.fittingSize.height, 360, accuracy: 1.0)
    }

    /// The corner grip must actually receive the drag through SwiftUI's gesture system, with the
    /// focused search field in the same tree.
    func testCornerGripGestureReachesThePalette() throws {
        final class Recorder { var events: [(PopupResizeEdge, ResultCardDragPhase)] = [] }
        let recorder = Recorder()
        let host = NSHostingView(rootView: AnyView(makePalette(onResize: { recorder.events.append(($0, $1)) })))
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
        XCTAssertTrue(phases.contains(.began), "corner drag never reached the palette: \(phases)")
        XCTAssertTrue(phases.contains(.changed), "resize updates never reached the palette: \(phases)")
        XCTAssertTrue(phases.contains(.ended), "resize end never reported: \(phases)")
        XCTAssertTrue(recorder.events.allSatisfy { $0.0 == .bottomRight })
    }
}
