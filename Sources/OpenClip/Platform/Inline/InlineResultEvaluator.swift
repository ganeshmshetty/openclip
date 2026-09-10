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

private final class InlineOnceResume: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(_ continuation: CheckedContinuation<String?, Never>, with value: String?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return false }
        didResume = true
        continuation.resume(returning: value)
        return true
    }
}

@MainActor
public final class InlineResultEvaluator {
    public static let shared = InlineResultEvaluator()

    private var prewarmedResults: [String: (result: String, textHash: Int)] = [:]
    private var runningTasks: [UUID: [String: Task<String?, Never>]] = [:]

    public init() {}

    /// Tier 1: Evaluates synchronous built-in actions immediately without spawning tasks.
    public func evaluateSynchronous(action: any Action, context: ActionContext) -> String? {
        guard action.chrome.isInlineResult else { return nil }
        if let calculate = action as? CalculateAction {
            return calculate.evaluateSynchronously(context.selection.text)
        }
        return nil
    }

    /// Evaluates an inline action asynchronously with a hard execution timeout.
    /// If the action exceeds the timeout budget, the task is cancelled and nil is returned.
    public func evaluateAsync(
        action: any Action,
        context: ActionContext,
        sessionID: UUID,
        timeout: TimeInterval = PopupMetrics.inlineEvaluationTimeout
    ) async -> String? {
        guard action.chrome.isInlineResult else { return nil }

        let performTask = Task { @MainActor () -> String? in
            do {
                let result = try await action.perform(context)
                switch result {
                case .text(let text):
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                default:
                    return nil
                }
            } catch {
                return nil
            }
        }

        let timeoutNanoseconds = UInt64(max(0.001, timeout) * 1_000_000_000)
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
        }

        let resumer = InlineOnceResume()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                Task {
                    let outcome = await performTask.value
                    if resumer.resume(continuation, with: outcome) {
                        timeoutTask.cancel()
                    }
                }
                Task {
                    _ = await timeoutTask.value
                    if resumer.resume(continuation, with: nil) {
                        performTask.cancel()
                    }
                }
            }
        } onCancel: {
            performTask.cancel()
            timeoutTask.cancel()
        }
    }

    /// Tier 2: Populates the prewarm cache for inline actions during selection retrieval.
    public func prewarm(actions: [any Action], context: ActionContext, sessionID: UUID = UUID()) {
        let text = context.selection.text
        let hash = text.hashValue
        for action in actions where action.chrome.isInlineResult {
            if let syncResult = evaluateSynchronous(action: action, context: context) {
                prewarmedResults[action.id] = (result: syncResult, textHash: hash)
            } else {
                startEvaluation(action: action, context: context, sessionID: sessionID) { [weak self] result in
                    guard let self, let result, !result.isEmpty else { return }
                    self.prewarmedResults[action.id] = (result: result, textHash: hash)
                }
            }
        }
    }

    /// Returns a prewarmed result if present and valid for the given selected text hash.
    public func prewarmedResult(for actionID: String, textHash: Int) -> String? {
        guard let cached = prewarmedResults[actionID], cached.textHash == textHash else {
            return nil
        }
        return cached.result
    }

    /// Clears prewarmed cache entries.
    public func clearPrewarmed() {
        prewarmedResults.removeAll()
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

        let task = Task { @MainActor [weak self] () -> String? in
            guard let self else { return nil }
            guard !Task.isCancelled else { return nil }

            let result = await self.evaluateAsync(
                action: action,
                context: context,
                sessionID: sessionID,
                timeout: timeout
            )

            guard !Task.isCancelled else { return nil }

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

    /// Cancels and removes all in-flight evaluation tasks for a popup session.
    public func cancelSession(_ sessionID: UUID) {
        if let sessionTasks = runningTasks.removeValue(forKey: sessionID) {
            for task in sessionTasks.values {
                task.cancel()
            }
        }
    }
}
