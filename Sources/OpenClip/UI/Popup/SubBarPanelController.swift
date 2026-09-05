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
    public let panel: SubBarPanel
    private var hostingView: NSHostingView<AnyView>?
    private var graceTask: Task<Void, Never>?
    private var dwellTask: Task<Void, Never>?
    public private(set) var activeState: ActiveSubGroupState?
    public var isShowing: Bool { panel.isVisible }
    public var isPinned: Bool { activeState?.isPinned == true }
    public var panelFrame: NSRect { panel.frame }
    /// Called when the sub-bar hides so parent state (like active button highlight) is dismissed immediately.
    public var onDismiss: (@MainActor @Sendable () -> Void)?

    public init(panel: SubBarPanel = SubBarPanel()) {
        self.panel = panel
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
        onResult: @escaping @MainActor @Sendable (ActionResult) -> Void,
        onRunAI: @escaping @MainActor @Sendable (String) -> Void,
        onRunLoadingAction: @escaping @MainActor @Sendable (any Action) -> Void,
        onWillPerformAction: @escaping @MainActor @Sendable (any Action) -> Void,
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

        let state = ActiveSubGroupState(
            groupID: groupAction.id,
            parentIndex: parentIndex,
            subActionIDs: subActions.map(\.id),
            isPinned: isPinned,
            parentButtonFrame: parentButtonScreenFrame
        )
        self.activeState = state
        panel.horizontalAnchor = .none

        let contentView = SubBarContentView(
            subActions: subActions,
            effectiveTheme: effectiveTheme,
            effectiveColorScheme: effectiveColorScheme,
            scale: scale,
            context: context,
            presenter: presenter,
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
            }
        )

        let hosting = SubBarPanel.ContentView(rootView: AnyView(contentView))
        self.hostingView = hosting
        panel.contentView = hosting
        hosting.layoutSubtreeIfNeeded()

        let fit = hosting.fittingSize
        let panelWidth = max(fit.width, PopupMetrics.actionButtonWidth)
        let panelHeight = max(fit.height, 30)

        // Horizontal positioning:
        // Anchors left to parent button, and pulls leftward towards the main bar body when
        // the sub-bar overhangs significantly past the main bar's right edge.
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
                // Ensure the sub-bar doesn't shift past the main bar's left edge or uncover the parent button
                let minAllowedX = max(mainBarContent.minX, parentButtonScreenFrame.maxX - contentWidth)
                contentX = max(minAllowedX, candidateX)
            }
        }

        let panelX = contentX - shadowInset

        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: parentButtonScreenFrame.midX, y: parentButtonScreenFrame.midY)) } ?? NSScreen.main
        let screenBounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let minX = screenBounds.minX + PopupMetrics.popupPadding
        let maxX = max(minX, screenBounds.maxX - panelWidth - PopupMetrics.popupPadding)
        let clampedX = max(minX, min(panelX, maxX))

        // Vertical positioning: 6pt visual gap from the main bar's button
        // Prefers opening in the same direction as the main bar (away from selected text),
        // but flips if constrained by the screen boundaries.
        let preferAbove = mainBarAbove ?? searchResultsAbove
        let yAbove = parentButtonScreenFrame.maxY + 6 - shadowInset
        let yBelow = parentButtonScreenFrame.minY - 6 + shadowInset - panelHeight
        let padding = PopupMetrics.popupPadding

        let panelY: CGFloat
        if preferAbove {
            if yAbove + panelHeight <= screenBounds.maxY - padding {
                panelY = yAbove
            } else if yBelow >= screenBounds.minY + padding {
                panelY = yBelow
            } else {
                panelY = yAbove
            }
        } else {
            if yBelow >= screenBounds.minY + padding {
                panelY = yBelow
            } else if yAbove + panelHeight <= screenBounds.maxY - padding {
                panelY = yAbove
            } else {
                panelY = yBelow
            }
        }

        panel.setFrame(NSRect(x: clampedX, y: panelY, width: panelWidth, height: panelHeight), display: true)
        panel.orderFront(nil)
        return panelY == yAbove
    }

    /// Pin the current active sub-bar so it stays open until explicitly closed or an action runs.
    public func pin() {
        if let current = activeState {
            activeState = current.pinned()
            cancelGrace()
        }
    }

    /// Whether an action index on the main bar is an immediate neighbor of the active parent action (within 1 position).
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
        guard isShowing || activeState != nil else { return }
        activeState = nil
        SubBarHoverState.shared.location = nil
        panel.horizontalAnchor = .none
        panel.ignoresMouseEvents = false
        panel.orderOut(nil)
        panel.contentView = nil
        onDismiss?()
    }

    /// Checks if a screen location is over interactive sub-bar content (excluding transparent shadow ring).
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
}

