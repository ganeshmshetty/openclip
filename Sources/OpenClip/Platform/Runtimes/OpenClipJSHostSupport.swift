// OpenClipJSHostSupport.swift
// OpenClip
//
// Threading/support boxes for OpenClipJSHost: the watchdog timeout flag, the sync-evaluation
// gate, JS-context/value/runloop boxes, and the mutable collections used to ferry results out of
// the JS effect blocks. Split out of OpenClipJSHost.swift.
import Foundation
import JavaScriptCore
import Core

private typealias OpenClipJSTerminationCallback = @convention(c) (
    JSContextRef?,
    UnsafeMutableRawPointer?
) -> Bool

// JavaScriptCore's Objective-C API no longer exposes JSVirtualMachine.invalidate(), but its C API
// still exports the VM watchdog used by WebKit. Declare the two functions here because Apple ships
// their declarations in JSContextRefPrivate.h rather than the public module interface.
@_silgen_name("JSContextGroupSetExecutionTimeLimit")
private func setJSContextGroupExecutionTimeLimit(
    _ group: JSContextGroupRef,
    _ limit: Double,
    _ callback: OpenClipJSTerminationCallback?,
    _ callbackData: UnsafeMutableRawPointer?
)

@_silgen_name("JSContextGroupClearExecutionTimeLimit")
private func clearJSContextGroupExecutionTimeLimit(_ group: JSContextGroupRef)

private func terminateTimedOutScript(
    _: JSContextRef?,
    _ callbackData: UnsafeMutableRawPointer?
) -> Bool {
    if let callbackData {
        Unmanaged<TimeoutFlag>.fromOpaque(callbackData).takeUnretainedValue().markTimedOut()
    }
    return true
}

/// Owns JavaScriptCore's execution-time limit for one context. The runtime invokes the callback and
/// terminates synchronous JavaScript even while `evaluateScript` is still on the stack.
final class JSExecutionTimeLimit {
    private let context: JSContext
    private let group: JSContextGroupRef
    private let timeoutFlag: TimeoutFlag
    private var isCleared = false

    init(context: JSContext, timeout: TimeInterval, timeoutFlag: TimeoutFlag) {
        self.context = context
        group = JSContextGetGroup(context.jsGlobalContextRef)
        self.timeoutFlag = timeoutFlag
        setJSContextGroupExecutionTimeLimit(
            group,
            timeout,
            terminateTimedOutScript,
            Unmanaged.passUnretained(self.timeoutFlag).toOpaque()
        )
    }

    deinit {
        clear()
    }

    func clear() {
        guard !isCleared else { return }
        isCleared = true
        clearJSContextGroupExecutionTimeLimit(group)
    }
}

/// Bounds the number of concurrent synchronous JS evaluations. When a run carries a budget, the
/// runtime execution limit makes its slot recoverable after timeout; the cap still protects against
/// concurrent startup bursts. A run with no budget holds its slot until it settles.
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

/// Boxes the JS context **weakly** so a URLSession completion handler — which runs on a worker
/// thread — can hand the context back to the JS thread's runloop without strongly retaining it.
/// Holding a strong `JSContext` (directly or through a JSValue) from an off-thread closure risks
/// releasing the last JavaScript reference off the JS thread, which the memory-safety note in
/// `docs/architecture/known-debt.md` forbids. The evaluation retains its own context for the whole
/// run, so the weak reference is live exactly while the run is; afterwards the completion is
/// discarded by `FetchTaskBox.isEnded` anyway.
final class WeakJSContextBox: @unchecked Sendable {
    weak var context: JSContext?
    init(_ context: JSContext) { self.context = context }
}

/// Weak, Sendable handle to an arbitrary object, so an off-thread closure can reach a
/// JS-thread-owned object without retaining it — and without the compiler rejecting the capture.
/// Used by the fetch bridge so a URLSession completion (worker thread) can hand work to the JS
/// thread's runloop while holding no strong JavaScript reference (issue #47).
final class WeakRef<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

