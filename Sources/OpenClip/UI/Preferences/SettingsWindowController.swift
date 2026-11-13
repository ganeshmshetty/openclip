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
    private static var previousPolicy: NSApplication.ActivationPolicy?

    /// The test host is the app itself, so a window opened by a test would give it a Dock icon that outlives an
    /// interrupted run. Tests that assert the policy switch turn this off.
    static var isSuppressed = NSClassFromString("XCTestCase") != nil

    public static func enter() {
        guard !isSuppressed else { return }
        if count == 0 && previousPolicy == nil {
            previousPolicy = NSApp.activationPolicy()
        }
        count += 1
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    public static func leave() {
        guard !isSuppressed, count > 0 else { return }
        count -= 1
        guard count == 0 else { return }
        Task { @MainActor in
            // Another window may have entered before this deferred cleanup runs.
            guard count == 0 else { return }
            // Restore the original policy when no regular windows remain visible
            let hasVisibleRegularWindows = NSApp.windows.contains {
                $0.isVisible && $0.level == .normal && !($0.className.contains("Popup") || $0.className.contains("Panel"))
            }
            if !hasVisibleRegularWindows {
                NSApp.setActivationPolicy(previousPolicy ?? .accessory)
                previousPolicy = nil
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

        if let window, window.isVisible {
            // Pair each `enter()` with exactly one `leave()` in `windowWillClose`. Presenting an
            // already-visible window must not increment the count again, or the app never returns
            // to accessory mode and the Dock icon lingers until quit.
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            postDidShow()
            return
        }

        // A window kept alive across closes stays bound to the Space it was created on, so
        // reopening it from another desktop drags the user back to that one. Building a fresh
        // window per open binds it to the Space the user is actually on.
        let window = makeWindow()
        AppActivationPolicy.enter()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Activation lands asynchronously; re-assert once so a first open cannot stay behind.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window, window.isVisible else { return }
            window.makeKeyAndOrderFront(nil)
        }
        postDidShow()
    }

    private func postDidShow() {
        NotificationCenter.default.post(name: .openClipPreferencesWindowDidShow, object: nil)
        StarPrompt.shared.present()
    }

    private init() {
        super.init(window: nil)
    }

    private func makeWindow() -> NSWindow {
        let initialSize = NSSize(width: 860, height: 640)
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
        window.setFrameUsingName("OpenClipSettingsWindow")
        window.isReleasedWhenClosed = false
        // A restorable window can be resurrected by AppKit at launch, on whatever Space it was
        // last saved to, before the rest of the app is wired.
        window.isRestorable = false
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

        window.delegate = self
        self.window = window
        return window
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        StarPrompt.shared.dismissIfShowing()
        AppActivationPolicy.leave()
        // Drop the reference so the next open builds a window for the then-active Space. Deferred
        // because the close notification runs while AppKit is still tearing the window down.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, !window.isVisible else { return }
            self.window = nil
        }
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        true
    }
}
