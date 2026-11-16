// ResultPresentation.swift
// OpenClip
//
// Explicit card format for text results. Extensions declare it in the manifest or return it with
// a text result; nil keeps the built-in Markdown auto-detection for AI answers.
import Foundation

public enum ResultPresentation: String, Codable, Sendable, Equatable, CaseIterable {
    case plain
    case markdown
    case code
    case diff
}

/// Text bound for the result card, with an optional explicit presentation.
public struct ResultTextContent: Sendable, Equatable {
    public let text: String
    /// nil leaves the card's built-in detection in charge.
    public let presentation: ResultPresentation?

    public init(text: String, presentation: ResultPresentation? = nil) {
        self.text = text
        self.presentation = presentation
    }
}
