// ActionWithRules.swift
// OpenClip
//
// Protocol for actions that declare extension visibility rules (native content, regex, and app rules).
import Foundation

public protocol ActionWithRules: Action {
    var rules: ExtensionActionRules? { get }
}
