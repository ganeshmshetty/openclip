// ClipBasketManager.swift
// OpenClip
//
// Composition root for the Clip Basket's platform behavior: hotkeys, panel lifecycle, and pasting
// one item at a time into whatever app is frontmost. The panel never activates OpenClip, so the
// frontmost app stays the paste destination while the basket is open.
import AppKit
import KeyboardShortcuts
import Core

extension KeyboardShortcuts.Name {
    static let toggleClipBasket = Self("toggleClipBasket", initial: .init(.b, modifiers: [.command, .shift]))
    static let pasteNextFromBasket = Self("pasteNextFromBasket", initial: .init(.v, modifiers: [.control, .command]))
    static let pasteAllFromBasket = Self("pasteAllFromBasket", initial: .init(.v, modifiers: [.control, .option, .command]))
}

@MainActor
final class ClipBasketManager {
    static let shared = ClipBasketManager()

    private let store: ClipBasketStore
    private let panelController: ClipBasketPanelController
    private let paster: any ClipBasketPasting
    private let settingsStore: any SettingsStore

    private weak var popupController: PopupWindowController?
    private var hotkeysInstalled = false
    private var isDelivering = false

    init(
        store: ClipBasketStore = .shared,
        panelController: ClipBasketPanelController = ClipBasketPanelController(),
        paster: any ClipBasketPasting = ClipBasketPaster(),
        settingsStore: any SettingsStore = DefaultSettingsStore.shared
    ) {
        self.store = store
        self.panelController = panelController
        self.paster = paster
        self.settingsStore = settingsStore
    }

    func setup(popupController: PopupWindowController) {
        self.popupController = popupController
        installHotkeys()
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
            onClear: { [weak self] in self?.clear() },
            onClose: { [weak self] in self?.hide() }
        )
        Log.basket.debug("panel shown count=\(self.store.count, privacy: .public)")
    }

    func hide() {
        panelController.hide()
        store.setOpen(false)
        Log.basket.debug("panel hidden")
    }

    func pasteNext() {
        guard let item = store.popNext() else {
            showEmptyBasketToast()
            return
        }
        deliver(item)
    }

    func paste(itemID: UUID) {
        guard let item = store.pop(id: itemID) else {
            showEmptyBasketToast()
            return
        }
        deliver(item)
    }

    func pasteAll() {
        guard let text = store.joinedText else {
            showToast(StatusFeedback(
                message: String(localized: "No Text to Paste"),
                style: .info,
                symbolName: "text.alignleft"
            ))
            return
        }
        let item = ClipBasketItem(content: .text(RichPasteboardPayload(plainText: text)))
        deliver(item, clearsBasketOnSuccess: true)
    }

    func clear() {
        store.clear()
        if settingsStore.get(.clipBasketAutoCloseWhenEmpty), panelController.isShowing {
            hide()
        }
    }

    private func deliver(_ item: ClipBasketItem, clearsBasketOnSuccess: Bool = false) {
        guard !isDelivering else {
            if !clearsBasketOnSuccess {
                _ = store.undo()
            }
            return
        }
        isDelivering = true
        let plainText = store.pasteAsPlainText
        let targetApp = NSWorkspace.shared.frontmostApplication

        Task { @MainActor in
            defer { self.isDelivering = false }
            do {
                try await self.paster.paste(item, asPlainText: plainText, targetApp: targetApp)
                Log.basket.debug("pasted remaining=\(self.store.count, privacy: .public) plain=\(plainText, privacy: .public)")
                if clearsBasketOnSuccess {
                    self.store.clear()
                }
                self.finishDeliveryIfEmpty()
            } catch {
                Log.basket.error("paste failed: \(error.localizedDescription, privacy: .private)")
                if !clearsBasketOnSuccess {
                    _ = self.store.undo()
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
    }
}
