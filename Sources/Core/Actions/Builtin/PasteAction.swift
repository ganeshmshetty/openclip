// PasteAction.swift
// OpenClip
//
// Implements the standard paste action that triggers clipboard paste simulation.
//
// Delivery: no `delivery` declared (default nil), so the paste→copy default applies — a secondary
// click (or a primary click when paste is unavailable) derives `.copy` and shows the default
// "Copied" toast. Builtins and extensions therefore behave identically.
import Foundation

public struct PasteAction: ConfigurableAction, PasteRequiringAction {
    public let id = "builtin.paste"
    public var title: String { String(localized: "Paste") }
    public let preferenceIconName = "doc.on.clipboard"
    public var icon: ActionIcon { .text(String(localized: "Paste")) }
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        return true
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        return .simulatePaste
    }
}

