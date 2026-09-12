// ExtensionsStoreViewTests.swift
// OpenClip
//
// Covers the store view model's request lifecycle: out-of-order response protection
// (generation token), keystroke debouncing, stale-pagination discard, and the shared
// TTL page cache that survives tab switches.
import XCTest
@testable import Core
@testable import OpenClip

final class ExtensionsStoreViewTests: XCTestCase {
    @MainActor
    func testExtensionsStoreViewModelInitialState() {
        let viewModel = ExtensionsStoreViewModel(api: GatedStoreAPI())
        XCTAssertEqual(viewModel.searchQuery, "")
        XCTAssertTrue(viewModel.extensions.isEmpty)
        XCTAssertEqual(viewModel.currentPage, 1)
        XCTAssertFalse(viewModel.isLoading)
    }

    /// Typing fast must never surface results for an earlier prefix: when the newer query's
    /// response lands first, the slow older response is discarded by the generation token.
    @MainActor
    func testOutOfOrderResponsesKeepLatestQueryResults() async throws {
        let api = GatedStoreAPI(arrivals: [
            expectation(description: "query 'a' fetch started"),
            expectation(description: "query 'abc' fetch started")
        ])
        let viewModel = ExtensionsStoreViewModel(api: api, debounceNanos: 10_000_000)

        viewModel.searchQuery = "a"
        viewModel.queryDidChange()
        await fulfillment(of: [api.arrivals[0]], timeout: 2)

        viewModel.searchQuery = "abc"
        viewModel.queryDidChange()
        await fulfillment(of: [api.arrivals[1]], timeout: 2)

        // Newer prefix resolves first and wins.
        await api.release(query: "abc", names: ["abc-result"])
        try await Task.sleep(nanoseconds: 50_000_000)
        let afterNewest = viewModel.extensions.map(\.id)
        XCTAssertEqual(afterNewest, ["abc-result"])

        // Older, slower response lands late — discarded, not rendered or appended.
        await api.release(query: "a", names: ["stale-a"])
        try await Task.sleep(nanoseconds: 50_000_000)
        let afterStale = viewModel.extensions.map(\.id)
        XCTAssertEqual(afterStale, ["abc-result"],
                       "a superseded response must never replace or extend current results")
    }

    /// Rapid keystrokes coalesce into exactly one network request for the final text.
    @MainActor
    func testDebounceCoalescesRapidKeystrokes() async throws {
        let api = RecordingStoreAPI()
        let viewModel = ExtensionsStoreViewModel(api: api, debounceNanos: 50_000_000)

        viewModel.searchQuery = "s"
        viewModel.queryDidChange()
        viewModel.searchQuery = "sp"
        viewModel.queryDidChange()
        viewModel.searchQuery = "spa"
        viewModel.queryDidChange()

        try await Task.sleep(nanoseconds: 150_000_000) // quiet period elapses
        let queries = await api.recordedQueries()
        XCTAssertEqual(queries, ["spa"], "only the final query may hit the API")
        XCTAssertEqual(viewModel.extensions.map(\.id), ["spa-row"])
    }

    /// A page-2 prefetch parked mid-flight can neither block a new search nor append its
    /// rows to the fresh result set; the loading flag belongs to the winning generation.
    @MainActor
    func testStalePaginationAppendIsDiscardedAfterNewSearch() async throws {
        let api = GatedStoreAPI()
        let viewModel = ExtensionsStoreViewModel(api: api, debounceNanos: 10_000_000)

        viewModel.searchQuery = "old"
        let initial = Task { await viewModel.resetAndFetch() }
        try await waitUntil { await api.hasPending(query: "old", page: 1) }
        await api.release(query: "old", names: ["old-1", "old-2"], totalPages: 2)
        await initial.value
        XCTAssertEqual(viewModel.extensions.map(\.id), ["old-1", "old-2"])

        // Page-2 prefetch starts and parks on the gate…
        let prefetch = Task { await viewModel.fetchNextPage() }
        try await waitUntil { await api.hasPending(query: "old", page: 2) }

        // …then a brand-new result set is requested; it must not be blocked by the parked page…
        viewModel.searchQuery = "new"
        let refreshed = Task { await viewModel.resetAndFetch() }
        try await waitUntil { await api.hasPending(query: "new", page: 1) }
        await api.release(query: "new", names: ["new-1"])
        await refreshed.value
        XCTAssertEqual(viewModel.extensions.map(\.id), ["new-1"])

        // …and when the stale page finally lands it must not leak into the new list.
        await api.release(query: "old", page: 2, names: ["stale-page-2"], totalPages: 9)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(viewModel.extensions.map(\.id), ["new-1"])
        XCTAssertFalse(viewModel.isLoading)
        await prefetch.value
    }

