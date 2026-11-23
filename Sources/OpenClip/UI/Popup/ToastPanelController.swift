// ToastPanelController.swift
// OpenClip
//
// Owns the ToastPanel, its hosting view, and the auto-dismiss timer. Info/error toasts auto-dismiss
// after `autoDismissNanoseconds` unless `keepVisible`; loading and keep-visible toasts have no timer.
// An auto-dismissing toast pauses while the pointer rests on it and resumes the remaining time on leave.
//
// Toasts stay near the pointer captured when shown, above it where possible and clear of the bars.
// Loading completion keeps the same position.
import AppKit
import SwiftUI
import Core

public enum ToastPlacement: Sendable, Equatable {
    case overlay
    case above
    case nearCursor(CGPoint)
}

@MainActor
public final class ToastPanelController {
    private(set) var presentationID: UUID?
    private let cursorLocation: @MainActor () -> CGPoint
    public private(set) var currentPlacement: ToastPlacement = .overlay
    private var avoidanceRects: [CGRect] = []
    public private(set) var currentFeedback: StatusFeedback?
    public private(set) var isLoading = false
    private var _isShowing = false
    public var isShowing: Bool {
        if NSClassFromString("XCTestCase") != nil {
            return _isShowing
        }
        return panel.isVisible
    }
    /// The toast panel's current frame (screen coords).
    var panelFrame: NSRect { panel.frame }
    /// The popup avoidance frame, independent of the cursor position.
    var lastAnchorFrame: NSRect? { _lastAnchorFrame }
    /// The panel's mouse event pass-through state.
    var panelIgnoresMouseEvents: Bool { panel.ignoresMouseEvents }
    /// The feedback configured in the root hosting view.
    var rootFeedback: StatusFeedback { hostingView.rootView.feedback }

    private var panel: ToastPanel
    private var visibilityCheckTask: Task<Void, Never>?
    private var didAttemptSpaceRecovery = false
    private let autoDismissNanoseconds: UInt64
    /// Whether an auto-dismiss is pending (nil once it fires, is cancelled by hover, or cleared by `hide`).
    var hasPendingDismissal: Bool { dismissTask != nil }
    private var dismissTask: Task<Void, Never>?
    /// When a dismissible toast should disappear. Hover cancels the task but keeps this, so leaving resumes the time left.
    private var dismissalDeadline: Date?
    private let hostingView: ToastHostingView
    /// Optional popup avoidance frame, retained while a loading toast settles.
    private var _lastAnchorFrame: NSRect?

