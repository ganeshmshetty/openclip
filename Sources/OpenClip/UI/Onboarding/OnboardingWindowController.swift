// OnboardingWindowController.swift
// OpenClip
//
// Manages the NSWindow controller lifecycle for presenting the first launch onboarding window.
import AppKit
import SwiftUI

@MainActor
public final class OnboardingWindowController: NSWindowController {

    /// Borderless windows cannot become key by default; without this override every
    /// TextField/SecureField in the onboarding steps would be unusable (same rule
    /// PopupPanel handles with its `allowsKey` gate).
    private final class KeyableWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    public convenience init(onComplete: @escaping @MainActor () -> Void) {
        // Start with a generous rect; the view drives the window size via fixedSize
        let window = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to OpenClip"
        window.isMovableByWindowBackground = true
        // Transparent borderless window — the solid rounded card inside OnboardingView
        // is the only visible surface (no window background color to leak around the
        // rounded corners), while the transparent inset gives the card's shadow room.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.center()

        self.init(window: window)

        let view = OnboardingView {
            window.close()
            onComplete()
        }
        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        // A transparent container that insets the card so the SwiftUI shadow renders
        // inside the window instead of being clipped at its edges. The window itself
        // is shadowless (hasShadow = false) — the shadow follows the rounded card.
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = container
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            hosting.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        // Size the window to the card plus the shadow inset, then center it on screen.
        let inset: CGFloat = 32
        let fitting = hosting.fittingSize
        if fitting.width > 0, fitting.height > 0 {
            window.setContentSize(NSSize(width: fitting.width + inset * 2, height: fitting.height + inset * 2))
        }
        window.center()
    }

    public override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(sender)
    }
}
