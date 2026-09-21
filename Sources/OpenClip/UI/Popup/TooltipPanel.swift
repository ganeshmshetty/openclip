// TooltipPanel.swift
// OpenClip
//
// Defines the floating NSPanel subclass hosting the hover tooltip. Rendered in its own window
// (above the popup and sub-bar panels) so the tooltip escapes each bar panel's clipping — it can
// flip above/below the hovered bar and avoid the expanded sub-bar instead of being squeezed on
// top of the bar's own buttons. Purely passive: always ignores mouse events.
import AppKit
import SwiftUI
import Core

@MainActor
public final class TooltipPanel: NSPanel {
    /// Sits above the popup/sub-bar panels (both `.popUpMenu`) so the tooltip is never occluded
    /// by the surfaces it is annotating or avoiding.
    public static let windowLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)) + 1)

    public init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.level = Self.windowLevel
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false   // SwiftUI draws its own shadow inside the inset ring
        self.ignoresMouseEvents = true
        self.acceptsMouseMovedEvents = false
        self.isMovable = false
        self.hidesOnDeactivate = false
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}

/// Plain container hosting the tooltip view inside a transparent shadow-inset ring, mirroring
/// ToastPanelController's container so the window's constraint engine never tracks the SwiftUI
/// content directly. The panel ignores mouse events entirely, so the ring cannot swallow clicks.
final class TooltipContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }
}

final class TooltipHostingView: NSHostingView<PopupTooltipView> {}
