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

    func resume(_ continuation: CheckedContinuation<T, Never>, with value: T) {
        lock.lock()
        if resumed {
            lock.unlock()
            return
        }
        resumed = true
        lock.unlock()
        continuation.resume(returning: value)
    }
}
