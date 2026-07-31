import AppKit
import SwiftUI

@MainActor
public final class OnboardingWindowController: NSWindowController {

    public convenience init(onComplete: @escaping @MainActor () -> Void) {
        // Start with a generous rect; the view will shrink/grow via fixedSize
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to OpenClip"
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()

        self.init(window: window)

        let view = OnboardingView {
            window.close()
            onComplete()
        }
        let hosting = NSHostingView(rootView: view)
        // Let the hosting view drive the window size
        hosting.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = hosting
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            hosting.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor)
        ])
        // Fit the window to the SwiftUI content size
        if let fittingSize = window.contentView?.fittingSize, fittingSize.height > 0 {
            var frame = window.frame
            let newHeight = fittingSize.height
            frame.origin.y += frame.height - newHeight
            frame.size.height = newHeight
            window.setFrame(frame, display: false)
        }
    }

    public override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(sender)
    }
}
