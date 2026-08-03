// PopupPanel.swift
// OpenClip
//
// Defines a custom floating NSPanel subclass configured for non-activating popup bar display.
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
    }
}
