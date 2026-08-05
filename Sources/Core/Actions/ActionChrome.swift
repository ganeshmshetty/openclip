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
        /// AI preset action (a row in AIServiceManager's preset list). Reachable through the
        /// action-search palette and Preferences → Actions, never through the popup bar
        /// (the reorderable `builtin.aiTools` action is the bar's entry point to AI).
        case ai
    }

    public let badge: Badge
    public let rowStyle: RowStyle
    public let popupBehavior: PopupBehavior
    public let source: Source
    /// True when the action reads or mutates the real text selection (e.g. Copy/Cut) and is
    /// therefore unsafe when the text came from the clipboard rather than a live selection.
    public let requiresLiveSelection: Bool
    /// True when the action is an AI-mode launcher (the "AI Tools" bar entry). The popup bar
    /// routes its click into AI mode instead of `perform`, and the search palette excludes it
    /// (AI presets are already searchable there).
    public let launchesAI: Bool

    public init(
        badge: Badge = .none,
        rowStyle: RowStyle = .standard,
        popupBehavior: PopupBehavior = .perform,
        source: Source = .builtin,
        requiresLiveSelection: Bool = false,
        launchesAI: Bool = false
    ) {
        self.badge = badge
        self.rowStyle = rowStyle
        self.popupBehavior = popupBehavior
        self.source = source
        self.requiresLiveSelection = requiresLiveSelection
        self.launchesAI = launchesAI
    }
}
