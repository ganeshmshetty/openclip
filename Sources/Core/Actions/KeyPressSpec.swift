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

    /// Parses a manifest string of the form `"modifier+modifier+key"` (e.g. `"cmd+shift+v"`,
    /// `"return"`). Each leading token is a modifier; the last token is the key. Returns `nil`
    /// when there are no tokens or the key is empty. Core keeps only the parse + model — the
    /// Key→CGKeyCode mapping lives in the App handler.
    public init?(manifestString: String) {
        let tokens = manifestString.split(separator: "+", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !tokens.isEmpty, let last = tokens.last, !last.isEmpty else { return nil }
        var parsedModifiers: [KeyModifier] = []
        for token in tokens.dropLast() {
            switch token.lowercased() {
            case "command", "cmd": parsedModifiers.append(.command)
            case "shift": parsedModifiers.append(.shift)
            case "option", "alt": parsedModifiers.append(.option)
            case "control", "ctrl": parsedModifiers.append(.control)
            default: return nil
            }
        }
        self.key = last
        self.modifiers = parsedModifiers
    }
}