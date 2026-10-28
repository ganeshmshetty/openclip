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

    /// Memo identity: selection text, action, and a fingerprint of its inputs, so the warm cache
    /// never serves a stale preview after the script or an option changes.
    private struct MemoKey: Hashable {
        let textHash: Int
        let actionID: String
        let fingerprint: Int
    }

    /// Entries kept across popups: bounds memory while keeping re-selections warm.
    private static let maxMemoizedEntries = 200

    /// Longer results are shown but never memoized, so a large script result cannot pin memory.
    private static let maxMemoizedResultLength = 1024

    private var prewarmedResults: [String: (result: InlinePreview, textHash: Int, fingerprint: Int)] = [:]
    private var prewarmedTasks: [String: (task: Task<InlinePreview?, Never>, textHash: Int, fingerprint: Int)] = [:]
    private var memoizedResults: [MemoKey: InlinePreview] = [:]
    private var memoizedOrder: [MemoKey] = []
    private var runningTasks: [UUID: [String: Task<InlinePreview?, Never>]] = [:]

    public init() {}

    private func storeMemoized(key: MemoKey, result: InlinePreview) {
        guard result.text.count <= Self.maxMemoizedResultLength else { return }
        if memoizedResults[key] == nil {
            memoizedOrder.append(key)
            if memoizedOrder.count > Self.maxMemoizedEntries {
                let oldest = memoizedOrder.removeFirst()
                memoizedResults.removeValue(forKey: oldest)
            }
        }
        memoizedResults[key] = result
    }

    /// Everything besides the selected text that can change an inline action's output: script source and
    /// resolved option values. Pure actions fingerprint to a constant.
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
    public func evaluateSynchronous(action: any Action, context: ActionContext) -> InlinePreview? {
        guard action.chrome.isInlineResult else { return nil }
        if let calculate = action as? CalculateAction {
            guard let text = calculate.evaluateSynchronously(context.selection.text) else { return nil }
            return InlinePreview(text: text)
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
    ) async -> InlinePreview? {
        do {
            // Inline runs before the click, so resolve the match here: regex actions need their matched substring.
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
            if let javaScriptAction = javaScriptAction(from: action) {
                return try await javaScriptAction.inlinePreview(matchedContext, timeout: timeout)
            }
            let result = try await action.perform(matchedContext)
            switch result {
            case .text(let text):
                let preview = InlinePreview.resolve(returnedText: text)
                let trimmed = preview.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : preview
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
    ) async -> InlinePreview? {
        guard action.chrome.isInlineResult else { return nil }

        let boundedTimeout = max(0.001, timeout)
        return await withTaskGroup(of: InlinePreview?.self) { group in
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
                let task = Task { @MainActor [weak self] () -> InlinePreview? in
                    guard let self else { return nil }
                    let result = await self.evaluateAsync(action: action, context: context)
                    guard !Task.isCancelled else { return nil }
                    if let result, Self.displayable(result) {
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

    /// Returns a prewarmed or memoized result for this text hash, checking the action's input fingerprint.
    public func prewarmedResult(for action: any Action, textHash: Int) -> InlinePreview? {
        let key = memoKey(for: action, textHash: textHash)
        if let cached = prewarmedResults[action.id],
           cached.textHash == textHash,
           cached.fingerprint == key.fingerprint {
            return cached.result
        }
        return memoizedResults[key]
    }

    /// ID-only lookup for callers that hold only an id; skips the fingerprint check.
    public func prewarmedResult(for actionID: String, textHash: Int) -> InlinePreview? {
        if let cached = prewarmedResults[actionID], cached.textHash == textHash {
            return cached.result
        }
        return nil
    }

    /// Full invalidation of every cache and in-flight prewarm. `endSession` keeps the warm cache instead.
    public func clearPrewarmed() {
        for entry in prewarmedTasks.values {
            entry.task.cancel()
        }
        prewarmedTasks.removeAll()
        prewarmedResults.removeAll()
        memoizedResults.removeAll()
        memoizedOrder.removeAll()
    }

    /// Ends a popup session: cancels its evaluations and pending prewarms but keeps the warm caches,
    /// so the next show renders instantly.
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
        onResult: @escaping @MainActor (InlinePreview?) -> Void
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
        let task = Task { @MainActor [weak self] () -> InlinePreview? in
            guard let self else { return nil }
            guard !Task.isCancelled else { return nil }

            var result: InlinePreview?
            var attempts = 0
            if let prewarmed, prewarmed.textHash == hash, prewarmed.fingerprint == key.fingerprint {
                result = await prewarmed.task.value
                attempts = 1
            }

            // Retry once with a fresh budget so one slow cold evaluation does not silently drop the preview.
            while !Self.displayable(result), attempts < 2 {
                guard !Task.isCancelled else { return nil }
                result = await self.evaluateAsync(
                    action: action,
                    context: context,
                    timeout: timeout
                )
                attempts += 1
            }

            guard !Task.isCancelled else { return nil }

            if let result, Self.displayable(result) {
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
    public func runningTask(for actionID: String, sessionID: UUID) -> Task<InlinePreview?, Never>? {
        runningTasks[sessionID]?[actionID]
    }

    /// Returns an existing in-flight evaluation task across all sessions for click-race joining.
    public func runningTask(for actionID: String) -> Task<InlinePreview?, Never>? {
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

    private static func displayable(_ preview: InlinePreview?) -> Bool {
        guard let preview else { return false }
        return !preview.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
