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

/// Bounds the number of concurrent synchronous JS evaluations. The runtime execution limit makes
/// each slot recoverable after timeout; the cap still protects against concurrent startup bursts.
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

/// Thread-safe container that tracks in-flight URLSessionDataTasks and latches the end of the evaluation.
/// `cancelAll()` is terminal: once cancellation starts, any task added afterwards is cancelled
/// immediately rather than being appended (so a task racing in during `cancelAll()` cannot escape
/// cancellation).
final class FetchTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [URLSessionDataTask] = []
    private var ended = false

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

    /// Marks the end of the evaluation. In-flight tasks continue, and their results are discarded.
    func finish() {
        lock.lock()
        defer { lock.unlock() }
        ended = true
    }

    func cancelAll() {
        lock.lock()
        ended = true
        let currentTasks = tasks
        tasks.removeAll()
        lock.unlock()
        for task in currentTasks {
            task.cancel()
        }
    }
}
