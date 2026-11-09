// VisibilityMemo.swift
// OpenClip
//
// Presentation-scoped cache for expensive visibility answers. One memo is shared by the bar,
// palette, and prewarm paths for a single popup session; it is never reused across selections.
import Foundation

public final class VisibilityMemo: @unchecked Sendable {
    private let lock = NSLock()
    private var actionResults: [String: Bool] = [:]

    public init() {}

    public func result(for actionID: String) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return actionResults[actionID]
    }

    public func store(_ result: Bool, for actionID: String) {
        lock.lock()
        actionResults[actionID] = result
        lock.unlock()
    }
}
