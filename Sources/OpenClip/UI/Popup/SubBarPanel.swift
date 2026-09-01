// SubBarPanel.swift
// OpenClip
//
// Defines a floating NSPanel subclass configured for the horizontal group sub-bar.
// Non-activating, borderless, popUpMenu level, never key, with mouse events enabled.
import AppKit
import SwiftUI
import Core

@MainActor
public final class SubBarPanel: NSPanel {
    public init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.level = .popUpMenu
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.isMovable = false
        self.hidesOnDeactivate = false
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    /// Root content view of the sub-bar panel. Excludes the shadow inset ring from mouse clicks.
    public final class ContentView: NSHostingView<AnyView> {
        public static func isInsideClickableRegion(point: NSPoint, bounds: NSRect) -> Bool {
            bounds.insetBy(dx: PopupMetrics.popupShadowInset, dy: PopupMetrics.popupShadowInset).contains(point)
        }

        public override func isMousePoint(_ point: NSPoint, in rect: NSRect) -> Bool {
            Self.isInsideClickableRegion(point: point, bounds: bounds)
        }
    }
}
