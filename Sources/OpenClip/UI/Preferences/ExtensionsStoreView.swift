// ExtensionsStoreView.swift
// OpenClip
//
// Provides the extension store browsing view for the Actions tab in preferences,
// plus the shared view model used by onboarding. Formatted in a unified native macOS inset table.
import SwiftUI
import Core

/// How the store list is ordered. It replaced an All/Popular/New *filter*, which hid extensions
/// rather than reordering them — "Popular" dropped everything with no downloads yet, which is
/// exactly where a new extension starts.
public enum StoreSort: String, CaseIterable, Identifiable, Sendable {
    /// The catalogue's own order, with the curated showcase on top. The default.
    case featured
    case name
    case downloads
    case recentlyAdded

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .featured: return String(localized: "Featured")
        case .name: return String(localized: "Name")
        case .downloads: return String(localized: "Downloads")
        case .recentlyAdded: return String(localized: "Recently Added")
        }
    }

    public var symbol: String {
        switch self {
        case .featured: return "rosette"
        case .name: return "textformat"
        case .downloads: return "arrow.down.circle"
        case .recentlyAdded: return "clock"
        }
    }
}

@MainActor
public final class ExtensionsStoreViewModel: ObservableObject {
    @Published public var searchQuery: String = ""
    @Published public var extensions: [ExtensionItem] = []
    @Published public var featuredItems: [ExtensionItem] = []
    @Published public var newItems: [ExtensionItem] = []
    @Published public var selectedSort: StoreSort = .featured
    @Published public var isLoading: Bool = false
    @Published public var currentPage: Int = 1
    @Published public var totalPages: Int = 1
    @Published public var networkError: String? = nil