    // MARK: - ExtensionStoreCache

    func testCacheRoundTripAndKeyIsolation() async {
        let cache = ExtensionStoreCache(ttl: 60)
        let response = ExtensionsPageResponse(extensions: [], page: 1, totalPages: 3, totalCount: 30)
        await cache.store(response, baseURL: "https://prod.example/api", query: "Swift UI ", page: 1, limit: 12)

        // Normalized (trimmed + lowercased) query hits the same entry.
        let hit = await cache.response(baseURL: "https://prod.example/api", query: "swift ui", page: 1, limit: 12)
        XCTAssertEqual(hit?.totalPages, 3)
        // Different page / query / limit are distinct keys.
        let missPage = await cache.response(baseURL: "https://prod.example/api", query: "swift ui", page: 2, limit: 12)
        XCTAssertNil(missPage)
        let missLimit = await cache.response(baseURL: "https://prod.example/api", query: "swift ui", page: 1, limit: 50)
        XCTAssertNil(missLimit)
        let missQuery = await cache.response(baseURL: "https://prod.example/api", query: "other", page: 1, limit: 12)
        XCTAssertNil(missQuery)
        // A second client pointed at a different endpoint must never see prod's pages
        // (the shared instance is injected into every ExtensionsAPIClient by default).
        let otherBase = await cache.response(baseURL: "https://stub.test/api", query: "swift ui", page: 1, limit: 12)
        XCTAssertNil(otherBase)
    }

    func testCacheExpiresAfterTTLAndSupportsInvalidation() async throws {
        let cache = ExtensionStoreCache(ttl: 0.005)
        let response = ExtensionsPageResponse(extensions: [], page: 1, totalPages: 1, totalCount: 0)
        await cache.store(response, baseURL: "https://prod.example/api", query: "x", page: 1, limit: 12)
        try await Task.sleep(nanoseconds: 10_000_000)
        let expired = await cache.response(baseURL: "https://prod.example/api", query: "x", page: 1, limit: 12)
        XCTAssertNil(expired, "entries past the TTL must not be served")

        let fresh = ExtensionStoreCache(ttl: 60)
        await fresh.store(response, baseURL: "https://prod.example/api", query: "y", page: 1, limit: 12)
        await fresh.removeAll()
        let cleared = await fresh.response(baseURL: "https://prod.example/api", query: "y", page: 1, limit: 12)
        XCTAssertNil(cleared)
    }

    // MARK: - Store Sorting & Badges

