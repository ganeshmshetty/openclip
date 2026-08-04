// ActionChrome.swift
// OpenClip
//
// Defines UI policy metadata structures through the Chrome Door, including badge types, row styles, popup behaviors, and action sources.
// Enables data-driven UI views to inspect action presentation rules without runtime type checking or string matching.
import Foundation

public struct ActionChrome: Codable, Sendable, Equatable {
    public enum Badge: Codable, Sendable, Equatable {
        case none
        case script
        case url
        case custom
        case extensionPkg(String)
    }

    public enum RowStyle: Codable, Sendable, Equatable {
        case standard
        case transformGroup
    }

    public enum PopupBehavior: Codable, Sendable, Equatable {
        case perform
        case showTransformMenu
        case provideCompletions
    }

    public enum Source: Codable, Sendable, Equatable {
        case builtin
        case custom
        case extensionPkg(packageID: String)
    }

    public let badge: Badge
    public let rowStyle: RowStyle
    public let popupBehavior: PopupBehavior
    public let source: Source

    public init(
        badge: Badge = .none,
        rowStyle: RowStyle = .standard,
        popupBehavior: PopupBehavior = .perform,
        source: Source = .builtin
    ) {
        self.badge = badge
        self.rowStyle = rowStyle
        self.popupBehavior = popupBehavior
        self.source = source
    }
}
