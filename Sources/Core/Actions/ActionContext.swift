// ActionContext.swift
// OpenClip
//
// Encapsulates the execution context passed to actions, combining selection details with keyboard modifier flags.
import Foundation

public struct ActionContext: Sendable {
    public let selection: SelectionContext
    public let modifiers: ModifierFlags
    
    public init(
        selection: SelectionContext,
        modifiers: ModifierFlags = []
    ) {
        self.selection = selection
        self.modifiers = modifiers
    }
}
