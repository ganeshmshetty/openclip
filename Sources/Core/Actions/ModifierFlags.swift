// ModifierFlags.swift
// OpenClip
//
// Defines an option set representing keyboard modifier flags (Shift, Control, Option, Command) during action evaluation.
import Foundation

public struct ModifierFlags: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    
    public static let shift = ModifierFlags(rawValue: 1 << 0)
    public static let control = ModifierFlags(rawValue: 1 << 1)
    public static let option = ModifierFlags(rawValue: 1 << 2)
    public static let command = ModifierFlags(rawValue: 1 << 3)
}
