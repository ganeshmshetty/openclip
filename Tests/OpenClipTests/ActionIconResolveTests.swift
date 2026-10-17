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

final class IconifyFetchPolicyTests: XCTestCase {
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

