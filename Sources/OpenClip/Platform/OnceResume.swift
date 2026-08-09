// OnceResume.swift
// OpenClip
//
// Guarantees a `CheckedContinuation` is resumed exactly once when two or more racing producers
// (a worker and a deadline watchdog) may both try to settle it. Mirrors the TimeoutFlag/OnceGate
// lock-guarded pattern used across the runtimes. Split out of MacTextRetriever.swift.
import Foundation

/// Guarantees a `CheckedContinuation` is resumed exactly once when two or more racing producers
/// (a worker and a deadline watchdog) may both try to settle it. Mirrors the TimeoutFlag/OnceGate
/// lock-guarded pattern used across the runtimes.
final class OnceResume<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    @discardableResult
    func resume(_ continuation: CheckedContinuation<T, Never>, with value: T) -> Bool {
        lock.lock()
        if resumed {
            lock.unlock()
            return false
        }
        resumed = true
        lock.unlock()
        continuation.resume(returning: value)
        return true
    }
}

/// A thread-safe reference container for a `Task` to allow cross-isolation task cancellation.
/// Tracks cancellation even before a task is registered: a task registered after `cancel()` has
/// been called is cancelled immediately, so a deadline-triggered cancel is never lost to a
/// registration race (exec/timeout worker pairs in MacTextRetriever).
final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var isCancelled = false

    func set(_ task: Task<Void, Never>) {
        lock.lock()
        self.task = task
        let shouldCancel = isCancelled
        lock.unlock()
        if shouldCancel { task.cancel() }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let t = task
        lock.unlock()
        t?.cancel()
    }
}
