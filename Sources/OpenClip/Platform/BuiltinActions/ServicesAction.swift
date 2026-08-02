// ServicesAction.swift
// OpenClip
//
// Invokes system macOS Services menu operations for selected text content.
import Foundation
#if canImport(AppKit)
import AppKit
#endif
import Core

public struct ServicesAction: Action {
    public let id = "builtin.services"
    public let title = "Services"
    public let icon = ActionIcon.symbol("square.and.arrow.up")
    
    public init() {}
    
    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        return !context.selection.text.isEmpty
    }
    
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let text = context.selection.text
        if text.isEmpty { return .success }
        return .showServices(text)
    }
}