    @MainActor
    func testSortingOrdersTheCatalogueWithoutDroppingAnything() {
        let api = RecordingStoreAPI()
        let viewModel = ExtensionsStoreViewModel(api: api)
        XCTAssertEqual(viewModel.selectedSort, .featured, "the catalogue's own order to begin with")

        let item1 = ExtensionItem(id: "com.openclip.quick-translate", name: "Quick Translate",
                                  description: "", author: "openclip", icon: "", downloadCount: 1500, downloadURL: "")
        let item2 = ExtensionItem(id: "com.openclip.render-html", name: "Render HTML",
                                  description: "", author: "openclip", icon: "", downloadCount: 100, downloadURL: "", version: "1.1.0")
        let item3 = ExtensionItem(id: "com.openclip.basic-tool", name: "Basic Tool",
                                  description: "", author: "openclip", icon: "", downloadCount: 0, downloadURL: "", version: "1.0.0")

        viewModel.extensions = [item1, item2, item3]
        let everything = Set([item1, item2, item3].map(\.id))

        // Featured keeps the catalogue's order, and the showcase sections still work off it.
        XCTAssertEqual(viewModel.displayedExtensions.map(\.id),
                       ["com.openclip.quick-translate", "com.openclip.render-html", "com.openclip.basic-tool"])
        XCTAssertEqual(viewModel.featuredSectionItems.map(\.id), ["com.openclip.quick-translate"])
        XCTAssertEqual(viewModel.newSectionItems.map(\.id), ["com.openclip.render-html"])
        XCTAssertEqual(viewModel.remainingAllSectionItems.map(\.id), ["com.openclip.basic-tool"])

        viewModel.selectedSort = .name
        XCTAssertEqual(viewModel.displayedExtensions.map(\.name), ["Basic Tool", "Quick Translate", "Render HTML"])

        viewModel.selectedSort = .downloads
        XCTAssertEqual(viewModel.displayedExtensions.map(\.id),
                       ["com.openclip.quick-translate", "com.openclip.render-html", "com.openclip.basic-tool"])
        XCTAssertEqual(Set(viewModel.displayedExtensions.map(\.id)), everything,
                       "an extension nobody has downloaded yet sorts last, it does not disappear")

        viewModel.selectedSort = .recentlyAdded
        let recent = viewModel.displayedExtensions.map(\.id)
        XCTAssertEqual(recent.first, "com.openclip.render-html", "curated as recent, and past its first version")
        XCTAssertEqual(Set(recent), everything)
    }

    @MainActor
    func testSortingIsPureAndKeepsCatalogueOrderWithinARank() {
        func item(_ id: String, _ name: String, downloads: Int = 0, version: String = "1.0.0") -> ExtensionItem {
            ExtensionItem(id: id, name: name, description: "", author: "", icon: "",
                          downloadCount: downloads, downloadURL: "", version: version)
        }
        let a = item("com.x.a", "Alpha", downloads: 5)
        let b = item("com.x.b", "bravo", downloads: 5)
        let c = item("com.x.c", "Charlie", downloads: 9)
        let input = [a, b, c]

        XCTAssertEqual(ExtensionsStoreViewModel.sorted(input, by: .featured).map(\.id), input.map(\.id))
        XCTAssertEqual(ExtensionsStoreViewModel.sorted(input, by: .name).map(\.name), ["Alpha", "bravo", "Charlie"],
                       "names sort the way the Finder sorts them, not by code point")
        XCTAssertEqual(ExtensionsStoreViewModel.sorted(input, by: .downloads).map(\.id),
                       ["com.x.c", "com.x.a", "com.x.b"], "equal counts fall back to the name")

        // Nothing is added or lost, whatever the order.
        for sort in StoreSort.allCases {
            XCTAssertEqual(Set(ExtensionsStoreViewModel.sorted(input, by: sort).map(\.id)), Set(input.map(\.id)))
            XCTAssertEqual(ExtensionsStoreViewModel.sorted(input, by: sort).count, input.count)
        }

        // The API's own "new" list leads, in its order, and everything else keeps catalogue order.
        let ranked = ExtensionsStoreViewModel.sorted(input, by: .recentlyAdded, apiNewItems: [c, a])
        XCTAssertEqual(ranked.map(\.id), ["com.x.c", "com.x.a", "com.x.b"])
    }

    func testThePublicationDateIsParsedFromWhatTheCatalogueActuallySends() throws {
        // The shape the live catalogue uses: an internet timestamp with an offset.
        let offset = ExtensionItem.parsePublishedAt("2026-08-20T22:00:51+05:30")
        XCTAssertEqual(try XCTUnwrap(offset).timeIntervalSince1970, 1_787_243_451, accuracy: 1)

        // And the shapes it might use instead.
        XCTAssertNotNil(ExtensionItem.parsePublishedAt("2026-09-08T20:29:52Z"))
        XCTAssertNotNil(ExtensionItem.parsePublishedAt("2026-09-08T20:29:52.123Z"))
        XCTAssertNotNil(ExtensionItem.parsePublishedAt("2026-09-08"))
        XCTAssertNotNil(ExtensionItem.parsePublishedAt("  2026-09-08T20:29:52Z  "))

        // A snapshot from before the field existed, or a value that makes no sense, is nil rather
        // than a guess — the row simply says nothing about when it was added.
        XCTAssertNil(ExtensionItem.parsePublishedAt(nil))
        XCTAssertNil(ExtensionItem.parsePublishedAt(""))
        XCTAssertNil(ExtensionItem.parsePublishedAt("last tuesday"))
        XCTAssertNil(ExtensionItem(id: "x", name: "X", description: "", author: "", icon: "",
                                   downloadCount: 0, downloadURL: "").publishedDate)
    }

