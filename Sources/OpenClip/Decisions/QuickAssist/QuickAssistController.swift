// QuickAssistController.swift
// OpenClip
//
// Ties Quick Assist together: while Live assist is on it runs the focused-text monitor, feeds what
// the user types to `DecisionLiveAssistEngine`, and keeps the floating window in sync with the
// engine's rows. Switching Live assist off (Settings, the menu bar's Turn Off, the timed window
// expiring, or the window's own close button) tears all of that down again.
import AppKit
import Combine
import Core

@MainActor
public final class QuickAssistController {
    public static let shared = QuickAssistController()

    /// True while the focused-field monitor is running and the window is on screen.
    public private(set) var isActive = false

    private let engine: DecisionLiveAssistEngine
    private let monitor: FocusedTextMonitor
    private let panelController: QuickAssistPanelController
    private let settingsStore: any SettingsStore
    private var cancellables = Set<AnyCancellable>()

    public init(
        engine: DecisionLiveAssistEngine = .shared,
        monitor: FocusedTextMonitor = .shared,
        panelController: QuickAssistPanelController = QuickAssistPanelController(),
        settingsStore: any SettingsStore = DefaultSettingsStore.shared
    ) {
        self.engine = engine
        self.monitor = monitor
        self.panelController = panelController
        self.settingsStore = settingsStore

        engine.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshWindow() }
            }
            .store(in: &cancellables)

        // The Settings toggle, the menu bar submenu and the timed window all move the same two
        // settings, so observing the manager covers every route in and out.
        DecisionServiceManager.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.syncWithSettings() }
            }
            .store(in: &cancellables)
    }

    /// Starts or stops Quick Assist to match the current Live assist state. Safe to call often.
    public func syncWithSettings() {
        if engine.isEnabled {
            start()
        } else {
            stop()
        }
    }

    public func start() {
        guard !isActive else { return }
        guard monitor.isAvailable else {
            Log.decisions.notice("Quick Assist needs Accessibility permission")
            return
        }
        isActive = true
        monitor.onText = { [weak self] text in
            self?.engine.updateTyped(text)
        }
        monitor.start()
        engine.clearContext()
        refreshWindow()
        Log.decisions.info("Quick Assist active")
    }

    public func stop() {
        guard isActive else { return }
        isActive = false
        monitor.onText = nil
        monitor.stop()
        engine.deactivate()
        panelController.hide()
        Log.decisions.info("Quick Assist inactive")
    }

    /// The window's close button: turns Live assist off outright, clearing both the permanent
    /// toggle and any timed window from the menu bar, so it does not come straight back.
    public func closeFromWindow() {
        DecisionServiceManager.shared.liveAssistEnabled = false
        DecisionServiceManager.shared.liveAssistUntilTimestamp = 0
        stop()
    }

    /// The + button: whatever is selected in the app being typed in joins the context.
    public func addSelectionToContext() {
        guard let selection = monitor.selectedText() else { return }
        engine.addSelection(selection)
    }

    private func refreshWindow() {
        guard isActive else { return }
        panelController.show(
            model: QuickAssistViewModel(context: engine.context, rows: engine.rows, statusLine: engine.statusLine),
            onClose: { [weak self] in self?.closeFromWindow() },
            onAddSelection: { [weak self] in self?.addSelectionToContext() },
            onClearContext: { [weak self] in self?.engine.clearContext() }
        )
    }
}
