// ExtensionsDirectoryWatcher.swift
// OpenClip
//
// Hot-reloads extensions after filesystem changes settle, without scanning while idle.
import Foundation
import CoreServices
import Core

/// Immutable fingerprint of a directory tree. Two equal snapshots mean no file changed.
struct ExtensionsSnapshot: Equatable, Sendable {
    /// Relative file path (from the watched root) -> content modification date.
    let files: [String: Date]

    /// Recursively fingerprints non-hidden files under `root`; nil if missing or unreadable.
    /// Hidden items (`.install_staging_*`, .DS_Store) are skipped.
    static func build(from root: URL) -> ExtensionsSnapshot? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue,
              let enumerator = FileManager.default.enumerator(
                  at: root,
                  includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                  options: [.skipsHiddenFiles]
              ) else { return nil }

        let rootPath = root.standardizedFileURL.path
        var files: [String: Date] = [:]
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey]),
                  values.isDirectory != true,
                  let date = values.contentModificationDate else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(rootPath + "/") else { continue }
            let relativePath = String(path.dropFirst(rootPath.count + 1))
            files[relativePath] = date
        }
        return ExtensionsSnapshot(files: files)
    }
}

/// Filesystem events start bounded settling checks; unchanged trees have no scheduled work.
final class ExtensionsDirectoryWatcher: @unchecked Sendable {
    static let defaultSettleInterval: TimeInterval = 1.0

    private let queue = DispatchQueue(label: "com.openclip.extensions.watch")
    private let snapshot: @Sendable (URL) -> ExtensionsSnapshot?
    private let reload: @MainActor () async -> Void

    // State below is confined to `queue`.
    private var stream: FSEventStreamRef?
    private var settleWorkItem: DispatchWorkItem?
    private var session = UUID()
    private var interval = defaultSettleInterval
    private var root: URL?
    private var lastSeen: ExtensionsSnapshot?
    private var pending: ExtensionsSnapshot?
    private var reloadInFlight = false
    private var needsReload = false

    private final class StreamContext {
        weak var watcher: ExtensionsDirectoryWatcher?
        let session: UUID

        init(watcher: ExtensionsDirectoryWatcher, session: UUID) {
            self.watcher = watcher
            self.session = session
        }
    }

    init(
        snapshot: @escaping @Sendable (URL) -> ExtensionsSnapshot? = ExtensionsSnapshot.build,
        reload: @escaping @MainActor () async -> Void
    ) {
        self.snapshot = snapshot
        self.reload = reload
    }