    @MainActor
    func testRecentlyAddedSortsByTheCatalogueDateNewestFirst() {
        func item(_ id: String, published: String?) -> ExtensionItem {
            ExtensionItem(id: id, name: id, description: "", author: "", icon: "",
                          downloadCount: 0, downloadURL: "", publishedAt: published)
        }
        let old = item("com.x.old", published: "2026-01-02T10:00:00Z")
        let newest = item("com.x.newest", published: "2026-09-08T10:00:00Z")
        let middle = item("com.x.middle", published: "2026-05-05T10:00:00Z")
        let undated = item("com.x.undated", published: nil)

        let sorted = ExtensionsStoreViewModel.sorted([old, undated, newest, middle], by: .recentlyAdded)
        XCTAssertEqual(sorted.map(\.id),
                       ["com.x.newest", "com.x.middle", "com.x.old", "com.x.undated"],
                       "dated newest first, and anything the catalogue did not date goes last")
        XCTAssertEqual(sorted.count, 4, "nothing is dropped for having no date")
    }

    @MainActor
    func testSearchKeepsTheChosenOrder() {
        let api = RecordingStoreAPI()
        let viewModel = ExtensionsStoreViewModel(api: api)
        viewModel.selectedSort = .name

        viewModel.searchQuery = "translate"
        viewModel.queryDidChange()

        XCTAssertEqual(viewModel.selectedSort, .name, "sorting is not a filter, so searching does not undo it")
    }

    /// When the last fetched item belongs to featured/new sections, it does not appear in
    /// remainingAllSectionItems. Pagination must still trigger from the final rendered sectioned item.
    @MainActor
    func testPaginationTriggeredWhenLastFetchedItemNotInRemainingAllSectionItems() async throws {
        let api = GatedStoreAPI()
        let viewModel = ExtensionsStoreViewModel(api: api)

        // Item 1: standard item (lives in remainingAllSectionItems)
        let basic = ExtensionItem(id: "com.openclip.basic-tool", name: "Basic Tool",
                                  description: "", author: "openclip", icon: "", downloadCount: 0, downloadURL: "", version: "1.0.0")
        // Item 2: curated featured item (lives in featuredSectionItems, absent from remainingAllSectionItems)
        let featured = ExtensionItem(id: "com.openclip.quick-translate", name: "Quick Translate",
                                     description: "", author: "openclip", icon: "", downloadCount: 1500, downloadURL: "")

        let initial = Task { await viewModel.resetAndFetch() }
        try await waitUntil { await api.hasPending(query: "", page: 1) }
        await api.release(query: "", page: 1, items: [basic, featured], totalPages: 2)
        await initial.value

        XCTAssertEqual(viewModel.currentPage, 2)
        XCTAssertEqual(viewModel.extensions.last?.id, "com.openclip.quick-translate")
        XCTAssertEqual(viewModel.remainingAllSectionItems.map(\.id), ["com.openclip.basic-tool"])
        XCTAssertEqual(viewModel.featuredSectionItems.map(\.id), ["com.openclip.quick-translate"])

        // The final rendered item in the sectioned view is the last item of remainingAllSectionItems.
        XCTAssertEqual(viewModel.lastRenderedSectionedItemID, "com.openclip.basic-tool")
        XCTAssertTrue(viewModel.shouldTriggerSectionedPagination(for: "com.openclip.basic-tool"))
        XCTAssertFalse(viewModel.shouldTriggerSectionedPagination(for: "com.openclip.quick-translate"))

        // Simulating the onAppear trigger on the last rendered card initiates page 2 fetch.
        let nextPage = Task { await viewModel.fetchNextPage() }
        try await waitUntil { await api.hasPending(query: "", page: 2) }
        let page2Item = ExtensionItem(id: "com.openclip.extra-tool", name: "Extra Tool",
                                      description: "", author: "openclip", icon: "", downloadCount: 10, downloadURL: "")
        await api.release(query: "", page: 2, items: [page2Item], totalPages: 2)
        await nextPage.value

        XCTAssertEqual(viewModel.currentPage, 3)
        XCTAssertEqual(viewModel.extensions.map(\.id), ["com.openclip.basic-tool", "com.openclip.quick-translate", "com.openclip.extra-tool"])

        // Also verify case where remainingAllSectionItems is empty (all items are featured/new):
        let showcaseOnlyVM = ExtensionsStoreViewModel(api: api)
        let renderHtml = ExtensionItem(id: "com.openclip.render-html", name: "Render HTML",
                                       description: "", author: "openclip", icon: "", downloadCount: 100, downloadURL: "", version: "1.1.0")
        let showcaseInitial = Task { await showcaseOnlyVM.resetAndFetch() }
        try await waitUntil { await api.hasPending(query: "", page: 1) }
        await api.release(query: "", page: 1, items: [featured, renderHtml], totalPages: 2)
        await showcaseInitial.value

        XCTAssertTrue(showcaseOnlyVM.remainingAllSectionItems.isEmpty)
        XCTAssertEqual(showcaseOnlyVM.lastRenderedSectionedItemID, "com.openclip.render-html")
        XCTAssertTrue(showcaseOnlyVM.shouldTriggerSectionedPagination(for: "com.openclip.render-html"))
    }

