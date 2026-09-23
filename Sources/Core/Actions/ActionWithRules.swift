// ActionWithRules.swift
// OpenClip
//
// Protocol for actions that declare extension visibility rules (regex, app rules, expression gates).
import Foundation

public protocol ActionWithRules: Action {
    var rules: ExtensionActionRules? { get }
}
