// PasteAction.swift
// OpenClip
//
// Implements the standard paste action that triggers clipboard paste simulation.
import Foundation

public struct PasteAction: ConfigurableAction {
    public let id = "builtin.paste"
    public let title = "Paste"
    public let preferenceIconName = "doc.on.clipboard"
    public let icon = ActionIcon.text("Paste")
    
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

