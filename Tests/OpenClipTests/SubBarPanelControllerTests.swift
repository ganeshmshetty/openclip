// SubBarPanelControllerTests.swift
// OpenClipTests

import XCTest
import AppKit
import SwiftUI
@testable import OpenClip
@testable import Core

@MainActor
final class SubBarPanelControllerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TestIsolation.reset()
    }

    private struct TestAction: Action, Sendable {
        let id: String
        let title: String
        let icon: ActionIcon
        var chrome: ActionChrome { ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin) }
        @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
        @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .none }
    }

    private func makeContext() -> ActionContext {
        let selection = SelectionContext(
            text: "test",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        return ActionContext(selection: selection)
    }

    func testSubBarPanelProperties() {
        let panel = SubBarPanel()
        XCTAssertEqual(panel.level, .popUpMenu)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor, .clear)
    }

    func testShowAndHideSubBar() {
        let controller = SubBarPanelController()
        let parent = TestAction(id: "group.test", title: "Test Group", icon: .symbol("folder"))
        let sub1 = TestAction(id: "sub.1", title: "Sub 1", icon: .text("One"))
        let sub2 = TestAction(id: "sub.2", title: "Sub 2", icon: .text("Two"))

        let parentFrame = NSRect(x: 200, y: 300, width: 40, height: 29)
        controller.show(
            for: parent,
            parentIndex: 0,
            subActions: [sub1, sub2],
            parentButtonScreenFrame: parentFrame,
            isPinned: false,
            searchResultsAbove: true,
            effectiveTheme: "dark",
            effectiveColorScheme: .dark,
            scale: 1.0,
            context: makeContext(),
            presenter: ActionCustomizationManager.shared,
            onResult: { _ in },
            onRunAI: { _ in },
            onRunLoadingAction: { _ in },
            onWillPerformAction: { _ in },
            onActionPerformed: { _ in },
            onClickIntent: { .primary }
        )

        XCTAssertTrue(controller.isShowing)
        XCTAssertEqual(controller.activeState?.groupID, "group.test")
        XCTAssertFalse(controller.isPinned)

        controller.pin()
        XCTAssertTrue(controller.isPinned)

        controller.hide()
        XCTAssertFalse(controller.isShowing)
        XCTAssertNil(controller.activeState)
    }

    func testIsOverContentExcludesShadowRing() {
        let controller = SubBarPanelController()
        let parent = TestAction(id: "group.test", title: "Test Group", icon: .symbol("folder"))
        let sub1 = TestAction(id: "sub.1", title: "Sub 1", icon: .symbol("star"))

        let parentFrame = NSRect(x: 200, y: 300, width: 40, height: 29)
        controller.show(
            for: parent,
            parentIndex: 0,
            subActions: [sub1],
            parentButtonScreenFrame: parentFrame,
            isPinned: true,
            searchResultsAbove: true,
            effectiveTheme: "dark",
            effectiveColorScheme: .dark,
            scale: 1.0,
            context: makeContext(),
            presenter: ActionCustomizationManager.shared,
            onResult: { _ in },
            onRunAI: { _ in },
            onRunLoadingAction: { _ in },
            onWillPerformAction: { _ in },
            onActionPerformed: { _ in },
            onClickIntent: { .primary }
        )

        let frame = controller.panelFrame
        // Center of panel is interactive content
        let centerPoint = CGPoint(x: frame.midX, y: frame.midY)
        XCTAssertTrue(controller.isOverContent(centerPoint))

        // Extreme corner is inside frame but inside transparent shadow ring
        let cornerPoint = CGPoint(x: frame.minX + 2, y: frame.minY + 2)
        XCTAssertFalse(controller.isOverContent(cornerPoint))

        // Outside frame entirely is false
        let outsidePoint = CGPoint(x: frame.minX - 50, y: frame.minY - 50)
        XCTAssertFalse(controller.isOverContent(outsidePoint))

        controller.hide()
    }

    func testLeftAnchoringExpandsRightward() {
        let controller = SubBarPanelController()
        let parent = TestAction(id: "group.test", title: "Test Group", icon: .symbol("folder"))
        let sub1 = TestAction(id: "sub.1", title: "Sub 1", icon: .symbol("star"))

        let shadowInset = PopupMetrics.popupShadowInset

        // Any button anchors its content left flush with the button's left edge, expanding rightward
        let buttonFrame = NSRect(x: 420, y: 310, width: 30, height: 30)
        controller.show(
            for: parent,
            parentIndex: 0,
            subActions: [sub1],
            parentButtonScreenFrame: buttonFrame,
            isPinned: true,
            searchResultsAbove: true,
            effectiveTheme: "dark",
            effectiveColorScheme: .dark,
            scale: 1.0,
            context: makeContext(),
            presenter: ActionCustomizationManager.shared,
            onResult: { _ in },
            onRunAI: { _ in },
            onRunLoadingAction: { _ in },
            onWillPerformAction: { _ in },
            onActionPerformed: { _ in },
            onClickIntent: { .primary }
        )
        // Content left must align flush with button's left edge when no overhang
        XCTAssertEqual(controller.panelFrame.minX + shadowInset, buttonFrame.minX, accuracy: 0.5)

        controller.hide()
    }

    func testOverhangPullsTowardMainBar() {
        let controller = SubBarPanelController()
        let parent = TestAction(id: "group.test", title: "Test Group", icon: .symbol("folder"))
        let sub1 = TestAction(id: "sub.1", title: "Sub 1", icon: .symbol("star"))
        let sub2 = TestAction(id: "sub.2", title: "Sub 2", icon: .symbol("heart"))
        let sub3 = TestAction(id: "sub.3", title: "Sub 3", icon: .symbol("bolt"))
        let sub4 = TestAction(id: "sub.4", title: "Sub 4", icon: .symbol("gear"))

        let shadowInset = PopupMetrics.popupShadowInset
        // Main bar spans from 100 to 300 (content span 116 to 284)
        let mainBarFrame = NSRect(x: 100, y: 300, width: 200, height: 60)
        // Button near the right edge of main bar
        let buttonFrame = NSRect(x: 240, y: 310, width: 30, height: 30)

        controller.show(
            for: parent,
            parentIndex: 3,
            subActions: [sub1, sub2, sub3, sub4],
            parentButtonScreenFrame: buttonFrame,
            mainBarScreenFrame: mainBarFrame,
            isPinned: false,
            searchResultsAbove: true,
            effectiveTheme: "dark",
            effectiveColorScheme: .dark,
            scale: 1.0,
            context: makeContext(),
            presenter: ActionCustomizationManager.shared,
            onResult: { _ in },
            onRunAI: { _ in },
            onRunLoadingAction: { _ in },
            onWillPerformAction: { _ in },
            onActionPerformed: { _ in },
            onClickIntent: { .primary }
        )

        let contentLeft = controller.panelFrame.minX + shadowInset
        // Should be pulled to the left of button's minX to reduce right overhang
        XCTAssertLessThan(contentLeft, buttonFrame.minX)
        // But should still cover or reach the button's right edge
        let contentRight = controller.panelFrame.maxX - shadowInset
        XCTAssertGreaterThanOrEqual(contentRight, buttonFrame.minX)

        controller.hide()
    }

    func testOnDismissCalledWhenSubBarHides() {
        let controller = SubBarPanelController()
        let parent = TestAction(id: "group.test", title: "Test Group", icon: .symbol("folder"))
        let sub1 = TestAction(id: "sub.1", title: "Sub 1", icon: .symbol("star"))

        var dismissCount = 0
        controller.onDismiss = {
            dismissCount += 1
        }

        controller.show(
            for: parent,
            parentIndex: 0,
            subActions: [sub1],
            parentButtonScreenFrame: NSRect(x: 200, y: 300, width: 40, height: 29),
            isPinned: true,
            searchResultsAbove: true,
            effectiveTheme: "dark",
            effectiveColorScheme: .dark,
            scale: 1.0,
            context: makeContext(),
            presenter: ActionCustomizationManager.shared,
            onResult: { _ in },
            onRunAI: { _ in },
            onRunLoadingAction: { _ in },
            onWillPerformAction: { _ in },
            onActionPerformed: { _ in },
            onClickIntent: { .primary }
        )

        XCTAssertEqual(dismissCount, 0)
        controller.hide()
        XCTAssertEqual(dismissCount, 1)
    }

    func testIsImmediateNeighbor() {
        let controller = SubBarPanelController()
        let parent = TestAction(id: "group.test", title: "Test Group", icon: .symbol("folder"))
        let sub1 = TestAction(id: "sub.1", title: "Sub 1", icon: .symbol("star"))

        // Active parent at index 2
        controller.show(
            for: parent,
            parentIndex: 2,
            subActions: [sub1],
            parentButtonScreenFrame: NSRect(x: 200, y: 300, width: 40, height: 29),
            isPinned: false,
            searchResultsAbove: true,
            effectiveTheme: "dark",
            effectiveColorScheme: .dark,
            scale: 1.0,
            context: makeContext(),
            presenter: ActionCustomizationManager.shared,
            onResult: { _ in },
            onRunAI: { _ in },
            onRunLoadingAction: { _ in },
            onWillPerformAction: { _ in },
            onActionPerformed: { _ in },
            onClickIntent: { .primary }
        )

        // Same button
        XCTAssertTrue(controller.isImmediateNeighbor(actionIndex: 2))
        // Immediate left neighbor
        XCTAssertTrue(controller.isImmediateNeighbor(actionIndex: 1))
        // Immediate right neighbor
        XCTAssertTrue(controller.isImmediateNeighbor(actionIndex: 3))
        // Distant left
        XCTAssertFalse(controller.isImmediateNeighbor(actionIndex: 0))
        // Distant right
        XCTAssertFalse(controller.isImmediateNeighbor(actionIndex: 4))
        XCTAssertFalse(controller.isImmediateNeighbor(actionIndex: 5))

        controller.hide()
        // Nil when no sub-bar is visible
        XCTAssertFalse(controller.isImmediateNeighbor(actionIndex: 2))
    }

    func testSubBarGraceRestartAfterShowCancellation() async throws {
        let controller = SubBarPanelController()
        let parent = TestAction(id: "group.test", title: "Test Group", icon: .symbol("folder"))
        let sub1 = TestAction(id: "sub.1", title: "Sub 1", icon: .symbol("star"))

        // Place outside typical mouse location
        let buttonFrame = NSRect(x: 20000, y: 20000, width: 40, height: 29)

        // 1. Initial show
        controller.show(
            for: parent,
            parentIndex: 0,
            subActions: [sub1],
            parentButtonScreenFrame: buttonFrame,
            isPinned: false,
            searchResultsAbove: true,
            effectiveTheme: "dark",
            effectiveColorScheme: .dark,
            scale: 1.0,
            context: makeContext(),
            presenter: ActionCustomizationManager.shared,
            onResult: { _ in },
            onRunAI: { _ in },
            onRunLoadingAction: { _ in },
            onWillPerformAction: { _ in },
            onActionPerformed: { _ in },
            onClickIntent: { .primary }
        )
        XCTAssertTrue(controller.isShowing)

        // 2. Start grace timer
        controller.startGrace()

        // 3. Show again (e.g. updating actions or re-hovering group button)
        controller.show(
            for: parent,
            parentIndex: 0,
            subActions: [sub1],
            parentButtonScreenFrame: buttonFrame,
            isPinned: false,
            searchResultsAbove: true,
            effectiveTheme: "dark",
            effectiveColorScheme: .dark,
            scale: 1.0,
            context: makeContext(),
            presenter: ActionCustomizationManager.shared,
            onResult: { _ in },
            onRunAI: { _ in },
            onRunLoadingAction: { _ in },
            onWillPerformAction: { _ in },
            onActionPerformed: { _ in },
            onClickIntent: { .primary }
        )
        XCTAssertTrue(controller.isShowing)

        // 4. Start grace timer again after second show
        controller.startGrace()

        // 5. Wait for grace timer (350ms) to fire
        try await Task.sleep(nanoseconds: 450_000_000)

        // If graceTask was not cleared upon cancellation in show(), startGrace() failed and panel is still showing
        XCTAssertFalse(controller.isShowing)
    }

    func testSubBarGraceRestartAfterHideAndDwellCancellation() async throws {
        let controller = SubBarPanelController()
        let parent = TestAction(id: "group.test", title: "Test Group", icon: .symbol("folder"))
        let sub1 = TestAction(id: "sub.1", title: "Sub 1", icon: .symbol("star"))
        let buttonFrame = NSRect(x: 20000, y: 20000, width: 40, height: 29)

        func showSubBar() {
            controller.show(
                for: parent,
                parentIndex: 0,
                subActions: [sub1],
                parentButtonScreenFrame: buttonFrame,
                isPinned: false,
                searchResultsAbove: true,
                effectiveTheme: "dark",
                effectiveColorScheme: .dark,
                scale: 1.0,
                context: makeContext(),
                presenter: ActionCustomizationManager.shared,
                onResult: { _ in },
                onRunAI: { _ in },
                onRunLoadingAction: { _ in },
                onWillPerformAction: { _ in },
                onActionPerformed: { _ in },
                onClickIntent: { .primary }
            )
        }

        // Test hide() cancellation:
        showSubBar()
        controller.startGrace()
        controller.hide() // Should cancel and clear graceTask
        XCTAssertFalse(controller.isShowing)

        // Show again and start grace
        showSubBar()
        XCTAssertTrue(controller.isShowing)
        controller.startGrace()
        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertFalse(controller.isShowing)

        // Test startDwell() cancellation:
        showSubBar()
        controller.startGrace()
        // Calling startDwell when showing fast-switches and cancels grace
        controller.startDwell {
            showSubBar()
        }
        XCTAssertTrue(controller.isShowing)
        controller.startGrace()
        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertFalse(controller.isShowing)
    }

    func testShowSubBarWithGlassTheme() {
        let controller = SubBarPanelController()
        let parent = TestAction(id: "group.test", title: "Test Group", icon: .symbol("folder"))
        let sub1 = TestAction(id: "sub.1", title: "Sub 1", icon: .symbol("star"))
        let buttonFrame = NSRect(x: 200, y: 300, width: 40, height: 29)

        controller.show(
            for: parent,
            parentIndex: 0,
            subActions: [sub1],
            parentButtonScreenFrame: buttonFrame,
            isPinned: false,
            searchResultsAbove: false,
            effectiveTheme: "glass",
            effectiveColorScheme: .dark,
            scale: 1.0,
            context: makeContext(),
            presenter: ActionCustomizationManager.shared,
            onResult: { _ in },
            onRunAI: { _ in },
            onRunLoadingAction: { _ in },
            onWillPerformAction: { _ in },
            onActionPerformed: { _ in },
            onClickIntent: { .primary }
        )

        XCTAssertTrue(controller.isShowing)
        XCTAssertEqual(controller.activeState?.groupID, "group.test")
        controller.hide()
        XCTAssertFalse(controller.isShowing)
    }

    func testSubBarPanelContentViewInstallsTrackingAreaForCursorUpdate() {
        let panel = SubBarPanel()
        let host = SubBarPanel.ContentView(rootView: AnyView(Text("test")))
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 60)
        panel.contentView = host
        host.updateTrackingAreas()

        let trackingAreas = host.trackingAreas
        XCTAssertFalse(trackingAreas.isEmpty, "ContentView must install a tracking area")
        guard let area = trackingAreas.first else { return }
        XCTAssertTrue(area.options.contains(.cursorUpdate), "Tracking area must contain .cursorUpdate")
        XCTAssertTrue(area.options.contains(.activeAlways), "Tracking area must contain .activeAlways")
        XCTAssertTrue(area.options.contains(.inVisibleRect), "Tracking area must contain .inVisibleRect")
        XCTAssertTrue(area.options.contains(.mouseEnteredAndExited), "Tracking area must contain .mouseEnteredAndExited")
    }

    func testSubBarPanelContentViewCursorUpdateAndMouseEntered() {
        let host = SubBarPanel.ContentView(rootView: AnyView(Text("test")))
        let dummyEvent = NSEvent.mouseEvent(
            with: .mouseMoved,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        )!

        // Should execute cleanly without runtime error
        host.cursorUpdate(with: dummyEvent)
        host.mouseEntered(with: dummyEvent)
        host.resetCursorRects()
    }

    func testSubBarHoverLocationPublishedOnMouseMoveAndClearedOnHide() {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-\(UUID().uuidString)"))
        let subBar = SubBarPanelController()
        let controller = PopupWindowController(
            resultHandler: DefaultActionResultHandler(pasteboard: isolatedPasteboard),
            subBarController: subBar
        )
        let parent = TestAction(id: "group.test", title: "Test Group", icon: .symbol("folder"))
        let sub1 = TestAction(id: "sub.1", title: "Sub 1", icon: .symbol("star"))
        let buttonFrame = NSRect(x: 200, y: 300, width: 40, height: 29)

        subBar.show(
            for: parent,
            parentIndex: 0,
            subActions: [sub1],
            parentButtonScreenFrame: buttonFrame,
            isPinned: false,
            searchResultsAbove: true,
            effectiveTheme: "dark",
            effectiveColorScheme: .dark,
            scale: 1.0,
            context: makeContext(),
            presenter: ActionCustomizationManager.shared,
            onResult: { _ in },
            onRunAI: { _ in },
            onRunLoadingAction: { _ in },
            onWillPerformAction: { _ in },
            onActionPerformed: { _ in },
            onClickIntent: { .primary }
        )

        XCTAssertTrue(subBar.isShowing)

        // Mouse over center of sub-bar
        let center = CGPoint(x: subBar.panelFrame.midX, y: subBar.panelFrame.midY)
        controller.updateSubBarHover(at: center)
        XCTAssertNotNil(SubBarHoverState.shared.location, "SubBarHoverState location must be set when hovering over sub-bar")

        // Mouse moved far away
        let farAway = CGPoint(x: 10, y: 10)
        controller.updateSubBarHover(at: farAway)
        XCTAssertNil(SubBarHoverState.shared.location, "SubBarHoverState location must be nil when cursor is outside sub-bar")

        // Hide clears state
        subBar.hide()
        XCTAssertNil(SubBarHoverState.shared.location)
    }

    func testSubBarPanelRightAnchorPreservesRightEdgeOnResize() {
        let panel = SubBarPanel()
        panel.setFrame(NSRect(x: 200, y: 300, width: 300, height: 50), display: false)
        XCTAssertEqual(panel.frame.maxX, 500)

        panel.horizontalAnchor = .right

        // Shrink width to 100
        panel.setFrame(NSRect(x: 200, y: 300, width: 100, height: 50), display: false)
        XCTAssertEqual(panel.frame.maxX, 500, "SubBarPanel right edge must stay pinned when horizontalAnchor is .right")
        XCTAssertEqual(panel.frame.origin.x, 400)

        // Expand width to 400
        panel.setFrame(NSRect(x: 200, y: 300, width: 400, height: 50), display: false)
        XCTAssertEqual(panel.frame.maxX, 500, "SubBarPanel right edge must stay pinned when expanding with .right anchor")
        XCTAssertEqual(panel.frame.origin.x, 100)
    }

    func testSubBarVerticalPositionFollowsMainBarAbove() {
        let controller = SubBarPanelController()
        let parent = TestAction(id: "group.test", title: "Test Group", icon: .symbol("folder"))
        let sub1 = TestAction(id: "sub.1", title: "Sub 1", icon: .text("One"))

        let parentFrame = NSRect(x: 200, y: 300, width: 40, height: 29)

        // When mainBarAbove is true, sub-bar should be placed ABOVE the main bar's button
        controller.show(
            for: parent,
            parentIndex: 0,
            subActions: [sub1],
            parentButtonScreenFrame: parentFrame,
            isPinned: false,
            searchResultsAbove: false, // even if searchResultsAbove is false, mainBarAbove takes precedence
            mainBarAbove: true,
            effectiveTheme: "dark",
            effectiveColorScheme: .dark,
            scale: 1.0,
            context: makeContext(),
            presenter: ActionCustomizationManager.shared,
            onResult: { _ in },
            onRunAI: { _ in },
            onRunLoadingAction: { _ in },
            onWillPerformAction: { _ in },
            onActionPerformed: { _ in },
            onClickIntent: { .primary }
        )

        XCTAssertTrue(controller.isShowing)
        let shadowInset = PopupMetrics.popupShadowInset
        let contentMinY = controller.panelFrame.minY + shadowInset
        XCTAssertGreaterThanOrEqual(contentMinY, parentFrame.maxY, "Sub-bar visual content should sit above parent button")
        controller.hide()
    }

    func testSubBarVerticalPositionFollowsMainBarBelow() {
        let controller = SubBarPanelController()
        let parent = TestAction(id: "group.test", title: "Test Group", icon: .symbol("folder"))
        let sub1 = TestAction(id: "sub.1", title: "Sub 1", icon: .text("One"))

        let parentFrame = NSRect(x: 200, y: 400, width: 40, height: 29)

        // When mainBarAbove is false, sub-bar should be placed BELOW the main bar's button
        controller.show(
            for: parent,
            parentIndex: 0,
            subActions: [sub1],
            parentButtonScreenFrame: parentFrame,
            isPinned: false,
            searchResultsAbove: true, // even if searchResultsAbove is true, mainBarAbove takes precedence
            mainBarAbove: false,
            effectiveTheme: "dark",
            effectiveColorScheme: .dark,
            scale: 1.0,
            context: makeContext(),
            presenter: ActionCustomizationManager.shared,
            onResult: { _ in },
            onRunAI: { _ in },
            onRunLoadingAction: { _ in },
            onWillPerformAction: { _ in },
            onActionPerformed: { _ in },
            onClickIntent: { .primary }
        )

        XCTAssertTrue(controller.isShowing)
        let shadowInset = PopupMetrics.popupShadowInset
        let contentMaxY = controller.panelFrame.maxY - shadowInset
        XCTAssertLessThanOrEqual(contentMaxY, parentFrame.minY, "Sub-bar visual content should sit below parent button")
        controller.hide()
    }
}

