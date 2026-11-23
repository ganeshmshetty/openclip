// PopupPanel.swift
// OpenClip
//
// Non-activating floating NSPanel for the popup bar. It stays non-key unless `allowsKey` is set
// (search palette or AI card), and re-anchors content-driven resizes so the popup stays under the cursor.
import AppKit
import SwiftUI
import Core

@MainActor
public class PopupPanel: NSPanel {
    /// Lets the panel become key/main (search palette and AI card modes).
    public var allowsKey: Bool = false
    /// Search mode with results above the field: keep the bottom edge fixed and grow upward.
    public var pinBottomEdgeOnResize: Bool = false
    /// One-shot: releases the bottom pin after the palette's first growth, so later shrinking keeps the search field's top edge fixed.
    public var releasesBottomPinAfterGrowth: Bool = false
    /// Height cap applied in `setFrame`; the controller raises it for the result card and palette.
    public var heightCap: CGFloat = PopupMetrics.popupMaxHeight
    public enum HorizontalAnchor: Sendable {
        case none
        case center
        case left
        case right
    }

    /// Controls how horizontal width changes anchor the window:
    /// - `.none`: preserve requested origin.x
    /// - `.center`: preserve frame.midX (re-center)
    /// - `.left`: preserve frame.minX (grow/shrink from right)
    /// - `.right`: preserve frame.maxX (grow/shrink from left, chevrons stay under cursor)
    public var horizontalAnchor: HorizontalAnchor = .none

    /// Backwards-compatible property for `.center` anchoring.
    public var recenterXOnResize: Bool {
        get { horizontalAnchor == .center }
        set { horizontalAnchor = newValue ? .center : .none }
    }

    /// True during a user drag. Hover tracking must not toggle `ignoresMouseEvents` now, or the panel could be stranded under the pointer.
    public private(set) var isUserDragging = false

    public init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.level = .popUpMenu
        // Explicitly eligible to join another app's fullscreen Space (macOS 13+).
        self.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false   // SwiftUI draws its own shadow; panel shadow causes double artifacts
        self.acceptsMouseMovedEvents = true
        self.isMovable = true    // borderless; SwiftUI header gestures move the panel
    }

    /// The move is driven by `PopupWindowController.handleCardDrag`, since `NSHostingView` swallows
    /// `mouseDown` and AppKit's `performDrag` is unreachable. A user-placed panel turns off re-centering until `hide()`.
    public func prepareForUserDrag() {
        horizontalAnchor = .none
        isUserDragging = true
    }

    public func endUserDrag() {
        isUserDragging = false
    }

    override public var canBecomeKey: Bool { allowsKey }
    override public var canBecomeMain: Bool { allowsKey }

    /// Root view. The transparent shadow ring is excluded from hit-testing so clicks there reach the window beneath.
    public final class ContentView: NSHostingView<PopupView> {
        private var trackingAreaRef: NSTrackingArea?

        /// Hover tracking for when OpenClip is inactive (e.g. over another app's fullscreen Space): event
        /// monitors and `.onHover` do not fire there. The controller recomputes from the live pointer,
        /// since relayouts emit spurious exits.
        var onMouseMoved: (() -> Void)?

        /// Only the area inside the shadow ring belongs to the popup. Pure, so it is unit-testable.
        public nonisolated static func isInsideClickableRegion(point: NSPoint, bounds: NSRect) -> Bool {
            bounds.insetBy(dx: PopupMetrics.popupShadowInset, dy: PopupMetrics.popupShadowInset).contains(point)
        }

        public nonisolated override func isMousePoint(_ point: NSPoint, in rect: NSRect) -> Bool {
            guard Thread.isMainThread else { return false }
            return MainActor.assumeIsolated {
                Self.isInsideClickableRegion(point: point, bounds: self.bounds)
            }
        }

        /// Accessibility hit-testing resolves elements on a helper thread, so this override must not
        /// assert the main actor: a background caller gets no view, which keeps the overlay out of the
        /// AX tree instead of trapping.
        public nonisolated override func hitTest(_ point: NSPoint) -> NSView? {
            guard Thread.isMainThread else { return nil }
            return MainActor.assumeIsolated { self.hitTestOnMainThread(point) }
        }

        private func hitTestOnMainThread(_ point: NSPoint) -> NSView? {
            guard Self.isInsideClickableRegion(point: point, bounds: bounds) else {
                return nil
            }
            return super.hitTest(point)
        }

        public override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let existing = trackingAreaRef {
                removeTrackingArea(existing)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.cursorUpdate, .activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
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
            onMouseMoved?()
        }

        public override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            onMouseMoved?()
        }

        public override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            onMouseMoved?()
        }

        public override func resetCursorRects() {
            super.resetCursorRects()
            let clickable = bounds.insetBy(dx: PopupMetrics.popupShadowInset, dy: PopupMetrics.popupShadowInset)
            if !clickable.isEmpty {
                addCursorRect(clickable, cursor: .arrow)
            }
        }
    }

    /// SwiftUI resizes the panel top-anchored with no callback, so every resize is clamped and its
    /// anchored edge re-pinned here. Origin-only moves and the first placement pass through.
    override public func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var clamped = frameRect
        let heightWasClamped = clamped.size.height > heightCap
        let activeScreenFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        if let screenFrame = activeScreenFrame {
            let maxWidth = max(0, screenFrame.width - PopupMetrics.popupPadding * 2)
            clamped.size.width = min(clamped.size.width, maxWidth)
        }
        clamped.size.height = min(clamped.size.height, heightCap)

        // Keep the requested top edge (maxY) when height clamping changed the height.
        if clamped.height != frameRect.height, !pinBottomEdgeOnResize {
            clamped.origin.y = frameRect.maxY - clamped.height
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

        // Re-anchor after a size change or height clamp; otherwise the clamped delta leaks into the origin and the pinned edge drifts.
        let sizeChangedOrClamped = frame.height > 0 && horizontalAnchor != .none
            && (clamped.height != frame.height || heightWasClamped)
        if sizeChangedOrClamped {
            if pinBottomEdgeOnResize {
                clamped.origin.y = frame.origin.y
                if releasesBottomPinAfterGrowth, clamped.height > frame.height {
                    pinBottomEdgeOnResize = false
                    releasesBottomPinAfterGrowth = false
                }
            } else {
                clamped.origin.y = frame.maxY - clamped.height
            }
        }

        super.setFrame(clamped, display: flag)
    }
}
