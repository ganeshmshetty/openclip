import AppKit
import SwiftUI
import XCTest
@testable import Core
@testable import OpenClip

@MainActor
private final class SpaceTestPanel: PopupPanel {
    var simulatedActiveSpace = false
    var reportedVisible = true
    var reportedKey = false
    var ordering: [String] = []
    override var isOnActiveSpace: Bool { simulatedActiveSpace }
    override var isVisible: Bool { reportedVisible }
    override var isKeyWindow: Bool { reportedKey }
    override func orderOut(_ sender: Any?) { ordering.append("out") }
    override func orderFront(_ sender: Any?) { ordering.append("front") }
}

@MainActor
final class PopupSpaceRecoveryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TestIsolation.reset()
    }

    private func fixture() -> (PopupWindowController, SpaceTestPanel) {
        let controller = PopupWindowController(settingsStore: MemorySettingsStore())
        let panel = SpaceTestPanel()
        controller.panel = panel
        controller.startTestSession(for: SelectionContext(text: "private selection",
            sourceApp: AppIdentity(bundleIdentifier: "com.test.source", processIdentifier: 99999), traceID: 42))
        return (controller, panel)
    }

    func testOffSpacePopupRecreatesOnceWithoutReplacingContentOrTakingFocus() {
        let (controller, panel) = fixture()
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        panel.contentView = content
        let frame = panel.frame
        let attempt = controller.presentationAttemptID
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllApplications))
        let replacement = SpaceTestPanel()
        XCTAssertTrue(controller.recoverPopupSpaceIfNeeded(for: attempt, frontmostPID: 99999, makePanel: { replacement }))
        XCTAssertTrue(controller.panel === replacement)
        XCTAssertEqual(panel.ordering, ["out"])
        XCTAssertEqual(replacement.ordering, ["front"])
        XCTAssertNil(panel.contentView)
        XCTAssertTrue(replacement.contentView === content)
        XCTAssertEqual(replacement.frame, frame)
        XCTAssertFalse(replacement.canBecomeKey)
        XCTAssertTrue(replacement.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(controller.recoverPopupSpaceIfNeeded(for: attempt, frontmostPID: 99999))
        XCTAssertEqual(panel.ordering, ["out"])
        controller.hide()
    }

    func testHealthyHiddenKeyAndChangedSourcePopupsAreNotReordered() {
        let (controller, panel) = fixture()
        let attempt = controller.presentationAttemptID
        panel.simulatedActiveSpace = true
        XCTAssertFalse(controller.recoverPopupSpaceIfNeeded(for: attempt, frontmostPID: 99999))
        panel.simulatedActiveSpace = false
        panel.reportedVisible = false
        XCTAssertFalse(controller.recoverPopupSpaceIfNeeded(for: attempt, frontmostPID: 99999))
        panel.reportedVisible = true
        panel.reportedKey = true
        XCTAssertFalse(controller.recoverPopupSpaceIfNeeded(for: attempt, frontmostPID: 99999))
        panel.reportedKey = false
        XCTAssertFalse(controller.recoverPopupSpaceIfNeeded(for: attempt, frontmostPID: 88888))
        XCTAssertFalse(controller.recoverPopupSpaceIfNeeded(for: attempt, frontmostPID: nil))
        controller.modeStore.mode = .search
        XCTAssertFalse(controller.recoverPopupSpaceIfNeeded(for: attempt, frontmostPID: 99999))
        controller.modeStore.mode = .content
        XCTAssertFalse(controller.recoverPopupSpaceIfNeeded(for: attempt, frontmostPID: 99999))
        XCTAssertTrue(panel.ordering.isEmpty)
        controller.hide()
    }

    func testStaleChecksCannotRecoverReplacementOrDismissedPopup() {
        let (controller, panel) = fixture()
        let oldAttempt = controller.presentationAttemptID
        controller.startTestSession(for: SelectionContext(text: "replacement",
            sourceApp: AppIdentity(processIdentifier: 99999)))
        XCTAssertFalse(controller.recoverPopupSpaceIfNeeded(for: oldAttempt, frontmostPID: 99999))
        XCTAssertTrue(panel.ordering.isEmpty)
        let currentAttempt = controller.presentationAttemptID
        controller.hide()
        panel.ordering.removeAll()
        XCTAssertFalse(controller.recoverPopupSpaceIfNeeded(for: currentAttempt, frontmostPID: 99999))
        XCTAssertTrue(panel.ordering.isEmpty)
    }

    /// Regression: the panels' `.activeAlways` tracking area feeds hover while OpenClip is inactive
    /// (floating over another app's fullscreen Space), where no event monitor sees the pointer. That
    /// path must not toggle click-through (`ignoresMouseEvents`), or the panel would stop receiving
    /// its own tracking events and strand hover/tooltips/sub-bars.
    func testTrackingHoverDoesNotToggleClickThrough() {
        let (controller, panel) = fixture()
        panel.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        panel.setFrame(NSRect(x: 300, y: 300, width: 200, height: 80), display: false)
        PopupHoverState.shared.usesGlobalMouseMonitoring = true
        defer {
            PopupHoverState.shared.usesGlobalMouseMonitoring = false
            PopupHoverState.shared.location = nil
        }
        let outside = CGPoint(x: panel.frame.maxX + 40, y: panel.frame.maxY + 40)

        panel.ignoresMouseEvents = false
        controller.updatePopupHover(at: outside, toggleClickThrough: false)
        XCTAssertFalse(panel.ignoresMouseEvents)

        // The event-monitor path keeps its click-through behavior.
        controller.updatePopupHover(at: outside, toggleClickThrough: true)
        XCTAssertTrue(panel.ignoresMouseEvents)
        controller.hide()
    }

    func testOffSpaceTooltipRecreatesOnceWithoutReplacingContent() throws {
        let (controller, panel) = tooltipFixture()
        defer { controller.hide() }
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllApplications))
        controller.show(text: "Copy", targetScreenFrame: tooltipTarget, cursorLocation: tooltipCursor)
        XCTAssertTrue(controller.isShowing)
        panel.reportedVisible = true
        panel.simulatedActiveSpace = false
        panel.ordering.removeAll()
        let content = panel.contentView
        let frame = panel.frame
        let replacement = SpaceTooltipPanel()
        let attempt = try XCTUnwrap(controller.presentationID)
        XCTAssertTrue(controller.recoverTooltipSpaceIfNeeded(for: attempt, makePanel: { replacement }))
        XCTAssertTrue(controller.panel === replacement)
        XCTAssertEqual(panel.ordering, ["out"])
        XCTAssertEqual(replacement.ordering, ["front"])
        XCTAssertNil(panel.contentView)
        XCTAssertTrue(replacement.contentView === content)
        XCTAssertEqual(replacement.frame, frame)
        XCTAssertEqual(replacement.alphaValue, 1)
        XCTAssertFalse(replacement.canBecomeKey)
        XCTAssertTrue(replacement.collectionBehavior.contains(.canJoinAllApplications))
        XCTAssertFalse(controller.recoverTooltipSpaceIfNeeded(for: attempt, makePanel: { SpaceTooltipPanel() }))
        XCTAssertEqual(panel.ordering, ["out"])
    }

    func testTooltipSpaceRecoverySkipsHealthyHiddenKeyAndStaleShows() throws {
        let (controller, panel) = tooltipFixture()
        defer { controller.hide() }
        controller.show(text: "", targetScreenFrame: tooltipTarget, cursorLocation: tooltipCursor)
        XCTAssertFalse(controller.isShowing)
        XCTAssertTrue(panel.ordering.isEmpty)

        controller.show(text: "Copy", targetScreenFrame: .zero, cursorLocation: tooltipCursor)
        XCTAssertFalse(controller.isShowing)

        controller.show(text: "Copy", targetScreenFrame: tooltipTarget, cursorLocation: tooltipCursor)
        let attempt = try XCTUnwrap(controller.presentationID)
        panel.reportedVisible = true
        panel.simulatedActiveSpace = true
        panel.ordering.removeAll()
        XCTAssertFalse(controller.recoverTooltipSpaceIfNeeded(for: attempt))
        XCTAssertTrue(panel.ordering.isEmpty)

        panel.simulatedActiveSpace = false
        panel.reportedKey = true
        XCTAssertFalse(controller.recoverTooltipSpaceIfNeeded(for: attempt))
        panel.reportedKey = false
        panel.ordering.removeAll()
        controller.hide()
        XCTAssertNil(controller.presentationID)
        XCTAssertFalse(controller.isShowing)
        XCTAssertFalse(controller.recoverTooltipSpaceIfNeeded(for: attempt))
    }

    func testVisibleTooltipRetargetKeepsThePanelUp() {
        let (controller, panel) = tooltipFixture()
        defer { controller.hide() }
        controller.show(text: "Copy", targetScreenFrame: tooltipTarget, cursorLocation: tooltipCursor)
        panel.reportedVisible = true
        panel.alphaValue = 1
        panel.ordering.removeAll()
        controller.show(text: "Paste", targetScreenFrame: tooltipTarget, cursorLocation: tooltipCursor)
        XCTAssertTrue(controller.isShowing)
        XCTAssertTrue(panel.ordering.isEmpty)
        XCTAssertNotNil(controller.presentationID)
    }

    func testZeroTooltipMeasureFallsBackToTextSize() {
        let zero = TooltipPanelController.resolvedTooltipSize(measured: .zero, text: "Copy", maxWidth: 40)
        XCTAssertEqual(zero.width, ceil(("Copy" as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium)]).width) + 14)
        XCTAssertGreaterThan(zero.height, 6)
        let wide = TooltipPanelController.resolvedTooltipSize(
            measured: .zero, text: String(repeating: "W", count: 80), maxWidth: 40)
        XCTAssertEqual(wide.width, 54)
        let measured = CGSize(width: 48, height: 18)
        XCTAssertEqual(
            TooltipPanelController.resolvedTooltipSize(measured: measured, text: "Copy", maxWidth: 40),
            measured
        )
    }

    func testOffSpaceSubBarRecreatesOnceWithoutReplacingContent() {
        let panel = SpaceSubBarPanel()
        panel.reportedVisible = false
        let controller = SubBarPanelController(panel: panel, tooltipController: TooltipPanelController())
        defer { controller.hide() }
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllApplications))
        presentProbeSubBar(controller)
        XCTAssertNotNil(controller.activeState)
        panel.reportedVisible = true
        panel.simulatedActiveSpace = false
        panel.horizontalAnchor = .right
        panel.ignoresMouseEvents = true
        panel.ordering.removeAll()
        let content = panel.contentView
        let frame = panel.frame
        let appearance = panel.appearance
        let replacement = SpaceSubBarPanel()
        let attempt = controller.spacePresentationID
        XCTAssertTrue(controller.recoverSubBarSpaceIfNeeded(for: attempt, makePanel: { replacement }))
        XCTAssertTrue(controller.panel === replacement)
        XCTAssertEqual(panel.ordering, ["out"])
        XCTAssertEqual(replacement.ordering, ["front"])
        XCTAssertNil(panel.contentView)
        XCTAssertTrue(replacement.contentView === content)
        XCTAssertEqual(replacement.frame, frame)
        XCTAssertEqual(replacement.horizontalAnchor, .right)
        XCTAssertFalse(replacement.ignoresMouseEvents)
        XCTAssertEqual(replacement.appearance, appearance)
        XCTAssertFalse(replacement.canBecomeKey)
        XCTAssertTrue(replacement.collectionBehavior.contains(.canJoinAllApplications))
        XCTAssertFalse(controller.recoverSubBarSpaceIfNeeded(for: attempt))
        XCTAssertEqual(panel.ordering, ["out"])
    }

    func testSubBarSpaceRecoverySkipsHealthyHiddenKeyAndStaleShows() {
        let panel = SpaceSubBarPanel()
        panel.reportedVisible = false
        let controller = SubBarPanelController(panel: panel, tooltipController: TooltipPanelController())
        defer { controller.hide() }
        presentProbeSubBar(controller)
        let attempt = controller.spacePresentationID
        panel.reportedVisible = true
        panel.simulatedActiveSpace = true
        panel.ordering.removeAll()
        XCTAssertFalse(controller.recoverSubBarSpaceIfNeeded(for: attempt))
        XCTAssertTrue(panel.ordering.isEmpty)

        panel.simulatedActiveSpace = false
        panel.reportedKey = true
        XCTAssertFalse(controller.recoverSubBarSpaceIfNeeded(for: attempt))
        panel.reportedKey = false
        controller.hide()
        XCTAssertNil(controller.activeState)
        XCTAssertFalse(controller.recoverSubBarSpaceIfNeeded(for: attempt))
    }

    private var tooltipTarget: CGRect { CGRect(x: 200, y: 400, width: 36, height: 28) }
    private var tooltipCursor: CGPoint { CGPoint(x: 210, y: 410) }

    private func tooltipFixture() -> (TooltipPanelController, SpaceTooltipPanel) {
        let panel = SpaceTooltipPanel()
        panel.reportedVisible = false
        return (TooltipPanelController(panel: panel), panel)
    }

    private func presentProbeSubBar(_ controller: SubBarPanelController) {
        let group = SpaceProbeAction(id: "group.probe", title: "Group")
        let child = SpaceProbeAction(id: "group.probe.child", title: "Child")
        _ = controller.show(
            for: group,
            parentIndex: 0,
            subActions: [child],
            parentButtonScreenFrame: NSRect(x: 220, y: 220, width: 40, height: 30),
            isPinned: false,
            effectiveTheme: "glass",
            effectiveColorScheme: .dark,
            scale: 1,
            context: ActionContext(selection: SelectionContext(text: "probe")),
            presenter: SpaceProbePresenter(),
            onResult: { _ in },
            onRunAI: { _ in },
            onRunLoadingAction: { _, _ in },
            onWillPerformAction: { _, _ in true },
            onActionPerformed: { _ in },
            onClickIntent: { .primary }
        )
    }
}

