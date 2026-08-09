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
    /// Executes a leaf effect with its side-effect body but never asks the presenter to dismiss
    /// the popup. Canvas-session effects use this door (Task 13): dismissal lives in the
    /// controller's top-level decision, never inside the effect handler, so this is the "effect
    /// door that never hides". Non-throwing — a thrown error is swallowed and logged.
    @MainActor
    func handleWithoutDismissal(_ result: ActionResult, in view: NSView?) async
}

/// Physical-key posting seam (Task 15): `DefaultActionResultHandler` posts keystrokes through an
/// injected `KeyboardEventPosting` (production default `SessionEventTapPoster` emits the real
/// `CGEvent`), so tests can assert `deliverKeyboardEffect`'s resign→activate→post→restore ordering
/// with a recording poster instead of a real key.
public protocol KeyboardEventPosting: Sendable {
    @MainActor
    func postKey(keyCode: CGKeyCode, flags: CGEventFlags)
}

/// The production poster: posts a synthetic key (down + up) to the session event tap — the same
/// `CGEvent` sequence the effect handler always emitted.
@MainActor
public struct SessionEventTapPoster: KeyboardEventPosting {
    public init() {}

    public func postKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        src?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents],
                                                       state: .eventSuppressionStateSuppressionInterval)
        let resolvedFlags = CGEventFlags(rawValue: flags.rawValue | 0x000008)
        if let keydown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
           let keyup = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
            keydown.flags = resolvedFlags
            keyup.flags = resolvedFlags
            keydown.post(tap: .cgSessionEventTap)
            keyup.post(tap: .cgSessionEventTap)
        }
    }
}

@MainActor
public final class DefaultActionResultHandler: ActionResultHandler, Sendable {
    private let settingsStore: SettingsStore
    private let keyboardPoster: KeyboardEventPosting

    public init(settingsStore: SettingsStore = DefaultSettingsStore.shared,
                keyboardPoster: KeyboardEventPosting = SessionEventTapPoster()) {
        self.settingsStore = settingsStore
        self.keyboardPoster = keyboardPoster
    }


    public func handle(_ result: ActionResult, in view: NSView? = nil) async throws {
        try await execute(result, in: view)
    }

    public func handleWithoutDismissal(_ result: ActionResult, in view: NSView? = nil) async {
        do {
            try await execute(result, in: view)
        } catch {
            // Never rethrow into the canvas door: the presenter already suppresses dismissal and a
            // throw would fall back to the legacy error-status path. Log instead.
            Log.resultHandler.error("canvas effect failed: \(error.localizedDescription)")
        }
    }

    /// The single side-effect body shared by `handle` (throws) and `handleWithoutDismissal`
    /// (swallows). Deliberately no dismissal step — hiding is decided by the presenter, never here.
    private func execute(_ result: ActionResult, in view: NSView?) async throws {
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
        case .showContent, .showContentTree, .showCanvas, .showStatus, .openConfiguration, .sequence:
            break
        case .keepVisible(let inner):
            try await execute(inner, in: view)

        // Keyboard execution: keyPress posts a synthetic keystroke; runShortcut launches the
        // shortcuts CLI under the shared subprocess watchdog (thrown errors surface as a status).
        case .keyPress(let spec):
            postKeyPress(spec)
        case .runShortcut(let name, let input):
            try await runShortcut(name: name, input: input)

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
        postKey(keyCode: keyCode, flags: modifier)
    }

    /// Posts a synthetic key press (key + modifiers from a `KeyPressSpec`) to the frontmost app.
    /// Unknown key names are skipped best-effort (no-op) rather than throwing.
    private func postKeyPress(_ spec: KeyPressSpec) {
        guard let keyCode = Self.keyCode(for: spec.key) else { return }
        var flags: CGEventFlags = []
        for modifier in spec.modifiers {
            switch modifier {
            case .command: flags.insert(.maskCommand)
            case .shift: flags.insert(.maskShift)
            case .option: flags.insert(.maskAlternate)
            case .control: flags.insert(.maskControl)
            }
        }
        postKey(keyCode: keyCode, flags: flags)
    }

    private func postKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        keyboardPoster.postKey(keyCode: keyCode, flags: flags)
    }

    /// Runs a registered Shortcuts.app shortcut via the `shortcuts` CLI. The process runs through
    /// `ShellProcessRunner`, which supplies the 30s timeout watchdog and the throw-on-non-zero-exit
    /// policy (surfaced by the presenter as a `.showStatus(.error)`). Input is passed via `-i` with a
    /// temp file; output is intentionally discarded.
    private func runShortcut(name: String, input: String?) async throws {
        let binary = URL(fileURLWithPath: Constants.shortcutsBinaryPath)
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw NSError(domain: Constants.actionErrorDomain, code: Int(Constants.actionErrorCode),
                          userInfo: [NSLocalizedDescriptionKey: "Shortcuts CLI is not available on this system."])
        }

        var arguments = ["run", name]
        var tempURL: URL?
        if let input, !input.isEmpty {
            tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("openclip-shortcut-input-\(UUID().uuidString).txt")
            try input.write(to: tempURL!, atomically: true, encoding: .utf8)
            arguments += ["-i", tempURL!.path]
        }
        defer {
            if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
        }

        _ = try await ShellProcessRunner.run(ShellProcessRunner.Invocation(
            executableURL: binary,
            arguments: arguments,
            environment: ProcessInfo.processInfo.environment
        ))
    }

    /// Maps a `KeyPressSpec` key name to a QWERTY virtual key code. Letters/digits use the ANSI
    /// layout values; unknown names return nil and the press is skipped. Known limitation: a
    /// non-QWERTY physical layout may remap letter/digit keys.
    private static func keyCode(for keyName: String) -> CGKeyCode? {
        let lower = keyName.lowercased()
        let named: [String: CGKeyCode] = [
            "return": 0x24, "enter": 0x24,
            "escape": 0x35, "esc": 0x35,
            "tab": 0x30,
            "space": 0x31,
            "delete": 0x33, "backspace": 0x33,
            "forwarddelete": 0x75,
            "up": 0x7E, "down": 0x7D, "left": 0x7B, "right": 0x7C,
            "home": 0x73, "end": 0x77,
            "pageup": 0x74, "pagedown": 0x79
        ]
        if let code = named[lower] { return code }

        if lower.count == 1, let scalar = lower.unicodeScalars.first {
            let value = Int(scalar.value)
            if value >= 0x61 && value <= 0x7A { // a-z in QWERTY kVK_ANSI_* order
                let layout: [CGKeyCode] = [
                    0x00, 0x0B, 0x08, 0x02, 0x0E, 0x03, 0x05, 0x04, 0x22, 0x26, 0x28, 0x25, 0x2E,
                    0x2D, 0x1F, 0x23, 0x0C, 0x0F, 0x01, 0x11, 0x20, 0x09, 0x0D, 0x07, 0x10, 0x06
                ]
                return layout[value - 0x61]
            }
            if value >= 0x30 && value <= 0x39 { // 0-9
                let digits: [CGKeyCode] = [0x1D, 0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19]
                return digits[value - 0x30]
            }
        }
        return nil
    }
}
