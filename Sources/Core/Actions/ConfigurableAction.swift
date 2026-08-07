// ConfigurableAction.swift
// OpenClip
//
// Defines the protocol for actions that expose custom configuration views and icon preferences.
// Allows UI settings surfaces to dynamically display configuration controls and table icons without hardcoding action identifiers.
import Foundation

public protocol ConfigurableAction: Action {
    var preferenceIconName: String { get }
}