    /// Curated featured extensions in priority order (shared with onboarding).
    public static let curatedFeaturedIDs: [String] = [
        "com.openclip.quick-translate",   // Quick Translate
        "com.openclip.runcommand",        // Run in Terminal
        "com.openclip.copy-as-markdown",  // Copy as Markdown
        "com.openclip.shortenlink",       // Shorten Link
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
            downloadCount: 307,
            downloadURL: "https://github.com/ganeshmshetty/openclip-extensions/releases/download/com.openclip.quick-translate@1.0.0/QuickTranslate.openclipext.zip",
            version: "1.0.0",
            iconURL: "https://cdn.jsdelivr.net/gh/ganeshmshetty/openclip-extensions@main/published/icons/com.openclip.quick-translate.svg"
        ),
        ExtensionItem(
            id: "com.openclip.runcommand",
            name: "Run in Terminal",
            description: "Run selected text as a command in Terminal, iTerm, Warp, or Ghostty.",
            author: "OpenClip Team",
            icon: "icon.svg",
            downloadCount: 20,
            downloadURL: "https://github.com/ganeshmshetty/openclip-extensions/releases/download/com.openclip.runcommand@1.0.0/RunCommand.openclipext.zip",
            version: "1.0.0",
            iconURL: "https://cdn.jsdelivr.net/gh/ganeshmshetty/openclip-extensions@main/published/icons/com.openclip.runcommand.svg"
        ),
        ExtensionItem(
            id: "com.openclip.copy-as-markdown",
            name: "Copy as Markdown",
            description: "Convert rich text, web selections, and tables into clean Markdown.",
            author: "OpenClip Team",
            icon: "icon.svg",
            downloadCount: 35,
            downloadURL: "https://github.com/ganeshmshetty/openclip-extensions/releases/download/com.openclip.copy-as-markdown@1.0.0/CopyAsMarkdown.openclipext.zip",
            version: "1.0.0",
            iconURL: "https://cdn.jsdelivr.net/gh/ganeshmshetty/openclip-extensions@main/published/icons/com.openclip.copy-as-markdown.svg"
        ),
        ExtensionItem(
            id: "com.openclip.shortenlink",
            name: "Shorten Link",
            description: "Shorten the selected URL using TinyURL, is.gd, or v.gd.",
            author: "OpenClip Team",
            icon: "icon.svg",
            downloadCount: 25,
            downloadURL: "https://github.com/ganeshmshetty/openclip-extensions/releases/download/com.openclip.shortenlink@1.0.0/ShortenLink.openclipext.zip",
            version: "1.0.0",
            iconURL: "https://cdn.jsdelivr.net/gh/ganeshmshetty/openclip-extensions@main/published/icons/com.openclip.shortenlink.svg"
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

    public func isFeatured(_ item: ExtensionItem) -> Bool {
        if !featuredItems.isEmpty {
            return featuredItems.contains(where: { $0.id.caseInsensitiveCompare(item.id) == .orderedSame })
        }
        return Self.curatedFeaturedIDs.contains(where: { $0.caseInsensitiveCompare(item.id) == .orderedSame })
    }

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

    /// The storefront below the featured showcase: everything else, in catalog
    /// order. New and updated items used to get a showcase of their own, which
    /// meant three stacked lists competing for the first look; they are part of
    /// the catalog now.
    public var catalogSectionItems: [ExtensionItem] {
        let featured = Set(featuredSectionItems.map { $0.id.lowercased() })
        return extensions.filter { !featured.contains($0.id.lowercased()) }
    }

    /// ID of the last item rendered across the sectioned storefront, used to trigger pagination.
    public var lastRenderedSectionedItemID: String? {
        catalogSectionItems.last?.id ?? featuredSectionItems.last?.id
    }

    /// True when the given item is the final rendered item in the sectioned storefront.
    public func shouldTriggerSectionedPagination(for itemID: String) -> Bool {
        itemID == lastRenderedSectionedItemID
    }

    /// True when the given item is the final rendered item in the flat store list.
    public func shouldTriggerFlatPagination(for itemID: String) -> Bool {
        itemID == displayedExtensions.last?.id
    }

    /// Orders `items` without dropping any of them. Pure, so the ordering is pinned by tests.
    ///
    /// `newest` is a rank rather than a date: the catalogue carries no published-at field, so the
    /// API's own "new" list comes first (in its order), then the curated recent ids, then anything
    /// whose version says it has moved past its first release. Ties keep catalogue order, which is
    /// why the rank is paired with the original index instead of relying on a stable sort.
    public static func sorted(
        _ items: [ExtensionItem],
        by sort: StoreSort,
        apiNewItems: [ExtensionItem] = []
    ) -> [ExtensionItem] {
        switch sort {
        case .featured:
            return items

        case .name:
            return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        case .downloads:
            return items.sorted {
                if $0.downloadCount != $1.downloadCount {
                    return $0.downloadCount > $1.downloadCount
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }

        case .recentlyAdded:
            var apiRank: [String: Int] = [:]
            for (index, item) in apiNewItems.enumerated() {
                apiRank[item.id.lowercased()] = index
            }
            let curated = Set(recentNewIDs.map { $0.lowercased() })

            func rank(_ item: ExtensionItem) -> (Int, Int) {
                let id = item.id.lowercased()
                if let position = apiRank[id] { return (0, position) }
                if curated.contains(id) { return (1, 0) }
                return (isNew(item) ? 2 : 3, 0)
            }

            return items.enumerated()
                .sorted { left, right in
                    let leftRank = rank(left.element)
                    let rightRank = rank(right.element)
                    if leftRank != rightRank { return leftRank < rightRank }
                    return left.offset < right.offset
                }
                .map(\.element)
        }
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
        Self.sorted(extensions, by: selectedSort, apiNewItems: newItems)
    }

    /// Debounced, cancellable search entry point for per-keystroke changes. Coalesces rapid
    /// typing into one request and cancels any in-flight one; the view calls this from
    /// `onChange(of: searchQuery)` instead of spawning its own unstructured task.
    public func queryDidChange() {
        // The chosen order carries over into the results: sorting is not a filter, so a search
        // does not need to undo it.
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.debounceNanos)
            guard !Task.isCancelled else { return }
            await self.resetAndFetch(limit: self.pageLimit, keepPrevious: true)
        }
    }

    public func fetchNextPage(isReset: Bool = false, ignoreCache: Bool = false) async {
        let gen = generation
        guard !isLoading || isReset, currentPage <= totalPages else { return }
        isLoading = true

        do {
            let response = try await api.fetchExtensions(query: searchQuery, page: currentPage, limit: pageLimit, ignoreCache: ignoreCache)
            // Superseded mid-flight (newer search/reset owns the result set): touch nothing,
            // especially not `isLoading`, which now belongs to the winning generation.
            guard gen == generation else { return }
            networkError = nil
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
            guard gen == generation else { return }
            isLoading = false
        } catch {
            guard gen == generation else { return }
            Log.extensions.warning("Failed to fetch extension store page \(self.currentPage) for query '\(self.searchQuery)'")
            if isReset && extensions.isEmpty {
                networkError = error.localizedDescription
                extensions = []
            }
            isLoading = false
        }
    }

