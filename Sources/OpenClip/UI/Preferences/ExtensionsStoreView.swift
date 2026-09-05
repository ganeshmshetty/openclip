// ExtensionsStoreView.swift
// OpenClip
//
// Provides the extension store browsing view for the Actions tab in preferences,
// plus the shared view model used by onboarding. Formatted in a unified native macOS inset table.
import SwiftUI
import Core

public enum StoreFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case popular
    case new

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return String(localized: "All")
        case .popular: return String(localized: "Popular")
        case .new: return String(localized: "New")
        }
    }
}

@MainActor
public final class ExtensionsStoreViewModel: ObservableObject {
    @Published public var searchQuery: String = ""
    @Published public var extensions: [ExtensionItem] = []
    @Published public var featuredItems: [ExtensionItem] = []
    @Published public var newItems: [ExtensionItem] = []
    @Published public var selectedFilter: StoreFilter = .all
    @Published public var isLoading: Bool = false
    @Published public var currentPage: Int = 1
    @Published public var totalPages: Int = 1

    /// Curated featured extensions in priority order (shared with onboarding).
    public static let curatedFeaturedIDs: [String] = [
        "com.openclip.quick-translate",  // Quick Translate
        "com.openclip.wordcount",       // Word & Character Count
        "com.openclip.speakselection",  // Speak Selection
        "com.openclip.obsidiancapture", // Obsidian Capture
        "com.openclip.applereminders",  // Apple Reminders
        "com.openclip.githubsearch",    // GitHub Search
    ]

    /// High-quality built-in fallbacks for curated items ensuring the Featured showcase
    /// reliably renders all 4 extensions even offline, on slow network, or across pagination slices.
    public static let fallbackFeaturedItems: [ExtensionItem] = [
        ExtensionItem(
            id: "com.openclip.quick-translate",
            name: "Quick Translate",
            description: "Translate selected text instantly — result previewed in the popup or pasted in place.",
            author: "OpenClip Team",
            icon: "character.bubble",
            downloadCount: 121,
            downloadURL: "https://github.com/ganeshmshetty/openclip-extensions/releases/download/com.openclip.quick-translate@1.0.0/QuickTranslate.openclipext.zip",
            version: "1.0.0",
            iconURL: "https://cdn.jsdelivr.net/gh/ganeshmshetty/openclip-extensions@main/published/icons/com.openclip.quick-translate.svg"
        ),
        ExtensionItem(
            id: "com.openclip.wordcount",
            name: "Word & Character Count",
            description: "Count the words and characters in the selected text.",
            author: "OpenClip Team",
            icon: "text.alignleft",
            downloadCount: 84,
            downloadURL: "https://github.com/ganeshmshetty/openclip-extensions/releases/download/com.openclip.wordcount@1.0.2/WordCount.openclipext.zip",
            version: "1.0.2",
            iconURL: "https://cdn.jsdelivr.net/gh/ganeshmshetty/openclip-extensions@main/published/icons/com.openclip.wordcount.svg"
        ),
        ExtensionItem(
            id: "com.openclip.speakselection",
            name: "Speak Selection",
            description: "Text-to-speech using system voice.",
            author: "OpenClip Team",
            icon: "icon.svg",
            downloadCount: 74,
            downloadURL: "https://github.com/ganeshmshetty/openclip-extensions/releases/download/com.openclip.speakselection@1.0.1/SpeakSelection.openclipext.zip",
            version: "1.0.1",
            iconURL: "https://cdn.jsdelivr.net/gh/ganeshmshetty/openclip-extensions@main/published/icons/com.openclip.speakselection.svg"
        ),
        ExtensionItem(
            id: "com.openclip.obsidiancapture",
            name: "Obsidian Capture",
            description: "Capture selected text to an Obsidian vault note.",
            author: "OpenClip Team",
            icon: "icon.svg",
            downloadCount: 6,
            downloadURL: "https://github.com/ganeshmshetty/openclip-extensions/releases/download/com.openclip.obsidiancapture@1.0.0/ObsidianCapture.openclipext.zip",
            version: "1.0.0",
            iconURL: "https://cdn.jsdelivr.net/gh/ganeshmshetty/openclip-extensions@main/published/icons/com.openclip.obsidiancapture.svg"
        )
    ]

