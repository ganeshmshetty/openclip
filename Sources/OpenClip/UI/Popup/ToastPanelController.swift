// ToastPanelController.swift
// OpenClip
//
// Owns the ToastPanel + its NSHostingView(ToastView) and the auto-dismiss timer. The single
// status surface: replaces the removed inline banner. Info/error toasts auto-dismiss after
// `autoDismissNanoseconds` unless `keepVisible`; loading and keep-visible toasts have no timer
// and are cleared via swapTo/hide.
//
// Toasts are linked to the popup that produced them: each show takes an anchor frame (the
// popup's screen frame) and the bubble centers directly in-place over that frame, clamped
// to the visible frame. There is deliberately no pointer fallback: an unanchored toast
// centers on the main screen rather than chasing the cursor.
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
    /// The toast panel's mouse event pass-through state. Internal for tests.
    var panelIgnoresMouseEvents: Bool { panel.ignoresMouseEvents }

    private let panel: ToastPanel
    private let autoDismissNanoseconds: UInt64
    private var dismissTask: Task<Void, Never>?
    private let hostingView: ToastHostingView
    /// The popup frame the toast should attach to; nil falls back to main-screen centering.
    private var _lastAnchorFrame: NSRect?

    public init(panel: ToastPanel = ToastPanel(),
                autoDismissNanoseconds: UInt64 = PopupMetrics.toastDurationNanoseconds) {
        self.panel = panel
        self.autoDismissNanoseconds = autoDismissNanoseconds
        let view = ToastHostingView(rootView: ToastView(feedback: StatusFeedback(message: "", style: .info)))
        // Frame-based sizing: no `.preferredContentSize` (that option reports `fittingSize` as 0
        // and lets the window auto-size to a constrained measurement that truncates the message to
        // just the icon). We size the panel explicitly from `fittingSize` in `show`.
        self.hostingView = view
        // Wrap the hosting view in a plain container so the window's constraint engine never tracks
        // the SwiftUI content directly — an NSHostingView as a direct contentView that re-measures
        // during the display cycle triggers "marked as needing another Update Constraints in Window
        // pass" crashes.
        let container = ToastContainerView(frame: .zero)
        container.addSubview(view)
        self.panel.contentView = container
    }

    /// Shows (or replaces) a toast attached to the popup's frame. Info/error toasts auto-dismiss
    /// unless `keepVisible`; loading and keep-visible toasts have no timer and are cleared via
    /// `swapTo`/`hide`. `anchorFrame` is the popup's screen frame; when nil the previous anchor is
    /// reused, and with no anchor at all the toast centers on the main screen.
    public func show(_ feedback: StatusFeedback, anchorFrame: NSRect? = nil, onCancel: (() -> Void)? = nil) {
        dismissTask?.cancel()
        dismissTask = nil
        currentFeedback = feedback
        isLoading = feedback.isLoading
        if let anchorFrame { _lastAnchorFrame = anchorFrame }

        let isInteractive = feedback.isLoading && onCancel != nil
        let fit: CGSize
        if isInteractive {
            let scale = PopupMetrics.scaleMultiplier(for: DefaultSettingsStore.shared.get(SettingKey.popupScale))
            let font = NSFont.systemFont(ofSize: 11 * scale, weight: .regular)
            let normalTextWidth = (feedback.message as NSString).size(withAttributes: [.font: font]).width
            let cancelText = String(localized: "Cancel Task")
            let cancelTextWidth = (cancelText as NSString).size(withAttributes: [.font: font]).width

            hostingView.rootView = ToastView(feedback: feedback, onCancel: onCancel)
            hostingView.layoutSubtreeIfNeeded()
            let baseFit = hostingView.fittingSize

            let textDelta: CGFloat = max(0.0, ceil(cancelTextWidth - normalTextWidth))
            let targetWidth = baseFit.width + textDelta
            fit = CGSize(width: targetWidth, height: baseFit.height)

            hostingView.rootView = ToastView(feedback: feedback, onCancel: onCancel, reservedWidth: targetWidth)
            hostingView.layoutSubtreeIfNeeded()
        } else {
            hostingView.rootView = ToastView(feedback: feedback)
            hostingView.layoutSubtreeIfNeeded()
            fit = hostingView.fittingSize
        }

        // When interactive, size the panel directly to the bubble (inset = 0) so clicks in the
        // shadow ring genuinely pass through to underlying applications without being swallowed.
        // For passive toasts (ignoresMouseEvents = true), inflate by toastShadowInset for the drop shadow.
        let inset = isInteractive ? 0 : PopupMetrics.toastShadowInset
        hostingView.frame = NSRect(x: inset, y: inset, width: fit.width, height: fit.height)
        panel.contentView?.frame = NSRect(origin: .zero,
                                          size: NSSize(width: fit.width + inset * 2,
                                                       height: fit.height + inset * 2))
        place(at: fit, inset: inset)
        panel.ignoresMouseEvents = !isInteractive
        panel.orderFrontRegardless()
        if !feedback.isLoading && !feedback.keepVisible {
            startDismissal()
        }
    }

    /// Shows a loading (spinner) toast. Loading toasts have no timer and are cleared via
    /// `swapTo`/`hide`. When `onCancel` is provided, the toast becomes interactive and clicking
    /// invokes the callback.
    public func showLoading(message: String, anchorFrame: NSRect? = nil, onCancel: (() -> Void)? = nil) {
        show(StatusFeedback(message: message, style: .info, isLoading: true), anchorFrame: anchorFrame, onCancel: onCancel)
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
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
    }

    private func startDismissal() {
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: autoDismissNanoseconds)
            guard !Task.isCancelled else { return }
            self.hide()
        }
    }

    /// Centers the toast directly over the anchored popup frame (horizontally and vertically),
    /// clamped to the visible frame. `size` is the bubble's size; the window frame adds the
    /// `toastShadowInset` ring around it when non-interactive.
    private func place(at size: CGSize, inset: CGFloat) {
        guard let anchor = _lastAnchorFrame else {
            centerOnScreen(size: size, inset: inset)
            return
        }
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        var origin = CGPoint(x: anchor.midX - size.width / 2,
                             y: anchor.midY - size.height / 2)
        origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
        origin.y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        setPanelFrame(contentOrigin: origin, contentSize: size, inset: inset)
    }

    private func centerOnScreen(size: CGSize, inset: CGFloat) {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
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

/// Plain container view hosting the toast view. Insets hit-testing so clicks in the shadow ring
/// fall through to underlying applications.
final class ToastContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        // If the hit point is this container itself (outside any subviews in the shadow inset ring),
        // return nil so clicks pass through to underlying windows.
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

