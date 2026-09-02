// ActionResultHandler.swift
// OpenClip
//
// Serves as the Effect Door, executing macOS platform side-effects such as pasteboard mutations, URL
// opening, key event simulations, and user notifications (via UNUserNotificationCenter).
import Foundation
import AppKit
@preconcurrency import UserNotifications
import CoreServices
import Core

public protocol ActionResultHandler: Sendable {
    @MainActor
    func handle(_ result: ActionResult, in view: NSView?) async throws
    /// Executes a leaf effect with its side-effect body but never asks the presenter to dismiss
    /// the popup. Keep-open presentation effects (e.g. the AI result card's Paste/Copy) use this
    /// door: dismissal lives in the controller's top-level decision, never inside the effect
    /// handler, so this is the "effect door that never hides". Non-throwing — a thrown error is
    /// swallowed and logged.
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
    /// Resolves a word to its dictionary definition (headless DictionaryServices lookup). Injectable
    /// so tests can stub the lookup instead of hitting the real system dictionaries.
    public typealias DictionaryLookup = @Sendable (String) -> String?

    private let settingsStore: SettingsStore
    private let keyboardPoster: KeyboardEventPosting
    private let pasteboard: NSPasteboard
    private let pasteboardRestoreDelay: TimeInterval
    private let dictionaryLookup: DictionaryLookup
    private let icsCleanupDelay: TimeInterval
    private let openURL: @MainActor @Sendable (URL) -> Void
    private var pendingRestoreTask: Task<Void, Never>?

    public init(settingsStore: SettingsStore = DefaultSettingsStore.shared,
                keyboardPoster: KeyboardEventPosting = SessionEventTapPoster(),
                pasteboard: NSPasteboard = .general,
                dictionaryLookup: @escaping DictionaryLookup = DictionaryLookupFactory.systemLookup) {
        self.settingsStore = settingsStore
        self.keyboardPoster = keyboardPoster
        self.pasteboard = pasteboard
        self.dictionaryLookup = dictionaryLookup
        self.pasteboardRestoreDelay = Constants.pasteboardRestoreDelay
        self.icsCleanupDelay = Constants.icsCleanupDelay
        self.openURL = { NSWorkspace.shared.open($0) }
    }

