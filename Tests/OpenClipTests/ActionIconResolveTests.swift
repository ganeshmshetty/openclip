import XCTest
@testable import Core
@testable import OpenClip

final class ActionIconResolveTests: XCTestCase {
    func testResolveNilOrEmptyReturnsDefaultSymbol() {
        XCTAssertEqual(ActionIcon.resolve(from: nil), .symbol(Constants.defaultIconSymbol))
        XCTAssertEqual(ActionIcon.resolve(from: ""), .symbol(Constants.defaultIconSymbol))
        XCTAssertEqual(ActionIcon.resolve(from: "   "), .symbol(Constants.defaultIconSymbol))
    }

    func testResolveSymbolWrapperReturnsSymbol() {
        XCTAssertEqual(ActionIcon.resolve(from: "symbol(scissors)"), .symbol("scissors"))
        XCTAssertEqual(ActionIcon.resolve(from: "symbol(star.fill)"), .symbol("star.fill"))
    }

    func testResolveCustomPrefixReturnsLocalInCustomIconsDirectory() {
        let expected = ActionIcon.local(Constants.customIconsDirectory.appendingPathComponent("my_icon.png"))
        XCTAssertEqual(ActionIcon.resolve(from: "custom:my_icon.png"), expected)
    }

    func testResolveAbsolutePathReturnsLocal() {
        let expected = ActionIcon.local(URL(fileURLWithPath: "/Library/Application Support/OpenClip/icon.svg"))
        XCTAssertEqual(ActionIcon.resolve(from: "/Library/Application Support/OpenClip/icon.svg"), expected)
    }

    func testResolveFileURLReturnsLocal() {
        let expected = ActionIcon.local(URL(fileURLWithPath: "/tmp/test.png"))
        XCTAssertEqual(ActionIcon.resolve(from: "file:///tmp/test.png"), expected)
    }

    func testResolveImageExtensionWithDirectoryURL() {
        let packageDir = URL(fileURLWithPath: "/Users/test/.openclip/extensions/com.test")
        let expected = ActionIcon.local(packageDir.appendingPathComponent("icon.svg"))
        XCTAssertEqual(ActionIcon.resolve(from: "icon.svg", relativeTo: packageDir), expected)
    }

    func testResolveImageExtensionWithoutDirectoryURLDefaultsToCustomIcons() {
        let expected = ActionIcon.local(Constants.customIconsDirectory.appendingPathComponent("badge.png"))
        XCTAssertEqual(ActionIcon.resolve(from: "badge.png"), expected)
    }

    func testResolveWebURLReturnsURL() {
        let url = URL(string: "https://example.com/icon.png")!
        XCTAssertEqual(ActionIcon.resolve(from: "https://example.com/icon.png"), .url(url))
    }

    func testResolveBareNamesAndIconifyReturnSymbol() {
        XCTAssertEqual(ActionIcon.resolve(from: "star"), .symbol("star"))
        XCTAssertEqual(ActionIcon.resolve(from: "lucide:heart"), .symbol("lucide:heart"))
        XCTAssertEqual(ActionIcon.resolve(from: "tabler:search"), .symbol("tabler:search"))
    }

    func testResolveCustomPrefixRejectsPathTraversal() {
        XCTAssertEqual(ActionIcon.resolve(from: "custom:../../etc/passwd"), .symbol(Constants.defaultIconSymbol))
        XCTAssertEqual(ActionIcon.resolve(from: "custom:"), .symbol(Constants.defaultIconSymbol))
        XCTAssertEqual(ActionIcon.resolve(from: "custom:   "), .symbol(Constants.defaultIconSymbol))
        XCTAssertEqual(ActionIcon.resolve(from: "custom:sub/folder/icon.png"), .symbol(Constants.defaultIconSymbol))
    }

    // MARK: - Optical sizing

    /// The symbols the settings sidebar shows, each pinned to the correction that keeps the icon
    /// column even. A regression here is exactly what made the sidebar's glyphs run uneven.
    func testShippedSymbolsAreClassifiedForEvenOpticalSizing() {
        let expected: [String: IconOpticalCategory] = [
            // Built-in actions.
            "sparkles": .thinLine,
            "calendar.badge.plus": .standard,
            "equal.circle": .thinLine,
            "doc.on.doc": .wideAspect,
            "scissors": .wideAspect,
            "character.book.closed": .thinLine,
            "link": .thinLine,
            "doc.on.clipboard": .wideAspect,
            "folder": .wideAspect,
            "magnifyingglass": .thinLine,
            "text.badge.plus": .wideAspect,
            // Settings chrome.
            "slider.horizontal.3": .standard,
        ]
        for (symbol, category) in expected {
            XCTAssertEqual(IconOpticalCategory.classify(symbolName: symbol), category, symbol)
        }
    }

