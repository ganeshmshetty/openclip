// PopupPanel.swift
// OpenClip
//
// Defines a custom floating NSPanel subclass configured for non-activating popup bar display.
// The panel stays non-key by default (rule #9); `allowsKey` is enabled only while the
// action-search palette is active so the search field can receive typing.
import AppKit

@MainActor
public class PopupPanel: NSPanel {
    /// When true the panel may become the key/main window (search mode only).
    public var allowsKey: Bool = false

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
}
