// SubBarPanelController.swift
// OpenClip
//
// Manages the standalone SubBarPanel hosting GroupSubActionBarView for group actions and AI tools.
// Positions the sub-bar in screen coordinates relative to the parent button frame, handles
// dwell/grace timers, pinning state, and forwards action execution to the root result handler.
import AppKit
import SwiftUI
import Core

@MainActor
public final class SubBarPanelController {
    public private(set) var panel: SubBarPanel
    private var hostingView: NSHostingView<AnyView>?
    private var graceTask: Task<Void, Never>?
    private var dwellTask: Task<Void, Never>?
    public private(set) var activeState: ActiveSubGroupState?
    public var isShowing: Bool { panel.isVisible }
    public var isPinned: Bool { activeState?.isPinned == true }
    public var panelFrame: NSRect { panel.frame }
    /// Called when the sub-bar hides so parent state (like active button highlight) is dismissed immediately.
    public var onDismiss: (@MainActor @Sendable () -> Void)?
    /// Hover from the `.activeAlways` tracking area; needed when event monitors can't see the pointer (inactive app over a fullscreen Space).
    public var onTrackingMouseMoved: (@MainActor @Sendable () -> Void)?
    /// The screen-space hover-tooltip surface shared with PopupWindowController. Injected for tests.
    public let tooltipController: TooltipPanelController
    /// Main bar's screen frame for the current show; sub-bar tooltips avoid it.
    private var mainBarScreenFrame: NSRect?
    /// Invalidates a Space check when the sub-bar hides or shows again.
    private(set) var spacePresentationID = UUID()
    private var spaceRecoveryTask: Task<Void, Never>?
    private var didAttemptSpaceRecovery = false

    public init(panel: SubBarPanel = SubBarPanel(),
                tooltipController: TooltipPanelController = .shared) {
        self.panel = panel
        self.tooltipController = tooltipController
    }

