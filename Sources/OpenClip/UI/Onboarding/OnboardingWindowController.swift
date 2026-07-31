import AppKit
import SwiftUI

@MainActor
public final class OnboardingWindowController: NSWindowController {
    private var completionHandler: (@MainActor () -> Void)?
    
    public convenience init(onComplete: @escaping @MainActor () -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to OpenClip"
        window.center()
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        
        self.init(window: window)
        self.completionHandler = onComplete
        
        let onboardingView = OnboardingView { [weak self] in
            self?.close()
            onComplete()
        }
        window.contentView = NSHostingView(rootView: onboardingView)
    }
    
    public override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(sender)
    }
}
