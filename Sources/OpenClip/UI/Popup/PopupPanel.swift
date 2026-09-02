// PopupPanel.swift
// OpenClip
//
// Defines a custom floating NSPanel subclass configured for non-activating popup bar display.
// The panel stays non-key by default (rule #9); `allowsKey` is enabled only while the
// action-search palette or the native AI result card is active so the search field / card
// component can receive typing.
// Also re-anchors content-driven window growth: when `pinBottomEdgeOnResize` is set the panel
// keeps its bottom edge fixed while growing (search results above the field), instead of AppKit's
// default top-anchored growth that would shove the popup off the cursor; and when
// `recenterXOnResize` is set, a width change keeps the panel centered on its current center so
// swapping to the narrower search palette or a shorter pagination page never drifts it off the
// cursor. Both flags are cleared by `show(for:)` before a fresh placement.
import AppKit
import SwiftUI
import Core

@MainActor
public class PopupPanel: NSPanel {
    /// When true the panel may become the key/main window (action-search and AI-result-card modes).
    public var allowsKey: Bool = false
    /// When true (search mode with results above the field), content-driven growth keeps the
    /// panel's bottom edge fixed and grows upward so the field never shifts.
    public var pinBottomEdgeOnResize: Bool = false
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
        self.hasShadow = false   // SwiftUI draws its own shadow; panel shadow causes double artifacts
        self.acceptsMouseMovedEvents = true
    }

    override public var canBecomeKey: Bool { allowsKey }
    override public var canBecomeMain: Bool { allowsKey }

    /// Root content view of the popup panel. `PopupView` renders inside a transparent
    /// `popupShadowInset` ring so the SwiftUI drop shadow isn't clipped at the panel edge; without
    /// special handling that ring is part of the window frame, so a click in the visible shadow is
    /// delivered to (and swallowed by) the panel — no dismissal, and the app underneath never sees
    /// it. Excluding the ring from mouse hit-testing makes the window server route those clicks to
    /// whatever window is actually beneath the pointer, where the controller's global monitor then
    /// dismisses the popup.
    public final class ContentView: NSHostingView<PopupView> {
        private var trackingAreaRef: NSTrackingArea?

        /// Pure hit-test rule (unit-testable without a live SwiftUI tree): only the area inside the
        /// shadow ring belongs to the popup.
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

    /// The hosting view auto-resizes the panel window top-anchored when its SwiftUI content grows
    /// (e.g. entering search mode), with no callback to the controller — but every resize funnels
    /// through `setFrame`, so intercept here, clamp maximum width/height bounds, and pin the
    /// anchored edge(s) before the frame is displayed. Pure origin moves (repositioning) and the
    /// first placement (zero-sized frame) pass through untouched.
    override public func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var clamped = frameRect
        let heightWasClamped = clamped.size.height > PopupMetrics.popupMaxHeight
        let activeScreenFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        if let screenFrame = activeScreenFrame {
            let maxWidth = max(0, screenFrame.width - PopupMetrics.popupPadding * 2)
            clamped.size.width = min(clamped.size.width, maxWidth)
        }
        clamped.size.height = min(clamped.size.height, PopupMetrics.popupMaxHeight)

        // If height clamping altered the requested height, adjust origin.y to preserve the requested frame's top edge (maxY)
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

        // Re-anchor the pinned edge whenever the request changed the panel size OR was height-clamped.
        // A clamped request reaches this block with clamped.height == frame.height (the panel already
        // grew to the cap), yet its top-anchored origin still encodes the un-clamped height — without
        // re-anchoring, the clamped-off delta leaks into the origin and the pinned edge drifts.
        let sizeChangedOrClamped = frame.height > 0 && horizontalAnchor != .none
            && (clamped.height != frame.height || heightWasClamped)
        if sizeChangedOrClamped {
            if pinBottomEdgeOnResize {
                clamped.origin.y = frame.origin.y
            } else {
                clamped.origin.y = frame.maxY - clamped.height
            }
        }

        super.setFrame(clamped, display: flag)
    }
}
