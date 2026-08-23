// ToastPanelController.swift
// OpenClip
//
// Owns the ToastPanel + its NSHostingView(ToastView) and the auto-dismiss timer. The single
// status surface: replaces the removed inline banner. Info/error toasts auto-dismiss after
// `autoDismissNanoseconds` unless `keepVisible`; loading and keep-visible toasts have no timer
// and are cleared via swapTo/hide.
//
// Toasts are linked to the popup that produced them: each show takes an anchor frame (the
// popup's screen frame) and the bubble attaches just below it — flipping above when there is no
// room below — clamped to the visible frame. There is deliberately no pointer fallback: an
// unanchored toast centers on the main screen rather than chasing the cursor.
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
    /// The popup frame the toast last anchored to (screen coords); nil when none was ever given.
    /// Internal for tests — lets tests assert a toast anchored to the popup, not the cursor.
    var lastAnchorFrame: NSRect? { _lastAnchorFrame }

    private let panel: ToastPanel
    private let autoDismissNanoseconds: UInt64
    private var dismissTask: Task<Void, Never>?
    private let hostingView: NSHostingView<ToastView>
    /// The popup frame the toast should attach to; nil falls back to main-screen centering.
    private var _lastAnchorFrame: NSRect?

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

    /// Shows (or replaces) a toast attached to the popup's frame. Info/error toasts auto-dismiss
    /// unless `keepVisible`; loading and keep-visible toasts have no timer and are cleared via
    /// `swapTo`/`hide`. `anchorFrame` is the popup's screen frame; when nil the previous anchor is
    /// reused, and with no anchor at all the toast centers on the main screen.
    public func show(_ feedback: StatusFeedback, anchorFrame: NSRect? = nil) {
        dismissTask?.cancel()
        dismissTask = nil
        currentFeedback = feedback
        isLoading = feedback.isLoading
        if let anchorFrame { _lastAnchorFrame = anchorFrame }
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
    public func showLoading(message: String, anchorFrame: NSRect? = nil) {
        show(StatusFeedback(message: message, style: .info, isLoading: true), anchorFrame: anchorFrame)
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

    /// Attaches the toast to the anchored popup frame: horizontally centered on it, sitting just
    /// below its bottom edge — flipping above its top edge when there is no room below — clamped
    /// to the visible frame.
    private func place(at size: CGSize) {
        guard let anchor = _lastAnchorFrame else {
            // No popup has anchored this session: center on the main screen. Deliberately never
            // the pointer — a toast is linked to the surface that produced it, not the cursor.
            centerOnScreen(size: size)
            return
        }
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let gap = PopupMetrics.toastAnchorGap
        var origin = CGPoint(x: anchor.midX - size.width / 2,
                             y: anchor.minY - size.height - gap)
        if origin.y < visible.minY {
            origin.y = anchor.maxY + gap
        }
        origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
        origin.y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func centerOnScreen(size: CGSize) {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let origin = CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
