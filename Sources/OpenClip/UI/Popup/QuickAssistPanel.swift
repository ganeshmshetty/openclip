// QuickAssistPanel.swift
// OpenClip
//
// The floating Quick Assist window: one row per Decision tool marked "Show in Quick Assist",
// answering continuously as the user types in any app. Non-activating so typing never breaks,
// draggable anywhere on screen, and it remembers where it was put.
import AppKit
import SwiftUI
import Core

/// Borderless, non-activating floating panel. Dragging anywhere on its background moves it; it
/// never takes key focus, so the app being typed in keeps it.
@MainActor
public final class QuickAssistPanel: NSPanel {
    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: QuickAssistView.panelWidth, height: 120),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
        self.acceptsMouseMovedEvents = true
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}

/// Owns the panel, its hosting view, and where it sits on screen.
@MainActor
public final class QuickAssistPanelController {
    public var isShowing: Bool { panel.isVisible }
    /// Panel frame in screen coordinates. Internal for tests.
    var panelFrame: NSRect { panel.frame }

    private let panel: QuickAssistPanel
    private let hostingView: NSHostingView<QuickAssistView>
    private let settingsStore: any SettingsStore
    /// Held only so `deinit` can unregister it; the token is never mutated off the main actor, and
    /// a nonisolated `deinit` cannot read a main-actor property without this.
    private nonisolated(unsafe) var moveObserver: NSObjectProtocol?

    public init(panel: QuickAssistPanel = QuickAssistPanel(),
                settingsStore: any SettingsStore = DefaultSettingsStore.shared) {
        self.panel = panel
        self.settingsStore = settingsStore
        self.hostingView = NSHostingView(rootView: QuickAssistView(model: .init(rows: [], statusLine: nil), onClose: {}))
        // The window has to keep a real height while SwiftUI measures, or the first show
        // collapses it to nothing.
        hostingView.frame = NSRect(x: 0, y: 0, width: QuickAssistView.panelWidth, height: 120)
        panel.contentView = hostingView
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.rememberOrigin() }
        }
    }

    deinit {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }
    }

    /// Shows the window (placing it where the user last left it, else bottom-right) and renders
    /// `model`. Called on every update, so it doubles as the refresh path.
    public func show(
        model: QuickAssistViewModel,
        onClose: @escaping () -> Void,
        onAddSelection: @escaping () -> Void = {},
        onClearContext: @escaping () -> Void = {}
    ) {
        hostingView.rootView = QuickAssistView(
            model: model,
            onClose: onClose,
            onAddSelection: onAddSelection,
            onClearContext: onClearContext
        )
        hostingView.layoutSubtreeIfNeeded()
        let fit = hostingView.fittingSize
        let size = NSSize(width: QuickAssistView.panelWidth, height: max(60, fit.height))

        if panel.isVisible {
            // Keep the top-left corner fixed while the row count changes, so the window grows
            // downward instead of sliding its title around under the pointer.
            let top = panel.frame.maxY
            panel.setFrame(NSRect(x: panel.frame.minX, y: top - size.height, width: size.width, height: size.height),
                           display: true)
        } else {
            panel.setFrame(NSRect(origin: restoredOrigin(for: size), size: size), display: true)
            panel.orderFrontRegardless()
        }
    }

    public func hide() {
        guard panel.isVisible else { return }
        rememberOrigin()
        panel.orderOut(nil)
    }

    // MARK: - Position

    /// Where the window should open: the remembered spot when it is still on a connected screen,
    /// otherwise the bottom-right corner of the main screen.
    func restoredOrigin(for size: NSSize) -> NSPoint {
        let stored = NSPoint(x: settingsStore.get(.quickAssistOriginX),
                             y: settingsStore.get(.quickAssistOriginY))
        if stored != .zero {
            let frame = NSRect(origin: stored, size: size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                return stored
            }
        }
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: visible.maxX - size.width - Self.screenMargin,
                       y: visible.minY + Self.screenMargin)
    }

    private func rememberOrigin() {
        guard panel.isVisible else { return }
        settingsStore.set(.quickAssistOriginX, value: Double(panel.frame.origin.x))
        settingsStore.set(.quickAssistOriginY, value: Double(panel.frame.origin.y))
    }

    static let screenMargin: CGFloat = 24
}