    deinit {
        settleWorkItem?.cancel()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    func start(watching root: URL, interval: TimeInterval = ExtensionsDirectoryWatcher.defaultSettleInterval) {
        queue.async { [weak self] in
            guard let self, self.root == nil else { return }
            let root = URL(fileURLWithPath: Self.canonicalPath(root.path))
            self.root = root
            self.interval = max(0.01, interval)
            self.session = UUID()
            self.pending = nil
            guard self.startStream(watching: root) else {
                self.root = nil
                Log.extensions.error("Could not start extension filesystem monitoring")
                return
            }
            self.lastSeen = self.snapshot(root)
        }
    }

    private func startStream(watching root: URL) -> Bool {
        // Watching an existing ancestor also catches removal/recreation of the extensions root.
        var ancestor = root.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            ancestor.deleteLastPathComponent()
        }
        let box = StreamContext(watcher: self, session: session)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(box).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<StreamContext>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<StreamContext>.fromOpaque(info).release()
            },
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer
        )
        let createdStream = withExtendedLifetime(box) {
            FSEventStreamCreate(
                nil,
                { _, info, count, paths, flags, _ in
                    guard let info else { return }
                    let box = Unmanaged<StreamContext>.fromOpaque(info).takeUnretainedValue()
                    let paths = unsafeBitCast(paths, to: NSArray.self) as! [String]
                    box.watcher?.handleEvents(paths: paths, flags: flags, count: count, session: box.session)
                },
                &context,
                [ancestor.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                min(interval, 0.25),
                flags
            )
        }
        guard let stream = createdStream else { return false }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return false
        }
        self.stream = stream
        return true
    }

    private func handleEvents(
        paths: [String], flags: UnsafePointer<FSEventStreamEventFlags>, count: Int, session: UUID
    ) {
        guard session == self.session, let root else { return }
        let rescanFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped
                | kFSEventStreamEventFlagRootChanged
        )
        for index in 0..<count {
            let path = Self.canonicalPath(paths[index])
            let isDescendant = path.hasPrefix(root.path + "/")
            let isVisible = isDescendant && !path.dropFirst(root.path.count + 1)
                .split(separator: "/").contains(where: { $0.hasPrefix(".") })
            if flags[index] & rescanFlags != 0 || path == root.path || isVisible
                || root.path.hasPrefix(path + "/") {
                scheduleCheck()
                return
            }
        }
    }

    private static func canonicalPath(_ path: String) -> String {
        // Foundation normalizes /private differently once a deleted path no longer exists.
        var ancestor = URL(fileURLWithPath: path).standardizedFileURL
        var missingComponents: [String] = []
        while true {
            if let resolved = realpath(ancestor.path, nil) {
                defer { free(resolved) }
                return missingComponents.reversed().reduce(String(cString: resolved)) {
                    ($0 as NSString).appendingPathComponent($1)
                }
            }
            guard ancestor.path != "/" else { return path }
            missingComponents.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.session = UUID()
            self.settleWorkItem?.cancel()
            self.settleWorkItem = nil
            if let stream = self.stream {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
            }
            self.stream = nil
            self.root = nil
            self.lastSeen = nil
            self.pending = nil
            self.needsReload = false
        }
    }

    /// Drives snapshot reconciliation synchronously in tests.
    func pollOnce() {
        queue.sync { [weak self] in
            self?.settleWorkItem?.cancel()
            self?.settleWorkItem = nil
            self?.poll()
        }
    }

    private func scheduleCheck() {
        settleWorkItem?.cancel()
        let session = session
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.session == session, self.root != nil else { return }
            self.settleWorkItem = nil
            self.poll()
        }
        settleWorkItem = work
        queue.asyncAfter(deadline: .now() + interval, execute: work)
    }

    /// Runs on `queue` only.
    private func poll() {
        guard let root else { return }
        guard let current = snapshot(root) else {
            // Missing or unreadable (e.g. a package mid-replacement): skip, so the registry is kept.
            pending = nil
            return
        }
        if current == lastSeen {
            pending = nil
            return
        }
        guard let pending else {
            // First differing tick: remember it and wait for a second agreeing tick.
            self.pending = current
            scheduleCheck()
            return
        }
        guard pending == current else {
            // Still settling (kept changing since the last tick); slide the reference forward.
            self.pending = current
            scheduleCheck()
            return
        }
        lastSeen = current
        self.pending = nil
        guard !reloadInFlight else {
            // Defer until the in-flight reload completes, so loadExtensions never races the registry.
            needsReload = true
            return
        }
        Log.extensions.notice("Extensions directory changed; reloading extensions")
        dispatchReload()
    }

    /// Starts a reload task on the MainActor. Called from `queue` so the in-flight flags stay confined.
    private func dispatchReload() {
        reloadInFlight = true
        let session = session
        Task { @MainActor [weak self] in
            guard let self else { return }
            let isCurrent = self.queue.sync { self.session == session && self.root != nil }
            if isCurrent { await self.reload() }
            self.reloadCompleted()
        }
    }

    /// Runs on the MainActor after `reload`; hops back to `queue` to clear the in-flight flag.
    private func reloadCompleted() {
        queue.async { [weak self] in
            guard let self else { return }
            self.reloadInFlight = false
            guard self.needsReload, self.root != nil else { return }
            self.needsReload = false
            Log.extensions.notice("Extensions directory changed while reloading; reloading again")
            self.dispatchReload()
        }
    }
}
