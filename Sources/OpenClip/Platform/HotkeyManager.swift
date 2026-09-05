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
    private var lastFallbackClipboard: (changeCount: Int, text: String)?
    
    internal static func triggerAllowed(
        isAppEnabled: Bool,
        frontmost: NSRunningApplication?,
        settingsStore: SettingsStore = DefaultSettingsStore.shared
    ) -> Bool {
        guard isAppEnabled else { return false }
        if settingsStore.get(.pauseUntilTimestamp) > Date().timeIntervalSince1970 {
            return false
        }
        guard let frontmost,
              let bundleID = frontmost.bundleIdentifier else { return false }
        if AppFilter.isExcluded(bundleID: bundleID) {
            return false
        }
        let policy = RuleEngine.shared.resolvePolicies(for: bundleID)
        return !policy.disabled
    }

    public func setup(popupController: PopupWindowController) {
        KeyboardShortcuts.onKeyUp(for: .togglePopup) { [weak popupController] in
            Task { @MainActor in
                // Popup already visible: if in search mode, the hotkey dismisses the popup (toggle off);
                // if in actions bar mode, the hotkey transitions directly into search mode.
                if let popupController, popupController.isVisible {
                    if popupController.modeStore.mode == .search {
                        popupController.toggleMode()
                    } else {
                        popupController.enterSearch()
                    }
                    return
                }

                // No `.current` fallback: with no identifiable target app there is nothing to
                // retrieve from, and targeting OpenClip itself is explicitly forbidden.
                let frontmostApp = NSWorkspace.shared.frontmostApplication
                guard Self.triggerAllowed(
                    isAppEnabled: DefaultSettingsStore.shared.get(.isAppEnabled),
                    frontmost: frontmostApp
                ), let frontApp = frontmostApp else { return }
                let policy = RuleEngine.shared.resolvePolicies(for: frontApp.bundleIdentifier ?? "")
                let appIdentity = AppIdentity(frontApp)

                // Start the paste-availability probe now, in parallel with selection retrieval, so
                // show(for:pasteAvailable:) can apply the result on the first frame (no Paste/Cut
                // flash). Per-app rules (assume/deny paste) answer inside the probe and skip the AX
                // walk; otherwise it reflects the target app's focus context and is never cached.
                let probeTask = popupController?.preparePasteProbe(for: frontApp, policy: policy)

                var retrievedText = ""
                var selectionBounds: CGRect? = nil
                
                if let result = await SelectionRetrievalCoordinator().retrieve(
                    for: appIdentity,
                    policy: policy,
                    cursor: CursorClassifier.current
                ) {
                    retrievedText = result.text
                    selectionBounds = result.bounds
                }
                
                // No selection in the frontmost app: fall back to the clipboard so the popup has
                // text to act on instead of reporting "no input". isClipboardFallback marks the
                // text as not-from-a-live-selection; the registry drops Copy/Cut (they require a
                // real selection) and every other enabled action acts on the clipboard text.
                var isClipboardFallback = false
                if retrievedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let pasteboard = NSPasteboard.general
                    let currentChangeCount = pasteboard.changeCount
                    if let clipboard = pasteboard.string(forType: .string),
                       !clipboard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        retrievedText = clipboard
                        isClipboardFallback = true
                        self.lastFallbackClipboard = (currentChangeCount, clipboard)
                    }
                }

                // Mirror every other trigger site (deliverSelection, the hold path): empty,
                // whitespace-only, or oversized input never reaches delivery — otherwise an
                // empty selection + empty clipboard would pop a bar whose Copy/Cut act on
                // nothing, and a multi-megabyte clipboard would bypass the length cap.
                guard TextSanitizer.isSubstantial(retrievedText),
                      retrievedText.utf8.count <= Constants.maxTextLength else { return }
                
                let context = SelectionContext(
                    text: retrievedText,
                    sourceApp: appIdentity,
                    cursorPosition: NSEvent.mouseLocation,
                    selectionBounds: selectionBounds,
                    timestamp: Date(),
                    appPolicy: policy,
                    isClipboardFallback: isClipboardFallback
                )
                
                let canPaste = await probeTask?.value
                popupController?.show(for: context, pasteAvailable: canPaste, initialMode: .search)
            }
        }
    }
}
