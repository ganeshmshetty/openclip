// DebugLogStore.swift
// OpenClip
//
// Polls the LogReading source on a background serial queue and accumulates entries
// into a small ring buffer. Production instance: .shared (own-process unified-log
// readback). No UI observes it today; the CLI and tests read snapshots directly.
import Foundation

/// Background-collecting debug log store. `@unchecked Sendable` is sound:
/// `buffer` and `reader` are thread-safe, `cursor` is confined to the poll queue,
/// and `timer` is only touched from the owner (start/stop).
final class DebugLogStore: @unchecked Sendable {
    static let shared: DebugLogStore = DebugLogStore(
        reader: UnifiedLogReader(),
        buffer: DebugLogBuffer(capacity: 500)
    )

    private let reader: any LogReading
    private let buffer: DebugLogBuffer
    private let pollInterval: TimeInterval

    private let queue = DispatchQueue(label: "com.openclip.debuglog.poll")
    private var timer: DispatchSourceTimer?
    private var cursor: Date?

    init(reader: any LogReading, buffer: DebugLogBuffer, pollInterval: TimeInterval = 1.0) {
        self.reader = reader
        self.buffer = buffer
        self.pollInterval = pollInterval
    }

    func start() {
        guard timer == nil else { return }
        let newTimer = DispatchSource.makeTimerSource(queue: queue)
        newTimer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        newTimer.setEventHandler { [weak self] in
            self?.poll()
        }
        newTimer.resume()
        timer = newTimer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Chronological snapshot (oldest → newest).
    func snapshot() -> [DebugLogEntry] {
        buffer.snapshot()
    }

    func entries(matching filter: DebugLogFilter) -> [DebugLogEntry] {
        filter.apply(to: buffer.snapshot())
    }

    func clear() {
        buffer.clear()
    }

    /// Runs on `queue` only. A transient reader error must not kill the loop.
    private func poll() {
        do {
            let newEntries = try reader.read(after: cursor)
            if let lastDate = newEntries.last?.date {
                cursor = lastDate
            }
            buffer.append(contentsOf: newEntries)
        } catch {
            // keep polling on the next tick
        }
    }
}
