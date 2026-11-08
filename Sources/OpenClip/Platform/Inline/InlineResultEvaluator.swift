// InlineResultEvaluator.swift
// OpenClip
//
// Coordinates bounded, typed inline result evaluation for actions declaring
// `ActionChrome.isInlineResult`. Automatic evaluation runs the existing synchronous JavaScript
// entry point in a restricted preview environment: effect and clipboard capabilities are removed
// before top-level code or required modules execute.
import Foundation
import Core

@MainActor
public final class InlineResultEvaluator {
    public static let shared = InlineResultEvaluator()

    /// A cached evaluation outcome. Not-applicable is cached so `null` or an invalid return does
    /// not make the automatic path rerun the same script.
    public enum Outcome: Sendable, Equatable {
        case ready(InlineResultValue)
        case notApplicable
    }

    /// Full request identity: captured text, action, script/options fingerprint, declared output,
    /// display-only policy, and locale context.
    private struct MemoKey: Hashable {
        let textHash: Int
        let textCount: Int
        let actionID: String
        let outputKind: String
        let displayOnly: Bool
        let isPureBuiltin: Bool
        let sourceAppID: String
        let fingerprint: Int
    }

    private static let maxMemoizedEntries = 200
    private static let maxCachedBytes = 1024 * 1024

    private var cachedOutcomes: [MemoKey: Outcome] = [:]
    private var cachedOrder: [MemoKey] = []
    private var cachedBytes = 0
    /// Automatic evaluations that failed or were cancelled; explicit invocation may still retry.
    private var automaticFailures: Set<MemoKey> = []
    private var automaticFailureOrder: [MemoKey] = []

    private var prewarmedResults: [String: MemoKey] = [:]
    private var prewarmedOrder: [String] = []
    private var prewarmedTasks: [String: (task: Task<Outcome?, Never>, key: MemoKey)] = [:]
    private var runningTasks: [UUID: [String: (task: Task<Outcome?, Never>, key: MemoKey)]] = [:]

    public init() {}

    // MARK: - Cache

    private func cost(of outcome: Outcome) -> Int {
        switch outcome {
        case .notApplicable:
            return 64
        case .ready(let value):
            return value.rawValue.utf8.count + 128
        }
    }

    private func storeCached(key: MemoKey, outcome: Outcome) {
        if let existing = cachedOutcomes[key] {
            cachedBytes -= cost(of: existing)
        } else {
            cachedOrder.append(key)
        }
        cachedOutcomes[key] = outcome
        cachedBytes += cost(of: outcome)
        while cachedOrder.count > Self.maxMemoizedEntries || cachedBytes > Self.maxCachedBytes {
            guard let oldest = cachedOrder.first else { break }
            cachedOrder.removeFirst()
            if let removed = cachedOutcomes.removeValue(forKey: oldest) {
                cachedBytes -= cost(of: removed)
            }
        }
    }

    private func recordAutomaticFailure(_ key: MemoKey) {
        guard automaticFailures.insert(key).inserted else { return }
        automaticFailureOrder.append(key)
        while automaticFailureOrder.count > Self.maxMemoizedEntries {
            let oldest = automaticFailureOrder.removeFirst()
            automaticFailures.remove(oldest)
        }
    }

    private func cachedOutcome(for key: MemoKey) -> Outcome? {
        cachedOutcomes[key]
    }

    /// The warm map only remembers request identities; the value lives once in `cachedOutcomes`.
    private func storePrewarmed(actionID: String, key: MemoKey) {
        if prewarmedResults[actionID] == nil {
            prewarmedOrder.append(actionID)
        }
        prewarmedResults[actionID] = key
        while prewarmedOrder.count > Self.maxMemoizedEntries {
            let oldest = prewarmedOrder.removeFirst()
            prewarmedResults.removeValue(forKey: oldest)
        }
    }

