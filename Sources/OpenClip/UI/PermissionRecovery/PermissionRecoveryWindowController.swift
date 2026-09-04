// PermissionRecoveryWindowController.swift
// OpenClip
//
// Manages the NSWindow controller lifecycle for presenting the compact permission recovery window.
import AppKit
import SwiftUI

@MainActor
public final class PermissionRecoveryWindowController: NSWindowController, NSWindowDelegate {

    private final class KeyableWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    private var onCompleteHandler: (@MainActor () -> Void)?
    private var onDismissHandler: (@MainActor () -> Void)?
    private var hasResolved = false

    public convenience init(
        isUpdate: Bool,
        onComplete: @escaping @MainActor () -> Void,
        onDismiss: @escaping @MainActor () -> Void = {}
    ) {
        let window = KeyableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 260),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = isUpdate ? String(localized: "OpenClip Updated") : String(localized: "OpenClip Permissions")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()

        self.init(window: window)
        window.delegate = self

        self.onCompleteHandler = onComplete
        self.onDismissHandler = onDismiss

        let view = PermissionRecoveryView(
            isUpdate: isUpdate,
            onComplete: { [weak self] in
                self?.handleComplete()
            },
            onDismiss: { [weak self] in
                self?.handleDismiss()
            }
        )

        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = hosting
    }

    public func handleComplete() {
        guard !hasResolved else { return }
        hasResolved = true
        window?.close()
        close()
        let handler = onCompleteHandler
        onCompleteHandler = nil
        onDismissHandler = nil
        handler?()
    }

    public func handleDismiss() {
        guard !hasResolved else { return }
        hasResolved = true
        window?.close()
        close()
        let handler = onDismissHandler
        onCompleteHandler = nil
        onDismissHandler = nil
        handler?()
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        guard !hasResolved else { return }
        hasResolved = true
        let handler = onDismissHandler
        onCompleteHandler = nil
        onDismissHandler = nil
        handler?()
    }

    public override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(sender)
    }
}
