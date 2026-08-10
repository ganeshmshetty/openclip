// ExtensionsDirectoryWatcher.swift
// OpenClip
//
// Watches ~/.openclip/extensions for add/remove/edit changes and hot-reloads the loaded
// extension actions (new installs, uninstalls, and manifest edits appear without relaunch).
//
// Uses a lightweight poll-snapshot diff instead of FSEvents: each tick builds a recursive
// fingerprint of the tree (relative file path -> content mtime), compares it to the previous
// state, and calls the reload callback only once two consecutive ticks agree that the tree
// settled. The settle window keeps a reload from firing mid-copy when a package is still
// being written. Pure Foundation — no CoreServices, no FSEventStream.
import Foundation
import Core

/// Immutable fingerprint of a directory tree. Two equal snapshots mean no file changed.
struct ExtensionsSnapshot: Equatable {
    /// Relative file path (from the watched root) -> content modification date.
    let files: [String: Date]

    /// Recursively fingerprints every non-hidden file under `root`.
    /// Returns `nil` if the directory does not exist or is unreadable.
    /// Hidden items are skipped, matching `uninstallExtension`'s convention of ignoring
    /// `.install_staging_*` dirs and dotfiles .DS_Store left behind by installs.
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

/// Polls a directory, diffs `ExtensionsSnapshot`s, and fires a reload after a change settles.
/// The timer runs on a private queue; the reload closure is invoked on the MainActor.
final class ExtensionsDirectoryWatcher: @unchecked Sendable {
    /// Poll interval. The settle window is two consecutive agreeing ticks, so a change shows
    /// up within ~2× this interval.
    static let defaultPollInterval: TimeInterval = 1.0

    private let queue = DispatchQueue(label: "com.openclip.extensions.watch")
    private var timer: DispatchSourceTimer?

    /// Invoked on the MainActor when the directory tree settles into a new state.
    private let reload: @MainActor () async -> Void

    // State below is confined to `queue`.
    private var root: URL?
    private var lastSeen: ExtensionsSnapshot?
    private var pending: ExtensionsSnapshot?

    init(reload: @escaping @MainActor () async -> Void) {
        self.reload = reload
    }

    func start(watching root: URL, interval: TimeInterval = ExtensionsDirectoryWatcher.defaultPollInterval) {
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            self.root = root
            self.lastSeen = ExtensionsSnapshot.build(from: root)
            self.pending = nil
            let newTimer = DispatchSource.makeTimerSource(queue: self.queue)
            newTimer.schedule(deadline: .now() + interval, repeating: interval)
            newTimer.setEventHandler { [weak self] in
                self?.poll()
            }
            newTimer.resume()
            self.timer = newTimer
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
            self?.root = nil
            self?.lastSeen = nil
            self?.pending = nil
        }
    }

    /// Runs a single poll tick synchronously on the watch queue. Exposed so tests can drive
    /// the settle logic without waiting on the live timer.
    func pollOnce() {
        queue.sync { [weak self] in
            self?.poll()
        }
    }

    /// Runs on `queue` only.
    private func poll() {
        guard let root else { return }
        guard let current = ExtensionsSnapshot.build(from: root) else {
            // Directory missing or unreadable: don't reload. A transient state (e.g. a package
            // deleted mid-replacement) shouldn't wipe the registry.
            return
        }
        if current == lastSeen {
            pending = nil
            return
        }
        guard let pending else {
            // First differing tick: remember it and wait for a second agreeing tick.
            self.pending = current
            return
        }
        guard pending == current else {
            // Still settling (kept changing since the last tick); slide the reference forward.
            self.pending = current
            return
        }
        // Two consecutive ticks agree on the changed tree → settled.
        lastSeen = current
        self.pending = nil
        Log.extensions.notice("Extensions directory changed; reloading extensions")
        Task { @MainActor in
            await reload()
        }
    }
}