    @discardableResult
    public func show(
        for groupAction: any Action,
        parentIndex: Int,
        subActions: [any Action],
        parentButtonScreenFrame: NSRect,
        mainBarScreenFrame: NSRect? = nil,
        isPinned: Bool,
        searchResultsAbove: Bool = true,
        mainBarAbove: Bool? = nil,
        effectiveTheme: String,
        effectiveColorScheme: ColorScheme,
        scale: CGFloat,
        context: ActionContext,
        presenter: any ActionPresenting,
        modeStore: PopupModeStore = PopupModeStore(),
        onResult: @escaping @MainActor @Sendable (ActionResult) -> Void,
        onRunAI: @escaping @MainActor @Sendable (String) -> Void,
        onRunLoadingAction: @escaping @MainActor @Sendable (any Action, ActionResultDelivery.ClickIntent) -> Void,
        onWillPerformAction: @escaping @MainActor @Sendable (any Action, ActionResultDelivery.ClickIntent) -> Bool,
        onActionPerformed: @escaping @MainActor @Sendable (String) -> Void,
        onClickIntent: @escaping @MainActor @Sendable () -> ActionResultDelivery.ClickIntent
    ) -> Bool {
        dwellTask?.cancel()
        dwellTask = nil
        cancelGrace()

        guard !subActions.isEmpty else {
            hide()
            return false
        }

        spaceRecoveryTask?.cancel()
        spacePresentationID = UUID()
        didAttemptSpaceRecovery = false
        let spaceAttempt = spacePresentationID

        let state = ActiveSubGroupState(
            groupID: groupAction.id,
            parentIndex: parentIndex,
            subActionIDs: subActions.map(\.id),
            isPinned: isPinned,
            parentButtonFrame: parentButtonScreenFrame
        )
        self.activeState = state
        self.mainBarScreenFrame = mainBarScreenFrame
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: parentButtonScreenFrame.midX, y: parentButtonScreenFrame.midY)) } ?? NSScreen.main
        let screenWidth = screen?.visibleFrame.width ?? 1440.0

        let contentView = SubBarContentView(
            subActions: subActions,
            effectiveTheme: effectiveTheme,
            effectiveColorScheme: effectiveColorScheme,
            scale: scale,
            screenWidth: screenWidth,
            context: context,
            presenter: presenter,
            modeStore: modeStore,
            onResult: onResult,
            onRunAI: onRunAI,
            onRunLoadingAction: onRunLoadingAction,
            onWillPerformAction: onWillPerformAction,
            onActionPerformed: onActionPerformed,
            onClickIntent: onClickIntent,
            onHoverChange: { [weak self] isHovering in
                guard let self else { return }
                if isHovering {
                    self.cancelGrace()
                } else {
                    self.startGrace()
                }
            },
            onPaginationAnchor: { [weak self] anchor in
                self?.panel.horizontalAnchor = anchor
            },
            onContentSizeChange: { [weak self] size in
                self?.resizePanel(to: size)
            },
            onShowTooltip: { [weak self] text, localFrame, theme, isDark in
                self?.presentTooltip(text: text, localFrame: localFrame, effectiveTheme: theme, isDark: isDark)
            },
            onHideTooltip: { [weak self] in
                self?.tooltipController.hide()
            }
        )

        let hosting = SubBarPanel.ContentView(rootView: AnyView(contentView))
        hosting.onMouseMoved = { [weak self] in self?.onTrackingMouseMoved?() }
        self.hostingView = hosting
        panel.appearance = NSAppearance(named: effectiveColorScheme == .dark ? .darkAqua : .aqua)
        panel.contentView = hosting
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        let panelWidth = max(fit.width, PopupMetrics.actionButtonWidth)
        let panelHeight = max(fit.height, 30)

        // Anchor left to the parent button; pull toward the main bar when overhanging its right edge.
        let shadowInset = PopupMetrics.popupShadowInset
        let contentWidth = max(0, panelWidth - 2 * shadowInset)
        var contentX = parentButtonScreenFrame.minX

        if let mainBarFrame = mainBarScreenFrame {
            let mainBarContent = mainBarFrame.insetBy(dx: shadowInset, dy: shadowInset)
            let rawContentRight = contentX + contentWidth
            let overhang = rawContentRight - mainBarContent.maxX

            if overhang > 0 {
                // Pull left by ~55% of the right overhang
                let pullAmount = overhang * 0.55
                let candidateX = contentX - pullAmount
                // Don't shift past the main bar's left edge or uncover the parent button.
                let minAllowedX = max(mainBarContent.minX, parentButtonScreenFrame.maxX - contentWidth)
                contentX = max(minAllowedX, candidateX)
            }
        }

        let panelX = contentX - shadowInset
        let screenBounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let minX = screenBounds.minX + PopupMetrics.popupPadding
        let maxX = max(minX, screenBounds.maxX - panelWidth - PopupMetrics.popupPadding)
        let clampedX = max(minX, min(panelX, maxX))

        let placement = Self.verticalPlacement(
            parentButtonFrame: parentButtonScreenFrame,
            mainBarFrame: mainBarScreenFrame,
            panelHeight: panelHeight,
            preferAbove: mainBarAbove ?? searchResultsAbove,
            screenBounds: screenBounds
        )
        panel.setFrame(NSRect(x: clampedX, y: placement.y, width: panelWidth, height: panelHeight), display: true)
        panel.orderFront(nil)
        scheduleSpaceRecovery(for: spaceAttempt)
        return placement.isAbove
    }

    private func scheduleSpaceRecovery(for id: UUID) {
        guard NSClassFromString("XCTestCase") == nil else { return }
        spaceRecoveryTask?.cancel()
        spaceRecoveryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) }
            catch { return }
            self?.recoverSubBarSpaceIfNeeded(for: id)
        }
    }

    /// A reused window can keep stale Space membership; swap in a fresh panel once, keeping content and frame.
    @discardableResult
    func recoverSubBarSpaceIfNeeded(for id: UUID, makePanel: () -> SubBarPanel = { SubBarPanel() }) -> Bool {
        guard spacePresentationID == id, activeState != nil, !didAttemptSpaceRecovery,
              !panel.isKeyWindow, !panel.isVisible || !panel.isOnActiveSpace else { return false }
        didAttemptSpaceRecovery = true
        Log.presentation.notice("Recovering sub-bar window visible=\(panel.isVisible, privacy: .public) activeSpace=\(panel.isOnActiveSpace, privacy: .public)")
        let frame = panel.frame
        let content = panel.contentView
        let anchor = panel.horizontalAnchor
        let appearance = panel.appearance
        let replacement = makePanel()
        replacement.horizontalAnchor = anchor
        replacement.appearance = appearance
        // Click-through is momentary hover state. A fresh window accepts clicks, like a new show.
        replacement.ignoresMouseEvents = false
        panel.orderOut(nil)
        panel.contentView = nil
        panel = replacement
        replacement.contentView = content
        replacement.setFrame(frame, display: false)
        content?.updateTrackingAreas()
        replacement.orderFront(nil)
        return true
    }

    /// Places the child row outside the parent surface, flipping when the preferred side cannot fit.
    static func verticalPlacement(parentButtonFrame: CGRect, mainBarFrame: CGRect?,
                                  panelHeight: CGFloat, preferAbove: Bool,
                                  screenBounds: CGRect) -> (y: CGFloat, isAbove: Bool) {
        let shadowInset = PopupMetrics.popupShadowInset
        let contentTop = max(parentButtonFrame.maxY,
                             mainBarFrame.map { $0.maxY - shadowInset } ?? parentButtonFrame.maxY)
        let yAbove = contentTop + 6 - shadowInset
        let yBelow = parentButtonFrame.minY - 6 + shadowInset - panelHeight
        let padding = PopupMetrics.popupPadding
        let fitsAbove = yAbove + panelHeight <= screenBounds.maxY - padding
        let fitsBelow = yBelow >= screenBounds.minY + padding
        let above = preferAbove ? (fitsAbove || !fitsBelow) : (!fitsBelow && fitsAbove)
        return (above ? yAbove : yBelow, above)
    }

    /// Shows a sub-bar hover tooltip in the screen-space window, avoiding the main bar so it flips instead of covering the sub-bar's buttons.
    private func presentTooltip(text: String, localFrame: CGRect, effectiveTheme: String, isDark: Bool) {
        guard panel.isVisible, let contentView = panel.contentView else { return }
        let viewRect = NSRect(x: localFrame.minX, y: localFrame.minY, width: localFrame.width, height: localFrame.height)
        let windowRect = contentView.convert(viewRect, to: nil)
        let targetScreenFrame = panel.convertToScreen(windowRect)
        guard !targetScreenFrame.isEmpty else { return }
        var avoidanceRects: [CGRect] = []
        if let mainBarScreenFrame, mainBarScreenFrame.width > 0, mainBarScreenFrame.height > 0 {
            avoidanceRects.append(mainBarScreenFrame)
        }
        tooltipController.show(
            text: text,
            targetScreenFrame: targetScreenFrame,
            avoidanceRects: avoidanceRects,
            effectiveTheme: effectiveTheme,
            isDark: isDark,
            maxWidth: panel.frame.width - 32
        )
    }

    /// Keeps the active sub-bar open until explicitly closed or an action runs.
    public func pin() {
        if let current = activeState {
            activeState = current.pinned()
            cancelGrace()
        }
    }

    /// Whether an action index is adjacent to the active parent action.
    public func isImmediateNeighbor(actionIndex: Int) -> Bool {
        guard let parentIndex = activeState?.parentIndex else { return false }
        return abs(actionIndex - parentIndex) <= 1
    }

    /// Start a 150ms dwell timer before opening a transient sub-bar on hover.
    public func startDwell(action: @escaping @MainActor () -> Void) {
        dwellTask?.cancel()
        dwellTask = nil
        cancelGrace()

        // Fast-switching: if already showing, switch immediately
        if isShowing {
            action()
            return
        }

        dwellTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            self.dwellTask = nil
            action()
        }
    }

    public func cancelDwell(startGrace: Bool = true) {
        dwellTask?.cancel()
        dwellTask = nil
        if startGrace && !isPinned && isShowing {
            self.startGrace()
        }
    }

    public func startGrace() {
        guard !isPinned, isShowing else { return }
        let mouseLoc = NSEvent.mouseLocation
        if panel.isVisible && panel.frame.insetBy(dx: -4, dy: -4).contains(mouseLoc) {
            cancelGrace()
            return
        }
        if let parentFrame = activeState?.parentButtonFrame, parentFrame.insetBy(dx: -4, dy: -4).contains(mouseLoc) {
            cancelGrace()
            return
        }
        guard graceTask == nil else { return }
        graceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self.graceTask = nil
            self.hide()
        }
    }

    public func cancelGrace() {
        graceTask?.cancel()
        graceTask = nil
    }

    public func hide() {
        dwellTask?.cancel()
        dwellTask = nil
        cancelGrace()
        spaceRecoveryTask?.cancel()
        spaceRecoveryTask = nil
        spacePresentationID = UUID()
        guard isShowing || activeState != nil else { return }
        activeState = nil
        mainBarScreenFrame = nil
        SubBarHoverState.shared.location = nil
        panel.horizontalAnchor = .none
        panel.ignoresMouseEvents = false
        panel.orderOut(nil)
        panel.contentView = nil
        onDismiss?()
    }

    /// Whether a screen location is over interactive content (excluding the transparent shadow ring).
    public func isOverContent(_ screenLocation: CGPoint) -> Bool {
        guard panel.isVisible, panel.frame.contains(screenLocation), let contentView = panel.contentView else {
            return false
        }
        let windowPoint = panel.convertPoint(fromScreen: screenLocation)
        let contentPoint = contentView.convert(windowPoint, from: nil)
        if contentView is SubBarPanel.ContentView {
            return SubBarPanel.ContentView.isInsideClickableRegion(point: contentPoint, bounds: contentView.bounds)
        }
        return contentView.bounds.contains(contentPoint)
    }

    /// Resizes to content changes (e.g. pagination), keeping the horizontal anchor fixed.
    public func resizePanel(to proposedSize: CGSize, mouseLocation: CGPoint? = nil) {
        guard panel.isVisible else { return }
        let newWidth = max(proposedSize.width, PopupMetrics.actionButtonWidth)
        let newHeight = max(proposedSize.height, 30)
        let currentFrame = panel.frame
        guard abs(newWidth - currentFrame.width) > 0.5 || abs(newHeight - currentFrame.height) > 0.5 else { return }
        let newFrame = NSRect(x: currentFrame.origin.x, y: currentFrame.origin.y, width: newWidth, height: newHeight)
        panel.setFrame(newFrame, display: true)
        updateHoverLocation(at: mouseLocation)
    }

    /// Updates SubBarHoverState to the mouse position within the resized or moved window.
    public func updateHoverLocation(at screenLocation: CGPoint? = nil) {
        guard panel.isVisible, let contentView = panel.contentView else {
            SubBarHoverState.shared.location = nil
            return
        }
        let mouseLoc = screenLocation ?? NSEvent.mouseLocation
        let overContent = isOverContent(mouseLoc)
        if SubBarHoverState.shared.usesGlobalMouseMonitoring {
            panel.ignoresMouseEvents = !overContent
        }
        let windowPoint = panel.convertPoint(fromScreen: mouseLoc)
        let contentPoint = contentView.convert(windowPoint, from: nil)
        if contentView.bounds.contains(contentPoint) {
            let y = contentView.isFlipped ? contentPoint.y : contentView.bounds.height - contentPoint.y
            let point = CGPoint(x: contentPoint.x, y: y)
            if point != SubBarHoverState.shared.location {
                SubBarHoverState.shared.location = point
            }
        } else {
            SubBarHoverState.shared.location = nil
        }
    }
}