    /// Wide glyphs must shrink and thin ones must grow — growing a wide glyph was the original bug.
    func testWideGlyphsShrinkAndThinGlyphsGrow() {
        XCTAssertLessThan(IconOpticalCategory.wideAspect.opticalMultiplier, 1.0)
        XCTAssertLessThan(IconOpticalCategory.solidOrFilled.opticalMultiplier, 1.0)
        XCTAssertGreaterThan(IconOpticalCategory.thinLine.opticalMultiplier, 1.0)
        XCTAssertEqual(IconOpticalCategory.standard.opticalMultiplier, 1.0)
    }
}

final class ActionTextIconStyleTests: XCTestCase {
    func testTwoCharacterCJKTitlesRenderAsLabels() {
        // #156: 2-character CJK titles used the glyph badge (13.95 pt semibold rounded) while
        // 3+ character titles used the 15 pt regular label, so a group mixed two text sizes.
        XCTAssertTrue(ActionTextIconStyle.isCompactGlyph("AB"))
        XCTAssertTrue(ActionTextIconStyle.isCompactGlyph("#"))
        XCTAssertFalse(ActionTextIconStyle.isCompactGlyph(""))
        XCTAssertFalse(ActionTextIconStyle.isCompactGlyph("翻译"))
        XCTAssertFalse(ActionTextIconStyle.isCompactGlyph("コピ"))
        XCTAssertFalse(ActionTextIconStyle.isCompactGlyph("복사"))
        XCTAssertFalse(ActionTextIconStyle.isCompactGlyph("Copy"))
    }


    func testEmojiStayBadgesButMeasureFullWidth() {
        XCTAssertTrue(ActionTextIconStyle.isCompactGlyph("👍"))
        XCTAssertTrue(ActionTextIconStyle.rendersFullWidth("👍"))
        XCTAssertTrue(ActionTextIconStyle.rendersFullWidth("❤️"))
        XCTAssertFalse(ActionTextIconStyle.rendersFullWidth("a"))
    }
}

final class IconifyFetchPolicyTests: XCTestCase {
    func testOnlyTransientNetworkErrorsAreRetried() {
        XCTAssertTrue(IconifyFetchPolicy.shouldRetry(urlErrorCode: .timedOut))
        XCTAssertTrue(IconifyFetchPolicy.shouldRetry(urlErrorCode: .networkConnectionLost))
        XCTAssertFalse(IconifyFetchPolicy.shouldRetry(urlErrorCode: .notConnectedToInternet))
        XCTAssertFalse(IconifyFetchPolicy.shouldRetry(urlErrorCode: .cancelled))
        XCTAssertFalse(IconifyFetchPolicy.shouldRetry(urlErrorCode: .badURL))
        XCTAssertFalse(IconifyFetchPolicy.shouldRetry(urlErrorCode: nil))
    }

