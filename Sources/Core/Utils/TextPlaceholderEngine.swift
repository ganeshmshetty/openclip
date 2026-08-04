// TextPlaceholderEngine.swift
// OpenClip
//
// Replaces template placeholders such as {text}, {query}, {matched}, {capture1}/{1}…{captureN}/{N},
// and {bundleID} in URL strings and snippets with percent-encoded text values.
//
// The context-aware overload reads the match the popup threaded into ActionContext; the bare
// overload is kept (deprecated) for legacy callers and behaves as matched = text, no captures.
import Foundation

public struct TextPlaceholderEngine {
    /// Legacy bare overload: substitutes only `{text}`/`{query}` with `text`.
    /// Deprecated — use the context-aware overload instead.
    @available(*, deprecated, renamed: "replacePlaceholders(in:context:urlEncode:)")
    public static func replacePlaceholders(in template: String, with text: String, urlEncode: Bool = true) -> String {
        replace(in: template, text: text, matched: text, captures: [], bundleID: nil, urlEncode: urlEncode)
    }

    /// Context-aware overload supporting:
    /// - `{text}`, `{query}` — the full selection text
    /// - `{matched}` — the regex-matched substring (full selection if no regex)
    /// - `{capture1}`…`{captureN}` or `{1}`…`{N}` — regex capture groups 1...n
    /// - `{bundleID}` — the source app bundle identifier (empty if unavailable)
    public static func replacePlaceholders(
        in template: String,
        context: ActionContext,
        urlEncode: Bool
    ) -> String {
        replace(
            in: template,
            text: context.match?.text ?? context.selection.text,
            matched: context.match?.matchedText ?? context.selection.text,
            captures: context.match?.captures ?? [],
            bundleID: context.match?.sourceBundleID ?? context.selection.sourceApp.bundleIdentifier,
            urlEncode: urlEncode
        )
    }

    private static func replace(
        in template: String,
        text: String,
        matched: String,
        captures: [String],
        bundleID: String?,
        urlEncode: Bool
    ) -> String {
        func encode(_ value: String) -> String {
            urlEncode ? (value.addingPercentEncoding(withAllowedCharacters: Constants.queryValueAllowed) ?? value) : value
        }

        var result = template
        let encodedText = encode(text)
        result = result.replacingOccurrences(of: "{text}", with: encodedText)
        result = result.replacingOccurrences(of: "{query}", with: encodedText)
        result = result.replacingOccurrences(of: "{matched}", with: encode(matched))
        result = result.replacingOccurrences(of: "{bundleID}", with: encode(bundleID ?? ""))
        for (index, capture) in captures.enumerated() {
            let encodedCapture = encode(capture)
            result = result.replacingOccurrences(of: "{capture\(index + 1)}", with: encodedCapture)
            result = result.replacingOccurrences(of: "{\(index + 1)}", with: encodedCapture)
        }
        return result
    }
}
