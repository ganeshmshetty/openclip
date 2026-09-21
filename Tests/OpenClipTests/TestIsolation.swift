import XCTest
@testable import Core
@testable import OpenClip

/// Shared test-isolation helper.
///
/// XCTest instantiates one instance per test *method* and tears it down between methods, but the
/// target's shared singletons (`ActionRegistry.shared`, `ActionCustomizationManager.shared`,
/// `RuleEngine.shared`, `ExtensionManager.shared`) are static and persist for the whole suite. If a
/// test class registers actions, loads rules, wires callbacks, or sets a factory without cleaning
/// up, that state leaks into the next test class and makes failures order-dependent.
///
/// Every test class that touches the singletons should call `TestIsolation.reset()` first (typically
/// in `setUp()`), and the bigger suite runs are deterministic regardless of ordering.
/// `ActionCoordinator.shared` needs no explicit reset: it mirrors the registry's `@Published` state,
/// which `ActionRegistry.reset()` clears.
@MainActor
enum TestIsolation {
    static func reset() {
        ActionRegistry.shared.reset()
        ActionCustomizationManager.shared.reset()
        ActionBindingStore.shared.reset()
        RuleEngine.shared.reset()
        ExtensionManager.shared.reset()
        // The inline-result evaluator now retains its warm cache across popup sessions by design,
        // so tests sharing the singleton must start from a clean cache or a prior test's preview
        // leaks into the next and makes UI assertions order-dependent.
        InlineResultEvaluator.shared.clearPrewarmed()
        AIServiceManager.shared.providerOverride = nil
    }

    /// Serializes tests accessing shared process-wide gates/locks (e.g. `OpenClipJSHost.syncEvaluationGate`).
    public actor GateSerializer {
        public static let shared = GateSerializer()

        private var locked = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        /// Runs `body` exclusively, in FIFO arrival order: each call waits for the preceding holder to
        /// finish (success or error), executes `body` with no concurrent holder, then hands the gate to
        /// the next waiter — or unlocks it when none are queued. `body` is invoked directly so async
        /// `rethrows` semantics are preserved.
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

        /// Hands the gate to the next FIFO waiter, or unlocks it when none are queued.
        private func release() {
            if waiters.isEmpty {
                locked = false
            } else {
                waiters.removeFirst().resume()
            }
        }
    }
}