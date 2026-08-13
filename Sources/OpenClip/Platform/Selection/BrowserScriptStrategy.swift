// BrowserScriptStrategy.swift
// OpenClip
//
// Primary Safari/Chromium/Firefox/Arc selection path. Reads the current page selection through
// the browser's AppleScript automation bridge (AppleScriptRunner → osascript subprocess, so a
// hung `tell application` is watchdog-killed) and returns both the selected text and the page
// URL with zero clipboard writes. Returns nil on automation permission errors so the caller
// falls back to the AX web-area path.
import Foundation
import Core

public struct BrowserScriptStrategy {
    public struct BrowserResult: Sendable {
        public let text: String
        public let url: String?
    }

    /// Runs AppleScript through AppleScriptRunner (osascript subprocess, watchdog-killable).
    /// Returns nil on Apple Events permission error so the caller falls back to AX web area.
    public static func read(bundleIdentifier: String) async -> BrowserResult? {
        do {
            let text = try await AppleScriptRunner.shared.run(
                textScriptSource(bundleIdentifier: bundleIdentifier),
                timeout: Constants.browserScriptTimeout
            )
            let url = try? await AppleScriptRunner.shared.run(
                urlScriptSource(bundleIdentifier: bundleIdentifier),
                timeout: Constants.browserScriptTimeout
            )
            var resultText = text
            if DefaultAppRules.arcGroup.contains(bundleIdentifier) {
                resultText = stripSurroundingQuotes(resultText)
            }
            guard !resultText.isEmpty else { return nil }
            return BrowserResult(text: resultText, url: url)
        } catch {
            Log.selection.error("browser script retrieval failed for \(bundleIdentifier, privacy: .public): \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    /// Generates the AppleScript that reads the current selection. Safari-family apps use
    /// `do JavaScript` on the front document; Chromium/Firefox/Arc use `execute javascript`
    /// on the active tab. The script's result is the last expression's value.
    static func textScriptSource(bundleIdentifier: String) -> String {
        if DefaultAppRules.safariGroup.contains(bundleIdentifier) {
            return """
            tell application id "\(bundleIdentifier)"
              tell front document
                do JavaScript "window.getSelection().toString()"
              end tell
            end tell
            """
        }
        return """
        tell application id "\(bundleIdentifier)"
          tell active tab of front window
            execute javascript "window.getSelection().toString()"
          end tell
        end tell
        """
    }

    /// Generates the AppleScript that reads the active page's URL. Safari reads `URL of front
    /// document`; the others read `URL of active tab of front window` (expressed as the bare
    /// `URL` property inside the `tell active tab` block).
    static func urlScriptSource(bundleIdentifier: String) -> String {
        if DefaultAppRules.safariGroup.contains(bundleIdentifier) {
            return """
            tell application id "\(bundleIdentifier)"
              tell front document
                URL
              end tell
            end tell
            """
        }
        return """
        tell application id "\(bundleIdentifier)"
          tell active tab of front window
            URL
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