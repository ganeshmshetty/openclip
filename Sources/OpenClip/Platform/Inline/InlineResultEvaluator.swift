// InlineResultEvaluator.swift
// OpenClip
//
// Coordinates multi-tier non-blocking inline result evaluation for actions declaring
// `ActionChrome.isInlineResult == true`.
//
// - Tier 1: Instant synchronous pure-Swift evaluation (<0.1ms, e.g. CalculateAction)
// - Tier 2: Selection-probe prewarming (5-20ms AX retrieval overlap)
// - Tier 3: Asynchronous background execution bounded by hard timeout with session cancellation
import Foundation
import Core

@MainActor
public final class InlineResultEvaluator {
    public static let shared = InlineResultEvaluator()

    private var prewarmedResults: [String: (result: String, textHash: Int)] = [:]
    private var prewarmedTasks: [String: (task: Task<String?, Never>, textHash: Int)] = [:]
    private var memoizedResults: [Int: [String: String]] = [:]
    private var memoizedKeys: [Int] = []
    private var runningTasks: [UUID: [String: Task<String?, Never>]] = [:]

    public init() {}

    private func storeMemoized(textHash: Int, actionID: String, result: String) {
        if memoizedResults[textHash] == nil {
            memoizedKeys.append(textHash)
            if memoizedKeys.count > 50 {
                let oldest = memoizedKeys.removeFirst()
                memoizedResults.removeValue(forKey: oldest)
            }
            memoizedResults[textHash] = [:]
        }
        memoizedResults[textHash]?[actionID] = result
    }

    /// Tier 1: Evaluates synchronous built-in actions immediately without spawning tasks.
    public func evaluateSynchronous(action: any Action, context: ActionContext) -> String? {
        guard action.chrome.isInlineResult else { return nil }
        if let calculate = action as? CalculateAction {
            return calculate.evaluateSynchronously(context.selection.text)
        }
        return nil
    }

    @MainActor
    private static func javaScriptAction(from action: any Action) -> JavaScriptAction? {
        switch action {
        case let javaScriptAction as JavaScriptAction:
            return javaScriptAction
        case let decorated as DeliveryDecoratedAction:
            return javaScriptAction(from: decorated.base)
        case let decorated as KeywordDecoratedAction:
            return javaScriptAction(from: decorated.base)
        case let decorated as MenuDecoratedAction:
            return javaScriptAction(from: decorated.base)
        default:
            return nil
        }
    }

    @MainActor
    private static func performAction(
        _ action: any Action,
        context: ActionContext,
        timeout: TimeInterval
    ) async -> String? {
        do {
            let result: ActionResult
            if let javaScriptAction = javaScriptAction(from: action) {
                result = try await javaScriptAction.perform(context, timeout: timeout)
            } else {
                result = try await action.perform(context)
            }
            switch result {
            case .text(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : text
            default:
                return nil
            }
        } catch {
            return nil
        }
    }

    /// Evaluates an inline action asynchronously with a hard execution timeout.
    /// If the action exceeds the timeout budget, the task is cancelled and nil is returned.
    public func evaluateAsync(
        action: any Action,
        context: ActionContext,
        timeout: TimeInterval = PopupMetrics.inlineEvaluationTimeout
    ) async -> String? {
        guard action.chrome.isInlineResult else { return nil }

        let boundedTimeout = max(0.001, timeout)
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                await Self.performAction(action, context: context, timeout: boundedTimeout)
            }

            group.addTask {
                let nanos = UInt64(boundedTimeout * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                return nil
            }

            let first = await group.next()
            group.cancelAll()
            return first ?? nil
        }
    }

