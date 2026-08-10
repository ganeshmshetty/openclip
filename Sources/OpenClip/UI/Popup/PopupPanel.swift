// PopupPanel.swift
// OpenClip
//
// Defines a custom floating NSPanel subclass configured for non-activating popup bar display.
// The panel stays non-key by default (rule #9); `allowsKey` is enabled only while the
// action-search palette or the content canvas is active so the search field / focused canvas
// component can receive typing.
// Also re-anchors content-driven window growth: when `pinBottomEdgeOnResize` is set the panel
// keeps its bottom edge fixed while growing (search results above the field), instead of AppKit's
// default top-anchored growth that would shove the popup off the cursor; and when
// `recenterXOnResize` is set, a width change keeps the panel centered on its current center so
// swapping to the narrower search palette or a shorter pagination page never drifts it off the
// cursor. Both flags are cleared by `show(for:)` before a fresh placement.
import AppKit
import Core

@MainActor
public class PopupPanel: NSPanel {
    /// When true the panel may become the key/main window (action-search and content-canvas modes).
    public var allowsKey: Bool = false
    /// When true (search mode with results above the field), content-driven growth keeps the
    /// panel's bottom edge fixed and grows upward so the field never shifts.
    public var pinBottomEdgeOnResize: Bool = false
    /// When true, content-driven width changes keep the panel centered on its current horizontal
    /// center (search palette, pagination), instead of the hosting view's top-anchored default that
    /// preserves origin.x and drifts the popup off the cursor.
    public var recenterXOnResize: Bool = false

    public init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false   // SwiftUI draws its own shadow; panel shadow causes double artifacts
    }

    override public var canBecomeKey: Bool { allowsKey }
    override public var canBecomeMain: Bool { allowsKey }

    /// The hosting view auto-resizes the panel window top-anchored when its SwiftUI content grows
    /// (e.g. entering search mode), with no callback to the controller — but every resize funnels
    /// through `setFrame`, so intercept here, clamp maximum width/height bounds, and pin the
    /// anchored edge(s) before the frame is displayed. Pure origin moves (repositioning) and the
    /// first placement (zero-sized frame) pass through untouched.
    override public func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var clamped = frameRect
        if let screenFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            let maxWidth = max(0, screenFrame.width - Constants.popupPadding * 2)
            clamped.size.width = min(clamped.size.width, maxWidth)
        }
        clamped.size.height = min(clamped.size.height, Constants.popupMaxHeight)

        // If height clamping altered the requested height, adjust origin.y to preserve the requested frame's top edge (maxY)
        if clamped.height != frameRect.height, !pinBottomEdgeOnResize {
            clamped.origin.y = frameRect.maxY - clamped.height
        }

        if frame.width > 0, recenterXOnResize, clamped.width != frame.width {
            clamped.origin.x = frame.midX - clamped.width / 2
        }

        if frame.height > 0, recenterXOnResize, clamped.height != frame.height {
            if pinBottomEdgeOnResize {
                clamped.origin.y = frame.origin.y
            } else {
                clamped.origin.y = frame.maxY - clamped.height
            }
        }

        super.setFrame(clamped, display: flag)
    }
}
