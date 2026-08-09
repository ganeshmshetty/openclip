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
final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    func set(_ task: Task<Void, Never>) {
        lock.lock()
        self.task = task
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let t = task
        lock.unlock()
        t?.cancel()
    }
}
