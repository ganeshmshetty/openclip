// ClipBasketPasteboardMonitor.swift
// OpenClip
//
// Scoped ⌘C capture: polls NSPasteboard.general only while the basket panel is open. Excluded apps,
// disabled rules, protected pasteboard types and OpenClip's own marked paste writes never reach the
// basket. Reads run off the main actor with a bounded wait.
import AppKit
import Core

@MainActor
final class ClipBasketPasteboardMonitor {
    typealias CaptureHandler = @MainActor (ClipBasketContent, AppIdentity?) -> Void
    typealias IdentityProvider = @MainActor () -> AppIdentity?
    typealias ExclusionChecker = @MainActor (String) -> Bool
    typealias DisabledChecker = @MainActor (AppIdentity) -> Bool

    private static let readTimeout: UInt64 = 2_000_000_000

    private struct UncheckedPasteboard: @unchecked Sendable {
        let value: NSPasteboard
    }

    private let pasteboard: NSPasteboard
    private let accessPolicy: PasteboardAccessPolicy
    private let reader: ClipBasketPasteboardReader
    private let frontmostIdentity: IdentityProvider
    private let isExcluded: ExclusionChecker
    private let isDisabled: DisabledChecker
    private let pollInterval: TimeInterval

    private var task: Task<Void, Never>?
    private(set) var lastChangeCount: Int
    private var lastObservedIdentity: AppIdentity?
    private var readToken: UUID?
    private var isReading = false

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
        self.lastObservedIdentity = frontmostIdentity()
    }

    func start() {
        guard task == nil else { return }
        lastChangeCount = pasteboard.changeCount
        lastObservedIdentity = frontmostIdentity()
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
        readToken = nil
        isReading = false
        Log.basket.debug("pasteboard monitor stopped")
    }

    func tick() {
        guard !isReading else { return }

        let current = pasteboard.changeCount
        let identity = frontmostIdentity()
        guard current != lastChangeCount else {
            lastObservedIdentity = identity
            return
        }
        lastChangeCount = current

        guard !accessPolicy.deniesReads else {
            lastObservedIdentity = identity
            Log.basket.debug("pasteboard capture skipped: access denied")
            return
        }
        guard let identity else {
            lastObservedIdentity = nil
            return
        }
        if let bundleID = identity.bundleIdentifier, isExcluded(bundleID) {
            lastObservedIdentity = identity
            return
        }
        guard !isDisabled(identity) else {
            lastObservedIdentity = identity
            return
        }

        // The poll interval is coarse enough that the frontmost app can change between the copy
        // and this tick. Only attribute the change when the writer's app identity is stable.
        guard let previous = lastObservedIdentity, previous.isSameApp(as: identity) else {
            lastObservedIdentity = identity
            Log.basket.debug("pasteboard capture skipped reason=ambiguousWriter")
            return
        }
        lastObservedIdentity = identity
        beginRead(identity: identity)
    }

    private func beginRead(identity: AppIdentity) {
        isReading = true
        let token = UUID()
        readToken = token
        let box = UncheckedPasteboard(value: pasteboard)
        let reader = reader
        Task.detached(priority: .utility) { [weak self] in
            let result = reader.read(from: box.value)
            await MainActor.run {
                guard let self, self.readToken == token else { return }
                self.readToken = nil
                self.isReading = false
                self.handle(result, identity: identity)
            }
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.readTimeout)
            guard let self, self.readToken == token else { return }
            self.readToken = nil
            self.isReading = false
            Log.basket.warning("pasteboard capture read timed out")
        }
    }

    private func handle(_ result: ClipBasketPasteboardReadResult, identity: AppIdentity) {
        switch result {
        case .content(let content):
            onCapture?(content, identity)
        case .ignored(let reason):
            Log.basket.debug("pasteboard capture skipped reason=\(reason.rawValue, privacy: .public)")
        }
    }
}
