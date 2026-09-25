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
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        // Defaults to passive pass-through. ToastPanelController sets ignoresMouseEvents = false
        // for interactive loading toasts (clicks cancel the task) and for auto-dismissing toasts,
        // so the cursor can hold the toast by hovering it.
        self.ignoresMouseEvents = true
        self.isMovable = false
        self.hidesOnDeactivate = false
        self.acceptsMouseMovedEvents = true
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}