// OnboardingWindowController.swift
// OpenClip
//
// Manages the NSWindow controller lifecycle for presenting the first launch onboarding window.
import AppKit
import SwiftUI

@MainActor
public final class OnboardingWindowController: NSWindowController {

    public convenience init(onComplete: @escaping @MainActor () -> Void) {
        // Start with a generous rect; the view drives the window size via fixedSize
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to OpenClip"
        window.isMovableByWindowBackground = true
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

        // A transparent container that insets the card so the SwiftUI shadow (radius 20,
        // offset y 8) renders inside the window instead of being clipped at its edges.
        // The window itself is shadowless (hasShadow = false) — the shadow follows the
        // rounded glass corners of the card, not the window's square bounds.
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = container
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            hosting.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        // Size the window to the card plus the shadow inset, then center it on screen.
        let inset: CGFloat = 28
        let fitting = hosting.fittingSize
        if fitting.width > 0, fitting.height > 0 {
            var frame = window.frame
            frame.size = NSSize(width: fitting.width + inset * 2, height: fitting.height + inset * 2)
            window.setFrame(frame, display: false)
        }
        window.center()
    }

    public override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(sender)
    }
}
