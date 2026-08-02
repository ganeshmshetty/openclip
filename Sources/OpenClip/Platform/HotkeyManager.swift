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
    
    private init() {}
    
    public func setup(popupController: PopupWindowController) {
        KeyboardShortcuts.onKeyUp(for: .togglePopup) { [weak popupController] in
            Task { @MainActor in
                guard DefaultSettingsStore.shared.get(.isAppEnabled) else { return }
                
                let retriever = MacTextRetriever()
                let frontApp = NSWorkspace.shared.frontmostApplication ?? NSRunningApplication.current
                let policy = await RuleEngine.shared.resolvePolicies(for: frontApp.bundleIdentifier ?? "")
                
                var retrievedText = ""
                var selectionBounds: CGRect? = nil
                
                if let result = await retriever.retrieveTextResult(for: frontApp, policy: policy) {
                    retrievedText = result.text
                    selectionBounds = result.bounds
                }
                
                let context = SelectionContext(
                    text: retrievedText,
                    sourceApp: frontApp,
                    cursorPosition: NSEvent.mouseLocation,
                    selectionBounds: selectionBounds,
                    timestamp: Date(),
                    appPolicy: policy
                )
                
                popupController?.show(for: context)
            }
        }
    }
}
