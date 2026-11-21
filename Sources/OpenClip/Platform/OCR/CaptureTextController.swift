import AppKit
import CoreGraphics
import Core
import ScreenCaptureKit
import Vision

/// Owns the one-shot screen region capture and local Vision OCR flow.
@MainActor
final class CaptureTextController {
    private weak var popupController: PopupWindowController?
    private let settingsStore: SettingsStore
    private let resultHandler: DefaultActionResultHandler
    private var panels: [RegionSelectionPanel] = []
    private var captureTask: Task<Void, Never>?
    private let cursorLease = CaptureCursorLease()
    private var requestID: UUID?
    private var sourceApp: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

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
        let feedback = StatusFeedback(
            message: autoCopy ? String(localized: "Text copied") : String(localized: "Text captured"),
            style: .success,
            symbolName: "checkmark.circle.fill"
        )
        // One-step OCR + Translate: show the popup (which sets currentActionContext) then
        // immediately fire the translate AI preset so the result card appears without a second click.
        let autoTranslate = settingsStore.get(.captureTextAutoTranslate)
        if autoTranslate {
            if AIServiceManager.shared.isAIEnabled,
               let preset = AIServiceManager.shared.presets.first(where: { $0.id == "translate" && $0.isEnabled }) {
                showPopup(feedback)
                let prompt = AIServiceManager.shared.promptForPreset(preset)
                popupController?.runAIPreset(prompt: prompt, title: preset.title, presetID: preset.id)
                return
            } else {
                Log.ai.warning("OCR auto-translate skipped: AI or Translate preset is disabled")
            }
        }
        showPopup(feedback)
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
        observeSourceAppActivation(for: id)
        let screens = NSScreen.screens
        panels = screens.map { screen in
            let panel = RegionSelectionPanel(screen: screen)
            panel.onCursorRefresh = { [weak self] in self?.cursorLease.refresh() }
            panel.onSelection = { [weak self] rect, releasePoint, mouseDownPoint, selectedScreen in
                self?.beginRecognition(rect: rect, releasePoint: releasePoint, mouseDownPoint: mouseDownPoint, screen: selectedScreen, requestID: id)
            }
            panel.orderFrontRegardless()
            return panel
        }
        // OpenClip stays inactive so the source window keeps focus: activating would blur it (Safari's
        // AutoPiP enters Picture in Picture on blur) and can switch away from a full-screen Space.
        // Escape arrives through the global cancel shortcut instead of a key window.
        BackgroundCursor.setEnabled(true)
        cursorLease.begin()
    }

    func cancel() {
        if requestID != nil { popupController?.hideCaptureProgress() }
        requestID = nil
        captureTask?.cancel()
        captureTask = nil
        HotkeyManager.shared.disableCaptureCancellation()
        removeActivationObserver()
        closePanels()
    }

    private func beginRecognition(rect: CGRect, releasePoint: CGPoint, mouseDownPoint: CGPoint, screen: NSScreen, requestID id: UUID) {
        guard requestID == id else { return }
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
        guard let displayID,
              let geometry = CaptureRegionGeometry.map(rect: rect, screenFrame: screen.frame, scale: screen.backingScaleFactor, displayID: displayID) else {
            cancel()
            showFailure(String(localized: "Select a larger area"))
            return
        }
        // ScreenCaptureKit already excludes OpenClip windows, so the panels can close now.
        CaptureTextReleaseHandoff.closeOverlayThenStartWork(closeOverlay: closePanels) { [weak self] in
            guard let self else { return }
            self.captureTask = Task { @MainActor [weak self] in
                guard let self else { return }
                defer {
                    if self.requestID == id {
                        // No-op once the popup or a failure toast has replaced the spinner.
                        self.popupController?.hideCaptureProgress()
                        self.requestID = nil
                        self.captureTask = nil
                        HotkeyManager.shared.disableCaptureCancellation()
                        self.removeActivationObserver()
                        self.closePanels()
                    }
                }
                // A cancellation between scheduling this task and its first turn clears requestID;
                // showing the spinner then would outlive every cleanup path, since the defer below
                // only runs while this request is still current.
                guard self.requestID == id, !Task.isCancelled else { return }
                self.popupController?.showCaptureProgress(at: releasePoint) { [weak self] in self?.cancel() }
                do {
                    let image = try await Self.capture(displayID: geometry.displayID, sourceRect: geometry.sourceRect, pixelSize: geometry.pixelSize)
                    try Task.checkCancellation()
                    let text = try await Self.recognize(image)
                    try Task.checkCancellation()
                    guard self.requestID == id,
                          self.isSourceAppStillActive,
                          HotkeyManager.triggerAllowed(frontmost: self.sourceApp) else { return }
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        self.showFailure(String(localized: "No text found"))
                        return
                    }
                    let identity = self.sourceApp.map(AppIdentity.init) ?? AppIdentity(bundleIdentifier: nil, localizedName: nil)
                    let anchor = CaptureTextPopupAnchor.resolve(
                        releasePoint: releasePoint,
                        mouseDownPoint: mouseDownPoint,
                        currentPointer: NSEvent.mouseLocation
                    )
                    let context = SelectionContext(
                        text: text,
                        sourceApp: identity,
                        cursorPosition: anchor.cursorPosition,
                        mouseDownLocation: anchor.mouseDownLocation,
                        selectionBounds: rect,
                        timestamp: Date(),
                        appPolicy: RuleEngine.shared.resolvePolicies(for: identity),
                        source: .ocr,
                        isEditable: false,
                        pasteTargetAvailable: false
                    )
                    try await self.deliverRecognizedText(text, isCurrent: { [weak self] in
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
                    guard self.requestID == id else { return }
                    Log.selection.error("Capture Text failed: \(String(describing: error))")
                    self.showFailure(CaptureFailure(error).message)
                }
            }
        }
    }

    private func closePanels() {
        CaptureOverlayCleanup.close(
            closeOverlays: {
                self.panels.forEach { $0.close() }
                self.panels.removeAll()
            },
            // Pop only after AppKit has removed each overlay's cursor rects.
            restoreCursor: {
                self.cursorLease.end()
                BackgroundCursor.setEnabled(false)
            }
        )
    }

    private var isSourceAppStillActive: Bool {
        guard let sourceApp else { return false }
        let frontmost = NSWorkspace.shared.frontmostApplication
        return frontmost?.processIdentifier == sourceApp.processIdentifier
            || frontmost?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    private func observeSourceAppActivation(for id: UUID) {
        removeActivationObserver()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let activatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self, self.requestID == id, let activatedApp else { return }
                let isOpenClip = activatedApp.bundleIdentifier == Bundle.main.bundleIdentifier
                let isSource = activatedApp.processIdentifier == self.sourceApp?.processIdentifier
                if !isOpenClip && !isSource { self.cancel() }
            }
        }
    }

    private func removeActivationObserver() {
        guard let activationObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        self.activationObserver = nil
    }

    private func showFailure(_ message: String) {
        popupController?.showToast(StatusFeedback(message: message, style: .info, symbolName: "viewfinder"), at: NSEvent.mouseLocation)
    }

    private static func capture(displayID: CGDirectDisplayID, sourceRect: CGRect, pixelSize: CGSize) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayUnavailable
        }
        let excluded = content.windows.filter { $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        configuration.width = max(1, Int(pixelSize.width.rounded()))
        configuration.height = max(1, Int(pixelSize.height.rounded()))
        configuration.showsCursor = false
        return try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                if let error { continuation.resume(throwing: error) }
                else if let image { continuation.resume(returning: image) }
                else { continuation.resume(throwing: CaptureError.noImage) }
            }
        }
    }

    private static func recognize(_ image: CGImage) async throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let box = RecognitionRequestBox(request: request)
        // A detached task does not inherit cancellation, so cancel the Vision request itself.
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try VNImageRequestHandler(cgImage: image).perform([box.request])
                let lines = (box.request.results ?? []).compactMap { observation in
                    observation.topCandidates(1).first.map { RecognizedTextLayout.Line(text: $0.string, box: observation.boundingBox) }
                }
                return RecognizedTextLayout.join(lines)
            }.value
        } onCancel: {
            box.request.cancel()
        }
    }

    private static func blockedMessage(for app: NSRunningApplication?) -> String {
        if DefaultSettingsStore.shared.get(.pauseUntilTimestamp) > Date().timeIntervalSince1970 {
            return String(localized: "OpenClip is paused")
        }
        guard let name = app?.localizedName else { return String(localized: "OpenClip is paused") }
        return String(localized: "Paused in \(name)")
    }
}

