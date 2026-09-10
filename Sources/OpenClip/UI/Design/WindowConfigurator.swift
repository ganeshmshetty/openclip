// WindowConfigurator.swift
// OpenClip
//
// Reaches the NSWindow hosting a SwiftUI view. Some window properties have no
// SwiftUI spelling — a hard minimum size among them — and a view can be hosted
// by more than one window (the Settings scene and the window StatusBarController
// opens both show the preferences), so the settings belong with the view rather
// than with one of the call sites.
import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        apply(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Re-applied on update: the window can be attached after the first
        // layout, and SwiftUI resets some of these when the scene rebuilds.
        apply(from: nsView)
    }

    private func apply(from view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            configure(window)
        }
    }
}

extension View {
    /// Clamps the hosting window to a minimum content size.
    func minimumWindowContentSize(width: CGFloat, height: CGFloat) -> some View {
        background(
            WindowConfigurator { window in
                let content = NSSize(width: width, height: height)
                // Re-asserted every time rather than skipped when it already
                // matches: SwiftUI rewrites these as the split view's layout
                // changes, and it does not always rewrite both of them.
                window.contentMinSize = content
                window.minSize = window.frameRect(
                    forContentRect: NSRect(origin: .zero, size: content)
                ).size
                // A window already smaller than the new floor keeps its size
                // until something nudges it, so bring it up now.
                let frame = window.frame
                if frame.width < window.minSize.width || frame.height < window.minSize.height {
                    window.setContentSize(
                        NSSize(
                            width: max(window.contentLayoutRect.width, width),
                            height: max(window.contentLayoutRect.height, height)
                        )
                    )
                }
            }
        )
    }
}
