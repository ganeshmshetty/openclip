// ActionMatchInfo.swift
// OpenClip
//
// Describes what an extension action actually matched when the shared visibility evaluator
// resolved it: the full selection text, the regex-matched substring, capture groups 1...n, and
// the source app bundle ID. Populated by ActionVisibility during enablement evaluation and
// threaded into ActionContext.match so perform-time placeholders ({matched}, {captureN},
// {bundleID}) and shell env vars (OPENCLIP_MATCHED, OPENCLIP_CAPTURE_N, OPENCLIP_BUNDLE_ID)
// can consume the same match.
import Foundation

public struct ActionMatchInfo: Sendable, Equatable {
    /// Full selection text.
    public let text: String
    /// Substring matched by requirements.regex (full match); equals `text` if no regex.
    public let matchedText: String
    /// Regex capture groups 1...n (group 0 excluded).
    public let captures: [String]
    public let sourceBundleID: String?

    public init(
        text: String,
        matchedText: String,
        captures: [String],
        sourceBundleID: String?
    ) {
        self.text = text
        self.matchedText = matchedText
        self.captures = captures
        self.sourceBundleID = sourceBundleID
    }
}
