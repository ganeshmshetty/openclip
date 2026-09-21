// SettingsWindowController.swift
// OpenClip
//
// An AppKit NSWindowController that creates and manages the Settings window.
// Uses .fullSizeContentView, transparent titlebar, and an empty NSToolbar to achieve
// the native macOS 26 large corner radius and seamless Liquid Glass styling.
// Manages activation policy and window lifecycle standard to macOS menu-bar apps.

import AppKit
import SwiftUI
import Core

@MainActor
public enum AppActivationPolicy {
    private static var count = 0

    public static func enter() {
        count += 1
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    public static func leave() {
        count = max(0, count - 1)
        guard count == 0 else { return }
        Task { @MainActor in
            // Return to accessory mode when no regular windows remain visible
            let hasVisibleRegularWindows = NSApp.windows.contains {
                $0.isVisible && $0.level == .normal && !($0.className.contains("Popup") || $0.className.contains("Panel"))
            }
            if !hasVisibleRegularWindows {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

@MainActor
public final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    public static let shared = SettingsWindowController()

    public static func show(tab: PreferenceTab? = nil) {
        shared.present(tab: tab)
    }

    public func present(tab: PreferenceTab?) {
        if let tab {
            SettingsRouter.shared.select(tab.page)
        }
        guard let window else { return }

        AppActivationPolicy.enter()

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .openClipPreferencesWindowDidShow, object: nil)
    }

    private init() {
        let initialSize = NSSize(width: 860, height: 740)
        let minimumContent = NSSize(width: 760, height: 560)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.minSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: minimumContent)).size
        window.contentMinSize = minimumContent
        window.setFrameAutosaveName("OpenClipSettingsWindow")
        window.isReleasedWhenClosed = false
        window.center()

        // Empty NSToolbar is required for macOS 26 to render the large corner radius
        let toolbar = NSToolbar(identifier: "OpenClipSettingsToolbar")
        toolbar.showsBaselineSeparator = false
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none

        let controller = NSHostingController(rootView: PreferencesView())
        controller.sizingOptions = [.minSize]
        window.contentViewController = controller
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = NSColor.clear.cgColor
        window.isOpaque = false
        window.backgroundColor = .clear

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        AppActivationPolicy.leave()
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        true
    }
}