    /// Sorting reorders the catalogue, so the row rendered last is not the item fetched last.
    /// Pagination hangs off the last *rendered* row, or the next page never loads.
    @MainActor
    func testPaginationTriggersOnTheLastRenderedRowNotTheLastFetched() async throws {
        let api = GatedStoreAPI()
        let viewModel = ExtensionsStoreViewModel(api: api)
        viewModel.selectedSort = .downloads

        let quiet = ExtensionItem(id: "com.openclip.quiet", name: "Quiet",
                                  description: "", author: "openclip", icon: "", downloadCount: 10, downloadURL: "")
        let loud = ExtensionItem(id: "com.openclip.loud", name: "Loud",
                                 description: "", author: "openclip", icon: "", downloadCount: 500, downloadURL: "")

        let initial = Task { await viewModel.resetAndFetch() }
        try await waitUntil { await api.hasPending(query: "", page: 1) }
        await api.release(query: "", page: 1, items: [quiet, loud], totalPages: 2)
        await initial.value

        XCTAssertEqual(viewModel.currentPage, 2)
        XCTAssertEqual(viewModel.extensions.last?.id, "com.openclip.loud", "fetched last")
        XCTAssertEqual(viewModel.displayedExtensions.map(\.id),
                       ["com.openclip.loud", "com.openclip.quiet"],
                       "and rendered first, because it has the most downloads")

        XCTAssertTrue(viewModel.shouldTriggerFlatPagination(for: "com.openclip.quiet"))
        XCTAssertFalse(viewModel.shouldTriggerFlatPagination(for: "com.openclip.loud"))

        // Simulating the onAppear trigger on the last rendered card initiates page 2 fetch.
        let nextPage = Task { await viewModel.fetchNextPage() }
        try await waitUntil { await api.hasPending(query: "", page: 2) }
        let page2Item = ExtensionItem(id: "com.openclip.middling", name: "Middling",
                                      description: "", author: "openclip", icon: "", downloadCount: 200, downloadURL: "")
        await api.release(query: "", page: 2, items: [page2Item], totalPages: 2)
        await nextPage.value

        XCTAssertEqual(viewModel.currentPage, 3)
        XCTAssertEqual(viewModel.displayedExtensions.map(\.id),
                       ["com.openclip.loud", "com.openclip.middling", "com.openclip.quiet"],
                       "the new page is ordered in with the rest, not appended blindly")
        XCTAssertTrue(viewModel.shouldTriggerFlatPagination(for: "com.openclip.quiet"))
    }