    public init(panel: ToastPanel = ToastPanel(),
                autoDismissNanoseconds: UInt64 = PopupMetrics.toastDurationNanoseconds,
                cursorLocation: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation }) {
        self.panel = panel
        self.autoDismissNanoseconds = autoDismissNanoseconds
        self.cursorLocation = cursorLocation
        let view = ToastHostingView(rootView: ToastView(feedback: StatusFeedback(message: "", style: .info)))
        // Frame-based sizing: `.preferredContentSize` reports fittingSize as 0 and truncates the message.
        self.hostingView = view
        // Plain container: the window's constraint engine must not track SwiftUI content directly.
        let container = ToastContainerView(frame: .zero)
        container.addSubview(view)
        self.panel.contentView = container
    }

    /// Shows feedback near the cursor; a settled loading result keeps its original position.
    public func show(_ feedback: StatusFeedback, anchorFrame: NSRect? = nil,
                     placement: ToastPlacement? = nil, avoidanceRects: [CGRect] = [],
                     onCancel: (() -> Void)? = nil) {
        let finishesLoading = isShowing && isLoading && !feedback.isLoading && placement == nil
        let resolvedPlacement = placement ?? (finishesLoading ? currentPlacement : .nearCursor(cursorLocation()))
        dismissTask?.cancel()
        dismissTask = nil
        visibilityCheckTask?.cancel()
        visibilityCheckTask = nil
        didAttemptSpaceRecovery = false
        presentationID = UUID()
        currentFeedback = feedback
        currentPlacement = resolvedPlacement
        self.avoidanceRects = avoidanceRects
        isLoading = feedback.isLoading
        if let anchorFrame {
            _lastAnchorFrame = anchorFrame
        } else if !finishesLoading {
            _lastAnchorFrame = nil
        }

        let isInteractive = feedback.isLoading && onCancel != nil
        // Timed toasts accept pointer events so the cursor can hold them; interactive loading toasts accept them to cancel.
        let isDismissible = !feedback.isLoading && !feedback.keepVisible
        let hoverRelay: (Bool) -> Void = { [weak self] hovering in self?.handleHover(hovering) }
        let fit: CGSize
        if isInteractive {
            let scale = PopupMetrics.scaleMultiplier(for: DefaultSettingsStore.shared.get(SettingKey.popupScale))
            let font = NSFont.systemFont(ofSize: 11 * scale, weight: .regular)
            let formattedMessage = ToastView.formatMessage(feedback.message)
            let normalTextWidth = (formattedMessage as NSString).size(withAttributes: [.font: font]).width
            let cancelText = String(localized: "Cancel Task")
            let cancelTextWidth = (cancelText as NSString).size(withAttributes: [.font: font]).width

            hostingView.rootView = ToastView(feedback: feedback, onCancel: onCancel, onHover: hoverRelay)
            hostingView.layoutSubtreeIfNeeded()
            let baseFit = hostingView.fittingSize

            let textDelta: CGFloat = max(0.0, ceil(cancelTextWidth - normalTextWidth))
            let targetWidth = baseFit.width + textDelta
            fit = CGSize(width: targetWidth, height: baseFit.height)

            hostingView.rootView = ToastView(feedback: feedback, onCancel: onCancel, reservedWidth: targetWidth, onHover: hoverRelay)
            hostingView.layoutSubtreeIfNeeded()
        } else {
            hostingView.rootView = ToastView(feedback: feedback, onHover: hoverRelay)
            hostingView.layoutSubtreeIfNeeded()
            fit = hostingView.fittingSize
        }

        // Every toast keeps transparent inset space for its SwiftUI shadow, even when interactive.
        let inset = PopupMetrics.toastShadowInset
        hostingView.frame = NSRect(x: inset, y: inset, width: fit.width, height: fit.height)
        panel.contentView?.frame = NSRect(origin: .zero,
                                          size: NSSize(width: fit.width + inset * 2,
                                                       height: fit.height + inset * 2))
        place(at: fit, inset: inset)
        panel.ignoresMouseEvents = !(isInteractive || isDismissible)
        _isShowing = true
        if NSClassFromString("XCTestCase") == nil {
            panel.orderFrontRegardless()
            scheduleVisibilityCheck()
        }
        if !feedback.isLoading && !feedback.keepVisible {
            startDismissal()
        }
    }

    /// Shows a spinner toast with no timer, cleared by `swapTo`/`hide`. A non-nil `onCancel` makes it clickable.
    public func showLoading(message: String, anchorFrame: NSRect? = nil, onCancel: (() -> Void)? = nil) {
        show(StatusFeedback(message: message, style: .info, isLoading: true), anchorFrame: anchorFrame, onCancel: onCancel)
    }

    /// Replaces a loading toast with a settled status; info/error auto-dismiss unless `keepVisible`.
    public func swapTo(_ feedback: StatusFeedback) {
        show(feedback, anchorFrame: _lastAnchorFrame, placement: isShowing ? currentPlacement : nil,
             avoidanceRects: avoidanceRects)
    }

    public func hide() {
        visibilityCheckTask?.cancel()
        visibilityCheckTask = nil
        dismissTask?.cancel()
        dismissTask = nil
        dismissalDeadline = nil
        currentFeedback = nil
        presentationID = nil
        currentPlacement = .overlay
        avoidanceRects = []
        isLoading = false
        _isShowing = false
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
        hostingView.rootView = ToastView(feedback: StatusFeedback(message: "", style: .info))
    }

    private func scheduleVisibilityCheck() {
        guard let id = presentationID else { return }
        visibilityCheckTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) }
            catch { return }
            self?.recoverToastSpaceIfNeeded(for: id)
        }
    }

    /// A reused window can keep stale Space membership; swap in a fresh panel once, keeping content and frame.
    @discardableResult
    func recoverToastSpaceIfNeeded(for id: UUID, makePanel: () -> ToastPanel = { ToastPanel() }) -> Bool {
        guard presentationID == id, _isShowing, !didAttemptSpaceRecovery,
              !panel.isKeyWindow, !panel.isVisible || !panel.isOnActiveSpace else { return false }
        didAttemptSpaceRecovery = true
        Log.presentation.notice("Recovering toast window visible=\(panel.isVisible, privacy: .public) activeSpace=\(panel.isOnActiveSpace, privacy: .public)")
        let frame = panel.frame
        let content = panel.contentView
        let replacement = makePanel()
        replacement.appearance = panel.appearance
        replacement.ignoresMouseEvents = panel.ignoresMouseEvents
        panel.orderOut(nil)
        panel.contentView = nil
        panel = replacement
        replacement.contentView = content
        replacement.setFrame(frame, display: false)
        replacement.orderFrontRegardless()
        return true
    }

    /// Starts a fresh auto-dismiss window from `autoDismissNanoseconds`.
    private func startDismissal() {
        dismissalDeadline = Date().addingTimeInterval(TimeInterval(autoDismissNanoseconds) / 1_000_000_000)
        scheduleDismissal()
    }

    /// Hides at the deadline, or immediately if it already passed while hovered.
    private func scheduleDismissal() {
        dismissTask?.cancel()
        dismissTask = nil
        guard let deadline = dismissalDeadline else { return }
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else {
            hide()
            return
        }
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.hide()
        }
    }

    /// Hover pauses the countdown; leaving resumes the remaining time. No-op for loading and keep-visible toasts.
    func handleHover(_ hovering: Bool) {
        guard _isShowing, !isLoading, currentFeedback?.keepVisible != true else { return }
        if hovering {
            dismissTask?.cancel()
            dismissTask = nil
        } else {
            scheduleDismissal()
        }
    }

    /// Positions the separate window using its stored cursor position, even without a popup.
    private func place(at size: CGSize, inset: CGFloat) {
        let screen: NSScreen?
        if case .nearCursor(let cursor) = currentPlacement {
            screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        } else if let anchor = _lastAnchorFrame {
            screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) || $0.frame.intersects(anchor) } ?? NSScreen.main
        } else {
            centerOnScreen(size: size, inset: inset)
            return
        }
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let origin = Self.contentOrigin(size: size, anchor: _lastAnchorFrame ?? .zero, visible: visible,
                                       placement: currentPlacement, avoidanceRects: avoidanceRects)
        setPanelFrame(contentOrigin: origin, contentSize: size, inset: inset)
    }

    /// Repositions the existing window without restarting its timer or changing its content.
    func reposition(anchorFrame: NSRect, avoidanceRects: [CGRect] = []) {
        guard isShowing else { return }
        _lastAnchorFrame = anchorFrame
        self.avoidanceRects = avoidanceRects
        place(at: hostingView.frame.size, inset: PopupMetrics.toastShadowInset)
    }

    static func contentOrigin(size: CGSize, anchor: CGRect, visible: CGRect,
                              placement: ToastPlacement, avoidanceRects: [CGRect] = []) -> CGPoint {
        if case .nearCursor(let cursor) = placement {
            return nearCursorOrigin(size: size, cursor: cursor, visible: visible,
                                    obstacles: [anchor] + avoidanceRects)
        }
        var origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.midY - size.height / 2)
        if placement == .above {
            origin.y = anchor.maxY - PopupMetrics.popupShadowInset + PopupMetrics.captureStatusGap
            for rect in avoidanceRects.sorted(by: { $0.minY < $1.minY }) {
                let content = rect.insetBy(dx: PopupMetrics.popupShadowInset, dy: PopupMetrics.popupShadowInset)
                if CGRect(origin: origin, size: size).intersects(content) {
                    origin.y = content.maxY + PopupMetrics.captureStatusGap
                }
            }
        }
        origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
        origin.y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        return origin
    }

    /// Prefer just above the captured pointer position, then the nearest clear side.
    private static func nearCursorOrigin(size: CGSize, cursor: CGPoint, visible: CGRect,
                                         obstacles: [CGRect]) -> CGPoint {
        let gap: CGFloat = 12
        let bounds = visible.insetBy(dx: PopupMetrics.toastShadowInset, dy: PopupMetrics.toastShadowInset)
        let contentRects = obstacles.filter { !$0.isEmpty && !$0.isNull }.map {
            $0.insetBy(dx: PopupMetrics.popupShadowInset, dy: PopupMetrics.popupShadowInset)
                .insetBy(dx: -4, dy: -4)
        }
        func clamp(_ point: CGPoint) -> CGPoint {
            CGPoint(x: min(max(point.x, bounds.minX), max(bounds.minX, bounds.maxX - size.width)),
                    y: min(max(point.y, bounds.minY), max(bounds.minY, bounds.maxY - size.height)))
        }
        func isClear(_ point: CGPoint) -> Bool {
            let frame = CGRect(origin: point, size: size)
            return !frame.insetBy(dx: -4, dy: -4).contains(cursor)
                && !contentRects.contains { $0.intersects(frame) }
        }
        var candidates = [
            CGPoint(x: cursor.x - size.width / 2, y: cursor.y + gap),
            CGPoint(x: cursor.x - size.width / 2, y: cursor.y - gap - size.height),
            CGPoint(x: cursor.x + gap, y: cursor.y - size.height / 2),
            CGPoint(x: cursor.x - gap - size.width, y: cursor.y - size.height / 2)
        ].map(clamp)
        if let above = candidates.first, above.y >= cursor.y + gap, isClear(above) { return above }
        var alternatives: [CGPoint] = []
        for rect in contentRects {
            alternatives.append(CGPoint(x: cursor.x - size.width / 2, y: rect.maxY + gap))
            alternatives.append(CGPoint(x: cursor.x - size.width / 2, y: rect.minY - gap - size.height))
            alternatives.append(CGPoint(x: rect.maxX + gap, y: cursor.y - size.height / 2))
            alternatives.append(CGPoint(x: rect.minX - gap - size.width, y: cursor.y - size.height / 2))
        }
        func distance(_ point: CGPoint) -> CGFloat {
            hypot(point.x + size.width / 2 - cursor.x, point.y + size.height / 2 - cursor.y)
        }
        alternatives = alternatives.map(clamp)
        alternatives.sort { distance($0) < distance($1) }
        // Prefer clearing the bar above over falling back below the pointer; stay near the pointer.
        if let above = alternatives.first(where: {
            $0.y >= cursor.y + gap && distance($0) <= PopupMetrics.toastPreferredAboveDistance && isClear($0)
        }) { return above }
        if let clear = candidates.first(where: isClear) { return clear }
        if let clear = alternatives.first(where: isClear) { return clear }
        candidates += alternatives
        // Extremely constrained screens: minimize overlap while keeping the bubble onscreen.
        func overlap(_ point: CGPoint) -> CGFloat {
            contentRects.reduce(0) { total, rect in
                let intersection = CGRect(origin: point, size: size).intersection(rect)
                return total + (intersection.isNull ? 0 : intersection.width * intersection.height)
            }
        }
        return candidates.min { overlap($0) < overlap($1) } ?? clamp(cursor)
    }

    private func centerOnScreen(size: CGSize, inset: CGFloat) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let origin = CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        setPanelFrame(contentOrigin: origin, contentSize: size, inset: inset)
    }

    /// Frames the panel around a bubble at `contentOrigin`, expanding by `inset` on every side.
    private func setPanelFrame(contentOrigin: CGPoint, contentSize: CGSize, inset: CGFloat) {
        panel.setFrame(NSRect(x: contentOrigin.x - inset,
                              y: contentOrigin.y - inset,
                              width: contentSize.width + inset * 2,
                              height: contentSize.height + inset * 2),
                       display: true)
    }
}

/// Plain container view hosting the toast view. Excludes the shadow ring from view hit-testing.
final class ToastContainerView: NSView {
    /// Accessibility hit-testing resolves elements on a helper thread, so this override must not
    /// assert the main actor: a background caller gets no view instead of trapping.
    override nonisolated func hitTest(_ point: NSPoint) -> NSView? {
        guard Thread.isMainThread else { return nil }
        return MainActor.assumeIsolated { self.hitTestOnMainThread(point) }
    }

    private func hitTestOnMainThread(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        // A hit on the container itself (the shadow ring) must not activate the toast.
        if view === self {
            return nil
        }
        return view
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

/// Hosting view subclass that accepts first mouse click so clicks on the non-key panel register immediately.
final class ToastHostingView: NSHostingView<ToastView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