    /// Everything besides the selected text that can change an inline action's output: script
    /// source, resolved option values, and exposed locale/time-zone context.
    private func fingerprint(for action: any Action) -> Int {
        guard let javaScriptAction = Self.javaScriptAction(from: action) else { return 0 }
        var hasher = Hasher()
        hasher.combine(javaScriptAction.scriptCode)
        for option in javaScriptAction.actionOptions {
            hasher.combine(option.identifier)
            hasher.combine(javaScriptAction.optionStore.stringValue(actionID: javaScriptAction.id, option: option))
        }
        hasher.combine(Locale.current.identifier)
        hasher.combine(TimeZone.current.identifier)
        return hasher.finalize()
    }

    private func memoKey(for action: any Action, context: ActionContext) -> MemoKey {
        let text = context.selection.text
        return MemoKey(
            textHash: text.hashValue,
            textCount: text.count,
            actionID: action.id,
            outputKind: action.chrome.outputKind.rawValue,
            displayOnly: action.chrome.displayOnly,
            isPureBuiltin: action is CalculateAction,
            sourceAppID: context.selection.sourceApp.bundleIdentifier ?? "",
            fingerprint: fingerprint(for: action)
        )
    }

    // MARK: - Tier 1: pure Swift

    /// Synchronous built-ins evaluated without spawning tasks.
    public func evaluateSynchronous(action: any Action, context: ActionContext) -> InlineResultValue? {
        guard action.chrome.isInlineResult else { return nil }
        if let calculate = action as? CalculateAction {
            guard let text = calculate.evaluateSynchronously(context.selection.text) else { return nil }
            return InlineResultValue.makeText(text)
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

    // MARK: - Value validation

    /// Accepts only a typed value compatible with the declared inline output. A shorthand string
    /// is coerced by that output; a typed object must match exactly.
    private static func value(
        from result: ActionResult,
        action: any Action
    ) -> InlineResultValue? {
        let output = action.chrome.outputKind
        let displayOnly = action.chrome.displayOnly
        switch result {
        case .inlineValue(let value):
            guard value.matches(declaredOutput: output) else { return nil }
            switch value {
            case .text(let text):
                return InlineResultValue.makeText(text, displayOnly: displayOnly)
            case .color(let color):
                return .color(color)
            }
        case .text(let text):
            return InlineResultValue.makeLegacyString(text, for: output, displayOnly: displayOnly)
        case .color(let color):
            return output == .color ? .color(color) : nil
        default:
            return nil
        }
    }

    @MainActor
    private static func performAction(
        _ action: any Action,
        context: ActionContext,
        timeout: TimeInterval
    ) async -> Outcome? {
        do {
            // Inline runs before the click, so resolve the match here: regex actions need their matched substring.
            let matchedContext: ActionContext
            if context.match != nil {
                matchedContext = ActionContext(
                    selection: context.selection,
                    modifiers: context.modifiers,
                    isSecondaryClick: false,
                    match: context.match
                )
            } else if let match = action.matchInfo(for: context) {
                matchedContext = ActionContext(
                    selection: context.selection,
                    modifiers: context.modifiers,
                    isSecondaryClick: false,
                    match: match
                )
            } else {
                matchedContext = ActionContext(
                    selection: context.selection,
                    modifiers: context.modifiers,
                    isSecondaryClick: false
                )
            }
            let result: ActionResult
            if let javaScriptAction = javaScriptAction(from: action) {
                result = try await javaScriptAction.perform(
                    matchedContext,
                    timeout: timeout,
                    restrictedToPreview: true
                )
            } else {
                result = try await action.perform(matchedContext)
            }
            guard let value = value(from: result, action: action) else {
                return .notApplicable
            }
            return .ready(value)
        } catch {
            return nil
        }
    }

    private func evaluateOutcome(
        action: any Action,
        context: ActionContext,
        timeout: TimeInterval
    ) async -> Outcome? {
        let boundedTimeout = max(0.001, timeout)
        return await withTaskGroup(of: Outcome?.self) { group in
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

    /// Evaluates once with a hard execution budget. Kept for callers that only need a value.
    public func evaluateAsync(
        action: any Action,
        context: ActionContext,
        timeout: TimeInterval = PopupMetrics.inlineEvaluationTimeout
    ) async -> InlineResultValue? {
        guard action.chrome.isInlineResult else { return nil }
        guard case .ready(let value) = await evaluateOutcome(action: action, context: context, timeout: timeout) else {
            return nil
        }
        return value
    }

    // MARK: - Prewarm and automatic evaluation

    /// Populates the warm cache during selection retrieval.
    public func prewarm(actions: [any Action], context: ActionContext) {
        for action in actions where action.chrome.isInlineResult {
            let key = memoKey(for: action, context: context)
            if let cached = cachedOutcome(for: key) {
                storePrewarmed(actionID: action.id, key: key)
                continue
            }
            if let syncValue = evaluateSynchronous(action: action, context: context) {
                let outcome = Outcome.ready(syncValue)
                storePrewarmed(actionID: action.id, key: key)
                storeCached(key: key, outcome: outcome)
                continue
            }
            if automaticFailures.contains(key) { continue }
            if let existing = prewarmedTasks[action.id], existing.key == key { continue }
            let task = Task { @MainActor [weak self] () -> Outcome? in
                guard let self else { return nil }
                let outcome = await self.evaluateOutcome(action: action, context: context, timeout: PopupMetrics.inlineEvaluationTimeout)
                guard !Task.isCancelled else { return nil }
                guard let outcome else { return nil }
                self.storePrewarmed(actionID: action.id, key: key)
                self.storeCached(key: key, outcome: outcome)
                return outcome
            }
            prewarmedTasks[action.id] = (task: task, key: key)
        }
    }

    /// Awaits pending prewarm evaluation tasks up to the anticipation budget.
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

    /// Returns a ready value for this exact selection/action identity. Not-applicable is nil.
    public func prewarmedResult(for action: any Action, context: ActionContext) -> InlineResultValue? {
        let key = memoKey(for: action, context: context)
        guard let stored = prewarmedResults[action.id], stored == key else { return nil }
        guard let cached = cachedOutcome(for: stored), case .ready(let value) = cached else { return nil }
        return value
    }

    /// Full invalidation of every cache and in-flight prewarm.
    public func clearPrewarmed() {
        for entry in prewarmedTasks.values {
            entry.task.cancel()
        }
        prewarmedTasks.removeAll()
        prewarmedResults.removeAll()
        prewarmedOrder.removeAll()
        cachedOutcomes.removeAll()
        cachedOrder.removeAll()
        cachedBytes = 0
        automaticFailures.removeAll()
        automaticFailureOrder.removeAll()
    }

    /// Ends a popup session: cancels its evaluations and pending prewarms. Extension results are
    /// session-scoped (time/randomness make persistent determinism unsafe); only proven pure
    /// built-ins such as Calculate keep their warm value across sessions.
    public func endSession(_ sessionID: UUID) {
        cancelSession(sessionID)
        for entry in prewarmedTasks.values {
            entry.task.cancel()
        }
        prewarmedTasks.removeAll()
        prewarmedResults = prewarmedResults.filter { $0.value.isPureBuiltin }
        prewarmedOrder.removeAll { prewarmedResults[$0] == nil }
        cachedOutcomes = cachedOutcomes.filter { $0.key.isPureBuiltin }
        cachedOrder.removeAll { !$0.isPureBuiltin }
        cachedBytes = cachedOutcomes.values.reduce(0) { $0 + cost(of: $1) }
        automaticFailures.removeAll()
        automaticFailureOrder.removeAll()
    }

    /// Starts automatic evaluation for a popup session. Runs at most once per request identity.
    public func startEvaluation(
        action: any Action,
        context: ActionContext,
        sessionID: UUID,
        timeout: TimeInterval = PopupMetrics.inlineEvaluationTimeout,
        onResult: @escaping @MainActor (InlineResultValue?) -> Void
    ) {
        guard action.chrome.isInlineResult else {
            onResult(nil)
            return
        }
        let key = memoKey(for: action, context: context)
        if let ready = prewarmedResults[action.id],
           ready == key,
           let cached = cachedOutcome(for: ready),
           case .ready(let value) = cached {
            onResult(value)
            return
        }
        if let cached = cachedOutcome(for: key) {
            if case .ready(let value) = cached { onResult(value) }
            return
        }
        if automaticFailures.contains(key) {
            onResult(nil)
            return
        }

        let task = Task { @MainActor [weak self] () -> Outcome? in
            guard let self else { return nil }
            guard !Task.isCancelled else { return nil }
            let prewarmed = self.prewarmedTasks[action.id].flatMap { $0.key == key ? $0.task : nil }
            let outcome: Outcome?
            if let prewarmed {
                outcome = await prewarmed.value
            } else {
                outcome = await self.evaluateOutcome(action: action, context: context, timeout: timeout)
            }
            guard !Task.isCancelled else { return nil }
            guard let outcome else {
                self.recordAutomaticFailure(key)
                self.finish(actionID: action.id, sessionID: sessionID)
                return nil
            }
            self.storeCached(key: key, outcome: outcome)
            if case .ready(let value) = outcome {
                self.storePrewarmed(actionID: action.id, key: key)
                self.finish(actionID: action.id, sessionID: sessionID)
                onResult(value)
            } else {
                self.finish(actionID: action.id, sessionID: sessionID)
                onResult(nil)
            }
            return outcome
        }
        runningTasks[sessionID, default: [:]][action.id] = (task: task, key: key)
    }

    private func finish(actionID: String, sessionID: UUID) {
        runningTasks[sessionID]?.removeValue(forKey: actionID)
        if runningTasks[sessionID]?.isEmpty == true {
            runningTasks.removeValue(forKey: sessionID)
        }
    }

    // MARK: - Explicit invocation (shared activation seam)

    /// Resolves a deliverable value for a deliberate activation: a cached value, the in-flight
    /// evaluation, or a fresh bounded restricted evaluation. Never runs the action unrestricted.
    /// Display-only actions are never invoked.
    public func invoke(
        action: any Action,
        context: ActionContext,
        sessionID: UUID?,
        timeout: TimeInterval = PopupMetrics.inlineEvaluationTimeout
    ) async -> InlineResultValue? {
        guard action.chrome.isInlineResult, !action.chrome.displayOnly else { return nil }

        let key = memoKey(for: action, context: context)
        if let cached = cachedOutcome(for: key) {
            if case .ready(let value) = cached { return value }
            // A cached null/invalid outcome falls through to a deliberate fresh evaluation.
        }
        let inFlight = inFlightEntry(for: action.id, key: key, sessionID: sessionID)
        if let inFlight {
            if case .ready(let value) = await inFlight.task.value {
                return value
            }
        }
        let outcome = await evaluateOutcome(action: action, context: context, timeout: timeout)
        guard let outcome else { return nil }
        storeCached(key: key, outcome: outcome)
        if case .ready(let value) = outcome {
            storePrewarmed(actionID: action.id, key: key)
            return value
        }
        return nil
    }

    /// Returns an existing in-flight evaluation task for click-race joining.
    public func runningTask(for actionID: String, sessionID: UUID) -> Task<Outcome?, Never>? {
        runningTasks[sessionID]?[actionID]?.task
    }

    /// Returns an existing in-flight evaluation task across all sessions.
    public func runningTask(for actionID: String) -> Task<Outcome?, Never>? {
        for tasks in runningTasks.values {
            if let entry = tasks[actionID] {
                return entry.task
            }
        }
        return nil
    }

    /// Only an evaluation for this exact request identity may be joined; a task from an older
    /// selection must never deliver its value.
    private func inFlightEntry(
        for actionID: String,
        key: MemoKey,
        sessionID: UUID?
    ) -> (task: Task<Outcome?, Never>, key: MemoKey)? {
        if let sessionID, let entry = runningTasks[sessionID]?[actionID] {
            return entry.key == key ? entry : nil
        }
        return runningTasks.values.lazy.compactMap { $0[actionID] }.first { $0.key == key }
    }

    /// Cancels and removes all in-flight evaluation tasks for a popup session.
    public func cancelSession(_ sessionID: UUID) {
        if let sessionTasks = runningTasks.removeValue(forKey: sessionID) {
            for entry in sessionTasks.values {
                entry.task.cancel()
            }
        }
    }
}
