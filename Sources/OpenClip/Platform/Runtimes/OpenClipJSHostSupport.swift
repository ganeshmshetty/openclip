// OpenClipJSHostSupport.swift
// OpenClip
//
// Threading/support boxes for OpenClipJSHost: the watchdog timeout flag, the sync-evaluation
// gate, JS-context/value/runloop boxes, and the mutable collections used to ferry results out of
// the JS effect blocks. Split out of OpenClipJSHost.swift.
import Foundation
import JavaScriptCore
import Core

/// Bounds the number of concurrent synchronous JS evaluations. A stuck sync script holds its slot
/// forever (it cannot be interrupted), so `tryEnter` refuses new evaluations once the cap is
/// reached instead of leaking more cooperative-pool threads.
final class SyncEvaluationGate: @unchecked Sendable {
    private let lock = NSLock()
    let capacity: Int
    private var inFlight = 0

    init(capacity: Int) {
        self.capacity = capacity
    }

    func tryEnter() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard inFlight < capacity else { return false }
        inFlight += 1
        return true
    }

    func leave() {
        lock.lock()
        defer { lock.unlock() }
        inFlight -= 1
    }

    var inFlightCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return inFlight
    }
}

/// Boxes the JS context so the fetch completion handler can hand it back to the JS thread's
/// runloop. The context is only ever *used* on the JS thread.
final class JSContextBox: @unchecked Sendable {
    let context: JSContext
    init(_ context: JSContext) { self.context = context }
}

/// Boxes a JSValue so a `@Sendable` URLSession completion can hand it back to the JS thread's
/// runloop without the compiler rejecting a non-Sendable capture. The value is only ever *used* on
/// the JS thread (inside the CFRunLoopPerformBlock).
final class JSValueBox: @unchecked Sendable {
    let value: JSValue
    init(_ value: JSValue) { self.value = value }
}

final class RunLoopBox: @unchecked Sendable {
    let runLoop: CFRunLoop
    init(_ runLoop: CFRunLoop) { self.runLoop = runLoop }
}

/// Mutable evaluation state written by the JS effect blocks and read back on the host thread. Boxed
/// so the `@convention(block)` closures capture a Sendable reference instead of a non-Sendable local
/// `var` — the region-based isolation checker rejects the direct capture inside a `Task.detached`
/// region.
final class CollectedBox: @unchecked Sendable {
    var value: OpenClipJSHost.Collected
    init() { self.value = OpenClipJSHost.Collected() }
}

/// Call-ordered side effects collected from the JS effect blocks (mirrors CollectedBox rationale).
final class EffectsBox: @unchecked Sendable {
    var value: [OpenClipJSHost.Effect]
    init() { self.value = [] }
}

/// Settled by the promise bridge on the JS thread (via `openclip.__resolve`/`__reject`) and read by
/// the host's pump loop on that same thread. Lock-guarded so property access across threads/closures is safe.
final class PromiseState: @unchecked Sendable {
    private let lock = NSLock()
    private var _isSettled = false
    private var _resolvedValue: JSValue?
    private var _rejectedValue: JSValue?

    var isSettled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isSettled
    }

    var resolvedValue: JSValue? {
        lock.lock()
        defer { lock.unlock() }
        return _resolvedValue
    }

    var rejectedValue: JSValue? {
        lock.lock()
        defer { lock.unlock() }
        return _rejectedValue
    }

    func resolve(_ value: JSValue) {
        lock.lock()
        defer { lock.unlock() }
        guard !_isSettled else { return }
        _resolvedValue = value
        _isSettled = true
    }

    func reject(_ error: JSValue) {
        lock.lock()
        defer { lock.unlock() }
        guard !_isSettled else { return }
        _rejectedValue = error
        _isSettled = true
    }
}

/// Boxes the stable `URLSessionDataTask.taskIdentifier` so the fetch completion can remove its own
/// task without capturing a mutable reference across threads. The identifier is written on the JS
/// thread before `resume()` and read back on the URLSession completion thread.
final class TaskIdentifierBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
    func set(_ value: Int) {
        lock.lock()
        defer { lock.unlock() }
        _value = value
    }
}

/// Thread-safe container to track active URLSessionDataTasks so they can be cancelled on watchdog timeout.
/// `cancelAll()` is terminal: once cancellation starts, any task added afterwards is cancelled
/// immediately rather than being appended (so a task racing in during `cancelAll()` cannot escape
/// cancellation).
final class FetchTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [URLSessionDataTask] = []
    private var cancelled = false

    func add(_ task: URLSessionDataTask) {
        lock.lock()
        defer { lock.unlock() }
        if cancelled {
            task.cancel()
            return
        }
        tasks.append(task)
    }

    /// Removes the tracked task with the given stable `taskIdentifier`.
    func remove(_ identifier: Int) {
        lock.lock()
        defer { lock.unlock() }
        tasks.removeAll(where: { $0.taskIdentifier == identifier })
    }

    func cancelAll() {
        lock.lock()
        cancelled = true
        let currentTasks = tasks
        tasks.removeAll()
        lock.unlock()
        for task in currentTasks {
            task.cancel()
        }
    }
}