    /// The Featured section must always return 4 extensions: even before fetching,
    /// When the API response includes `featured` extensions (as provided by the website API),
    /// featuredSectionItems returns all curated featured items directly.
    @MainActor
    func testServerDrivenFeaturedExtensionsPopulatesFeaturedSection() async throws {
        let api = GatedStoreAPI()
        let viewModel = ExtensionsStoreViewModel(api: api)

        let serverFeatured = [
            ExtensionItem(id: "com.openclip.quick-translate", name: "Quick Translate", description: "", author: "openclip", icon: "", downloadCount: 120, downloadURL: ""),
            ExtensionItem(id: "com.openclip.wordcount", name: "Word Count", description: "", author: "openclip", icon: "", downloadCount: 84, downloadURL: ""),
            ExtensionItem(id: "com.openclip.speakselection", name: "Speak Selection", description: "", author: "openclip", icon: "", downloadCount: 74, downloadURL: ""),
            ExtensionItem(id: "com.openclip.obsidiancapture", name: "Obsidian Capture", description: "", author: "openclip", icon: "", downloadCount: 6, downloadURL: "")
        ]

        let fetchTask = Task { await viewModel.resetAndFetch() }
        try await waitUntil { await api.hasPending(query: "", page: 1) }
        let reminderItem = ExtensionItem(id: "com.openclip.applereminders", name: "Apple Reminders",
                                         description: "Live from API", author: "openclip", icon: "", downloadCount: 50, downloadURL: "")
        await api.release(query: "", page: 1, items: [reminderItem], featured: serverFeatured)
        await fetchTask.value

        // Must have all 4 featured items from the server response
        XCTAssertEqual(viewModel.featuredSectionItems.count, 4)
        XCTAssertEqual(viewModel.featuredSectionItems.map(\.id), [
            "com.openclip.quick-translate",
            "com.openclip.wordcount",
            "com.openclip.speakselection",
            "com.openclip.obsidiancapture"
        ])
    }

    /// Server-provided `response.featured` dynamically overrides local fallbacks, allowing
    /// featured extensions to be updated instantly from the website without native app updates.
    @MainActor
    func testServerDrivenFeaturedExtensionsOverridesCatalogAndFallbacks() async throws {
        let api = GatedStoreAPI()
        let viewModel = ExtensionsStoreViewModel(api: api)

        let serverFeatured = [
            ExtensionItem(id: "com.custom.promo-1", name: "Promo 1", description: "", author: "openclip", icon: "", downloadCount: 100, downloadURL: ""),
            ExtensionItem(id: "com.custom.promo-2", name: "Promo 2", description: "", author: "openclip", icon: "", downloadCount: 200, downloadURL: ""),
            ExtensionItem(id: "com.custom.promo-3", name: "Promo 3", description: "", author: "openclip", icon: "", downloadCount: 300, downloadURL: ""),
            ExtensionItem(id: "com.custom.promo-4", name: "Promo 4", description: "", author: "openclip", icon: "", downloadCount: 400, downloadURL: "")
        ]

        let fetchTask = Task { await viewModel.resetAndFetch() }
        try await waitUntil { await api.hasPending(query: "", page: 1) }
        await api.release(query: "", page: 1, items: [], featured: serverFeatured)
        await fetchTask.value

        XCTAssertEqual(viewModel.featuredSectionItems.map(\.id), [
            "com.custom.promo-1",
            "com.custom.promo-2",
            "com.custom.promo-3",
            "com.custom.promo-4"
        ])

        // Query change should preserve featuredSectionItems
        viewModel.searchQuery = "promo"
        viewModel.queryDidChange()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(viewModel.featuredSectionItems.map(\.id), [
            "com.custom.promo-1",
            "com.custom.promo-2",
            "com.custom.promo-3",
            "com.custom.promo-4"
        ])
    }

