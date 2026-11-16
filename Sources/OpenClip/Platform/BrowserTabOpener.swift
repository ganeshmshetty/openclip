// BrowserTabOpener.swift
// OpenClip
//
// Opens a URL in the browser the selection came from via the browser's own scripting, so the tab
// lands in the front window. LaunchServices would open a new window when the only window is private.
// Every step is best-effort and falls back to LaunchServices.
import Foundation
import AppKit
import ApplicationServices
import Core

@MainActor
public struct BrowserTabOpener {
    public init() {}
    /// Injected so tests can avoid `osascript`.
    var runAppleScript: @MainActor @Sendable (String, TimeInterval) async throws -> String = { source, timeout in
        try await AppleScriptRunner.shared.run(source, timeout: timeout)
    }
    /// Hands the URL to the app through LaunchServices. Returns whether LaunchServices accepted it.
    var openWithApplication: @MainActor @Sendable (URL, String) async -> Bool = { url, bundleID in
        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: applicationURL,
                configuration: configuration
            ) { application, error in
                continuation.resume(returning: application != nil && error == nil)
            }
        }
    }
    /// Whether the app's focused window is a Firefox private window. Firefox only marks this in the
    /// title ("… Private Browsing"), and the suffix is localized, so this is best-effort: other
    /// languages just keep the normal-window path.
    var isPrivateWindow: @MainActor @Sendable (String) -> Bool = { bundleID in
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier else {
            return false
        }
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return false }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success,
              let title = title as? String else { return false }
        return title.hasSuffix("Private Browsing")
    }
    /// Runs `firefox --private-window URL` against the running instance. No shell involved.
    var launchPrivateWindow: @MainActor @Sendable (URL, String) -> Bool = { url, bundleID in
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let executable = Bundle(url: appURL)?.executableURL else { return false }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--private-window", url.absoluteString]
        do { try process.run() } catch { return false }
        return true
    }
    /// Last resort: the system default handler.
    var openDefault: @MainActor @Sendable (URL) -> Void = { url in
        NSWorkspace.shared.open(url)
    }

    /// Short on purpose so a busy browser never holds the action up.
    static let appleScriptTimeout: TimeInterval = 5

    /// Mozilla's own channels; forks name their binary and private title differently.
    static let firefoxPrivateCapable: Set<String> = [
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly"
    ]

    public func open(_ url: URL, inApp bundleID: String) async {
        // Firefox has no tab scripting and sends external URLs to a normal window (#205).
        if Self.firefoxPrivateCapable.contains(bundleID), isPrivateWindow(bundleID), launchPrivateWindow(url, bundleID) {
            return
        }
        if BrowserDetector.isBrowser(bundleIdentifier: bundleID) {
            do {
                _ = try await runAppleScript(Self.appleScript(url: url, bundleID: bundleID), Self.appleScriptTimeout)
                return
            } catch {
                Log.resultHandler.error("browser tab via AppleScript failed for \(bundleID, privacy: .public): \(error.localizedDescription, privacy: .private); falling back to LaunchServices")
            }
        }
        if !(await openWithApplication(url, bundleID)) {
            openDefault(url)
        }
    }

    /// Safari's dictionary spells the tab-focus step differently from Chromium.
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

    /// Backslashes before quotes, matching `AppleScriptAction`.
    static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
