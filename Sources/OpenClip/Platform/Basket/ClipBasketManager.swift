// ClipBasketManager.swift
// OpenClip
//
// Composition root for the Clip Basket's platform behavior: hotkeys, panel lifecycle, and pasting
// one item at a time into whatever app is frontmost. The panel never activates OpenClip, so the
// frontmost app stays the paste destination while the basket is open.
import AppKit
import Combine
import KeyboardShortcuts
import Core

extension KeyboardShortcuts.Name {
    // The browser bookmark-bar chord (⇧⌘B) and paste-and-match-style chord (⇧⌘V) are left to
    // system/app defaults; the basket uses control-based chords instead.
    static let toggleClipBasket = Self("toggleClipBasket", initial: .init(.b, modifiers: [.control, .command]))
    static let pasteNextFromBasket = Self("pasteNextFromBasket", initial: .init(.v, modifiers: [.control, .command]))
    static let pasteAllFromBasket = Self("pasteAllFromBasket", initial: .init(.v, modifiers: [.control, .option, .command]))
    static let armedBasketPaste = Self("armedBasketPaste", initial: .init(.v, modifiers: [.command]))
}

@MainActor
final class ClipBasketManager {
    static let shared = ClipBasketManager()

    typealias ArmedHotkeySetter = @MainActor (Bool) -> Void

    private let store: ClipBasketStore
    private let panelController: ClipBasketPanelController
    private let paster: any ClipBasketPasting
    private let monitor: ClipBasketPasteboardMonitor
    private let settingsStore: any SettingsStore
    private let setArmedHotkeyEnabled: ArmedHotkeySetter
    private let armedPasteTimeout: TimeInterval
    private let monitorsOutsideClicks: Bool

    private weak var popupController: PopupWindowController?
    private var hotkeysInstalled = false
    private var isSubscribed = false
    private var armedHotkeyEnabled = false
    private var isDelivering = false
    private var armedTimeoutTask: Task<Void, Never>?
    private var outsideClickMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    init(
        store: ClipBasketStore = .shared,
        panelController: ClipBasketPanelController = ClipBasketPanelController(),
        paster: any ClipBasketPasting = ClipBasketPaster(),
        monitor: ClipBasketPasteboardMonitor = ClipBasketPasteboardMonitor(),
        settingsStore: any SettingsStore = DefaultSettingsStore.shared,
        armedPasteTimeout: TimeInterval = 20,
        monitorsOutsideClicks: Bool = true,
        setArmedHotkeyEnabled: @escaping ArmedHotkeySetter = { enabled in
            if enabled {
                KeyboardShortcuts.enable(.armedBasketPaste)
            } else {
                KeyboardShortcuts.disable(.armedBasketPaste)
            }
        }
    ) {
        self.store = store
        self.panelController = panelController
        self.paster = paster
        self.monitor = monitor
        self.settingsStore = settingsStore
        self.armedPasteTimeout = armedPasteTimeout
        self.monitorsOutsideClicks = monitorsOutsideClicks
        self.setArmedHotkeyEnabled = setArmedHotkeyEnabled
    }

    func setup(popupController: PopupWindowController) {
        self.popupController = popupController
        installHotkeys()
        subscribeToState()
        monitor.onCapture = { [weak self] content, sourceApp in
            guard let self, self.store.isOpen else { return }
            guard self.store.enqueue(ClipBasketItem(content: content, sourceApp: sourceApp)) else {
                Log.basket.debug("capture skipped reason=basketFull")
                return
            }
            Log.basket.debug("captured kind=\(Self.kind(of: content), privacy: .public) count=\(self.store.count, privacy: .public)")
        }
        syncArmedHotkey()
        syncMonitor()
    }

    var isVisible: Bool { panelController.isShowing }

    func toggle() {
        if panelController.isShowing {
            hide()
        } else {
            show()
        }
    }