    /// Server-provided `response.new` dynamically populates the New & Updated showcase section.
    @MainActor
    func testServerDrivenNewExtensionsOverridesCatalog() async throws {
        let api = GatedStoreAPI()
        let viewModel = ExtensionsStoreViewModel(api: api)

        let serverNew = [
            ExtensionItem(id: "com.custom.new-1", name: "New 1", description: "", author: "openclip", icon: "", downloadCount: 10, downloadURL: "", version: "1.2.0"),
            ExtensionItem(id: "com.custom.new-2", name: "New 2", description: "", author: "openclip", icon: "", downloadCount: 20, downloadURL: "", version: "1.1.0")
        ]

        let fetchTask = Task { await viewModel.resetAndFetch() }
        try await waitUntil { await api.hasPending(query: "", page: 1) }
        await api.release(query: "", page: 1, items: [], new: serverNew)
        await fetchTask.value

        XCTAssertEqual(viewModel.newSectionItems.map(\.id), ["com.custom.new-1", "com.custom.new-2"])
    }

    @MainActor
    func testRefreshCatalogInvalidatesCacheAndReloads() async throws {
        let api = RefreshTrackingStoreAPI()
        let viewModel = ExtensionsStoreViewModel(api: api)

        await viewModel.resetAndFetch(limit: 50)
        XCTAssertEqual(viewModel.extensions.count, 1)
        let invalidateCount1 = await api.getInvalidateCount()
        let fetchCount1 = await api.getFetchCount()
        XCTAssertEqual(invalidateCount1, 0)
        XCTAssertEqual(fetchCount1, 1)

        await viewModel.refreshCatalog()
        let invalidateCount2 = await api.getInvalidateCount()
        let fetchCount2 = await api.getFetchCount()
        let lastIgnoreCache = await api.getLastIgnoreCache()
        XCTAssertEqual(invalidateCount2, 1)
        XCTAssertEqual(fetchCount2, 2)
        XCTAssertEqual(lastIgnoreCache, true)
        XCTAssertEqual(viewModel.currentPage, 2)
        XCTAssertFalse(viewModel.isLoading)
    }

    @MainActor
    func testNetworkErrorSurfacesOnFetchFailure() async throws {
        struct FailingAPI: ExtensionStoreFetching {
            func fetchExtensions(query: String, page: Int, limit: Int) async throws -> ExtensionsPageResponse {
                throw NSError(domain: "Network", code: -1009, userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."])
            }
        }

        let viewModel = ExtensionsStoreViewModel(api: FailingAPI())
        await viewModel.resetAndFetch()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.extensions.isEmpty)
        XCTAssertEqual(viewModel.networkError, "The Internet connection appears to be offline.")
    }

    @MainActor
    func testPopularFilterSortsByDownloadsWithoutPrepend() {
        let api = RecordingStoreAPI()
        let viewModel = ExtensionsStoreViewModel(api: api)

        let featuredItem = ExtensionItem(id: "com.openclip.quick-translate", name: "Quick Translate",
                                         description: "", author: "openclip", icon: "", downloadCount: 50, downloadURL: "")
        let topItem = ExtensionItem(id: "com.openclip.top-tool", name: "Top Tool",
                                    description: "", author: "openclip", icon: "", downloadCount: 500, downloadURL: "")
        let mediumItem = ExtensionItem(id: "com.openclip.medium-tool", name: "Medium Tool",
                                       description: "", author: "openclip", icon: "", downloadCount: 150, downloadURL: "")

        viewModel.extensions = [featuredItem, topItem, mediumItem]
        viewModel.featuredItems = [featuredItem]
        viewModel.selectedSort = .downloads

        // Top item with 500 downloads must be first, not the featured item with 50 downloads
        XCTAssertEqual(viewModel.displayedExtensions.map(\.id), [
            "com.openclip.top-tool",
            "com.openclip.medium-tool",
            "com.openclip.quick-translate"
        ])
    }

