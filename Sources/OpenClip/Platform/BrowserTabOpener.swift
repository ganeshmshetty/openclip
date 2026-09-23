// BrowserTabOpener.swift
// OpenClip
//
// Opens a URL in the browser the selection came from, preferring the browser's own scripting so the
// tab lands in the window the user is actually in. macOS routes externally-opened URLs to the
// regular (non-incognito) profile, so handing the URL to LaunchServices spawns a new window when the
// only window is private; `tell front window to make new tab` targets the front window directly.
//
// Every step is best-effort: if the browser can't be scripted (Automation denied, no window, or an
// unsupported dictionary) this falls back to the previous LaunchServices behaviour, so nothing ever
// gets worse than before. The AppleScript budget is its own short constant, deliberately independent
// of the shared script timeout.
import Foundation
import AppKit
import Core

@MainActor
public struct BrowserTabOpener {
    public init() {}
    /// Runs an AppleScript source and returns its trimmed result. Injected so tests can drive the
    /// success and failure paths without touching `osascript`.
    var runAppleScript: @MainActor @Sendable (String, TimeInterval) async throws -> String = { source, timeout in
        try await AppleScriptRunner.shared.run(source, timeout: timeout)
    }
    /// Hands the URL to the app through LaunchServices. Returns whether LaunchServices accepted it.
    var openWithApplication: @MainActor @Sendable (URL, String) -> Bool = { url, bundleID in
        NSWorkspace.shared.open(
            [url],
            withAppBundleIdentifier: bundleID,
            options: [],
            additionalEventParamDescriptor: nil,
            launchIdentifiers: nil
        )
    }
    /// Last resort: the system default handler.
    var openDefault: @MainActor @Sendable (URL) -> Void = { url in
        NSWorkspace.shared.open(url)
    }

    /// Budget for the scripting attempt. Short and independent of `Constants.scriptTimeout`: opening
    /// a tab is a quick ask, and a busy browser must never hold the action up.
    static let appleScriptTimeout: TimeInterval = 5

    public func open(_ url: URL, inApp bundleID: String) async {
        if BrowserDetector.isBrowser(bundleIdentifier: bundleID) {
            do {
                _ = try await runAppleScript(Self.appleScript(url: url, bundleID: bundleID), Self.appleScriptTimeout)
                return
            } catch {
                Log.resultHandler.error("browser tab via AppleScript failed for \(bundleID, privacy: .public): \(error.localizedDescription, privacy: .private); falling back to LaunchServices")
            }
        }
        if !openWithApplication(url, bundleID) {
            openDefault(url)
        }
    }

    /// The script that adds a tab to the browser's front window. Safari's dictionary spells the
    /// focus step differently from the Chromium family.
    static func appleScript(url: URL, bundleID: String) -> String {
        let escaped = escape(url.absoluteString)
        if bundleID.hasPrefix("com.apple.Safari") || bundleID == "com.kagi.kagimacOS" {
            return """
            tell application id "\(bundleID)"
                activate
                tell front window to set current tab to (make new tab with properties {URL:"\(escaped)"})
            end tell
            """
        }
        return """
        tell application id "\(bundleID)"
            activate
            tell front window to make new tab with properties {URL:"\(escaped)"}
            set active tab index of front window to (count of tabs of front window)
        end tell
        """
    }

    /// AppleScript string escaping — backslashes then quotes, the same order `AppleScriptAction`
    /// uses for the selection it injects.
    static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
