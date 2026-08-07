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

/// Searches icons on demand using the Iconify API (same approach as PopClip).
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

    // MARK: - On-demand Iconify search (like PopClip)

    /// Call this whenever the search query changes.
    /// - Empty query shows first 160 SF Symbols only (no network call).
    /// - Non-empty query hits the Iconify search API with `palette=false`,
    ///   then merges matching SF Symbols at the top.
    public func search(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != lastQuery else { return }
        lastQuery = trimmed

        // Cancel any in-flight search
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

            // SF Symbol matches (local, instant)
            let sfMatches = sfSymbols.filter { $0.id.contains(lower) }.prefix(30)

            // Iconify search API — palette=false gives only monochrome icons. The network call +
            // JSON parse run off the main actor (nonisolated helper); results merge back below.
            let iconifyMatches = await Self.fetchIconifySearchResults(query: trimmed)

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.searchResults = Array(sfMatches) + iconifyMatches
                self.isSearching = false
            }
        }
    }

    /// Default icons shown when search is empty (first 160 SF Symbols)
    public var defaultIcons: [IconEntry] {
        Array(sfSymbols.prefix(160))
    }

    /// Queries the Iconify search API off the main actor and returns flat "prefix:name" entries.
    /// `nonisolated` runs on the cooperative thread pool, so the network I/O and JSON parse never
    /// block the UI — the caller merges results back via `MainActor.run`. `[IconEntry]` is Sendable,
    /// so it crosses the actor boundary without a box.
    private nonisolated static func fetchIconifySearchResults(query: String) async -> [IconEntry] {
        guard let url = URL(string: "https://api.iconify.design/search?query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)&limit=80&palette=false") else {
            return []
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let icons = json["icons"] as? [String] else {
            Log.icons.warning("Iconify search for '\(query)' returned no usable results")
            return []
        }
        // icons are in "prefix:name" format — perfect, use directly
        return icons.map { iconId in
            let parts = iconId.split(separator: ":", maxSplits: 1)
            let label = parts.count == 2 ? String(parts[1]).replacingOccurrences(of: "-", with: " ").capitalized : iconId
            return IconEntry(id: iconId, name: label, library: "Iconify")
        }
    }
}
