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
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",

        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "com.google.Chrome.canary",
        "org.chromium.Chromium",

        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.brave.Browser.nightly",
        "com.brave.Browser.dev",

        "company.thebrowser.Browser",
        "company.thebrowser.dia",

        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Dev",
        "com.microsoft.edgemac.Canary",

        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",

        "com.kagi.kagimacOS",

        "app.zen-browser.zen",

        "com.operasoftware.Opera",
        "com.operasoftware.OperaNext",
        "com.operasoftware.OperaDeveloper",
        "com.operasoftware.OperaGX",

        "com.vivaldi.Vivaldi",

        "com.duckduckgo.macos.browser",

        "org.torproject.torbrowser",

        "net.imput.SigmaOS",

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

    /// Returns the browser to open `url` in, or `nil` when it should go through
    /// the system. Only http(s) links go to the source browser; custom schemes
    /// (e.g. `scratchpad:`, `goodlinks://`) would otherwise trigger the browser's
    /// "allow this website to open…" prompt.
    public static func browserToOpen(_ url: URL, sourceBundleIdentifier: String?) -> String? {
        guard let sourceBundleIdentifier, isBrowser(bundleIdentifier: sourceBundleIdentifier),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return nil
        }
        return sourceBundleIdentifier
    }
}