    func show() {
        store.setOpen(true)
        panelController.show(
            store: store,
            onPasteNext: { [weak self] in self?.pasteNext() },
            onPasteAll: { [weak self] in self?.pasteAll() },
            onPasteItem: { [weak self] id in self?.paste(itemID: id) },
            onRemoveItem: { [weak self] id in self?.remove(itemID: id) },
            onRunAction: { [weak self] in self?.runActionOnBasket() },
            onSetArmed: { [weak self] armed in self?.setArmedPaste(armed) },
            onClear: { [weak self] in self?.clear() },
            onClose: { [weak self] in self?.hide() }
        )
        syncArmedHotkey()
        syncMonitor()
        Log.basket.debug("panel shown count=\(self.store.count, privacy: .public)")
    }

    func hide() {
        monitor.stop()
        panelController.hide()
        store.setOpen(false)
        syncArmedHotkey()
        syncMonitor()
        Log.basket.debug("panel hidden")
    }

    func pasteNext() {
        guard let item = store.popNext() else {
            showEmptyBasketToast()
            return
        }
        deliver(item, rollbackIndex: 0)
    }

    func paste(itemID: UUID) {
        let rollbackIndex = store.items.firstIndex { $0.id == itemID }
        guard let item = store.pop(id: itemID) else {
            showEmptyBasketToast()
            return
        }
        deliver(item, rollbackIndex: rollbackIndex)
    }

    func remove(itemID: UUID) {
        _ = store.pop(id: itemID)
        syncArmedHotkey()
    }

    func pasteAll() {
        guard let snapshot = store.joinedTextSnapshot() else {
            showToast(StatusFeedback(
                message: String(localized: "No Text to Paste"),
                style: .info,
                symbolName: "text.alignleft"
            ))
            return
        }
        let item = ClipBasketItem(content: .text(RichPasteboardPayload(plainText: snapshot.text)))
        deliver(item, removalIDs: snapshot.itemIDs)
    }

    func runActionOnBasket() {
        guard let text = store.joinedText else {
            showToast(StatusFeedback(
                message: String(localized: "No Text to Run an Action On"),
                style: .info,
                symbolName: "text.alignleft"
            ))
            return
        }
        let sourceApp = NSWorkspace.shared.frontmostApplication.map { AppIdentity($0) } ?? AppIdentity()
        let context = SelectionContext(
            text: text,
            sourceApp: sourceApp,
            cursorPosition: NSEvent.mouseLocation,
            timestamp: Date(),
            isClipboardFallback: true,
            source: .clipboard
        )
        hide()
        popupController?.show(for: context, pasteAvailable: nil, initialMode: .search)
        Log.basket.debug("opened action search for basket count=\(self.store.count, privacy: .public)")
    }

    func clear() {
        store.clear()
        syncArmedHotkey()
        if settingsStore.get(.clipBasketAutoCloseWhenEmpty), panelController.isShowing {
            hide()
        }
    }

    func setArmedPaste(_ armed: Bool) {
        store.setCommandVArmed(armed)
        if armed {
            startArmedWatchdogs()
        } else {
            stopArmedWatchdogs()
        }
        syncArmedHotkey()
    }

    func handleArmedPaste() {
        guard store.isOpen, store.isCommandVArmed, !store.isEmpty else {
            syncArmedHotkey()
            return
        }
        guard !isDelivering else {
            syncArmedHotkey()
            return
        }
        // The synthetic ⌘V posted by the paste must not re-enter this handler.
        armedHotkeyEnabled = false
        setArmedHotkeyEnabled(false)
        pasteNext()
    }

    func syncArmedHotkey() {
        let shouldEnable = store.isOpen && store.isCommandVArmed && !store.isEmpty
        if !shouldEnable {
            stopArmedWatchdogs()
        }
        guard shouldEnable != armedHotkeyEnabled else { return }
        armedHotkeyEnabled = shouldEnable
        setArmedHotkeyEnabled(shouldEnable)
        Log.basket.debug("armed paste hotkey enabled=\(shouldEnable, privacy: .public)")
    }

    func syncMonitor() {
        let shouldRun = store.isOpen && settingsStore.get(.clipBasketAutoCaptureCopies)
        if shouldRun, !monitor.isRunning {
            monitor.start()
        } else if !shouldRun, monitor.isRunning {
            monitor.stop()
        }
    }

    var isCapturing: Bool { monitor.isRunning }

