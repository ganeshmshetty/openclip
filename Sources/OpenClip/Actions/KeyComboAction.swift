import Foundation
import AppKit
import CoreGraphics
import Core

@MainActor
public struct KeyComboAction: Action {
    public let id: String
    public let title: String
    public let icon: ActionIcon
    public let keyCode: CGKeyCode
    public let modifiers: CGEventFlags
    
    public init(id: String, title: String, iconSymbol: String = "keyboard", keyCode: CGKeyCode, modifiers: CGEventFlags = []) {
        self.id = id
        self.title = title
        self.icon = .symbol(iconSymbol)
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
    
    public func isEnabled(for context: ActionContext) -> Bool {
        return true
    }
    
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let source = CGEventSource(stateID: .hidSystemState)
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return .failure(NSError(domain: "KeyComboAction", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGEvent"]))
        }
        
        keyDown.flags = modifiers
        keyUp.flags = modifiers
        
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        
        return .success
    }
}
