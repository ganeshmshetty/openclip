import AppKit

@MainActor
public class PopupPanel: NSPanel {
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

        // Route mouse-moved events to this window even when it's not the key window.
        // Without this, NSTrackingArea (which SwiftUI's onContinuousHover uses internally)
        // never fires for .nonactivatingPanel windows because they never become key.
        self.acceptsMouseMovedEvents = true
    }
}


