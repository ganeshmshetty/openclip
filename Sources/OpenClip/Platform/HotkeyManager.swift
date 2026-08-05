// HotkeyManager.swift
// OpenClip
//
// Manages global keyboard shortcuts using macOS event monitors and KeyboardShortcuts registrations.
import Foundation
import AppKit
import KeyboardShortcuts
import Core

extension KeyboardShortcuts.Name {
    public static let togglePopup = Self("togglePopup", default: .init(.c, modifiers: [.command, .option]))
}

@MainActor
public final class HotkeyManager {
    public static let shared = HotkeyManager()
    private let retriever = MacTextRetriever()
    
    private init() {}
    
    public func setup(popupController: PopupWindowController) {
        KeyboardShortcuts.onKeyUp(for: .togglePopup) { [weak popupController] in
            Task { @MainActor in
                guard DefaultSettingsStore.shared.get(.isAppEnabled) else { return }

                // Popup already visible: the hotkey toggles actions → search palette → dismiss,
                // instead of re-running text retrieval and re-showing.
                if let popupController, popupController.isVisible {
                    popupController.toggleMode()
                    return
                }

                let frontApp = NSWorkspace.shared.frontmostApplication ?? NSRunningApplication.current
                let policy = await RuleEngine.shared.resolvePolicies(for: frontApp.bundleIdentifier ?? "")
                let appIdentity = AppIdentity(frontApp)
                
                var retrievedText = ""
                var selectionBounds: CGRect? = nil
                
                if let result = await self.retriever.retrieveTextResult(for: appIdentity, policy: policy) {
                    retrievedText = result.text
                    selectionBounds = result.bounds
                }
                
                // No selection in the frontmost app: fall back to the clipboard so the popup has
                // text to act on instead of reporting "no input". isClipboardFallback marks the
                // text as not-from-a-live-selection; the registry drops Copy/Cut (they require a
                // real selection) and every other enabled action acts on the clipboard text.
                var isClipboardFallback = false
                if retrievedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let clipboard = NSPasteboard.general.string(forType: .string),
                   !clipboard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    retrievedText = clipboard
                    isClipboardFallback = true
                }
                
                let context = SelectionContext(
                    text: retrievedText,
                    sourceApp: appIdentity,
                    cursorPosition: NSEvent.mouseLocation,
                    selectionBounds: selectionBounds,
                    timestamp: Date(),
                    appPolicy: policy,
                    isClipboardFallback: isClipboardFallback
                )
                
                popupController?.show(for: context)
            }
        }
    }
}
