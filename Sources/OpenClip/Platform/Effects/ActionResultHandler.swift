// ActionResultHandler.swift
// OpenClip
//
// Serves as the Effect Door, executing macOS platform side-effects such as pasteboard mutations, URL opening, and key event simulations.
import Foundation
import AppKit
import Core

public protocol ActionResultHandler: Sendable {
    @MainActor
    func handle(_ result: ActionResult, in view: NSView?) async throws
}

@MainActor
public final class DefaultActionResultHandler: ActionResultHandler, Sendable {
    private let settingsStore: SettingsStore

    public init(settingsStore: SettingsStore = DefaultSettingsStore.shared) {
        self.settingsStore = settingsStore
    }


    public func handle(_ result: ActionResult, in view: NSView? = nil) async throws {
        switch result {
        case .copy(let text):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

        case .cut(let text):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            simulateKeyShortcut(keyCode: Constants.deleteVirtualKey, modifier: [])

        case .paste(let text):
            let pasteboard = NSPasteboard.general
            let copyToClipboard = settingsStore.get(.completionCopyToClipboard)

            
            if copyToClipboard {
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                simulateKeyShortcut(keyCode: Constants.vVirtualKey, modifier: .maskCommand)
            } else {
                let savedItems = backupPasteboard(pasteboard)
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                simulateKeyShortcut(keyCode: Constants.vVirtualKey, modifier: .maskCommand)
                
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(Constants.pasteboardRestoreDelay * 1_000_000_000))
                    self.restorePasteboard(pasteboard, items: savedItems)
                }
            }

        case .openURL(let url):
            NSWorkspace.shared.open(url)

        case .showServices(let text):
            let picker = NSSharingServicePicker(items: [text])
            if let view {
                picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            }

        case .simulatePaste:
            simulateKeyShortcut(keyCode: Constants.vVirtualKey, modifier: .maskCommand)

        case .success, .none:
            break

        case .failure(let error):
            throw error
        }
    }

    private func backupPasteboard(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy.types.isEmpty ? nil : copy
        }
    }

    private func restorePasteboard(_ pasteboard: NSPasteboard, items: [NSPasteboardItem]) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
    }

    private func simulateKeyShortcut(keyCode: CGKeyCode, modifier: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        src?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents], state: .eventSuppressionStateSuppressionInterval)
        
        let flags = CGEventFlags(rawValue: modifier.rawValue | 0x000008)
        if let keydown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
           let keyup = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
            keydown.flags = flags
            keyup.flags = flags
            keydown.post(tap: .cgSessionEventTap)
            keyup.post(tap: .cgSessionEventTap)
        }
    }
}
