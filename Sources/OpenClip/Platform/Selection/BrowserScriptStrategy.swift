// BrowserScriptStrategy.swift
// OpenClip
//
// Primary Safari/Chromium/Firefox/Arc selection path. Reads the current page selection through
// the browser's AppleScript automation bridge (AppleScriptRunner → osascript subprocess, so a
// hung `tell application` is watchdog-killed) and returns both the selected text and the selected
// HTML (cloneContents of the selection range) with zero clipboard writes. Returns nil on
// automation permission errors so the caller falls back to the AX web-area path.
import Foundation
import Core

public struct BrowserScriptStrategy {
    public struct BrowserResult: Sendable {
        public let text: String
        public let html: String?

        public init(text: String, html: String? = nil) {
            self.text = text
            self.html = html
        }
    }

    /// JS evaluated in the page to read the selection's text and HTML. Returns a JSON object so the
    /// two values survive the AppleScript string bridge as one parseable payload; `html` is empty
    /// when the selection is collapsed or the range cannot be cloned.
    private static let selectionScript = "(function(){var s=window.getSelection();var t=s?s.toString():'';var h='';if(s&&s.rangeCount>0&&!s.isCollapsed){var r=s.getRangeAt(0);var c=document.createElement('div');c.appendChild(r.cloneContents());h=c.innerHTML;}return JSON.stringify({text:t,html:h});})()"

    /// Runs AppleScript through AppleScriptRunner (osascript subprocess, watchdog-killable).
    /// Returns nil on Apple Events permission error so the caller falls back to AX web area.
    public static func read(bundleIdentifier: String) async -> BrowserResult? {
        do {
            let raw = try await AppleScriptRunner.shared.run(
                textScriptSource(bundleIdentifier: bundleIdentifier),
                timeout: Constants.browserScriptTimeout
            )
            // Arc's `execute javascript` wraps string results in an extra pair of double quotes.
            let payload = DefaultAppRules.matchesAny(DefaultAppRules.arcGroup, bundleID: bundleIdentifier)
                ? stripSurroundingQuotes(raw)
                : raw
            guard let result = decodePayload(payload) else { return nil }
            guard !result.text.isEmpty else { return nil }
            return result
        } catch {
            Log.selection.error("browser script retrieval failed for \(bundleIdentifier, privacy: .public): \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    /// Decodes the page-script JSON payload. Falls back to treating the raw string as plain text
    /// (no HTML) if the bridge returned a non-JSON value, so a browser/version quirk degrades
    /// gracefully to the previous text-only behavior.
    private static func decodePayload(_ json: String) -> BrowserResult? {
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(SelectionPayload.self, from: data) else {
            return BrowserResult(text: json)
        }
        return BrowserResult(text: payload.text, html: payload.html)
    }

    private struct SelectionPayload: Decodable {
        let text: String
        let html: String?
    }

    /// Generates the AppleScript that reads the current selection. Safari-family apps use
    /// `do JavaScript` on the front document; Chromium/Firefox/Arc use `execute javascript`
    /// on the active tab. The script's result is the last expression's value.
    static func textScriptSource(bundleIdentifier: String) -> String {
        if DefaultAppRules.safariGroup.contains(bundleIdentifier) {
            return """
            tell application id "\(bundleIdentifier)"
              tell front document
                do JavaScript "\(selectionScript)"
              end tell
            end tell
            """
        }
        return """
        tell application id "\(bundleIdentifier)"
          tell active tab of front window
            execute javascript "\(selectionScript)"
          end tell
        end tell
        """
    }

    /// Removes a single pair of surrounding double-quotes, matching Arc's `execute javascript`
    /// string results. Any other text passes through unchanged.
    static func stripSurroundingQuotes(_ text: String) -> String {
        guard text.count >= 2, text.first == "\"", text.last == "\"" else { return text }
        return String(text.dropFirst().dropLast())
    }
}
