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
import SDWebImageSVGCoder

public protocol ActionResultHandler: Sendable {
    @MainActor
    func handle(_ result: ActionResult, in view: NSView?) async throws
    @MainActor
    func handleWithoutDismissal(_ result: ActionResult, in view: NSView?) async

    @MainActor
    func handle(_ result: ActionResult, in view: NSView?, targetApp: NSRunningApplication?) async throws
    @MainActor
    func handleWithoutDismissal(_ result: ActionResult, in view: NSView?, targetApp: NSRunningApplication?) async

    @MainActor
    func handle(_ result: ActionResult, in view: NSView?, targetApp: NSRunningApplication?,
                isSelectionCurrent: @escaping @MainActor (SelectionContext) -> Bool) async throws
}

extension ActionResultHandler {
    @MainActor
    public func handle(_ result: ActionResult, in view: NSView?, targetApp: NSRunningApplication?,
                       isSelectionCurrent: @escaping @MainActor (SelectionContext) -> Bool) async throws {
        try await handle(result, in: view, targetApp: targetApp)
    }
    @MainActor
    public func handle(_ result: ActionResult, in view: NSView?, targetApp: NSRunningApplication?) async throws {
        try await handle(result, in: view)
    }

    @MainActor
    public func handleWithoutDismissal(_ result: ActionResult, in view: NSView?, targetApp: NSRunningApplication?) async {
        await handleWithoutDismissal(result, in: view)
    }
}

/// Seam for posting keystrokes, so tests can record key order without real events.
public protocol KeyboardEventPosting: Sendable {
    @MainActor
    func postKey(keyCode: CGKeyCode, flags: CGEventFlags)
}

/// Production poster: synthetic key down and up to the session event tap.
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
            keydown.setIntegerValueField(.eventSourceUserData, value: KeyboardEventPoster.syntheticEventTag)
            keyup.setIntegerValueField(.eventSourceUserData, value: KeyboardEventPoster.syntheticEventTag)
            keydown.flags = resolvedFlags
            keyup.flags = resolvedFlags
            keydown.post(tap: .cgSessionEventTap)
            keyup.post(tap: .cgSessionEventTap)
        }
    }
}

@MainActor
public final class DefaultActionResultHandler: ActionResultHandler, Sendable {
    /// Injectable so tests can stub the dictionary lookup.
    public typealias DictionaryLookup = @Sendable (String) -> String?

    public typealias AppActivator = @MainActor @Sendable (NSRunningApplication) -> Void
    public typealias TargetActiveChecker = @MainActor @Sendable (NSRunningApplication) async -> Bool

    private let settingsStore: SettingsStore
    private let keyboardPoster: KeyboardEventPosting
    private let pasteboard: NSPasteboard
    private let pasteboardRestoreDelay: TimeInterval
    private let dictionaryLookup: DictionaryLookup
    private let icsCleanupDelay: TimeInterval
    private let openURL: @MainActor @Sendable (URL) -> Void
    private let openURLInApp: @MainActor @Sendable (URL, String) async -> Void
    private let appActivator: AppActivator
    private let targetActiveChecker: TargetActiveChecker
    private let frontmostPID: @MainActor () -> pid_t?
    private let copyOverlayPresent: @MainActor () -> Bool
    private let copySoundPlayer: @MainActor (CopySound) -> Void