    /// Pauses scoped capture while an action performs its own native copy, so the enrichment copy
    /// does not become a basket item.
    func suspendCapture() {
        monitor.stop()
    }

    func resumeCapture() {
        syncMonitor()
    }

    private func deliver(
        _ item: ClipBasketItem,
        rollbackIndex: Int? = nil,
        removalIDs: [UUID] = []
    ) {
        guard !isDelivering else {
            if let rollbackIndex {
                store.restore(item, at: rollbackIndex)
            }
            syncArmedHotkey()
            return
        }
        if armedHotkeyEnabled {
            armedHotkeyEnabled = false
            setArmedHotkeyEnabled(false)
        }
        isDelivering = true
        let plainText = store.pasteAsPlainText
        let targetApp = NSWorkspace.shared.frontmostApplication

        Task { @MainActor in
            defer {
                self.isDelivering = false
                self.syncArmedHotkey()
            }
            do {
                try await self.paster.paste(item, asPlainText: plainText, targetApp: targetApp)
                Log.basket.debug("pasted remaining=\(self.store.count, privacy: .public) plain=\(plainText, privacy: .public)")
                if !removalIDs.isEmpty {
                    self.store.remove(itemIDs: removalIDs)
                }
                self.finishDeliveryIfEmpty()
            } catch {
                Log.basket.error("paste failed: \(error.localizedDescription, privacy: .private)")
                if let rollbackIndex {
                    self.store.restore(item, at: rollbackIndex)
                }
                self.showToast(StatusFeedback(error: error))
            }
        }
    }

    private func finishDeliveryIfEmpty() {
        guard store.isEmpty, settingsStore.get(.clipBasketAutoCloseWhenEmpty) else { return }
        hide()
        showToast(StatusFeedback(
            message: String(localized: "Basket complete"),
            style: .success,
            symbolName: "basket"
        ))
    }

    private func showEmptyBasketToast() {
        showToast(StatusFeedback(
            message: String(localized: "Basket is empty"),
            style: .info,
            symbolName: "basket"
        ))
    }

    private func showToast(_ feedback: StatusFeedback) {
        popupController?.showToast(feedback, at: NSEvent.mouseLocation)
    }

    private func startArmedWatchdogs() {
        armedTimeoutTask?.cancel()
        armedTimeoutTask = nil
        if monitorsOutsideClicks, outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.setArmedPaste(false) }
            }
        }
        guard armedPasteTimeout > 0 else { return }
        armedTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.armedPasteTimeout ?? 0) * 1_000_000_000))
            guard !Task.isCancelled, let self, self.store.isCommandVArmed else { return }
            self.setArmedPaste(false)
            Log.basket.debug("armed paste timed out")
        }
    }

    private func stopArmedWatchdogs() {
        armedTimeoutTask?.cancel()
        armedTimeoutTask = nil
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    private func installHotkeys() {
        guard !hotkeysInstalled else { return }
        hotkeysInstalled = true

        KeyboardShortcuts.onKeyDown(for: .toggleClipBasket) { [weak self] in
            MainActor.assumeIsolated { self?.toggle() }
        }
        KeyboardShortcuts.onKeyDown(for: .pasteNextFromBasket) { [weak self] in
            MainActor.assumeIsolated { self?.pasteNext() }
        }
        KeyboardShortcuts.onKeyDown(for: .pasteAllFromBasket) { [weak self] in
            MainActor.assumeIsolated { self?.pasteAll() }
        }
        KeyboardShortcuts.onKeyDown(for: .armedBasketPaste) { [weak self] in
            MainActor.assumeIsolated { self?.handleArmedPaste() }
        }
        KeyboardShortcuts.disable(.armedBasketPaste)
    }

    private func subscribeToState() {
        guard !isSubscribed else { return }
        isSubscribed = true
        settingsStore.publisher(for: .clipBasketAutoCaptureCopies)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.syncMonitor() }
            }
            .store(in: &cancellables)
    }

    private static func kind(of content: ClipBasketContent) -> String {
        switch content {
        case .text: return "text"
        case .image: return "image"
        case .files: return "files"
        }
    }
}
