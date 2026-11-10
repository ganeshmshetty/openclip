// VisibilityMemo.swift
// OpenClip
//
// Presentation-scoped cache for expensive visibility answers. One memo is shared by the bar,
// palette, and prewarm paths for a single popup session; it is never reused across selections.
import Foundation

/// Presentation-scoped cache for expensive visibility answers. Shared by the bar, palette, and
/// prewarm for one popup session; never reused across selections.
public final class VisibilityMemo: @unchecked Sendable {
    private let lock = NSLock()
    private var actionResults: [String: Bool] = [:]

    public init() {}

    /// Returns the cached answer for an action in this presentation, if one exists.
    public func result(for actionID: String) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return actionResults[actionID]
    }

    /// Stores one final visibility answer for this presentation.
    public func store(_ result: Bool, for actionID: String) {
        lock.lock()
        actionResults[actionID] = result
        lock.unlock()
    }
}
