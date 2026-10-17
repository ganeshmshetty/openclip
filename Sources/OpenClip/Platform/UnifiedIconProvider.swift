// UnifiedIconProvider.swift
// OpenClip
//
// Provides unified icon fetching and caching for SF Symbols, open-source icon sets, and SVG images.
import Foundation
import SwiftUI
import Core

public struct IconEntry: Identifiable, Sendable, Hashable {
    /// Iconify format: "prefix:name" e.g. "lucide:zap", OR a plain SF Symbol name e.g. "star.fill"
    public let id: String
    public let name: String
    public let library: String

    public init(id: String, name: String, library: String) {
        self.id = id
        self.name = name
        self.library = library
    }
}

// MARK: - UnifiedIconProvider

/// Searches icons on demand using the Iconify API.
/// - SF Symbols are loaded locally from the system plist (instant).
/// - All other icons are searched via `https://api.iconify.design/search`
///   with `palette=false` to ensure only monochrome/adaptive icons are returned.
@MainActor
public final class UnifiedIconProvider: ObservableObject, Sendable {
    public static let shared = UnifiedIconProvider()

    @Published public private(set) var sfSymbols: [IconEntry] = []
    @Published public private(set) var searchResults: [IconEntry] = []
    @Published public private(set) var isSearching = false
    @Published public private(set) var sfLoaded = false

    private var searchTask: Task<Void, Never>?
    private var lastQuery = ""

    private init() {
        Task { await loadSFSymbols() }
    }

    // MARK: - SF Symbols (local, instant)

    private func loadSFSymbols() async {
        let entries = await Task.detached(priority: .utility) { () -> [IconEntry] in
            let plistURL = URL(fileURLWithPath: "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist")
            guard let data = try? Data(contentsOf: plistURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                  let symbolsDict = plist["symbols"] as? [String: Any] else { return [] }

            let localeSuffixes = [".ar", ".hi", ".zh", ".ja", ".ko", ".ru", ".he", ".th", ".el", ".fa"]
            return symbolsDict.keys
                .filter { name in !localeSuffixes.contains(where: { name.hasSuffix($0) }) }
                .sorted()
                .map { IconEntry(id: $0, name: $0, library: "SF Symbol") }
        }.value

        self.sfSymbols = entries
        self.sfLoaded = true
    }

    // MARK: - On-demand Iconify search

    /// Call this whenever the search query changes.
    /// - Empty query shows first 160 SF Symbols only (no network call).
    /// - Non-empty query hits the Iconify search API with `palette=false`,
    ///   then merges matching SF Symbols at the top.
    public func search(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != lastQuery else { return }
        lastQuery = trimmed

        searchTask?.cancel()

        if trimmed.isEmpty {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            // Small debounce so we don't fire on every keystroke
            try? await Task.sleep(nanoseconds: 250_000_000) // 250ms
            guard !Task.isCancelled else { return }

            let lower = trimmed.lowercased()

            let sfMatches = sfSymbols.filter { $0.id.contains(lower) }.prefix(30)

        // palette=false keeps only monochrome icons. The network call runs off the main actor; results merge back below.
            let iconifyMatches = await Self.fetchIconifySearchResults(query: trimmed)

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.searchResults = Array(sfMatches) + iconifyMatches
                self.isSearching = false
            }
        }
    }

    public var defaultIcons: [IconEntry] {
        Array(sfSymbols.prefix(160))
    }

    /// Queries the Iconify search API off the main actor and returns flat "prefix:name" entries.
    /// `nonisolated` keeps network I/O and JSON parsing off the main actor; the caller merges results via `MainActor.run`.
    private nonisolated static func fetchIconifySearchResults(query: String) async -> [IconEntry] {
        var components = URLComponents(string: "https://api.iconify.design/search")
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: "120"),
            URLQueryItem(name: "palette", value: "false")
        ]
        guard let url = components?.url else {
            return []
        }
        let request = URLRequest(url: url, timeoutInterval: 10)
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let icons = json["icons"] as? [String] else {
            Log.icons.warning("Iconify search for '\(query)' returned no usable results")
            return []
        }
        let prefixes = icons.compactMap { $0.split(separator: ":", maxSplits: 1).first.map(String.init) }
        let multicolor = await IconifyPaletteCatalog.shared.multicolorPrefixes(among: prefixes)
        let usable = icons.filter { iconId in
            iconId.split(separator: ":", maxSplits: 1).first.map { !multicolor.contains(String($0)) } ?? true
        }
        return usable.prefix(80).map { iconId in
            let parts = iconId.split(separator: ":", maxSplits: 1)
            let label = parts.count == 2 ? String(parts[1]).replacingOccurrences(of: "-", with: " ").capitalized : iconId
            return IconEntry(id: iconId, name: label, library: "Iconify")
        }
    }
}

