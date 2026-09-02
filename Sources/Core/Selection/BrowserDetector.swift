// BrowserDetector.swift
// OpenClip
//
// Detects whether an application bundle identifier belongs to a known macOS web browser.
// Used to route web searches and URL actions to the currently active browser without
// triggering unwanted application switches.
import Foundation

public enum BrowserDetector: Sendable {
    /// Canonical set of known macOS web browser bundle identifiers.
    public static let knownBrowserBundleIDs: Set<String> = [
        // Apple Safari & Preview
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",

        // Google Chrome & Chromium
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "com.google.Chrome.canary",
        "org.chromium.Chromium",

        // Brave Browser
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.brave.Browser.nightly",
        "com.brave.Browser.dev",

        // Arc Browser
        "company.thebrowser.Browser",
        "company.thebrowser.dia",

        // Microsoft Edge
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Dev",
        "com.microsoft.edgemac.Canary",

        // Mozilla Firefox
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",

        // Orion (Kagi)
        "com.kagi.kagimacOS",

        // Zen Browser
        "app.zen-browser.zen",

        // Opera
        "com.operasoftware.Opera",
        "com.operasoftware.OperaNext",
        "com.operasoftware.OperaDeveloper",
        "com.operasoftware.OperaGX",

        // Vivaldi
        "com.vivaldi.Vivaldi",

        // DuckDuckGo Privacy Browser
        "com.duckduckgo.macos.browser",

        // Tor Browser
        "org.torproject.torbrowser",

        // SigmaOS
        "net.imput.SigmaOS",

        // Alternative / Privacy Browsers
        "org.waterfoxproject.waterfox",
        "io.gitlab.librewolf-community.librewolf",
        "net.mullvad.mullvadbrowser",
        "one.ablaze.floorp",
        "com.ghostery.dawn"
    ]

    /// Returns `true` if the bundle identifier corresponds to a known web browser.
    public static func isBrowser(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleIdentifier.isEmpty else {
            return false
        }
        return knownBrowserBundleIDs.contains(bundleIdentifier)
    }
}