    public init(settingsStore: SettingsStore = DefaultSettingsStore.shared,
                keyboardPoster: KeyboardEventPosting = SessionEventTapPoster(),
                pasteboard: NSPasteboard = .general,
                dictionaryLookup: @escaping DictionaryLookup = DictionaryLookupFactory.systemLookup,
                pasteboardRestoreDelay: TimeInterval = Constants.pasteboardRestoreDelay,
                icsCleanupDelay: TimeInterval = Constants.icsCleanupDelay,
                openURL: @escaping @MainActor @Sendable (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.settingsStore = settingsStore
        self.keyboardPoster = keyboardPoster
        self.pasteboard = pasteboard
        self.dictionaryLookup = dictionaryLookup
        self.pasteboardRestoreDelay = pasteboardRestoreDelay
        self.icsCleanupDelay = icsCleanupDelay
        self.openURL = openURL
    }


    public func handle(_ result: ActionResult, in view: NSView? = nil) async throws {
        try await execute(result, in: view)
    }

    public func handleWithoutDismissal(_ result: ActionResult, in view: NSView? = nil) async {
        do {
            try await execute(result, in: view)
        } catch {
            // Never rethrow into the keep-open door: the presenter already suppresses dismissal and a
            // throw would fall back to the legacy error-status path. Log instead.
            Log.resultHandler.error("effect failed: \(error.localizedDescription)")
        }
    }

    /// The single side-effect body shared by `handle` (throws) and `handleWithoutDismissal`
    /// (swallows). Deliberately no dismissal step — hiding is decided by the presenter, never here.
    private func execute(_ result: ActionResult, in view: NSView?) async throws {
        switch result {
        case .copy(let text):
            pendingRestoreTask?.cancel()
            pendingRestoreTask = nil
            let pasteboard = self.pasteboard
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)

        case .copyContent(let payload):
            pendingRestoreTask?.cancel()
            pendingRestoreTask = nil
            let pasteboard = self.pasteboard
            pasteboard.clearContents()
            writePayload(payload, to: pasteboard)

        case .copyDefinition(let word):
            pendingRestoreTask?.cancel()
            pendingRestoreTask = nil
            guard let definition = dictionaryLookup(word), !definition.isEmpty else {
                throw NSError(
                    domain: Constants.actionErrorDomain,
                    code: Int(Constants.actionErrorCode),
                    userInfo: [NSLocalizedDescriptionKey: "No dictionary definition found for “\(word)”."]
                )
            }
            let pasteboard = self.pasteboard
            pasteboard.clearContents()
            pasteboard.setString(definition, forType: .string)

        case .cut(let text):
            pendingRestoreTask?.cancel()
            pendingRestoreTask = nil
            let pasteboard = self.pasteboard
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            postKey(keyCode: Constants.deleteVirtualKey, flags: [])

        case .paste(let text):
            pendingRestoreTask?.cancel()
            pendingRestoreTask = nil
            let pasteboard = self.pasteboard
            deliverPaste(to: pasteboard) {
                let item = NSPasteboardItem()
                item.setString(text, forType: .string)
                item.setData(Data(), forType: PasteboardSnapshot.transientType)
                item.setData(Data(), forType: PasteboardSnapshot.autoGeneratedType)
                pasteboard.writeObjects([item])
            }

        case .pasteContent(let payload):
            pendingRestoreTask?.cancel()
            pendingRestoreTask = nil
            let pasteboard = self.pasteboard
            deliverPaste(to: pasteboard) {
                writePayload(payload, to: pasteboard, transient: true)
            }

        case .openURL(let url):
            openURL(url)
            scheduleICSFileCleanupIfNeeded(for: url)

        case .showServices(let text):
            let picker = NSSharingServicePicker(items: [text])
            if let view {
                picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            }

        case .shareService(let identifier, let text):
            guard let service = NSSharingService(named: NSSharingService.Name(identifier)) else {
                Log.resultHandler.error("Sharing service not found: \(identifier, privacy: .public)")
                throw NSError(
                    domain: Constants.actionErrorDomain,
                    code: Int(Constants.actionErrorCode),
                    userInfo: [NSLocalizedDescriptionKey: "Sharing service '\(identifier)' is not available on this system."]
                )
            }
            service.perform(withItems: [text])

        case .notify(let title, let body):
            try await postNotification(title: title, body: body)

        case .simulatePaste:
            postKey(keyCode: Constants.vVirtualKey, flags: .maskCommand)

        // Presentation/flow results are presenter-owned (PopupWindowController). The handler treats
        // them as no-ops so the switch stays exhaustive without crashing when one is routed here.
        case .toast, .openConfiguration, .sequence, .text:
            break

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

    // MARK: - Temporary .ics cleanup

    /// Temporary `.ics` files handed to the Calendar app (via `.openURL`) are deleted after a short
    /// deferred delay so they don't accumulate in the temp directory. Only files that match the
    /// producer's exact convention (`Constants.icsFilenamePrefix`, `.ics` extension, inside the temp
    /// directory, and a regular file) are touched — directories, arbitrary `.ics` files, and non-temp
    /// paths are left alone.
    private func scheduleICSFileCleanupIfNeeded(for url: URL) {
        guard Self.isCleanableTemporaryICSFile(url) else { return }

        let fileURL = url
        let delay = icsCleanupDelay
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard Self.isCleanableTemporaryICSFile(fileURL) else { return }
            do {
                try FileManager.default.removeItem(at: fileURL)
                Log.resultHandler.info("Removed temporary calendar event file \(fileURL.lastPathComponent, privacy: .public)")
            } catch {
                Log.resultHandler.error("Failed to remove temporary calendar event file: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    /// Removes stale `OpenClipEvent-*.ics` files left in the temp directory by a previous session
    /// that exited before the deferred cleanup ran (crash, quit during the delay window, etc.).
    /// Called once at app launch.
    public static func purgeStaleCalendarTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return }
        for item in items where isCleanableTemporaryICSFile(item) {
            do {
                try FileManager.default.removeItem(at: item)
                Log.resultHandler.info("Purged stale temporary calendar event file \(item.lastPathComponent, privacy: .public)")
            } catch {
                Log.resultHandler.error("Failed to purge temporary calendar event file: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    private static func isCleanableTemporaryICSFile(_ url: URL) -> Bool {
        guard url.isFileURL,
              url.pathExtension.lowercased() == "ics",
              url.lastPathComponent.hasPrefix(Constants.icsFilenamePrefix),
              isInTemporaryDirectory(url),
              isRegularFile(url) else { return false }
        return true
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
    }

    private static func isInTemporaryDirectory(_ url: URL) -> Bool {
        let tempPath = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path
        let filePath = url.resolvingSymlinksInPath().path
        return filePath == tempPath || filePath.hasPrefix(tempPath + "/")
    }

    /// Posts a user notification via `UNUserNotificationCenter`. Requests authorization if status is
    /// `.notDetermined` (first `notify` effect). If authorization is denied or fails, throws an error
    /// so the presenter surfaces the denial via status feedback.
    private func postNotification(title: String, body: String) async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        var isAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional

        if settings.authorizationStatus == .notDetermined {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            isAuthorized = granted
        }

        guard isAuthorized else {
            throw NSError(
                domain: Constants.actionErrorDomain,
                code: Int(Constants.actionErrorCode),
                userInfo: [NSLocalizedDescriptionKey: "Notification permission was denied. Enable notifications in System Settings."]
            )
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try await center.add(request)
    }

    private func writePayload(_ payload: RichPasteboardPayload, to pasteboard: NSPasteboard, transient: Bool = false) {
        let item = NSPasteboardItem()
        if let rtf = payload.rtf, let rtfData = rtf.data(using: .utf8) {
            item.setData(rtfData, forType: .rtf)
        }
        if let html = payload.html {
            item.setString(html, forType: .html)
        }
        if let text = payload.plainText {
            item.setString(text, forType: .string)
        }
        if transient {
            item.setData(Data(), forType: PasteboardSnapshot.transientType)
            item.setData(Data(), forType: PasteboardSnapshot.autoGeneratedType)
        }
        pasteboard.writeObjects([item])
    }

    /// Writes `write` onto the pasteboard then synthesizes ⌘V, honoring the per-click copy
    /// preference and restoring the previous pasteboard contents when the frontmost app ignores
    /// the paste (changeCount unchanged).
    private func deliverPaste(to pasteboard: NSPasteboard, write: () -> Void) {
        if settingsStore.get(.completionCopyToClipboard) {
            pasteboard.clearContents()
            write()
            postKey(keyCode: Constants.vVirtualKey, flags: .maskCommand)
        } else {
            let snapshot = PasteboardSnapshot.capture(pasteboard)
            pasteboard.clearContents()
            write()
            let changeCountAfterSet = pasteboard.changeCount
            postKey(keyCode: Constants.vVirtualKey, flags: .maskCommand)

            pendingRestoreTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(self.pasteboardRestoreDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                if pasteboard.changeCount == changeCountAfterSet {
                    snapshot.restore(to: pasteboard, transientMarkers: true)
                }
            }
        }
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
    /// policy (surfaced by the presenter as a `.toast(.error)`). Input is passed via `-i` with a
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

/// The production dictionary lookup for the `.copyDefinition` effect: a headless
/// `DCSCopyTextDefinition` call that never launches the Dictionary app. The pasteboard write happens
/// in `DefaultActionResultHandler`; this only resolves a word to its definition text.
public enum DictionaryLookupFactory {
    /// Looks up `word` via `DCSCopyTextDefinition` (default system dictionary). Returns nil when the
    /// word has no definition in the active dictionary or the lookup fails.
    public static let systemLookup: @Sendable (String) -> String? = { word in
        let cfWord = word as CFString
        let range = CFRange(location: 0, length: CFStringGetLength(cfWord))
        guard let definition = DCSCopyTextDefinition(nil, cfWord, range)?.takeRetainedValue() as String? else {
            return nil
        }
        let trimmed = definition.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
