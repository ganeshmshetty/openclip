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

    // MARK: - Store Filter & Badges

    @MainActor
    func testStoreFilterInitialStateAndDisplayedExtensions() {
        let api = RecordingStoreAPI()
        let viewModel = ExtensionsStoreViewModel(api: api)
        XCTAssertEqual(viewModel.selectedFilter, .all)

        let item1 = ExtensionItem(id: "com.openclip.quick-translate", name: "Quick Translate",
                                  description: "", author: "openclip", icon: "", downloadCount: 1500, downloadURL: "")
        let item2 = ExtensionItem(id: "com.openclip.render-html", name: "Render HTML",
                                  description: "", author: "openclip", icon: "", downloadCount: 100, downloadURL: "", version: "1.1.0")
        let item3 = ExtensionItem(id: "com.openclip.basic-tool", name: "Basic Tool",
                                  description: "", author: "openclip", icon: "", downloadCount: 0, downloadURL: "", version: "1.0.0")

        viewModel.extensions = [item1, item2, item3]

        // All filter returns everything
        viewModel.selectedFilter = .all
        XCTAssertEqual(viewModel.displayedExtensions.map(\.id), ["com.openclip.quick-translate", "com.openclip.render-html", "com.openclip.basic-tool"])

        // Showcase sections in 'All'
        XCTAssertEqual(viewModel.featuredSectionItems.map(\.id), ["com.openclip.quick-translate"])
        XCTAssertEqual(viewModel.newSectionItems.map(\.id), ["com.openclip.render-html"])
        XCTAssertEqual(viewModel.remainingAllSectionItems.map(\.id), ["com.openclip.basic-tool"])

        // Popular filter includes curated item (quick-translate) and popular items
        viewModel.selectedFilter = .popular
        let popularIDs = viewModel.displayedExtensions.map(\.id)
        XCTAssertTrue(popularIDs.contains("com.openclip.quick-translate"))
        XCTAssertFalse(popularIDs.contains("com.openclip.basic-tool"))

        // New filter includes render-html (version 1.1.0 / in recent list)
        viewModel.selectedFilter = .new
        let newIDs = viewModel.displayedExtensions.map(\.id)
        XCTAssertTrue(newIDs.contains("com.openclip.render-html"))
        XCTAssertFalse(newIDs.contains("com.openclip.basic-tool"))
    }

    @MainActor
    func testSearchQueryResetsFilterToAll() {
        let api = RecordingStoreAPI()
        let viewModel = ExtensionsStoreViewModel(api: api)
        viewModel.selectedFilter = .popular

        viewModel.searchQuery = "translate"
        viewModel.queryDidChange()

        XCTAssertEqual(viewModel.selectedFilter, .all, "Non-empty search query should automatically reset filter to .all")
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

    /// When the last fetched item is excluded by the active filter (e.g. .popular), it does not
    /// appear in displayedExtensions. Pagination must trigger from displayedExtensions.last.
    @MainActor
    func testPaginationTriggeredWhenLastFetchedItemExcludedByActiveFilter() async throws {
        let api = GatedStoreAPI()
        let viewModel = ExtensionsStoreViewModel(api: api)
        viewModel.selectedFilter = .popular

        let popularItem = ExtensionItem(id: "com.openclip.custom-popular", name: "Popular",
                                        description: "", author: "openclip", icon: "", downloadCount: 500, downloadURL: "")
        let obscureItem = ExtensionItem(id: "com.openclip.obscure-tool", name: "Obscure",
                                        description: "", author: "openclip", icon: "", downloadCount: 0, downloadURL: "", version: "1.0.0")

        let initial = Task { await viewModel.resetAndFetch() }
        try await waitUntil { await api.hasPending(query: "", page: 1) }
        await api.release(query: "", page: 1, items: [popularItem, obscureItem], totalPages: 2)
        await initial.value

        XCTAssertEqual(viewModel.currentPage, 2)
        // Last fetched item in full extensions array is obscureItem
        XCTAssertEqual(viewModel.extensions.last?.id, "com.openclip.obscure-tool")
        // But displayedExtensions in .popular only includes popularItem
        XCTAssertEqual(viewModel.displayedExtensions.map(\.id), ["com.openclip.custom-popular"])

        // Flat pagination must trigger on the last displayed item, not obscureItem
        XCTAssertTrue(viewModel.shouldTriggerFlatPagination(for: "com.openclip.custom-popular"))
        XCTAssertFalse(viewModel.shouldTriggerFlatPagination(for: "com.openclip.obscure-tool"))

        // Simulating the onAppear trigger on the last rendered card initiates page 2 fetch.
        let nextPage = Task { await viewModel.fetchNextPage() }
        try await waitUntil { await api.hasPending(query: "", page: 2) }
        let page2Item = ExtensionItem(id: "com.openclip.page2-popular", name: "Page 2 Popular",
                                      description: "", author: "openclip", icon: "", downloadCount: 200, downloadURL: "")
        await api.release(query: "", page: 2, items: [page2Item], totalPages: 2)
        await nextPage.value

        XCTAssertEqual(viewModel.currentPage, 3)
        XCTAssertEqual(viewModel.displayedExtensions.map(\.id), ["com.openclip.custom-popular", "com.openclip.page2-popular"])
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

    func release(query: String, page: Int = 1, items: [ExtensionItem], totalPages: Int = 1) {
        guard let continuation = pending.removeValue(forKey: "\(query)|\(page)") else {
            fatalError("no gated request for '\(query)|\(page)'")
        }
        continuation.resume(returning:
            ExtensionsPageResponse(extensions: items, page: page, totalPages: totalPages, totalCount: items.count))
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
