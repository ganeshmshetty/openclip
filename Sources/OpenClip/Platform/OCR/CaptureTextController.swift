// CaptureTextController.swift
// OpenClip
//
// Coordinates Capture Text: Apple's interactive region selection, the shared action-bar delivery,
// and the local Vision OCR pass.
import AppKit
import CoreGraphics
import Core
import Vision

/// Owns the one-shot screen region capture and local Vision OCR flow.
@MainActor
final class CaptureTextController {
    private weak var popupController: PopupWindowController?
    private let settingsStore: SettingsStore
    private let resultHandler: DefaultActionResultHandler
    private let selector = SystemRegionSelector()
    private var selectionTask: Task<Void, Never>?
    private var requestID: UUID?
    private var sourceApp: NSRunningApplication?

    init(popupController: PopupWindowController, settingsStore: SettingsStore = DefaultSettingsStore.shared,
         resultHandler: DefaultActionResultHandler = DefaultActionResultHandler()) {
        self.popupController = popupController
        self.settingsStore = settingsStore
        self.resultHandler = resultHandler
    }

    /// Shared completion path: never copy empty, cancelled, or superseded recognition results.
    func deliverRecognizedText(_ text: String, isCurrent: @escaping @MainActor () -> Bool,
                               showPopup: @MainActor (StatusFeedback) -> Void) async throws {
        try Task.checkCancellation()
        guard isCurrent(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let autoCopy = settingsStore.get(.captureTextAutoCopy)
        if autoCopy {
            guard try await resultHandler.copyText(text, isCurrent: isCurrent) else { return }
            ActionSoundPolicy.play(owner: nil, result: .copy(text))
        }
        try Task.checkCancellation()
        guard isCurrent() else { return }
        showPopup(StatusFeedback(
            message: autoCopy ? String(localized: "Text copied") : String(localized: "Text captured"),
            style: .success,
            symbolName: "checkmark.circle.fill"
        ))
    }

    var isCapturing: Bool { requestID != nil }

    func toggleCapture(sourceApp: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) {
        if requestID != nil {
            cancel()
            return
        }
        guard HotkeyManager.triggerAllowed(frontmost: sourceApp) else {
            showFailure(Self.blockedMessage(for: sourceApp))
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            PermissionManager.shared.requestScreenRecordingPermission()
            showFailure(String(localized: "Allow Screen Recording for OpenClip in System Settings, then reopen OpenClip."))
            return
        }
        guard !NSScreen.screens.isEmpty else {
            showFailure(String(localized: "Could not capture this screen. Check Screen Recording access in System Settings."))
            return
        }

        let id = UUID()
        requestID = id
        self.sourceApp = sourceApp
        HotkeyManager.shared.enableCaptureCancellation()
        // The system selection would otherwise be able to capture OpenClip's own action bar.
        popupController?.hide(reason: "captureText")
        VisionTextRecognizer.shared.warmUpIfStale()

        selectionTask = Task { @MainActor [weak self] in
            await self?.performCapture(id: id)
        }
    }

    private func performCapture(id: UUID) async {
        defer {
            if requestID == id {
                // No-op once the popup or a failure toast has replaced the spinner.
                popupController?.hideCaptureProgress()
                requestID = nil
                selectionTask = nil
                HotkeyManager.shared.disableCaptureCancellation()
            }
        }
        do {
            guard let selection = try await selector.select() else { return }
            try Task.checkCancellation()
            guard requestID == id else { return }
            popupController?.showCaptureProgress(at: selection.releasePoint) { [weak self] in self?.cancel() }
            let recognitionStart = Date()
            let text = try await VisionTextRecognizer.recognize(selection.image)
            let recognitionMilliseconds = Int(Date().timeIntervalSince(recognitionStart) * 1000)
            Log.selection.info("Capture Text: recognition \(recognitionMilliseconds, privacy: .public)ms")
            try Task.checkCancellation()
            guard requestID == id,
                  isSourceAppStillActive,
                  HotkeyManager.triggerAllowed(frontmost: sourceApp) else {
                Log.selection.notice("Capture Text: dropped the result (source app changed or the hotkey is blocked)")
                return
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Log.selection.notice("Capture Text: no text recognized")
                showFailure(String(localized: "No text found"))
                return
            }
            let identity = sourceApp.map(AppIdentity.init) ?? AppIdentity(bundleIdentifier: nil, localizedName: nil)
            let anchor = CaptureTextPopupAnchor.resolve(
                releasePoint: selection.releasePoint,
                mouseDownPoint: nil,
                currentPointer: NSEvent.mouseLocation
            )
            let context = SelectionContext(
                text: text,
                sourceApp: identity,
                cursorPosition: anchor.cursorPosition,
                mouseDownLocation: anchor.mouseDownLocation,
                selectionBounds: nil,
                timestamp: Date(),
                appPolicy: RuleEngine.shared.resolvePolicies(for: identity),
                source: .ocr,
                isEditable: false,
                pasteTargetAvailable: false
            )
            try await deliverRecognizedText(text, isCurrent: { [weak self] in
                guard let self else { return false }
                return self.requestID == id && self.isSourceAppStillActive
                    && HotkeyManager.triggerAllowed(frontmost: self.sourceApp)
            }) { feedback in
                self.popupController?.previousFrontmostApp = self.sourceApp
                self.popupController?.show(for: context, pasteAvailable: false, captureFeedback: feedback)
            }
        } catch is CancellationError {
            return
        } catch {
            guard requestID == id else { return }
            let error = error as NSError
            Log.selection.error("Capture Text failed: \(error.domain, privacy: .public) code=\(error.code, privacy: .public) \(error.localizedDescription, privacy: .public)")
            showFailure(CaptureFailure(error).message)
        }
    }

    func cancel() {
        if requestID != nil { popupController?.hideCaptureProgress() }
        requestID = nil
        selectionTask?.cancel()
        selectionTask = nil
        selector.cancel()
        HotkeyManager.shared.disableCaptureCancellation()
    }

    private var isSourceAppStillActive: Bool {
        guard let sourceApp else { return false }
        let frontmost = NSWorkspace.shared.frontmostApplication
        return frontmost?.processIdentifier == sourceApp.processIdentifier
            || frontmost?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    private func showFailure(_ message: String) {
        popupController?.showToast(StatusFeedback(message: message, style: .info, symbolName: "viewfinder"), at: NSEvent.mouseLocation)
    }

    private static func blockedMessage(for app: NSRunningApplication?) -> String {
        if DefaultSettingsStore.shared.get(.pauseUntilTimestamp) > Date().timeIntervalSince1970 {
            return String(localized: "OpenClip is paused")
        }
        guard let name = app?.localizedName else { return String(localized: "OpenClip is paused") }
        return String(localized: "Paused in \(name)")
    }
}

/// Maps a capture or recognition error to what the user can do about it.
enum CaptureFailure: Equatable {
    case captureFailed, recognitionFailed

    init(_ error: Error) {
        if (error as NSError).domain == VNErrorDomain {
            self = .recognitionFailed
        } else {
            self = .captureFailed
        }
    }

    var message: String {
        switch self {
        case .recognitionFailed: return String(localized: "Could not read text in this area.")
        case .captureFailed: return String(localized: "Could not capture this area. Try again.")
        }
    }
}

/// Turns Vision's text lines into the copied string. Vision already returns lines in reading order,
/// including column by column, so the order is kept; a fragment that continues the previous line
/// (overlapping it vertically, to its right) is joined with a space instead of a line break.
enum RecognizedTextLayout {
    /// `box` is Vision's normalized bounding box, origin at the bottom left.
    struct Line: Equatable {
        let text: String
        let box: CGRect
    }

    static func join(_ lines: [Line]) -> String {
        var output = ""
        var previous: Line?
        for line in lines {
            if let previous {
                output += continuesLine(previous, line) ? " " : "\n"
            }
            output += line.text
            previous = line
        }
        return output
    }

    static func continuesLine(_ previous: Line, _ next: Line) -> Bool {
        let overlap = min(previous.box.maxY, next.box.maxY) - max(previous.box.minY, next.box.minY)
        let shorter = min(previous.box.height, next.box.height)
        guard shorter > 0, overlap >= shorter * 0.5 else { return false }
        return next.box.minX >= previous.box.maxX - shorter * 0.5
    }
}

struct CaptureTextPopupAnchor: Equatable {
    let cursorPosition: CGPoint
    let mouseDownLocation: CGPoint?

    static func resolve(
        releasePoint: CGPoint,
        mouseDownPoint: CGPoint?,
        currentPointer: CGPoint,
        movementThreshold: CGFloat = 8
    ) -> CaptureTextPopupAnchor {
        let movedX = currentPointer.x - releasePoint.x
        let movedY = currentPointer.y - releasePoint.y
        guard hypot(movedX, movedY) > movementThreshold else {
            return CaptureTextPopupAnchor(cursorPosition: releasePoint, mouseDownLocation: mouseDownPoint)
        }
        return CaptureTextPopupAnchor(cursorPosition: currentPointer, mouseDownLocation: nil)
    }
}