    /// Tier 2: Populates the prewarm cache for synchronous and asynchronous inline actions during selection retrieval.
    public func prewarm(actions: [any Action], context: ActionContext) {
        let text = context.selection.text
        let hash = text.hashValue
        for action in actions where action.chrome.isInlineResult {
            if let memo = memoizedResults[hash]?[action.id] {
                prewarmedResults[action.id] = (result: memo, textHash: hash)
            } else if let syncResult = evaluateSynchronous(action: action, context: context) {
                prewarmedResults[action.id] = (result: syncResult, textHash: hash)
                storeMemoized(textHash: hash, actionID: action.id, result: syncResult)
            } else {
                if let existing = prewarmedTasks[action.id], existing.textHash == hash {
                    continue
                }
                let task = Task { @MainActor [weak self] () -> String? in
                    guard let self else { return nil }
                    let result = await self.evaluateAsync(action: action, context: context)
                    guard !Task.isCancelled else { return nil }
                    if let result, !result.isEmpty {
                        self.prewarmedResults[action.id] = (result: result, textHash: hash)
                        self.storeMemoized(textHash: hash, actionID: action.id, result: result)
                    }
                    return result
                }
                prewarmedTasks[action.id] = (task: task, textHash: hash)
            }
        }
    }

    /// Awaits pending prewarm evaluation tasks up to the given anticipation timeout budget.
    public func awaitPrewarmed(timeout: TimeInterval = 0.025) async {
        let activeTasks = prewarmedTasks.values.map(\.task)
        guard !activeTasks.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for task in activeTasks {
                group.addTask {
                    _ = await task.value
                }
            }
            group.addTask {
                let nanos = UInt64(max(0.001, timeout) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
            _ = await group.next()
            group.cancelAll()
        }
    }

    /// Returns a prewarmed result if present and valid for the given selected text hash.
    public func prewarmedResult(for actionID: String, textHash: Int) -> String? {
        if let cached = prewarmedResults[actionID], cached.textHash == textHash {
            return cached.result
        }
        if let memo = memoizedResults[textHash]?[actionID] {
            return memo
        }
        return nil
    }

    /// Clears prewarmed cache entries and cancels in-flight prewarm tasks.
    public func clearPrewarmed() {
        for entry in prewarmedTasks.values {
            entry.task.cancel()
        }
        prewarmedTasks.removeAll()
        prewarmedResults.removeAll()
        memoizedResults.removeAll()
        memoizedKeys.removeAll()
    }

    /// Tier 3: Registers and starts background evaluation of an inline action for a popup session.
    public func startEvaluation(
        action: any Action,
        context: ActionContext,
        sessionID: UUID,
        timeout: TimeInterval = PopupMetrics.inlineEvaluationTimeout,
        onResult: @escaping @MainActor (String?) -> Void
    ) {
        guard action.chrome.isInlineResult else {
            onResult(nil)
            return
        }

        let hash = context.selection.text.hashValue
        if let cached = prewarmedResult(for: action.id, textHash: hash) {
            onResult(cached)
            return
        }

        let prewarmed = prewarmedTasks[action.id]
        let task = Task { @MainActor [weak self] () -> String? in
            guard let self else { return nil }
            guard !Task.isCancelled else { return nil }

            let result: String?
            if let prewarmed, prewarmed.textHash == hash {
                result = await prewarmed.task.value
            } else {
                result = await self.evaluateAsync(
                    action: action,
                    context: context,
                    timeout: timeout
                )
            }

            guard !Task.isCancelled else { return nil }

            if let result, !result.isEmpty {
                self.storeMemoized(textHash: hash, actionID: action.id, result: result)
            }

            self.runningTasks[sessionID]?.removeValue(forKey: action.id)
            if self.runningTasks[sessionID]?.isEmpty == true {
                self.runningTasks.removeValue(forKey: sessionID)
            }

            onResult(result)
            return result
        }

        if runningTasks[sessionID] == nil {
            runningTasks[sessionID] = [:]
        }
        runningTasks[sessionID]?[action.id] = task
    }

    /// Returns an existing in-flight evaluation task for click-race joining.
    public func runningTask(for actionID: String, sessionID: UUID) -> Task<String?, Never>? {
        runningTasks[sessionID]?[actionID]
    }

    /// Returns an existing in-flight evaluation task across all sessions for click-race joining.
    public func runningTask(for actionID: String) -> Task<String?, Never>? {
        for tasks in runningTasks.values {
            if let task = tasks[actionID] {
                return task
            }
        }
        return nil
    }

    /// Cancels and removes all in-flight evaluation tasks for a popup session.
    public func cancelSession(_ sessionID: UUID) {
        if let sessionTasks = runningTasks.removeValue(forKey: sessionID) {
            for task in sessionTasks.values {
                task.cancel()
            }
        }
    }
}