    /// Extensions recognized as recent or highlighted catalog additions.
    public static let recentNewIDs: [String] = [
        "com.openclip.render-html",
        "com.openclip.caniuse",
        "com.openclip.devdocs",
        "com.openclip.waybackmachine",
        "com.openclip.logseqcapture",
        "com.openclip.craftdocs",
        "com.openclip.fantasticalevent",
        "com.openclip.wikipedia",
        "com.openclip.applemusic",
    ]

    public static func isFeatured(_ item: ExtensionItem) -> Bool {
        curatedFeaturedIDs.contains(where: { $0.caseInsensitiveCompare(item.id) == .orderedSame })
    }

    public static func isNew(_ item: ExtensionItem) -> Bool {
        if recentNewIDs.contains(where: { $0.caseInsensitiveCompare(item.id) == .orderedSame }) {
            return true
        }
        if let v = item.version, v != "1.0.0", !v.hasPrefix("1.0.0") {
            return true
        }
        return false
    }

    /// Curated featured/popular items (first few for the showcase section).
    /// Uses server-provided curated extensions from the API when available,
    /// or filters loaded catalog extensions by curated IDs.
    public var featuredSectionItems: [ExtensionItem] {
        if !featuredItems.isEmpty {
            return Array(featuredItems.prefix(4))
        }
        let byID = Dictionary(extensions.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let curated = Self.curatedFeaturedIDs.compactMap { byID[$0.lowercased()] }
        return Array(curated.prefix(4))
    }

    /// Top new/updated items for the showcase section.
    public var newSectionItems: [ExtensionItem] {
        if !newItems.isEmpty {
            return Array(newItems.prefix(4))
        }
        let featuredIDs = Set(featuredSectionItems.map { $0.id.lowercased() })
        let byID = Dictionary(extensions.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let curatedNew = Self.recentNewIDs.compactMap { byID[$0.lowercased()] }
        let updated = extensions.filter { ext in
            Self.isNew(ext) && !featuredIDs.contains(ext.id.lowercased())
        }
        var chosen = Set<String>()
        var result: [ExtensionItem] = []
        for item in (curatedNew + updated) {
            let id = item.id.lowercased()
            if !featuredIDs.contains(id) && chosen.insert(id).inserted {
                result.append(item)
            }
        }
        return Array(result.prefix(4))
    }

    /// The remaining catalog items for the "All Extensions" section when browsing "All",
    /// deduplicating items showcased in the featured and new sections above.
    public var remainingAllSectionItems: [ExtensionItem] {
        let showcased = Set(featuredSectionItems.map { $0.id.lowercased() } + newSectionItems.map { $0.id.lowercased() })
        return extensions.filter { !showcased.contains($0.id.lowercased()) }
    }

    /// ID of the last item rendered across the sectioned storefront, used to trigger pagination.
    public var lastRenderedSectionedItemID: String? {
        remainingAllSectionItems.last?.id
            ?? newSectionItems.last?.id
            ?? featuredSectionItems.last?.id
    }

    /// True when the given item is the final rendered item in the sectioned storefront.
    public func shouldTriggerSectionedPagination(for itemID: String) -> Bool {
        itemID == lastRenderedSectionedItemID
    }

    /// True when the given item is the final rendered item in the flat store list.
    public func shouldTriggerFlatPagination(for itemID: String) -> Bool {
        itemID == displayedExtensions.last?.id
    }

    /// Full list when the "Popular" filter tab is selected.
    public var popularFilterItems: [ExtensionItem] {
        let byID = Dictionary(extensions.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let curated = !featuredItems.isEmpty ? featuredItems : Self.curatedFeaturedIDs.compactMap { byID[$0.lowercased()] }
        var chosen = Set(curated.map { $0.id.lowercased() })
        let popular = extensions
            .filter { !chosen.contains($0.id.lowercased()) && $0.downloadCount > 0 }
            .sorted { $0.downloadCount > $1.downloadCount }
        for item in popular { chosen.insert(item.id.lowercased()) }
        return curated + popular
    }

    /// Full list when the "New" filter tab is selected.
    public var newFilterItems: [ExtensionItem] {
        if !newItems.isEmpty {
            var chosen = Set(newItems.map { $0.id.lowercased() })
            let other = extensions.filter { ext in
                !chosen.contains(ext.id.lowercased()) && Self.isNew(ext)
            }
            return newItems + other
        }
        let byID = Dictionary(extensions.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let curatedNew = Self.recentNewIDs.compactMap { byID[$0.lowercased()] }
        var chosen = Set(curatedNew.map { $0.id.lowercased() })
        let updated = extensions.filter { ext in
            !chosen.contains(ext.id.lowercased()) && Self.isNew(ext)
        }
        return curatedNew + updated
    }

    /// Monotonic result-set generation. Every reset bumps it; any response that resolves
    /// against a superseded generation is discarded, so a slow earlier request landing late
    /// (fast typing, page prefetch racing a new search) can never surface stale rows.
    private var generation = 0
    /// In-flight debounced search; cancelled when the query changes again.
    private var searchTask: Task<Void, Never>?
    private let api: any ExtensionStoreFetching
    /// Keystroke quiet period before a search actually fires.
    private let debounceNanos: UInt64
    /// Page size for the active fetch session; onboarding raises it so one request
    /// covers the whole catalog and curated picks are always in the result set.
    private var pageLimit: Int = Constants.storePageLimit

    public init(api: any ExtensionStoreFetching = ExtensionsAPIClient.shared,
                debounceNanos: UInt64 = 250_000_000) {
        self.api = api
        self.debounceNanos = debounceNanos
    }

    deinit { searchTask?.cancel() }

    public var displayedExtensions: [ExtensionItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            return extensions
        }
        switch selectedFilter {
        case .all:
            return extensions
        case .popular:
            return popularFilterItems
        case .new:
            return newFilterItems
        }
    }

    /// Debounced, cancellable search entry point for per-keystroke changes. Coalesces rapid
    /// typing into one request and cancels any in-flight one; the view calls this from
    /// `onChange(of: searchQuery)` instead of spawning its own unstructured task.
    public func queryDidChange() {
        if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            selectedFilter = .all
        }
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.debounceNanos)
            guard !Task.isCancelled else { return }
            await self.resetAndFetch(limit: self.pageLimit, keepPrevious: true)
        }
    }

