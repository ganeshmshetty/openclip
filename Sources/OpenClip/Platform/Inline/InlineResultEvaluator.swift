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

    /// Identity of one memoized inline result: the selection text, the action, and a fingerprint
    /// of the action's evaluated inputs (script + resolved option values). Including the
    /// fingerprint lets the warm cache survive across popups without serving a stale preview after
    /// the extension's script or a configured option changed.
    private struct MemoKey: Hashable {
        let textHash: Int
        let actionID: String
        let fingerprint: Int
    }

    /// Total memoized entries retained across popups. Bounds memory while keeping the common case
    /// (re-selecting the same or similar text) warm instead of re-evaluating from cold every show.
    private static let maxMemoizedEntries = 200

    /// Results longer than this are shown but never memoized, so a script returning a large string
    /// can't pin unbounded memory in the cross-popup cache.
    private static let maxMemoizedResultLength = 1024

    private var prewarmedResults: [String: (result: String, textHash: Int, fingerprint: Int)] = [:]
    private var prewarmedTasks: [String: (task: Task<String?, Never>, textHash: Int, fingerprint: Int)] = [:]
    private var memoizedResults: [MemoKey: String] = [:]
    private var memoizedOrder: [MemoKey] = []
    private var runningTasks: [UUID: [String: Task<String?, Never>]] = [:]

    public init() {}

    private func storeMemoized(key: MemoKey, result: String) {
        guard result.count <= Self.maxMemoizedResultLength else { return }
        if memoizedResults[key] == nil {
            memoizedOrder.append(key)
            if memoizedOrder.count > Self.maxMemoizedEntries {
                let oldest = memoizedOrder.removeFirst()
                memoizedResults.removeValue(forKey: oldest)
            }
        }
        memoizedResults[key] = result
    }

    /// A stable, in-process fingerprint of everything that can change an inline action's output
    /// besides the selected text: its script source and the resolved values of its options.
    /// Pure actions (e.g. Calculate) have no inputs and fingerprint to a constant.
    private func fingerprint(for action: any Action) -> Int {
        guard let javaScriptAction = Self.javaScriptAction(from: action) else { return 0 }
        var hasher = Hasher()
        hasher.combine(javaScriptAction.scriptCode)
        for option in javaScriptAction.actionOptions {
            hasher.combine(option.identifier)
            hasher.combine(javaScriptAction.optionStore.stringValue(actionID: javaScriptAction.id, option: option))
        }
        return hasher.finalize()
    }

    private func memoKey(for action: any Action, textHash: Int) -> MemoKey {
        MemoKey(textHash: textHash, actionID: action.id, fingerprint: fingerprint(for: action))
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
            // Inline evaluation runs before the user clicks the action, so it cannot rely on
            // the click path to populate ActionContext.match. Resolve the same match here so
            // regex based inline actions receive their matched substring (for example `$200`
            // inside a longer selection) instead of trying to parse the entire selection.
            let matchedContext: ActionContext
            if context.match != nil {
                matchedContext = context
            } else if let match = action.matchInfo(for: context) {
                matchedContext = ActionContext(
                    selection: context.selection,
                    modifiers: context.modifiers,
                    isSecondaryClick: context.isSecondaryClick,
                    match: match
                )
            } else {
                matchedContext = context
            }
            let result: ActionResult
            if let javaScriptAction = javaScriptAction(from: action) {
                result = try await javaScriptAction.perform(matchedContext, timeout: timeout)
            } else {
                result = try await action.perform(matchedContext)
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
            if ContextualActionClassifier.unwrap(action) is any LiveInlineAction { continue }
            let key = memoKey(for: action, textHash: hash)
            if let memo = memoizedResults[key] {
                prewarmedResults[action.id] = (result: memo, textHash: hash, fingerprint: key.fingerprint)
            } else if let syncResult = evaluateSynchronous(action: action, context: context) {
                prewarmedResults[action.id] = (result: syncResult, textHash: hash, fingerprint: key.fingerprint)
                storeMemoized(key: key, result: syncResult)
            } else {
                if let existing = prewarmedTasks[action.id],
                   existing.textHash == hash,
                   existing.fingerprint == key.fingerprint {
                    continue
                }
                let task = Task { @MainActor [weak self] () -> String? in
                    guard let self else { return nil }
                    let result = await self.evaluateAsync(action: action, context: context)
                    guard !Task.isCancelled else { return nil }
                    if let result, !result.isEmpty {
                        self.prewarmedResults[action.id] = (result: result, textHash: hash, fingerprint: key.fingerprint)
                        self.storeMemoized(key: key, result: result)
                    }
                    return result
                }
                prewarmedTasks[action.id] = (task: task, textHash: hash, fingerprint: key.fingerprint)
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
    ///
    /// The action-aware overload is preferred: it also validates the action's input fingerprint
    /// (script + resolved options) so a warmed result is never served after the action changed.
    public func prewarmedResult(for action: any Action, textHash: Int) -> String? {
        if ContextualActionClassifier.unwrap(action) is any LiveInlineAction { return nil }
        let key = memoKey(for: action, textHash: textHash)
        if let cached = prewarmedResults[action.id],
           cached.textHash == textHash,
           cached.fingerprint == key.fingerprint {
            return cached.result
        }
        return memoizedResults[key]
    }

    /// ID-only lookup retained for callers that only hold an action id. Validates the text hash but
    /// cannot check the input fingerprint; prefer ``prewarmedResult(for:textHash:)`` where possible.
    public func prewarmedResult(for actionID: String, textHash: Int) -> String? {
        if let cached = prewarmedResults[actionID], cached.textHash == textHash {
            return cached.result
        }
        return nil
    }

    /// Clears every cache and cancels all in-flight prewarm work. Full invalidation — use
    /// ``endSession(_:)`` to end a popup while keeping the warm cache for the next selection.
    public func clearPrewarmed() {
        for entry in prewarmedTasks.values {
            entry.task.cancel()
        }
        prewarmedTasks.removeAll()
        prewarmedResults.removeAll()
        memoizedResults.removeAll()
        memoizedOrder.removeAll()
    }

    /// Ends a popup session: cancels that session's in-flight evaluations and any pending prewarm
    /// tasks, but **retains** the warm result caches. Keeping them makes the next selection render
    /// instantly instead of paying a cold JavaScriptCore evaluation on every show.
    public func endSession(_ sessionID: UUID) {
        cancelSession(sessionID)
        for entry in prewarmedTasks.values {
            entry.task.cancel()
        }
        prewarmedTasks.removeAll()
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
        let key = memoKey(for: action, textHash: hash)
        if let cached = prewarmedResult(for: action, textHash: hash) {
            onResult(cached)
            return
        }

        let prewarmed = prewarmedTasks[action.id]
        let task = Task { @MainActor [weak self] () -> String? in
            guard let self else { return nil }
            guard !Task.isCancelled else { return nil }

            var result: String?
            var attempts = 0
            if let prewarmed, prewarmed.textHash == hash, prewarmed.fingerprint == key.fingerprint {
                result = await prewarmed.task.value
                attempts = 1
            }

            // A cold-start miss or a timed-out prewarm must not permanently deny the preview:
            // retry once with a fresh budget before giving up, so an occasional slow first
            // evaluation does not silently drop the inline result. At most two attempts total.
            while (result == nil || result?.isEmpty == true), attempts < 2 {
                guard !Task.isCancelled else { return nil }
                result = await self.evaluateAsync(
                    action: action,
                    context: context,
                    timeout: timeout
                )
                attempts += 1
            }

            guard !Task.isCancelled else { return nil }

            if let result, !result.isEmpty {
                self.storeMemoized(key: key, result: result)
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
