// SearchEnginePreset.swift
// OpenClip
//
// Curated one-click search engine presets for the built-in Search action. Pure domain metadata:
// the configured value always stays the `{query}` URL template string written through the option
// store, so a stored template that matches no preset simply renders as "Custom" — no migration,
// no loss of custom/self-hosted endpoints.
import Foundation

public struct SearchEnginePreset: Sendable, Equatable, Identifiable {
    /// Stable identifier used as the picker tag (e.g. "google", "kagi").
    public let id: String
    /// User-facing display name (e.g. "Google", "Brave Search").
    public let displayName: String
    /// The `{query}` URL template that SearchAction resolves against selected text.
    public let urlTemplate: String

    public init(id: String, displayName: String, urlTemplate: String) {
        self.id = id
        self.displayName = displayName
        self.urlTemplate = urlTemplate
    }

    // MARK: - Curated presets

    public static let google = SearchEnginePreset(
        id: "google",
        displayName: String(localized: "Google"),
        urlTemplate: "https://www.google.com/search?q={query}"
    )
    public static let duckduckgo = SearchEnginePreset(
        id: "duckduckgo",
        displayName: String(localized: "DuckDuckGo"),
        urlTemplate: "https://duckduckgo.com/?q={query}"
    )
    public static let kagi = SearchEnginePreset(
        id: "kagi",
        displayName: String(localized: "Kagi"),
        urlTemplate: "https://kagi.com/search?q={query}"
    )
    public static let brave = SearchEnginePreset(
        id: "brave",
        displayName: String(localized: "Brave Search"),
        urlTemplate: "https://search.brave.com/search?q={query}"
    )
    public static let bing = SearchEnginePreset(
        id: "bing",
        displayName: String(localized: "Bing"),
        urlTemplate: "https://www.bing.com/search?q={query}"
    )
    public static let ecosia = SearchEnginePreset(
        id: "ecosia",
        displayName: String(localized: "Ecosia"),
        urlTemplate: "https://www.ecosia.org/search?q={query}"
    )
    public static let baidu = SearchEnginePreset(
        id: "baidu",
        displayName: String(localized: "Baidu"),
        urlTemplate: "https://www.baidu.com/s?wd={query}"
    )
    public static let yahooJapan = SearchEnginePreset(
        id: "yahoojapan",
        displayName: String(localized: "Yahoo! JAPAN"),
        urlTemplate: "https://search.yahoo.co.jp/search?p={query}"
    )

    /// All curated presets, in picker order.
    public static let all: [SearchEnginePreset] = [google, duckduckgo, kagi, brave, bing, ecosia, baidu, yahooJapan]

    /// Default `{query}` template (Google). Single source of truth for the Search action's default.
    public static let defaultURLTemplate = google.urlTemplate

    // MARK: - Lookup

    /// Returns the preset whose URL template exactly matches `template`, or nil when the template
    /// is custom/empty. Matching is exact so a user's hand-edited variant of a preset URL (e.g.
    /// appending `&hl=en`) is treated as Custom rather than silently snapping back to the preset.
    public static func preset(matching template: String) -> SearchEnginePreset? {
        all.first { $0.urlTemplate == template }
    }

    /// Returns the preset with the given stable id, or nil.
    public static func preset(id: String) -> SearchEnginePreset? {
        all.first { $0.id == id }
    }
}
