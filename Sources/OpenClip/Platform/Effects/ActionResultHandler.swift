// ActionResultHandler.swift
// OpenClip
//
// Serves as the Effect Door, executing macOS platform side-effects such as pasteboard mutations, URL
// opening, key event simulations, and user notifications (via UNUserNotificationCenter).
import Foundation
import AppKit
import UserNotifications
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

        case .notify(let title, let body):
            postNotification(title: title, body: body)

        case .simulatePaste:
            simulateKeyShortcut(keyCode: Constants.vVirtualKey, modifier: .maskCommand)

        // Presentation/flow results are presenter-owned (PopupWindowController). The handler treats
        // them as no-ops so the switch stays exhaustive without crashing when one is routed here.
        case .showBubble, .showStatus, .openConfiguration, .sequence:
            break
        case .keepVisible(let inner):
            try await handle(inner, in: view)

        // Keyboard execution is Phase 8; nothing happens yet.
        case .keyPress, .runShortcut:
            break

        case .success, .none:
            break

        case .failure(let error):
            throw error
        }
    }

    /// Best-effort notification posting: only when the user granted notification authorization;
    /// otherwise skip silently (never crash on an unprivileged call).
    private func postNotification(title: String, body: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
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
