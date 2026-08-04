// KeyPressSpec.swift
// OpenClip
//
// Pure Core value type describing a synthetic key press to be sent to the frontmost app. Phase 8
// implements the actual key event execution in the effect door; this type is declared now so
// extensions can produce `.keyPress` results without touching AppKit.
import Foundation

public struct KeyPressSpec: Sendable, Equatable {
    public enum KeyModifier: String, Codable, Sendable {
        case command
        case shift
        case option
        case control
    }

    /// Key to press: "b", "return", "escape", or a virtual key name.
    public var key: String
    public var modifiers: [KeyModifier]

    public init(key: String, modifiers: [KeyModifier] = []) {
        self.key = key
        self.modifiers = modifiers
    }
}