    public func resetAndFetch(limit: Int = Constants.storePageLimit, keepPrevious: Bool = false, ignoreCache: Bool = false) async {
        // Bump first: any in-flight request from the previous generation is dead on arrival
        // and can neither append rows nor hold the loading flag against this fetch.
        generation += 1
        pageLimit = limit
        currentPage = 1
        totalPages = 1
        if !keepPrevious {
            extensions = []
            networkError = nil
        }
        isLoading = true
        await fetchNextPage(isReset: true, ignoreCache: ignoreCache)
    }

    /// Explicit manual refresh that clears cached store responses and reloads the fresh catalog from the network.
    public func refreshCatalog() async {
        await api.invalidateCache()
        await resetAndFetch(limit: max(pageLimit, 100), keepPrevious: false, ignoreCache: true)
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
        // The search field and the sort button live in the window toolbar, so the pane is just
        // the list. No padding around `storeContent`: the list has to reach the pane's top edge
        // for the system to fade it out under the toolbar the way the Form-based panes are. The
        // 12pt gutter lives on the scrolling content inside instead.
        storeContent
        .task {
            if viewModel.extensions.isEmpty {
                await viewModel.resetAndFetch(limit: 100)
            }
        }
    }

    private var storeContent: some View {
        VStack(spacing: 0) {
            if viewModel.extensions.isEmpty && viewModel.isLoading {
                skeletonList
            } else if viewModel.extensions.isEmpty && viewModel.networkError != nil {
                offlineStateView
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
            } else if !isSearching && viewModel.selectedSort == .featured {
                sectionedAllStoreContent
            } else {
                flatStoreContent
            }
        }
    }

    private var offlineStateView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "wifi.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.8))
            Text(String(localized: "Unable to Connect to Store"))
                .font(.headline)
                .foregroundColor(.primary)
            Text(String(localized: "Check your internet connection or network settings. If you are behind a corporate proxy or firewall, access to the extension store may be blocked."))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button {
                Task {
                    await viewModel.refreshCatalog()
                }
            } label: {
                Label(String(localized: "Try Again"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private func sectionHeader(_ title: String, count: Int? = nil) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.headline)
            if let count {
                Text("\(count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    private var sectionedAllStoreContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if !viewModel.featuredSectionItems.isEmpty {
                    sectionHeader(String(localized: "Featured"))
                    ForEach(Array(viewModel.featuredSectionItems.enumerated()), id: \.element.id) { index, ext in
                        if index > 0 {
                            rowDivider
                        }
                        storeRow(ext)
                    }
                }

                if !viewModel.catalogSectionItems.isEmpty {
                    sectionHeader(
                        String(localized: "All Extensions"),
                        count: viewModel.catalogSectionItems.count
                    )
                    ForEach(Array(viewModel.catalogSectionItems.enumerated()), id: \.element.id) { index, ext in
                        if index > 0 {
                            rowDivider
                        }
                        storeRow(ext)
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .opacity(viewModel.isLoading && !viewModel.extensions.isEmpty ? 0.65 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: viewModel.isLoading)
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 60)
            .padding(.trailing, 14)
    }

    private func storeRow(_ ext: ExtensionItem) -> some View {
        ExtensionCardView(item: ext, isFeatured: viewModel.isFeatured(ext))
            .onAppear {
                if viewModel.shouldTriggerSectionedPagination(for: ext.id) {
                    Task { await viewModel.fetchNextPage() }
                }
            }
    }

    private var flatStoreContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.displayedExtensions.enumerated()), id: \.element.id) { index, ext in
                    if index > 0 {
                        rowDivider
                    }
                    ExtensionCardView(item: ext, isFeatured: viewModel.isFeatured(ext))
                        .onAppear {
                            if viewModel.shouldTriggerFlatPagination(for: ext.id) {
                                Task { await viewModel.fetchNextPage() }
                            }
                        }
                }
            }
            .padding(.horizontal, 12)
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
            .padding(.horizontal, 12)
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