    public init(settingsStore: SettingsStore = DefaultSettingsStore.shared,
                keyboardPoster: KeyboardEventPosting = SessionEventTapPoster(),
                pasteboard: NSPasteboard = .general,
                dictionaryLookup: @escaping DictionaryLookup = DictionaryLookupFactory.systemLookup,
                appActivator: @escaping AppActivator = { $0.activate() },
                targetActiveChecker: @escaping TargetActiveChecker = SelectionReplacer.defaultTargetActiveChecker) {
        self.settingsStore = settingsStore
        self.keyboardPoster = keyboardPoster
        self.pasteboard = pasteboard
        self.dictionaryLookup = dictionaryLookup
        self.pasteboardRestoreDelay = Constants.pasteboardRestoreDelay
        self.icsCleanupDelay = Constants.icsCleanupDelay
        self.openURL = { NSWorkspace.shared.open($0) }
        self.openURLInApp = { url, bundleID in
            await BrowserTabOpener().open(url, inApp: bundleID)
        }
        self.appActivator = appActivator
        self.targetActiveChecker = targetActiveChecker
        self.frontmostPID = { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        self.copyOverlayPresent = {
            CopyTriggerGate.isForeignOverlayPresent(at: NSEvent.mouseLocation, intent: .explicitUserCopy)
        }
        self.copySoundPlayer = { $0.play() }
    }

    public init(settingsStore: SettingsStore = DefaultSettingsStore.shared,
                keyboardPoster: KeyboardEventPosting = SessionEventTapPoster(),
                pasteboard: NSPasteboard = .general,
                dictionaryLookup: @escaping DictionaryLookup = DictionaryLookupFactory.systemLookup,
                pasteboardRestoreDelay: TimeInterval = Constants.pasteboardRestoreDelay,
                icsCleanupDelay: TimeInterval = Constants.icsCleanupDelay,
                openURL: @escaping @MainActor @Sendable (URL) -> Void = { NSWorkspace.shared.open($0) },
                openURLInApp: @escaping @MainActor @Sendable (URL, String) async -> Void = { url, bundleID in
                    await BrowserTabOpener().open(url, inApp: bundleID)
                },
                appActivator: @escaping AppActivator = { $0.activate() },
                targetActiveChecker: @escaping TargetActiveChecker = SelectionReplacer.defaultTargetActiveChecker,
                frontmostPID: @escaping @MainActor () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
                copyOverlayPresent: @escaping @MainActor () -> Bool = {
                    CopyTriggerGate.isForeignOverlayPresent(at: NSEvent.mouseLocation, intent: .explicitUserCopy)
                },
                copySoundPlayer: @escaping @MainActor (CopySound) -> Void = { $0.play() }) {
        self.settingsStore = settingsStore
        self.keyboardPoster = keyboardPoster
        self.pasteboard = pasteboard
        self.dictionaryLookup = dictionaryLookup
        self.pasteboardRestoreDelay = pasteboardRestoreDelay
        self.icsCleanupDelay = icsCleanupDelay
        self.openURL = openURL
        self.openURLInApp = openURLInApp
        self.appActivator = appActivator
        self.targetActiveChecker = targetActiveChecker
        self.frontmostPID = frontmostPID
        self.copyOverlayPresent = copyOverlayPresent
        self.copySoundPlayer = copySoundPlayer
    }

    /// Plays the copy sound when the user enabled it. Call only after the clipboard write succeeded.
    private func playCopySoundIfEnabled() {
        guard settingsStore.get(.playCopySound) else { return }
        copySoundPlayer(CopySound(stored: settingsStore.get(.copySoundName)))
    }


    public func handle(_ result: ActionResult, in view: NSView?) async throws {
        try await execute(result, in: view, targetApp: nil)
    }

    public func handleWithoutDismissal(_ result: ActionResult, in view: NSView?) async {
        do {
            try await execute(result, in: view, targetApp: nil)
        } catch {
            Log.resultHandler.error("effect failed: \(error.localizedDescription)")
        }
    }

    public func handle(_ result: ActionResult, in view: NSView?, targetApp: NSRunningApplication?) async throws {
        try await execute(result, in: view, targetApp: targetApp)
    }

    public func handle(_ result: ActionResult, in view: NSView?, targetApp: NSRunningApplication?,
                       isSelectionCurrent: @escaping @MainActor (SelectionContext) -> Bool) async throws {
        try await execute(result, in: view, targetApp: targetApp, isSelectionCurrent: isSelectionCurrent)
    }

    public func handleWithoutDismissal(_ result: ActionResult, in view: NSView?, targetApp: NSRunningApplication?) async {
        do {
            try await execute(result, in: view, targetApp: targetApp)
        } catch {
            Log.resultHandler.error("effect failed: \(error.localizedDescription)")
        }
    }

    /// Capture can be superseded while waiting for the clipboard lease. Recheck before writing.
    @discardableResult
    func copyText(_ text: String, isCurrent: @MainActor () -> Bool = { true }) async throws -> Bool {
        let session = try await OpenSelection.ClipboardCoordinator.shared.acquireSession(priority: .userAction, pasteboard: pasteboard)
        defer { session.commitPermanent() }
        try Task.checkCancellation()
        guard isCurrent() else { return false }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        playCopySoundIfEnabled()
        return true
    }

    /// Shared by `handle` and `handleWithoutDismissal`. Never dismisses; the presenter decides.
    private func execute(_ result: ActionResult, in view: NSView?, targetApp: NSRunningApplication? = nil,
                         isSelectionCurrent: @escaping @MainActor (SelectionContext) -> Bool = { _ in true }) async throws {
        switch result {
        case .copySelection(let selection):
            do {
                try await copySelection(selection, targetApp: targetApp, isSelectionCurrent: isSelectionCurrent)
            } catch let failure as NativeCopyOperation.Failure {
                let message: String
                switch failure {
                case .targetChanged: message = String(localized: "The source selection is no longer available.")
                case .commandUnavailable: message = String(localized: "The application's Copy command is unavailable.")
                case .timedOut: message = String(localized: "The application did not confirm Copy in time.")
                case .copyBlocked: message = String(localized: "Finish the screen capture before copying.")
                }
                throw NSError(domain: Constants.actionErrorDomain, code: Int(Constants.actionErrorCode),
                              userInfo: [NSLocalizedDescriptionKey: message])
            }
            playCopySoundIfEnabled()
        case .copy(let text):
            try await copyText(text)

        case .copyContent(let payload):
            let clipboardSession = try await OpenSelection.ClipboardCoordinator.shared.acquireSession(priority: .userAction, pasteboard: self.pasteboard)
            defer { clipboardSession.commitPermanent() }
            let pasteboard = self.pasteboard
            pasteboard.clearContents()
            writePayload(payload, to: pasteboard)
            playCopySoundIfEnabled()

        case .copyDefinition(let word):
            guard let definition = dictionaryLookup(word), !definition.isEmpty else {
                throw NSError(
                    domain: Constants.actionErrorDomain,
                    code: Int(Constants.actionErrorCode),
                    userInfo: [NSLocalizedDescriptionKey: "No dictionary definition found for “\(word)”."]
                )
            }
            let clipboardSession = try await OpenSelection.ClipboardCoordinator.shared.acquireSession(priority: .userAction, pasteboard: self.pasteboard)
            defer { clipboardSession.commitPermanent() }
            let pasteboard = self.pasteboard
            pasteboard.clearContents()
            pasteboard.setString(definition, forType: .string)
            playCopySoundIfEnabled()

        case .cut(let text):
            let clipboardSession = try await OpenSelection.ClipboardCoordinator.shared.acquireSession(priority: .userAction, pasteboard: self.pasteboard)
            defer { clipboardSession.commitPermanent() }
            if let targetApp {
                appActivator(targetApp)
                let isActive = await targetActiveChecker(targetApp)
                guard isActive else {
                    throw NSError(
                        domain: Constants.actionErrorDomain,
                        code: Int(Constants.actionErrorCode),
                        userInfo: [NSLocalizedDescriptionKey: "Target application unavailable for cut."]
                    )
                }
            }
            let pasteboard = self.pasteboard
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            postKey(keyCode: Constants.deleteVirtualKey, flags: [])

        case .paste(let text):
            let copyToClipboard = settingsStore.get(.completionCopyToClipboard)
            let destinationApp = targetApp ?? NSWorkspace.shared.frontmostApplication
            try await OpenSelection.replace(
                with: text,
                in: destinationApp,
                pasteboard: self.pasteboard,
                restoreDelay: self.pasteboardRestoreDelay,
                restorePasteboard: !copyToClipboard,
                appActivator: self.appActivator,
                targetActiveChecker: self.targetActiveChecker,
                keyPoster: { [weak self] keyCode, flags in
                    self?.postKey(keyCode: keyCode, flags: flags)
                }
            )

        case .pasteContent(let payload):
            let copyToClipboard = settingsStore.get(.completionCopyToClipboard)
            let destinationApp = targetApp ?? NSWorkspace.shared.frontmostApplication
            try await OpenSelection.replace(
                with: payload.plainText ?? "",
                html: payload.html,
                rtf: payload.rtf,
                flavors: payload.flavors.map { PasteboardFlavor(type: $0.type, data: $0.data) },
                in: destinationApp,
                pasteboard: self.pasteboard,
                restoreDelay: self.pasteboardRestoreDelay,
                restorePasteboard: !copyToClipboard,
                appActivator: self.appActivator,
                targetActiveChecker: self.targetActiveChecker,
                keyPoster: { [weak self] keyCode, flags in
                    self?.postKey(keyCode: keyCode, flags: flags)
                }
            )

        case .openURL(let url):
            openURL(url)
            scheduleICSFileCleanupIfNeeded(for: url)

        case .openURLInApp(let url, let appBundleIdentifier):
            await openURLInApp(url, appBundleIdentifier)
            scheduleICSFileCleanupIfNeeded(for: url)

        case .showServices(let text):
            let picker = NSSharingServicePicker(items: [text])
            if let view {
                picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            }

        case .showDefinition(let word):
            // Standard Look Up popover, anchored to the panel content view.
            if let view {
                view.showDefinition(
                    for: NSAttributedString(string: word),
                    at: NSPoint(x: view.bounds.midX, y: view.bounds.midY)
                )
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

        case .copyFile(let url):
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw NSError(domain: Constants.actionErrorDomain,
                              code: Constants.actionErrorCode,
                              userInfo: [NSLocalizedDescriptionKey: "File does not exist: \(url.lastPathComponent)"])
            }
            let clipboardSession = try await OpenSelection.ClipboardCoordinator.shared.acquireSession(priority: .userAction, pasteboard: self.pasteboard)
            defer { clipboardSession.commitPermanent() }
            let pasteboard = self.pasteboard
            pasteboard.clearContents()
            var objects: [NSPasteboardWriting] = [url as NSURL]
            if FileOutputPayload(url: url).isImage {
                let data = try? await Task.detached { try Data(contentsOf: url) }.value
                if let data, !data.isEmpty {
                    let image = NSImage(data: data) ?? SDImageSVGCoder.shared.decodedImage(with: data, options: nil)
                    if let image, image.isValid, image.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil {
                        let item = NSPasteboardItem()
                        if let tiff = image.tiffRepresentation {
                            item.setData(tiff, forType: .tiff)
                            if let rep = NSBitmapImageRep(data: tiff),
                               let pngData = rep.representation(using: .png, properties: [:]) {
                                item.setData(pngData, forType: .png)
                            }
                        }
                        objects.append(item)
                    }
                }
            }
            pasteboard.writeObjects(objects)

        case .saveFile(let url):
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw NSError(domain: Constants.actionErrorDomain,
                              code: Constants.actionErrorCode,
                              userInfo: [NSLocalizedDescriptionKey: "File does not exist: \(url.lastPathComponent)"])
            }
            let destinationDirectory = resolveSaveLocation()
            let finalURL = try await Task.detached {
                try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
                let targetURL = Self.uniqueFileURL(for: url.lastPathComponent, in: destinationDirectory)
                if url.resolvingSymlinksInPath().path != targetURL.resolvingSymlinksInPath().path {
                    try FileManager.default.copyItem(at: url, to: targetURL)
                }
                return targetURL
            }.value
            Log.resultHandler.info("Saved file \(url.lastPathComponent, privacy: .public) to \(finalURL.path, privacy: .public)")

        case .simulatePaste:
            let clipboardSession = try await OpenSelection.ClipboardCoordinator.shared.acquireSession(priority: .userAction, pasteboard: self.pasteboard)
            defer { clipboardSession.commitPermanent() }
            try await activateTarget(targetApp)
            postKey(keyCode: Constants.vVirtualKey, flags: .maskCommand)
            let deliveryWindow = Task { try? await Task.sleep(nanoseconds: UInt64(self.pasteboardRestoreDelay * 1_000_000_000)) }
            _ = await deliveryWindow.value

        // Presenter-owned results: no-ops here, which keeps the switch exhaustive.
        case .toast, .openConfiguration, .sequence, .text, .file:
            break

        // keyPress posts a synthetic keystroke; runShortcut runs under the subprocess watchdog.
        case .keyPress(let spec):
            try await activateTarget(targetApp)
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

    /// Deletes temp `.ics` files handed to Calendar after a delay. Only regular files matching
    /// `Constants.icsFilenamePrefix` inside the temp directory are touched.
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

    /// Removes `.ics` files left by a session that quit before the deferred cleanup ran.
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

    /// Requests authorization on first use; throws when denied so the presenter shows the error.
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

    private func copySelection(_ selection: SelectionContext, targetApp: NSRunningApplication?,
                               isSelectionCurrent: @escaping @MainActor (SelectionContext) -> Bool) async throws {
        guard selection.source == .selection,
              let pid = selection.sourceApp.processIdentifier, pid > 0,
              let sourceApp = targetApp ?? NSRunningApplication(processIdentifier: pid),
              sourceApp.processIdentifier == pid else {
            throw NativeCopyOperation.Failure.targetChanged
        }
        let sourceIsCurrent: @MainActor () -> Bool = {
            let generationMatches = isSelectionCurrent(selection)
            let frontmost = self.frontmostPID()
            let matches = generationMatches && (frontmost == pid || frontmost == ProcessInfo.processInfo.processIdentifier)
            if !matches {
                Log.selection.debug("[Trace#\(selection.traceID ?? 0, privacy: .public)] native Copy refused: generationCurrent=\(generationMatches, privacy: .public) sourcePID=\(pid, privacy: .public) frontmostPID=\(frontmost ?? -1, privacy: .public)")
            }
            return matches
        }
        guard sourceIsCurrent() else { throw NativeCopyOperation.Failure.targetChanged }
        let timeout = PasteboardCopyEngine.pollingTimeout(for: selection.sourceApp.bundleIdentifier)
        try await NativeCopyOperation().perform(pasteboard: pasteboard, timeout: timeout,
                                               isAuthorized: sourceIsCurrent) {
            guard sourceIsCurrent() else { throw NativeCopyOperation.Failure.targetChanged }
            self.appActivator(sourceApp)
            let active = await self.targetActiveChecker(sourceApp)
            guard active, isSelectionCurrent(selection),
                  self.frontmostPID() == pid else { throw NativeCopyOperation.Failure.targetChanged }
            let canPost: @MainActor () -> Bool = {
                isSelectionCurrent(selection) && self.frontmostPID() == pid && !Task.isCancelled
            }
            guard canPost() else { throw NativeCopyOperation.Failure.targetChanged }
            guard !self.copyOverlayPresent() else {
                throw NativeCopyOperation.Failure.copyBlocked
            }
            if selection.appPolicy.useMenuCopy || selection.appPolicy.retrievalMode == .menuCopy {
                try await NativeCopyOperation.pressMenuCopy(processIdentifier: pid, timeout: 0.5, isAuthorized: canPost)
            } else {
                self.postKey(keyCode: Constants.copyVirtualKey, flags: .maskCommand)
            }
        }
    }

    private func activateTarget(_ targetApp: NSRunningApplication?) async throws {
        guard let targetApp else { try Task.checkCancellation(); return }
        appActivator(targetApp)
        guard await targetActiveChecker(targetApp), !Task.isCancelled else {
            throw OpenSelectionError.targetApplicationUnavailable
        }
    }

    private func writePayload(_ payload: RichPasteboardPayload, to pasteboard: NSPasteboard) {
        if !payload.flavors.isEmpty {
            // Write flavors verbatim, as clipboard managers do; `setData` avoids duplicate rich items.
            for flavor in payload.flavors {
                pasteboard.setData(flavor.data, forType: NSPasteboard.PasteboardType(flavor.type))
            }
        } else {
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
            pasteboard.writeObjects([item])
        }
    }

    /// Unknown key names are a silent no-op.
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

    /// Runs via `ShellProcessRunner` (watchdog, throw on non-zero exit). Input goes through a temp file.
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

    /// QWERTY ANSI virtual key codes; other layouts may remap letters and digits.
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

    /// Resolves the configured file-output directory, falling back to Downloads.
    public func resolveSaveLocation() -> URL {
        let savedPath = settingsStore.get(.fileSaveLocation).trimmingCharacters(in: .whitespacesAndNewlines)
        if !savedPath.isEmpty {
            let expanded = (savedPath as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    public nonisolated static func uniqueFileURL(for filename: String, in directory: URL) -> URL {
        let fileManager = FileManager.default
        var targetURL = directory.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: targetURL.path) else {
            return targetURL
        }

        let ext = (filename as NSString).pathExtension
        let baseName = (filename as NSString).deletingPathExtension
        var counter = 1

        while true {
            let newName = ext.isEmpty ? "\(baseName) (\(counter))" : "\(baseName) (\(counter)).\(ext)"
            targetURL = directory.appendingPathComponent(newName)
            if !fileManager.fileExists(atPath: targetURL.path) {
                return targetURL
            }
            counter += 1
        }
    }
}

/// Headless `DCSCopyTextDefinition` lookup; never launches Dictionary.app.
public enum DictionaryLookupFactory {
    /// Returns nil when the word has no definition.
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
