// ModifierFlags+AppKit.swift
// OpenClip
//
// Reads the live hardware modifiers for the gesture that triggered an action. Core receives the
// flags through ActionContext; Core itself stays free of AppKit.
import AppKit
import Core

extension ModifierFlags {
    static var currentHardware: ModifierFlags {
        var flags: ModifierFlags = []
        let eventFlags = NSEvent.modifierFlags
        if eventFlags.contains(.shift) { flags.insert(.shift) }
        if eventFlags.contains(.control) { flags.insert(.control) }
        if eventFlags.contains(.option) { flags.insert(.option) }
        if eventFlags.contains(.command) { flags.insert(.command) }
        return flags
    }
}
