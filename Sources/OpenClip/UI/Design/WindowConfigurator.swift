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

private final class ConfiguratorHostingView: NSView {
    var configure: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        runConfigure()
    }

    func runConfigure() {
        guard let window = self.window else { return }
        configure?(window)
        DispatchQueue.main.async { [weak window, weak self] in
            guard let window else { return }
            self?.configure?(window)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak window, weak self] in
            guard let window else { return }
            self?.configure?(window)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak window, weak self] in
            guard let window else { return }
            self?.configure?(window)
        }
    }
}

struct WindowConfigurator: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ConfiguratorHostingView(frame: .zero)
        view.configure = configure
        view.runConfigure()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let configView = nsView as? ConfiguratorHostingView {
            configView.configure = configure
            configView.runConfigure()
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
                for controller in WindowConfigurator.splitViewControllers(in: window) {
                    for item in controller.splitViewItems where item.titlebarSeparatorStyle != .none {
                        item.titlebarSeparatorStyle = .none
                    }
                }
            }
        )
    }

    /// Clears opaque backgrounds on scroll views so the behind-window liquid glass blurs through.
    func transparentScrollBackground() -> some View {
        background(
            WindowConfigurator { window in
                WindowConfigurator.clearScrollViews(in: window.contentView)
            }
        )
    }
}

extension WindowConfigurator {
    /// Every `NSSplitViewController` in `window`: checks the root controller hierarchy as well as
    /// any `NSSplitView` whose delegate is an `NSSplitViewController` in the view hierarchy (such
    /// as those created by SwiftUI's `NavigationSplitView`).
    static func splitViewControllers(in window: NSWindow) -> [NSSplitViewController] {
        var found = splitViewControllers(in: window.contentViewController)
        if let contentView = window.contentView {
            found.append(contentsOf: splitViewControllers(in: contentView))
        }
        var seen = Set<ObjectIdentifier>()
        return found.filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

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

    /// Every `NSSplitViewController` whose split view lives in `view`'s subtree.
    static func splitViewControllers(in view: NSView?) -> [NSSplitViewController] {
        guard let view else { return [] }
        var found: [NSSplitViewController] = []
        if let splitView = view as? NSSplitView, let controller = splitView.delegate as? NSSplitViewController {
            found.append(controller)
        }
        for child in view.subviews {
            found.append(contentsOf: splitViewControllers(in: child))
        }
        return found
    }

    static func clearScrollViews(in view: NSView?, depth: Int = 0) {
        guard let view else { return }
        if let sv = view as? NSScrollView {
            sv.drawsBackground = false
            sv.backgroundColor = .clear
        }
        if let cv = view as? NSClipView {
            cv.drawsBackground = false
            cv.backgroundColor = .clear
        }
        if let tv = view as? NSTableView {
            tv.backgroundColor = .clear
            tv.headerView?.layer?.backgroundColor = .clear
        }
        for child in view.subviews {
            clearScrollViews(in: child, depth: depth + 1)
        }
    }
}