    public func fetchNextPage(isReset: Bool = false) async {
        let gen = generation
        guard !isLoading || isReset, currentPage <= totalPages else { return }
        isLoading = true

        do {
            let response = try await api.fetchExtensions(query: searchQuery, page: currentPage, limit: pageLimit)
            // Superseded mid-flight (newer search/reset owns the result set): touch nothing,
            // especially not `isLoading`, which now belongs to the winning generation.
            guard gen == generation else { return }
            if let featured = response.featured, !featured.isEmpty {
                featuredItems = featured
            }
            if let new = response.new, !new.isEmpty {
                newItems = new
            }
            if isReset {
                extensions = response.extensions
            } else {
                extensions.append(contentsOf: response.extensions)
            }
            totalPages = response.totalPages
            currentPage += 1
            isLoading = false
        } catch is CancellationError {
            // Superseded or torn down; the winner manages its own state.
        } catch {
            guard gen == generation else { return }
            Log.extensions.warning("Failed to fetch extension store page \(self.currentPage) for query '\(self.searchQuery)'")
            if isReset && extensions.isEmpty {
                extensions = []
            }
            isLoading = false
        }
    }

    public func resetAndFetch(limit: Int = Constants.storePageLimit, keepPrevious: Bool = false) async {
        // Bump first: any in-flight request from the previous generation is dead on arrival
        // and can neither append rows nor hold the loading flag against this fetch.
        generation += 1
        pageLimit = limit
        currentPage = 1
        totalPages = 1
        if !keepPrevious {
            extensions = []
        }
        isLoading = true
        await fetchNextPage(isReset: true)
    }
}

public struct ExtensionStoreView: View {
    @ObservedObject var viewModel: ExtensionsStoreViewModel

    public init(viewModel: ExtensionsStoreViewModel) {
        self.viewModel = viewModel
    }