/// The inner content view rendered in SubBarPanel.
private struct SubBarContentView: View {
    let subActions: [any Action]
    let effectiveTheme: String
    let effectiveColorScheme: ColorScheme
    let scale: CGFloat
    let screenWidth: CGFloat?
    let context: ActionContext
    let presenter: any ActionPresenting
    let modeStore: PopupModeStore
    let onResult: @MainActor @Sendable (ActionResult) -> Void
    let onRunAI: @MainActor @Sendable (String) -> Void
    let onRunLoadingAction: @MainActor @Sendable (any Action, ActionResultDelivery.ClickIntent) -> Void
    let onWillPerformAction: @MainActor @Sendable (any Action, ActionResultDelivery.ClickIntent) -> Bool
    let onActionPerformed: @MainActor @Sendable (String) -> Void
    let onClickIntent: @MainActor @Sendable () -> ActionResultDelivery.ClickIntent
    let onHoverChange: @MainActor @Sendable (Bool) -> Void
    let onPaginationAnchor: (@MainActor (PopupPanel.HorizontalAnchor) -> Void)?
    let onContentSizeChange: (@MainActor (CGSize) -> Void)?
    /// Shows a sub-bar button's hover tooltip: (text, button frame in popupHoverSpace, theme token, isDark).
    let onShowTooltip: @MainActor (String, CGRect, String, Bool) -> Void
    /// Hides the screen-space hover tooltip.
    let onHideTooltip: @MainActor () -> Void