/// Vision's request class predates Sendable; cancelling it from another thread is supported.
private final class RecognitionRequestBox: @unchecked Sendable {
    let request: VNRecognizeTextRequest
    init(request: VNRecognizeTextRequest) { self.request = request }
}

enum CaptureError: Error { case displayUnavailable, noImage }

/// Maps a capture or recognition error to what the user can do about it.
enum CaptureFailure: Equatable {
    case permission, displayUnavailable, captureFailed, recognitionFailed

    init(_ error: Error) {
        if let error = error as? CaptureError {
            self = error == .displayUnavailable ? .displayUnavailable : .captureFailed
        } else if let error = error as? SCStreamError {
            self = error.code == .userDeclined ? .permission : .captureFailed
        } else if (error as NSError).domain == VNErrorDomain {
            self = .recognitionFailed
        } else {
            self = .captureFailed
        }
    }

    var message: String {
        switch self {
        case .permission: return String(localized: "Could not capture text. Allow Screen Recording in System Settings, then try again.")
        case .displayUnavailable: return String(localized: "This display is no longer available. Try again.")
        case .captureFailed: return String(localized: "Could not capture this area. Try again.")
        case .recognitionFailed: return String(localized: "Could not read text in this area.")
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

@MainActor
enum CaptureTextReleaseHandoff {
    static func closeOverlayThenStartWork(closeOverlay: () -> Void, startWork: () -> Void) {
        closeOverlay()
        startWork()
    }
}

@MainActor
final class CaptureCursorLease {
    private let pushCursor: () -> Void
    private let popCursor: () -> Void
    private let setCursor: () -> Void
    private let asyncSet: (@escaping () -> Void) -> Void
    private let asyncReassert: (@escaping () -> Void) -> Void
    private var pushCount = 0
    private(set) var isActive = false

    init(
        pushCursor: @escaping () -> Void = { NSCursor.crosshair.push() },
        popCursor: @escaping () -> Void = { NSCursor.pop() },
        setCursor: @escaping () -> Void = { NSCursor.crosshair.set() },
        asyncSet: @escaping (@escaping () -> Void) -> Void = { work in DispatchQueue.main.async(execute: work) },
        asyncReassert: @escaping (@escaping () -> Void) -> Void = { work in DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work) }
    ) {
        self.pushCursor = pushCursor
        self.popCursor = popCursor
        self.setCursor = setCursor
        self.asyncSet = asyncSet
        self.asyncReassert = asyncReassert
    }

    func begin() {
        guard !isActive else { return }
        isActive = true
        pushIfActive()
        // Activation resets the cursor after the synchronous push, so re-assert once it settles.
        asyncSet { [weak self] in self?.setIfActive() }
        asyncReassert { [weak self] in self?.pushIfActive() }
    }

    func refresh() {
        guard isActive else { return }
        setCursor()
    }

    func end() {
        guard isActive else { return }
        isActive = false
        while pushCount > 0 {
            popCursor()
            pushCount -= 1
        }
    }

    private func pushIfActive() {
        guard isActive else { return }
        pushCursor()
        pushCount += 1
        setCursor()
    }

    private func setIfActive() {
        guard isActive else { return }
        setCursor()
    }
}

@MainActor
enum CaptureOverlayCleanup {
    static func close(closeOverlays: () -> Void, restoreCursor: () -> Void) {
        closeOverlays()
        restoreCursor()
    }
}

struct CaptureTextPopupAnchor: Equatable {
    let cursorPosition: CGPoint
    let mouseDownLocation: CGPoint?

    static func resolve(
        releasePoint: CGPoint,
        mouseDownPoint: CGPoint,
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

struct CaptureRegionGeometry: Equatable {
    let displayID: CGDirectDisplayID
    let sourceRect: CGRect
    let pixelSize: CGSize

    static func map(rect: CGRect, screenFrame: CGRect, scale: CGFloat, displayID: CGDirectDisplayID) -> CaptureRegionGeometry? {
        let clamped = rect.standardized.intersection(screenFrame)
        guard clamped.width >= 8, clamped.height >= 8 else { return nil }
        let local = CGRect(x: clamped.minX - screenFrame.minX,
                           y: screenFrame.maxY - clamped.maxY,
                           width: clamped.width, height: clamped.height)
        let safeScale = max(1, scale)
        return CaptureRegionGeometry(
            displayID: displayID,
            sourceRect: local,
            pixelSize: CGSize(width: local.width * safeScale, height: local.height * safeScale)
        )
    }
}

@MainActor
private final class RegionSelectionPanel: NSPanel {
    private let displayScreen: NSScreen
    var onCursorRefresh: (() -> Void)?
    var onSelection: ((CGRect, CGPoint, CGPoint, NSScreen) -> Void)?

    init(screen: NSScreen) {
        displayScreen = screen
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        contentView = RegionSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size), owner: self)
    }

    // Becoming key would take focus from the source window, which is exactly what activation did.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    fileprivate func refreshCaptureCursor() { onCursorRefresh?() }
    fileprivate func finish(_ rect: CGRect, releasePoint: CGPoint, mouseDownPoint: CGPoint) {
        onSelection?(rect, releasePoint, mouseDownPoint, displayScreen)
    }
}

@MainActor
private final class RegionSelectionView: NSView {
    weak var owner: RegionSelectionPanel?
    private var cursorTrackingArea: NSTrackingArea?
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var mouseDownScreenPoint: CGPoint?

    init(frame: CGRect, owner: RegionSelectionPanel) { self.owner = owner; super.init(frame: frame) }
    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorTrackingArea {
            removeTrackingArea(cursorTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.cursorUpdate, .mouseMoved, .activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        cursorTrackingArea = trackingArea
    }

    override func cursorUpdate(with event: NSEvent) {
        owner?.refreshCaptureCursor()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        owner?.refreshCaptureCursor()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        owner?.refreshCaptureCursor()
    }

    override func mouseMoved(with event: NSEvent) {
        owner?.refreshCaptureCursor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            NSCursor.crosshair.set()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.32).setFill()
        bounds.fill()
        if let startPoint, let currentPoint {
            let rect = CGRect(x: min(startPoint.x, currentPoint.x), y: min(startPoint.y, currentPoint.y), width: abs(currentPoint.x - startPoint.x), height: abs(currentPoint.y - startPoint.y))
            NSColor.white.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 2
            path.stroke()
            NSColor.white.withAlphaComponent(0.16).setFill()
            path.fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        owner?.refreshCaptureCursor()
        startPoint = convert(event.locationInWindow, from: nil)
        mouseDownScreenPoint = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        currentPoint = startPoint
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        owner?.refreshCaptureCursor()
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let startPoint else { return }
        owner?.refreshCaptureCursor()
        currentPoint = convert(event.locationInWindow, from: nil)
        let local = CGRect(x: min(startPoint.x, currentPoint!.x), y: min(startPoint.y, currentPoint!.y), width: abs(startPoint.x - currentPoint!.x), height: abs(startPoint.y - currentPoint!.y))
        let screenRect = local.offsetBy(dx: owner?.frame.minX ?? 0, dy: owner?.frame.minY ?? 0)
        let releasePoint = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        owner?.finish(screenRect, releasePoint: releasePoint, mouseDownPoint: mouseDownScreenPoint ?? releasePoint)
    }
}
