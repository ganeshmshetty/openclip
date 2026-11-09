import XCTest
@testable import Core
@testable import OpenClip

/// Resets the process-wide singletons, which persist across the suite, so one test class's state
/// can't leak into the next. Call from `setUp()` in any class that touches them.
@MainActor
enum TestIsolation {
    static func reset() {
        ActionRegistry.shared.reset()
        ActionCustomizationManager.shared.reset()
        ActionBindingStore.shared.reset()
        RuleEngine.shared.reset()
        ExtensionManager.shared.reset()
        // Warm cache persists across popup sessions; start clean so a prior preview can't leak.
        InlineResultEvaluator.shared.clearPrewarmed()
        AIServiceManager.shared.providerOverride = nil
        CustomActionJSRunnerRegistry.runner = DefaultCustomActionJSRunner()
        TextSpellCheckerRegistry.checker = nil
    }

    /// Serializes tests accessing shared process-wide gates/locks (e.g. `OpenClipJSHost.syncEvaluationGate`).
    public actor GateSerializer {
        public static let shared = GateSerializer()

        private var locked = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        /// Runs `body` exclusively, in FIFO arrival order.
        public func serialize<T: Sendable>(_ body: @Sendable () async throws -> T) async rethrows -> T {
            if locked {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    waiters.append(continuation)
                }
            }
            locked = true
            defer { release() }
            return try await body()
        }

        private func release() {
            if waiters.isEmpty {
                locked = false
            } else {
                waiters.removeFirst().resume()
            }
        }
    }
}