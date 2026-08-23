// ToastPanel.swift
// OpenClip
//
// The non-key floating panel behind the description toast. Mirrors PopupPanel conventions:
// borderless, non-activating, popUpMenu level, never key, SwiftUI-drawn shadow.
import AppKit

@MainActor
public final class ToastPanel: NSPanel {
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
        // Purely informational surface — never key, no interactive content. Let every click (the
        // bubble AND the toastShadowInset ring hosting its shadow) fall through to the app below.
        self.ignoresMouseEvents = true
        self.isMovable = false
        self.hidesOnDeactivate = false
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}