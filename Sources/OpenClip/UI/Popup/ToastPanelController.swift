// ToastPanelController.swift
// OpenClip
//
// Owns the ToastPanel + its NSHostingView(ToastView) and the auto-dismiss timer. The single
// status surface: replaces the removed inline banner. Info/error toasts auto-dismiss after
// `autoDismissNanoseconds` unless `keepVisible`; loading and keep-visible toasts have no timer
// and are cleared via swapTo/hide.
import AppKit
import SwiftUI
import Core

@MainActor
public final class ToastPanelController {
    public private(set) var currentFeedback: StatusFeedback?
    public private(set) var isLoading = false
    public var isShowing: Bool { panel.isVisible }
    /// The toast panel's current frame (screen coords). Internal for tests.
    var panelFrame: NSRect { panel.frame }
    /// The screen point the toast last anchored to (screen coords); nil when the toast fell back to
    /// the cursor. Internal for tests — lets tests assert a toast anchored to the popup, not cursor.
    var lastAnchorPoint: CGPoint? { _lastAnchorPoint }

    private let panel: ToastPanel
    private let autoDismissNanoseconds: UInt64
    private var dismissTask: Task<Void, Never>?
    private let hostingView: NSHostingView<ToastView>
    /// The screen point the toast should center on; nil falls back to the cursor.
    private var _lastAnchorPoint: CGPoint?

    public init(panel: ToastPanel = ToastPanel(),
                autoDismissNanoseconds: UInt64 = PopupMetrics.toastDurationNanoseconds) {
        self.panel = panel
        self.autoDismissNanoseconds = autoDismissNanoseconds
        let view = NSHostingView(rootView: ToastView(feedback: StatusFeedback(message: "", style: .info)))
        // Frame-based sizing: no `.preferredContentSize` (that option reports `fittingSize` as 0
        // and lets the window auto-size to a constrained measurement that truncates the message to
        // just the icon). We size the panel explicitly from `fittingSize` in `show`.
        self.hostingView = view
        // Wrap the hosting view in a plain container so the window's constraint engine never tracks
        // the SwiftUI content directly — an NSHostingView as a direct contentView that re-measures
        // during the display cycle triggers "marked as needing another Update Constraints in Window
        // pass" crashes.
        let container = NSView(frame: .zero)
        container.addSubview(view)
        self.panel.contentView = container
    }

    /// Shows (or replaces) a toast centered on an anchor point. Info/error toasts auto-dismiss
    /// unless `keepVisible`; loading and keep-visible toasts have no timer and are cleared via
    /// `swapTo`/`hide`. `anchorPoint` is the screen position the toast centers on; when nil the
    /// previous anchor is reused, and when there is none the cursor is used.
    public func show(_ feedback: StatusFeedback, anchorPoint: CGPoint? = nil) {
        dismissTask?.cancel()
        dismissTask = nil
        currentFeedback = feedback
        isLoading = feedback.isLoading
        if let anchorPoint { _lastAnchorPoint = anchorPoint }
        hostingView.rootView = ToastView(feedback: feedback)
        // Size from the freshly-set content, not a stale pre-layout measurement: without a layout
        // pass the hosting view reports a large default fitting size and the toast renders oversized.
        hostingView.layoutSubtreeIfNeeded()
        let fit = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: fit)
        panel.contentView?.frame = NSRect(origin: .zero, size: fit)
        place(at: fit)
        panel.orderFrontRegardless()
        if !feedback.isLoading && !feedback.keepVisible {
            startDismissal()
        }
    }

    /// Shows a loading (spinner) toast. Loading toasts have no timer and are cleared via
    /// `swapTo`/`hide`.
    public func showLoading(message: String, anchorPoint: CGPoint? = nil) {
        show(StatusFeedback(message: message, style: .info, isLoading: true), anchorPoint: anchorPoint)
    }

    /// Replaces a loading toast with a settled status. Info/error statuses auto-dismiss unless
    /// `keepVisible`; loading and keep-visible statuses have no timer and are cleared via a later
    /// `swapTo`/`hide`.
    public func swapTo(_ feedback: StatusFeedback) {
        show(feedback)
    }

    public func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        currentFeedback = nil
        isLoading = false
        panel.orderOut(nil)
    }

    private func startDismissal() {
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: autoDismissNanoseconds)
            guard !Task.isCancelled else { return }
            self.hide()
        }
    }

    /// Centers the toast on the anchor point (falling back to the cursor), clamped to the
    /// visible frame.
    private func place(at size: CGSize) {
        // Pick the screen from the anchor point (or the cursor when there is no anchor), never the
        // centered toast origin: near screen edges the toast origin can land on the wrong screen.
        let reference = _lastAnchorPoint ?? NSEvent.mouseLocation
        var origin = CGPoint(x: reference.x - size.width / 2, y: reference.y - size.height / 2)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(reference) }) ?? NSScreen.main {
            let vf = screen.visibleFrame
            origin.x = min(max(origin.x, vf.minX), vf.maxX - size.width)
            origin.y = min(max(origin.y, vf.minY), vf.maxY - size.height)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
