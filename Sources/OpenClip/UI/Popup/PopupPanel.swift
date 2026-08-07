// PopupPanel.swift
// OpenClip
//
// Defines a custom floating NSPanel subclass configured for non-activating popup bar display.
// The panel stays non-key by default (rule #9); `allowsKey` is enabled only while the
// action-search palette is active so the search field can receive typing.
// Also re-anchors content-driven window growth: when `pinBottomEdgeOnResize` is set the panel
// keeps its bottom edge fixed while growing (search results above the field), instead of AppKit's
// default top-anchored growth that would shove the popup off the cursor; and when
// `recenterXOnResize` is set, a width change keeps the panel centered on its current center so
// swapping to the narrower search palette or a shorter pagination page never drifts it off the
// cursor. Both flags are cleared by `show(for:)` before a fresh placement.
import AppKit

@MainActor
public class PopupPanel: NSPanel {
    /// When true the panel may become the key/main window (search mode only).
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
    /// through `setFrame`, so intercept here and pin the anchored edge(s) before the frame is
    /// displayed. Pure origin moves (repositioning) and the first placement (zero-sized frame) pass
    /// through untouched.
    override public func setFrame(_ frameRect: NSRect, display flag: Bool) {
        if frame.width > 0, frameRect.width != frame.width {
            var corrected = frameRect
            // Preserve the horizontal center across width changes (search palette, pagination) so
            // the popup stays under the cursor instead of drifting to the top-left anchor.
            if recenterXOnResize {
                corrected.origin.x = frame.midX - frameRect.width / 2
            }
            if pinBottomEdgeOnResize, frame.height > 0, frameRect.height != frame.height {
                corrected.origin.y = frame.origin.y
            }
            super.setFrame(corrected, display: flag)
        } else if pinBottomEdgeOnResize, frame.height > 0, frameRect.height != frame.height {
            var corrected = frameRect
            corrected.origin.y = frame.origin.y
            super.setFrame(corrected, display: flag)
        } else {
            super.setFrame(frameRect, display: flag)
        }
    }
}