@MainActor
private final class SpaceTooltipPanel: TooltipPanel {
    var simulatedActiveSpace = false
    var reportedVisible = true
    var reportedKey = false
    var ordering: [String] = []
    override var isOnActiveSpace: Bool { simulatedActiveSpace }
    override var isVisible: Bool { reportedVisible }
    override var isKeyWindow: Bool { reportedKey }
    override func orderOut(_ sender: Any?) { ordering.append("out") }
    override func orderFrontRegardless() { ordering.append("front") }
}

@MainActor
private final class SpaceSubBarPanel: SubBarPanel {
    var simulatedActiveSpace = false
    var reportedVisible = true
    var reportedKey = false
    var ordering: [String] = []
    override var isOnActiveSpace: Bool { simulatedActiveSpace }
    override var isVisible: Bool { reportedVisible }
    override var isKeyWindow: Bool { reportedKey }
    override func orderOut(_ sender: Any?) { ordering.append("out") }
    override func orderFront(_ sender: Any?) { ordering.append("front") }
}

private struct SpaceProbeAction: Action, Sendable {
    let id: String
    let title: String
    var icon: ActionIcon { .symbol("star") }
    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .none }
}

private struct SpaceProbePresenter: ActionPresenting {
    func displayTitle(for action: any Action) -> String { action.title }
    func popupIcon(for action: any Action) -> ActionIcon { action.icon }
    func tableIcon(for action: any Action) -> ActionIcon { action.icon }
}
