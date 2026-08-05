// SubAction.swift
// OpenClip
//
// Data-driven sub-action membership. An action that can be opened "into" (an extension group, the
// AI Tools launcher, etc.) conforms to SubActionProviding and declares how it resolves its children
// from a catalog. SubActionResolver is the single entry point the popup bar / palette use; it hides
// protocol lookup from callers. Pure Core — no AppKit/SwiftUI.
import Foundation

/// Opt-in capability: an action declares its sub-actions given the full catalog.
public protocol SubActionProviding: Action {
    func subActions(in catalog: [any Action]) -> [any Action]
}

/// Pure entry point: resolves a parent action's children from a catalog. Returns [] when the parent
/// does not provide sub-actions.
public struct SubActionResolver {
    public init() {}

    public func subActions(of parent: any Action, in catalog: [any Action]) -> [any Action] {
        guard let provider = parent as? any SubActionProviding else { return [] }
        return provider.subActions(in: catalog)
    }
}