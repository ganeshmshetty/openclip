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

extension View {
    /// Keeps the title bar's hairline hidden on every page of the hosting window.
    ///
    /// macOS decides this per split-view column, from whether that column's content scrolls under
    /// the title bar: a page whose top element is a scroll view got no line, and a page that
    /// starts with something static — a hero, a search field, a preview — got one. Setting it on
    /// the window is not enough, because `NSSplitViewItem.titlebarSeparatorStyle` outranks the
    /// window's, and SwiftUI rewrites the items' style as the layout changes. So both are set, and
    /// re-set on every update the way `minimumWindowContentSize` re-asserts its own values.
    func hidesTitlebarSeparator() -> some View {
        background(
            WindowConfigurator { window in
                window.titlebarSeparatorStyle = .none
                for controller in WindowConfigurator.splitViewControllers(in: window.contentViewController) {
                    for item in controller.splitViewItems where item.titlebarSeparatorStyle != .none {
                        item.titlebarSeparatorStyle = .none
                    }
                }
            }
        )
    }
}

extension WindowConfigurator {
    /// Every `NSSplitViewController` under `root`, including nested ones: SwiftUI hosts a
    /// `NavigationSplitView` inside one, but how deep it sits is its own business.
    static func splitViewControllers(in root: NSViewController?) -> [NSSplitViewController] {
        guard let root else { return [] }
        var found: [NSSplitViewController] = []
        if let controller = root as? NSSplitViewController {
            found.append(controller)
        }
        for child in root.children {
            found.append(contentsOf: splitViewControllers(in: child))
        }
        return found
    }
}