/// The inner content view rendered in SubBarPanel.
private struct SubBarContentView: View {
    let subActions: [any Action]
    let effectiveTheme: String
    let effectiveColorScheme: ColorScheme
    let scale: CGFloat
    let context: ActionContext
    let presenter: any ActionPresenting
    let onResult: @MainActor @Sendable (ActionResult) -> Void
    let onRunAI: @MainActor @Sendable (String) -> Void
    let onRunLoadingAction: @MainActor @Sendable (any Action) -> Void
    let onWillPerformAction: @MainActor @Sendable (any Action) -> Void
    let onActionPerformed: @MainActor @Sendable (String) -> Void
    let onClickIntent: @MainActor @Sendable () -> ActionResultDelivery.ClickIntent
    let onHoverChange: @MainActor @Sendable (Bool) -> Void
    let onPaginationAnchor: (@MainActor (PopupPanel.HorizontalAnchor) -> Void)?

    @State private var currentPage: Int = 0
    private let hoverState: SubBarHoverState = .shared
    @State private var hoveredTarget: PopupHoverTarget? = nil
    @State private var activeTooltip: (text: String, frame: CGRect)? = nil
    @State private var isTooltipHot: Bool = false
    @State private var tooltipTask: Task<Void, Never>? = nil
    @State private var hoverFrames: [PopupHoverTarget: CGRect] = [:]

    private var cornerRadius: CGFloat { PopupMetrics.popupCornerRadius * scale }

    var body: some View {
        let subBar = GroupSubActionBarView(
            subActions: subActions,
            currentPage: $currentPage,
            hoverState: hoverState,
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
            scale: scale
        )

        let styledSubBar = Group {
            if effectiveTheme == "glass" {
                subBar
                    .layeredGlassSurface(cornerRadius: cornerRadius, colorScheme: effectiveColorScheme)
            } else {
                subBar
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(effectiveTheme == "dark" ? Color(red: 0.20, green: 0.20, blue: 0.22) : Color(red: 0.91, green: 0.91, blue: 0.93))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(effectiveTheme == "light" ? Color.black.opacity(0.20) : Color.white.opacity(0.22), lineWidth: 1.0)
                    )
                    .shadow(color: Color.black.opacity(effectiveTheme == "light" ? 0.16 : 0.32), radius: 6, x: 0, y: 3)
            }
        }

        styledSubBar
            .environment(\.colorScheme, effectiveColorScheme)
            .environment(\.popupEffectiveTheme, effectiveTheme)
            .padding(PopupMetrics.popupShadowInset)
        .coordinateSpace(name: "popupHoverSpace")
        .onPreferenceChange(PopupHoverFramePreferenceKey.self) { frames in
            hoverFrames = frames
            updateHoveredTarget(for: hoverState.location)
        }
        .onReceive(hoverState.$location) { location in
            updateHoveredTarget(for: location)
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { geo in
                if let tooltip = activeTooltip {
                    PopupTooltipContainer(
                        text: tooltip.text,
                        targetFrame: tooltip.frame,
                        containerWidth: geo.size.width,
                        effectiveTheme: effectiveTheme,
                        isDark: effectiveColorScheme == .dark
                    )
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onHover { isHovering in
            onHoverChange(isHovering)
        }
        .onChange(of: hoveredTarget) { _, newTarget in
            updateTooltip(for: newTarget)
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
        tooltipTask?.cancel()
        guard let target, let frame = hoverFrames[target] else {
            withAnimation(.easeOut(duration: 0.1)) {
                activeTooltip = nil
            }
            tooltipTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                isTooltipHot = false
            }
            return
        }

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

        guard let text else { return }

        if isTooltipHot {
            withAnimation(.easeInOut(duration: 0.1)) {
                activeTooltip = (text: text, frame: frame)
            }
        } else {
            tooltipTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                isTooltipHot = true
                withAnimation(.easeOut(duration: 0.15)) {
                    activeTooltip = (text: text, frame: frame)
                }
            }
        }
    }
}