/// JS-thread-owned store of the resolve/reject functions for in-flight fetches, keyed by URL task
/// identifier. The URLSession completion runs on a worker thread and must not hold JavaScript
/// references — releasing the last one off the JS thread is the memory-safety hazard called out in
/// `docs/architecture/known-debt.md` — so it looks the pair up here (through a `WeakRef`) inside the
/// JS thread's runloop block. Entries are removed when settled, or released with this object at the
/// end of the run, always on the JS thread.
final class FetchResolvers: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [Int: (resolve: JSValue, reject: JSValue)] = [:]

    func register(_ identifier: Int, resolve: JSValue, reject: JSValue) {
        lock.lock()
        entries[identifier] = (resolve, reject)
        lock.unlock()
    }

    /// Removes and returns the resolve/reject pair for `identifier`, or nil if it was already
    /// settled or removed.
    func take(_ identifier: Int) -> (resolve: JSValue, reject: JSValue)? {
        lock.lock()
        defer { lock.unlock() }
        return entries.removeValue(forKey: identifier)
    }

    /// Drops every pending pair, releasing the retained resolve/reject JSValues on the calling
    /// thread. Called at the end of a run (on the JS thread) so a fetch that never settled —
    /// cancelled, timed out, or completed after the run ended, all of which skip `take` — cannot
    /// keep its JSContext alive through the registry (issue #47).
    func clearPending() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
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

    /// Drops the settled JSValues once the evaluation has consumed the outcome. The resolve/reject
    /// blocks stored on `openclip` still reference this object, and `openclip` is owned by the
    /// context, so a retained JSValue would reach back to the context and keep the whole
    /// JSVirtualMachine alive (issue #47). Clearing breaks that last edge.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        _resolvedValue = nil
        _rejectedValue = nil
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

/// Thread-safe container that tracks in-flight URLSessionDataTasks and latches the end of the evaluation.
/// `cancelAll()` is terminal: once cancellation starts, any task added afterwards is cancelled
/// immediately rather than being appended (so a task racing in during `cancelAll()` cannot escape
/// cancellation).
final class FetchTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [URLSessionDataTask] = []
    private var ended = false
    private var closeHandler: (@Sendable () -> Void)?
    private var didClose = false

    /// True after the evaluation ends. The fetch bridge reads this before it calls the JavaScript VM.
    var isEnded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ended
    }

    func add(_ task: URLSessionDataTask) {
        lock.lock()
        let shouldCancel = ended
        if !shouldCancel {
            tasks.append(task)
        }
        lock.unlock()
        if shouldCancel {
            task.cancel()
        }
    }

    /// Removes the tracked task with the given stable `taskIdentifier`.
    func remove(_ identifier: Int) {
        lock.lock()
        defer { lock.unlock() }
        tasks.removeAll(where: { $0.taskIdentifier == identifier })
    }

    /// Registers a one-shot cleanup that runs when the evaluation ends (`finish()` or
    /// `cancelAll()`), on whichever thread ends it. The fetch bridge uses it to invalidate its
    /// per-evaluation `URLSession`: Apple retains a session — and, with it, its delegate, worker
    /// threads, and Mach ports — until explicit invalidation, so without this every async run
    /// leaked one session for the life of the process (issue #46). If the box has already closed,
    /// the handler runs immediately so a registration racing the end cannot be dropped.
    func setCloseHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        if didClose {
            lock.unlock()
            handler()
            return
        }
        closeHandler = handler
        lock.unlock()
    }

    func finish() {
        lock.lock()
        ended = true
        let handler = takeCloseHandlerLocked()
        lock.unlock()
        handler?()
    }

    func cancelAll() {
        lock.lock()
        ended = true
        let currentTasks = tasks
        tasks.removeAll()
        let handler = takeCloseHandlerLocked()
        lock.unlock()
        for task in currentTasks {
            task.cancel()
        }
        handler?()
    }

    /// Consumes the close handler exactly once, so `finish()` and `cancelAll()` cannot both run it.
    private func takeCloseHandlerLocked() -> (@Sendable () -> Void)? {
        guard !didClose else { return nil }
        didClose = true
        defer { closeHandler = nil }
        return closeHandler
    }
}
