import XCTest
@testable import Core

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
        RuleEngine.shared.reset()
        ExtensionManager.shared.reset()
    }
}