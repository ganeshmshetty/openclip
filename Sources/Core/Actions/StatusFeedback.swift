// StatusFeedback.swift
// OpenClip
//
// Pure Core value type describing the transient toast the popup surfaces (decision 9/10): a message
// with a style and an optional SF Symbol preset name. The app view maps style → color/symbol design
// tokens when rendering; this type stays AppKit/SwiftUI-free. `keepVisible: true` keeps the popup
// open and stops auto-dismiss (defaults to dismissing).
import Foundation

public struct StatusFeedback: Sendable, Equatable {
    public enum Style: String, Sendable {
        case success
        case error
        case info
    }

    public var message: String
    public var style: Style
    /// Optional SF Symbol preset name; the app maps a nil value to the style's default token.
    public var symbolName: String?
    /// True when this status renders a spinner instead of a symbol (loading/opening state).
    public var isLoading: Bool
    /// True keeps the popup open and stops auto-dismiss; defaults to dismissing.
    public var keepVisible: Bool

    public init(message: String, style: Style, symbolName: String? = nil, isLoading: Bool = false, keepVisible: Bool = false) {
        self.message = message
        self.style = style
        self.symbolName = symbolName
        self.isLoading = isLoading
        self.keepVisible = keepVisible
    }

    /// Builds an `.error` status for a thrown error, using the localized description when available.
    public init(error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        self.init(message: message, style: .error)
    }
}