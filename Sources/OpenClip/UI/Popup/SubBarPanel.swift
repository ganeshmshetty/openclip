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
    /// Controls how horizontal width changes anchor the sub-bar window (e.g. .right for pagination).
    public var horizontalAnchor: PopupPanel.HorizontalAnchor = .none

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

    override public func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var clamped = frameRect
        let activeScreenFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        if let screenFrame = activeScreenFrame {
            let maxWidth = max(0, screenFrame.width - PopupMetrics.popupPadding * 2)
            clamped.size.width = min(clamped.size.width, maxWidth)
        }

        if self.frame.width > 0, horizontalAnchor != .none, clamped.width != self.frame.width {
            let unconstrainedX: CGFloat
            switch horizontalAnchor {
            case .none:
                unconstrainedX = clamped.origin.x
            case .center:
                unconstrainedX = self.frame.midX - clamped.width / 2
            case .left:
                unconstrainedX = self.frame.minX
            case .right:
                unconstrainedX = self.frame.maxX - clamped.width
            }

            if let screenFrame = activeScreenFrame {
                let padding = PopupMetrics.popupPadding
                let minX = screenFrame.minX + padding
                let maxX = screenFrame.maxX - clamped.width - padding
                if maxX >= minX {
                    clamped.origin.x = max(minX, min(unconstrainedX, maxX))
                } else {
                    clamped.origin.x = minX
                }
            } else {
                clamped.origin.x = unconstrainedX
            }
        }

        super.setFrame(clamped, display: flag)
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    /// Root content view of the sub-bar panel. Excludes the shadow inset ring from mouse clicks.
    public final class ContentView: NSHostingView<AnyView> {
        private var trackingAreaRef: NSTrackingArea?

        public static func isInsideClickableRegion(point: NSPoint, bounds: NSRect) -> Bool {
            bounds.insetBy(dx: PopupMetrics.popupShadowInset, dy: PopupMetrics.popupShadowInset).contains(point)
        }

        public override func isMousePoint(_ point: NSPoint, in rect: NSRect) -> Bool {
            Self.isInsideClickableRegion(point: point, bounds: bounds)
        }

        public override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let existing = trackingAreaRef {
                removeTrackingArea(existing)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.cursorUpdate, .activeAlways, .inVisibleRect, .mouseEnteredAndExited],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            self.trackingAreaRef = area
        }

        public override func cursorUpdate(with event: NSEvent) {
            NSCursor.arrow.set()
        }

        public override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            NSCursor.arrow.set()
        }

        public override func resetCursorRects() {
            super.resetCursorRects()
            let clickable = bounds.insetBy(dx: PopupMetrics.popupShadowInset, dy: PopupMetrics.popupShadowInset)
            if !clickable.isEmpty {
                addCursorRect(clickable, cursor: .arrow)
            }
        }
    }
}