// MARK: - Iconify fetch policy

/// Timeout, retry, and filtering rules for Iconify requests, kept pure so tests can pin them.
enum IconifyFetchPolicy {
    static let maxConcurrentRequests = 6
    static let requestTimeout: TimeInterval = 8
    static let maxAttempts = 3
    /// A failed icon is not refetched inside this window, so a scrolling grid cannot hammer the API.
    static let failureCooldown: TimeInterval = 30

    /// Fallback for when the collections endpoint is unreachable. The search API returns multicolor sets
    /// despite `palette=false`, and as template images they collapse into solid shapes.
    static let multicolorPrefixes: Set<String> = [
        "selfhst", "thesvg-color", "token-branded", "logos", "devicon", "material-icon-theme",
        "vscode-icons", "skill-icons", "flat-color-icons", "twemoji", "openmoji", "noto",
        "fluent-emoji", "fluent-emoji-flat", "emojione", "fxemoji", "streamline-emojis"
    ]

    enum StatusOutcome: Equatable {
        case success
        case retry
        case giveUp
    }

    static func outcome(forStatusCode status: Int) -> StatusOutcome {
        switch status {
        case 200..<300:
            return .success
        case 408, 429, 500...599:
            return .retry
        default:
            return .giveUp
        }
    }

    /// Exponential backoff before a retry: 0.4 s, then 0.8 s. The first attempt never waits.
    static func backoffNanoseconds(beforeAttempt attempt: Int) -> UInt64 {
        guard attempt > 0 else { return 0 }
        let base: UInt64 = 400_000_000
        return base << UInt64(min(attempt - 1, 4))
    }

    /// Only transient failures are worth another attempt; offline, bad URL or cancelled never improve.
    static func shouldRetry(urlErrorCode code: URLError.Code?) -> Bool {
        switch code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    static func collectionsURL(for prefixes: Set<String>) -> URL? {
        guard !prefixes.isEmpty else { return nil }
        return URL(string: "https://api.iconify.design/collections?prefixes=\(prefixes.sorted().joined(separator: ","))")
    }

    /// `palette: true` in the collections response marks a set that carries its own colors.
    static func paletteFlags(fromCollectionsJSON data: Data) -> [String: Bool] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var flags: [String: Bool] = [:]
        for (prefix, info) in json {
            if let palette = (info as? [String: Any])?["palette"] as? Bool { flags[prefix] = palette }
        }
        return flags
    }

    static func isCoolingDown(failedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(failedAt) < failureCooldown
    }

    static func svgURL(for iconId: String) -> URL? {
        let parts = iconId.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return URL(string: "https://api.iconify.design/\(parts[0])/\(parts[1]).svg")
    }

    static func isMulticolor(iconId: String) -> Bool {
        let parts = iconId.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return false }
        return multicolorPrefixes.contains(String(parts[0]))
    }
}

/// Which Iconify sets are multicolor, asked of the collections endpoint once per prefix.
actor IconifyPaletteCatalog {
    static let shared = IconifyPaletteCatalog()

    private var flags: [String: Bool] = [:]
    private let fetch: @Sendable (URL) async -> Data?

    init(fetch: @escaping @Sendable (URL) async -> Data? = { url in
        try? await URLSession.shared.data(from: url).0
    }) {
        self.fetch = fetch
    }

    func multicolorPrefixes(among prefixes: [String]) async -> Set<String> {
        let unknown = Set(prefixes.filter { flags[$0] == nil })
        if let url = IconifyFetchPolicy.collectionsURL(for: unknown), let data = await fetch(url) {
            flags.merge(IconifyFetchPolicy.paletteFlags(fromCollectionsJSON: data)) { _, new in new }
        }
        return Set(prefixes.filter { flags[$0] ?? IconifyFetchPolicy.multicolorPrefixes.contains($0) })
    }
}