    @State private var currentPage: Int = 0
    private let hoverState: SubBarHoverState = .shared
    @State private var hoveredTarget: PopupHoverTarget? = nil
    @State private var tooltipPresenter = TooltipPresenter()
    @State private var hoverFrames: [PopupHoverTarget: CGRect] = [:]

    private var cornerRadius: CGFloat { PopupMetrics.popupCornerRadius * scale }

    var body: some View {
        let subBar = GroupSubActionBarView(
            subActions: subActions,
            currentPage: $currentPage,
            hoverState: hoverState,
            modeStore: modeStore,
            onResult: onResult,
            onRunAI: onRunAI,
            onRunLoadingAction: onRunLoadingAction,
            onWillPerformAction: onWillPerformAction,
            onActionPerformed: onActionPerformed,
            onClickIntent: onClickIntent,
            onHoverTarget: { target, isHovering in
                if isHovering {
                    hoveredTarget = target
                } else if hoveredTarget == target {
                    hoveredTarget = nil
                }
            },
            onPaginationAnchor: onPaginationAnchor,
            context: context,
            presenter: presenter,
            effectiveTheme: effectiveTheme,
            hoveredTarget: hoveredTarget,
            scale: scale,
            screenWidth: screenWidth
        )

        let styledSubBar = subBar
            .popupCardChrome(
                cornerRadius: cornerRadius,
                effectiveTheme: effectiveTheme,
                colorScheme: effectiveColorScheme
            )

        styledSubBar
            .environment(\.colorScheme, effectiveColorScheme)
            .environment(\.popupEffectiveTheme, effectiveTheme)
            .padding(PopupMetrics.popupShadowInset)
            .coordinateSpace(name: "popupHoverSpace")
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: PopupContentSizePreferenceKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(PopupHoverFramePreferenceKey.self) { frames in
                hoverFrames = frames
                updateHoveredTarget(for: hoverState.location)
            }
            .onPreferenceChange(PopupContentSizePreferenceKey.self) { size in
                MainActor.assumeIsolated {
                    guard size.width > 0, size.height > 0 else { return }
                    onContentSizeChange?(size)
                }
            }
            .onReceive(hoverState.$location) { location in
                updateHoveredTarget(for: location)
            }
        .contentShape(Rectangle())
        .onHover { isHovering in
            onHoverChange(isHovering)
        }
        .onChange(of: hoveredTarget) { _, newTarget in
            updateTooltip(for: newTarget)
        }
        .onDisappear {
            tooltipPresenter.reset { onHideTooltip() }
        }
    }

    private func updateHoveredTarget(for location: CGPoint?) {
        let target = location.flatMap { point in
            hoverFrames.first(where: { $0.value.contains(point) })?.key
        }
        guard target != hoveredTarget else { return }
        hoveredTarget = target
    }

    private func updateTooltip(for target: PopupHoverTarget?) {
        let resolved: (text: String, frame: CGRect)? = {
            guard let target, let frame = hoverFrames[target] else { return nil }
            let text: String? = {
                switch target {
                case .subAction(let index):
                    guard index < subActions.count else { return nil }
                    return subActions[index].displayTitle(using: presenter)
                case .chevron("chevron.left.sub"):
                    return String(localized: "Previous page")
                case .chevron("chevron.right.sub"):
                    return String(localized: "Next page")
                default:
                    return nil
                }
            }()
            guard let text else { return nil }
            return (text, frame)
        }()
        tooltipPresenter.update(
            text: resolved?.text,
            show: { [onShowTooltip, effectiveTheme, isDark = effectiveColorScheme == .dark] in
                guard let resolved else { return }
                onShowTooltip(resolved.text, resolved.frame, effectiveTheme, isDark)
            },
            hide: { [onHideTooltip] in
                onHideTooltip()
            }
        )
    }
}