    private var isSearching: Bool {
        !viewModel.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public var body: some View {
        VStack(spacing: 0) {
            filterPillsRow
            storeContent
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 0)
        .task {
            if viewModel.extensions.isEmpty {
                await viewModel.resetAndFetch(limit: 100)
            }
        }
    }

    private var filterPillsRow: some View {
        HStack(spacing: 8) {
            ForEach(StoreFilter.allCases) { filter in
                let isSelected = viewModel.selectedFilter == filter && !isSearching
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if isSearching {
                            viewModel.searchQuery = ""
                        }
                        viewModel.selectedFilter = filter
                    }
                } label: {
                    HStack(spacing: 4.5) {
                        if filter == .popular {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 9.5, weight: .semibold))
                        } else if filter == .new {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        Text(filter.title)
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 4.5)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                    )
                    .foregroundColor(isSelected ? .white : .secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .opacity(isSearching ? 0.4 : 1.0)
    }

    private var storeContent: some View {
        VStack(spacing: 0) {
            if viewModel.extensions.isEmpty && viewModel.isLoading {
                skeletonList
            } else if viewModel.displayedExtensions.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No extensions found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !isSearching && viewModel.selectedFilter == .all {
                sectionedAllStoreContent
            } else {
                flatStoreContent
            }
        }
    }

    private func sectionHeader(title: String, icon: String, count: Int? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.accentColor)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            if let count {
                Text("(\(count))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private var sectionedAllStoreContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Section 1: Featured
                if !viewModel.featuredSectionItems.isEmpty {
                    sectionHeader(title: String(localized: "Featured"), icon: "rosette")
                    ForEach(Array(viewModel.featuredSectionItems.enumerated()), id: \.element.id) { index, ext in
                        if index > 0 {
                            Divider()
                                .padding(.leading, 60)
                                .padding(.trailing, 14)
                        }
                        ExtensionCardView(item: ext)
                            .onAppear {
                                if viewModel.shouldTriggerSectionedPagination(for: ext.id) {
                                    Task { await viewModel.fetchNextPage() }
                                }
                            }
                    }
                }

                // Section 2: New & Updated
                if !viewModel.newSectionItems.isEmpty {
                    sectionHeader(title: String(localized: "New & Updated"), icon: "clock.arrow.circlepath")
                    ForEach(Array(viewModel.newSectionItems.enumerated()), id: \.element.id) { index, ext in
                        if index > 0 {
                            Divider()
                                .padding(.leading, 60)
                                .padding(.trailing, 14)
                        }
                        ExtensionCardView(item: ext)
                            .onAppear {
                                if viewModel.shouldTriggerSectionedPagination(for: ext.id) {
                                    Task { await viewModel.fetchNextPage() }
                                }
                            }
                    }
                }

                // Section 3: All Extensions
                if !viewModel.remainingAllSectionItems.isEmpty {
                    sectionHeader(title: String(localized: "All Extensions"), icon: "square.grid.2x2", count: viewModel.remainingAllSectionItems.count)
                    ForEach(Array(viewModel.remainingAllSectionItems.enumerated()), id: \.element.id) { index, ext in
                        if index > 0 {
                            Divider()
                                .padding(.leading, 60)
                                .padding(.trailing, 14)
                        }
                        ExtensionCardView(item: ext)
                            .onAppear {
                                if viewModel.shouldTriggerSectionedPagination(for: ext.id) {
                                    Task { await viewModel.fetchNextPage() }
                                }
                            }
                    }
                }
            }
        }
        .opacity(viewModel.isLoading && !viewModel.extensions.isEmpty ? 0.65 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: viewModel.isLoading)
    }

    private var flatStoreContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.displayedExtensions.enumerated()), id: \.element.id) { index, ext in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 60)
                            .padding(.trailing, 14)
                    }
                    ExtensionCardView(item: ext)
                        .onAppear {
                            if viewModel.shouldTriggerFlatPagination(for: ext.id) {
                                Task { await viewModel.fetchNextPage() }
                            }
                        }
                }
            }
        }
        .opacity(viewModel.isLoading && !viewModel.extensions.isEmpty ? 0.65 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: viewModel.isLoading)
    }

    private var skeletonList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { index in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 60)
                            .padding(.trailing, 14)
                    }
                    ExtensionCardSkeletonRow()
                }
            }
        }
    }
}

// MARK: - Extension Card Skeleton Row

private struct ExtensionCardSkeletonRow: View {
    @State private var isPulsing = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.07))
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.10))
                        .frame(width: 110, height: 12)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                        .frame(width: 60, height: 10)
                }
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 220, height: 11)
            }

            Spacer()

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.07))
                .frame(width: 64, height: 24)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .opacity(isPulsing ? 0.35 : 0.85)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}
