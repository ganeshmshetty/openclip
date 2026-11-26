// ClipBasketPasteboardMonitor.swift
// OpenClip
//
// Scoped ⌘C capture: polls NSPasteboard.general only while the basket panel is open. Excluded apps,
// disabled rules, protected pasteboard types and OpenClip's own paste writes never reach the basket.
import AppKit
import Core

@MainActor
final class ClipBasketPasteboardMonitor {
    typealias CaptureHandler = @MainActor (ClipBasketContent, AppIdentity?) -> Void
    typealias IdentityProvider = @MainActor () -> AppIdentity?
    typealias ExclusionChecker = @MainActor (String) -> Bool
    typealias DisabledChecker = @MainActor (AppIdentity) -> Bool

    private let pasteboard: NSPasteboard
    private let accessPolicy: PasteboardAccessPolicy
    private let reader: ClipBasketPasteboardReader
    private let frontmostIdentity: IdentityProvider
    private let isExcluded: ExclusionChecker
    private let isDisabled: DisabledChecker
    private let pollInterval: TimeInterval

    private var task: Task<Void, Never>?
    private(set) var lastChangeCount: Int
    private var isSelfWriting = false

    var onCapture: CaptureHandler?

    var isRunning: Bool { task != nil }

    init(
        pasteboard: NSPasteboard = .general,
        accessPolicy: PasteboardAccessPolicy = PasteboardAccessPolicy(),
        reader: ClipBasketPasteboardReader = ClipBasketPasteboardReader(),
        pollInterval: TimeInterval = 0.25,
        frontmostIdentity: @escaping IdentityProvider = {
            NSWorkspace.shared.frontmostApplication.map(AppIdentity.init)
        },
        isExcluded: @escaping ExclusionChecker = { bundleID in
            AppFilter.isExcluded(bundleID: bundleID)
        },
        isDisabled: @escaping DisabledChecker = { identity in
            RuleEngine.shared.resolvePolicies(for: identity).disabled
        }
    ) {
        self.pasteboard = pasteboard
        self.accessPolicy = accessPolicy
        self.reader = reader
        self.pollInterval = pollInterval
        self.frontmostIdentity = frontmostIdentity
        self.isExcluded = isExcluded
        self.isDisabled = isDisabled
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard task == nil else { return }
        lastChangeCount = pasteboard.changeCount
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64((self?.pollInterval ?? 0.25) * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
        Log.basket.debug("pasteboard monitor started")
    }

    func stop() {
        guard task != nil else { return }
        task?.cancel()
        task = nil
        Log.basket.debug("pasteboard monitor stopped")
    }

    /// Marks a write made by the basket itself, so its synthetic paste and clipboard restore are
    /// consumed without becoming new basket items.
    func beginSelfWrite() {
        isSelfWriting = true
    }

    func endSelfWrite() {
        isSelfWriting = false
        lastChangeCount = pasteboard.changeCount
    }

    func tick() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        guard !isSelfWriting else { return }
        guard !accessPolicy.deniesReads else {
            Log.basket.debug("pasteboard capture skipped: access denied")
            return
        }
        guard let identity = frontmostIdentity() else { return }
        if let bundleID = identity.bundleIdentifier, isExcluded(bundleID) { return }
        guard !isDisabled(identity) else { return }

        switch reader.read(from: pasteboard) {
        case .content(let content):
            onCapture?(content, identity)
        case .ignored(let reason):
            Log.basket.debug("pasteboard capture skipped reason=\(reason.rawValue, privacy: .public)")
        }
    }
}