    func testPaletteFlagsReadCollectionsResponse() {
        let json = Data(#"{"mdi":{"palette":false},"logos":{"palette":true},"odd":{"name":"x"}}"#.utf8)
        XCTAssertEqual(IconifyFetchPolicy.paletteFlags(fromCollectionsJSON: json), ["mdi": false, "logos": true])
        XCTAssertEqual(IconifyFetchPolicy.paletteFlags(fromCollectionsJSON: Data("nope".utf8)), [:])
        XCTAssertEqual(IconifyFetchPolicy.collectionsURL(for: ["b", "a"])?.absoluteString,
                       "https://api.iconify.design/collections?prefixes=a,b")
        XCTAssertNil(IconifyFetchPolicy.collectionsURL(for: []))
    }

    func testStatusCodesSplitIntoSuccessRetryAndGiveUp() {
        XCTAssertEqual(IconifyFetchPolicy.outcome(forStatusCode: 200), .success)
        XCTAssertEqual(IconifyFetchPolicy.outcome(forStatusCode: 429), .retry)
        XCTAssertEqual(IconifyFetchPolicy.outcome(forStatusCode: 503), .retry)
        XCTAssertEqual(IconifyFetchPolicy.outcome(forStatusCode: 408), .retry)
        XCTAssertEqual(IconifyFetchPolicy.outcome(forStatusCode: 404), .giveUp)
        XCTAssertEqual(IconifyFetchPolicy.outcome(forStatusCode: 403), .giveUp)
    }

    func testBackoffDoublesAndFirstAttemptDoesNotWait() {
        XCTAssertEqual(IconifyFetchPolicy.backoffNanoseconds(beforeAttempt: 0), 0)
        XCTAssertEqual(IconifyFetchPolicy.backoffNanoseconds(beforeAttempt: 1), 400_000_000)
        XCTAssertEqual(IconifyFetchPolicy.backoffNanoseconds(beforeAttempt: 2), 800_000_000)
    }

    func testFailuresExpireAfterCooldown() {
        let failedAt = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(IconifyFetchPolicy.isCoolingDown(failedAt: failedAt, now: failedAt.addingTimeInterval(5)))
        XCTAssertFalse(IconifyFetchPolicy.isCoolingDown(
            failedAt: failedAt,
            now: failedAt.addingTimeInterval(IconifyFetchPolicy.failureCooldown + 1)
        ))
    }

    func testSVGURLRequiresPrefixAndName() {
        XCTAssertEqual(IconifyFetchPolicy.svgURL(for: "mdi:boat")?.absoluteString, "https://api.iconify.design/mdi/boat.svg")
        XCTAssertNil(IconifyFetchPolicy.svgURL(for: "boat"))
        XCTAssertNil(IconifyFetchPolicy.svgURL(for: ":boat"))
        XCTAssertNil(IconifyFetchPolicy.svgURL(for: "mdi:"))
    }

    func testMulticolorSetsAreFilteredButMonochromeSetsAreKept() {
        XCTAssertTrue(IconifyFetchPolicy.isMulticolor(iconId: "selfhst:chatgpt"))
        XCTAssertTrue(IconifyFetchPolicy.isMulticolor(iconId: "logos:claude"))
        XCTAssertFalse(IconifyFetchPolicy.isMulticolor(iconId: "mdi:boat"))
        XCTAssertFalse(IconifyFetchPolicy.isMulticolor(iconId: "devicon-plain:claude"))
        XCTAssertFalse(IconifyFetchPolicy.isMulticolor(iconId: "selfhst"))
    }
}

final class IconifyPaletteCatalogTests: XCTestCase {
    func testAsksOncePerPrefixAndFallsBackToStaticListOffline() async {
        let calls = LockedCounter()
        let json = Data(#"{"mdi":{"palette":false},"fluent-color":{"palette":true}}"#.utf8)
        let online = IconifyPaletteCatalog(fetch: { _ in calls.increment(); return json })
        let first = await online.multicolorPrefixes(among: ["mdi", "fluent-color"])
        let second = await online.multicolorPrefixes(among: ["mdi", "fluent-color"])
        XCTAssertEqual(first, ["fluent-color"])
        XCTAssertEqual(second, first)
        XCTAssertEqual(calls.value, 1)

        let offline = IconifyPaletteCatalog(fetch: { _ in nil })
        let fallback = await offline.multicolorPrefixes(among: ["logos", "mdi"])
        XCTAssertEqual(fallback, ["logos"])
    }
}

final class IconifySVGLoaderTests: XCTestCase {
    private static let svg = Data(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="10" height="10"/></svg>"#.utf8)

    private static func ok(_ request: URLRequest) -> (Data, URLResponse) {
        (Self.svg, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    func testConcurrentRequestsForOneIconShareOneFetch() async {
        let calls = LockedCounter()
        let loader = IconifySVGLoader(fetch: { request in
            calls.increment()
            try await Task.sleep(nanoseconds: 50_000_000)
            return Self.ok(request)
        })
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 { group.addTask { _ = await loader.image(for: "mdi:boat") } }
        }
        XCTAssertEqual(calls.value, 1)
    }

    func testNeverMoreThanTheCapInFlight() async {
        let running = LockedCounter()
        let loader = IconifySVGLoader(fetch: { request in
            running.increment()
            try await Task.sleep(nanoseconds: 30_000_000)
            running.decrement()
            return Self.ok(request)
        })
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<24 { group.addTask { _ = await loader.image(for: "mdi:icon-\(i)") } }
        }
        XCTAssertLessThanOrEqual(running.peak, IconifyFetchPolicy.maxConcurrentRequests)
        XCTAssertGreaterThan(running.peak, 1)
    }

    func testPermanentFailureIsNotRetriedAndCoolsDown() async {
        let calls = LockedCounter()
        let loader = IconifySVGLoader(fetch: { request in
            calls.increment()
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        })
        let first = await loader.image(for: "mdi:missing")
        let second = await loader.image(for: "mdi:missing")
        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(calls.value, 1)
    }
}

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private var maximum = 0
    private var total = 0

    func increment() { lock.withLock { current += 1; total += 1; maximum = max(maximum, current) } }
    func decrement() { lock.withLock { current -= 1 } }
    var value: Int { lock.withLock { total } }
    var peak: Int { lock.withLock { maximum } }
}
