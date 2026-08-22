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
    /// - `{html}` — the selection HTML (if captured)
    /// - `{rtf}` — the selection RTF (if captured)
    /// - `{matched}` — the regex-matched substring (full selection if no regex)
    /// - `{capture1}`…`{captureN}` or `{1}`…`{N}` — regex capture groups 1...n
    /// - `{bundleID}` — the source app bundle identifier (empty if unavailable)
    public static func replacePlaceholders(
        in template: String,
        context: ActionContext,
        urlEncode: Bool = true
    ) -> String {
        replace(
            in: template,
            text: context.match?.text ?? context.selection.text,
            html: context.selection.html,
            rtf: context.selection.rtf,
            matched: context.match?.matchedText ?? context.selection.text,
            captures: context.match?.captures ?? [],
            bundleID: context.match?.sourceBundleID ?? context.selection.sourceApp.bundleIdentifier,
            urlEncode: urlEncode
        )
    }

    private static let placeholderRegex = try? NSRegularExpression(pattern: #"\{([a-zA-Z0-9_]+)\}"#)

    private static func replace(
        in template: String,
        text: String,
        html: String? = nil,
        rtf: String? = nil,
        matched: String,
        captures: [String],
        bundleID: String?,
        urlEncode: Bool
    ) -> String {
        func encode(_ value: String) -> String {
            urlEncode ? (value.addingPercentEncoding(withAllowedCharacters: Constants.queryValueAllowed) ?? value) : value
        }

        var replacements: [String: String] = [
            "text": encode(text),
            "query": encode(text),
            "html": encode(html ?? ""),
            "rtf": encode(rtf ?? ""),
            "matched": encode(matched),
            "bundleID": encode(bundleID ?? "")
        ]
        for (index, capture) in captures.enumerated() {
            let encodedCapture = encode(capture)
            replacements["capture\(index + 1)"] = encodedCapture
            replacements["\(index + 1)"] = encodedCapture
        }

        guard let regex = placeholderRegex else { return template }
        let nsTemplate = template as NSString
        let fullRange = NSRange(location: 0, length: nsTemplate.length)
        let matches = regex.matches(in: template, range: fullRange)
        guard !matches.isEmpty else { return template }

        var result = ""
        var lastLocation = 0

        for match in matches {
            let matchRange = match.range(at: 0)
            let keyRange = match.range(at: 1)

            if matchRange.location > lastLocation {
                result += nsTemplate.substring(with: NSRange(location: lastLocation, length: matchRange.location - lastLocation))
            }

            let key = nsTemplate.substring(with: keyRange)
            if let replacement = replacements[key] {
                result += replacement
            } else {
                result += nsTemplate.substring(with: matchRange)
            }

            lastLocation = matchRange.location + matchRange.length
        }

        if lastLocation < nsTemplate.length {
            result += nsTemplate.substring(from: lastLocation)
        }

        return result
    }
}