    @MainActor
    func testIsFeaturedDynamicallyMatchesFeaturedItems() {
        let api = RecordingStoreAPI()
        let viewModel = ExtensionsStoreViewModel(api: api)

        let ext1 = ExtensionItem(id: "com.custom.promo", name: "Promo", description: "", author: "", icon: "", downloadCount: 0, downloadURL: "")
        let ext2 = ExtensionItem(id: "com.other.tool", name: "Tool", description: "", author: "", icon: "", downloadCount: 0, downloadURL: "")

        viewModel.featuredItems = [ext1]
        XCTAssertTrue(viewModel.isFeatured(ext1))
        XCTAssertFalse(viewModel.isFeatured(ext2))
    }

    // MARK: - Helpers

    @MainActor
    private func waitUntil(_ condition: () async -> Bool, timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() > deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

/// Fetcher whose responses park on gates the test releases in a chosen order — the only way
/// to deterministically reproduce out-of-order network resolution. Optionally fulfills one
/// XCTestExpectation per request, in arrival order.
private actor GatedStoreAPI: ExtensionStoreFetching {
    let arrivals: [XCTestExpectation]
    private var pending: [String: CheckedContinuation<ExtensionsPageResponse, Error>] = [:]
    private var arrivalIndex = 0

    init(arrivals: [XCTestExpectation] = []) {
        self.arrivals = arrivals
    }

    func fetchExtensions(query: String, page: Int, limit: Int) async throws -> ExtensionsPageResponse {
        if arrivals.indices.contains(arrivalIndex) {
            arrivals[arrivalIndex].fulfill()
        }
        arrivalIndex += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending["\(query)|\(page)"] = continuation
        }
    }

    func hasPending(query: String, page: Int) -> Bool {
        pending["\(query)|\(page)"] != nil
    }

    func release(query: String, page: Int = 1, items: [ExtensionItem], featured: [ExtensionItem]? = nil, new: [ExtensionItem]? = nil, totalPages: Int = 1) {
        guard let continuation = pending.removeValue(forKey: "\(query)|\(page)") else {
            fatalError("no gated request for '\(query)|\(page)'")
        }
        continuation.resume(returning:
            ExtensionsPageResponse(extensions: items, featured: featured, new: new, page: page, totalPages: totalPages, totalCount: items.count))
    }

    func release(query: String, page: Int = 1, names: [String], totalPages: Int = 1) {
        let items = names.map {
            ExtensionItem(id: $0, name: $0, description: "", author: "", icon: "",
                          downloadCount: 0, downloadURL: "")
        }
        release(query: query, page: page, items: items, totalPages: totalPages)
    }
}

/// Immediate-response fetcher that records which queries were requested.
private actor RecordingStoreAPI: ExtensionStoreFetching {
    private var queries: [String] = []

    func recordedQueries() -> [String] {
        queries
    }

    func fetchExtensions(query: String, page: Int, limit: Int) async throws -> ExtensionsPageResponse {
        queries.append(query)
        let item = ExtensionItem(id: "\(query)-row", name: query, description: "", author: "", icon: "",
                                 downloadCount: 0, downloadURL: "")
        return ExtensionsPageResponse(extensions: [item], page: page, totalPages: 1, totalCount: 1)
    }
}

private actor RefreshTrackingStoreAPI: ExtensionStoreFetching {
    var fetchCount = 0
    var invalidateCount = 0
    var lastIgnoreCache: Bool?

    func getFetchCount() -> Int { fetchCount }
    func getInvalidateCount() -> Int { invalidateCount }
    func getLastIgnoreCache() -> Bool? { lastIgnoreCache }

    func fetchExtensions(query: String, page: Int, limit: Int) async throws -> ExtensionsPageResponse {
        fetchCount += 1
        let item = ExtensionItem(id: "ext-\(fetchCount)", name: "Extension \(fetchCount)", description: "", author: "", icon: "", downloadCount: 0, downloadURL: "")
        return ExtensionsPageResponse(extensions: [item], page: page, totalPages: 1, totalCount: 1)
    }

    func fetchExtensions(query: String, page: Int, limit: Int, ignoreCache: Bool) async throws -> ExtensionsPageResponse {
        lastIgnoreCache = ignoreCache
        return try await fetchExtensions(query: query, page: page, limit: limit)
    }

    func invalidateCache() async {
        invalidateCount += 1
    }
}
