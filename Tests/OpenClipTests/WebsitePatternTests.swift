import XCTest
@testable import Core

final class WebsitePatternTests: XCTestCase {
    private func url(_ string: String) -> URL {
        URL(string: string)!
    }

    func testHostPatternMatchesHostAndSubdomains() {
        XCTAssertTrue(WebsitePattern.matches(url("https://google.com/maps"), pattern: "google.com"))
        XCTAssertTrue(WebsitePattern.matches(url("https://www.google.com/maps"), pattern: "google.com"))
        XCTAssertTrue(WebsitePattern.matches(url("https://maps.google.com/"), pattern: "google.com"))
        XCTAssertFalse(WebsitePattern.matches(url("https://notgoogle.com/"), pattern: "google.com"))
        XCTAssertFalse(WebsitePattern.matches(url("https://google.com.evil.test/"), pattern: "google.com"))
    }

    func testPathPatternMatchesAtSlashBoundary() {
        XCTAssertTrue(WebsitePattern.matches(url("https://www.google.com/maps"), pattern: "google.com/maps"))
        XCTAssertTrue(WebsitePattern.matches(url("https://www.google.com/maps/@37.7,-122.4,15z"), pattern: "google.com/maps"))
        XCTAssertFalse(WebsitePattern.matches(url("https://www.google.com/mapsomething"), pattern: "google.com/maps"))
        XCTAssertFalse(WebsitePattern.matches(url("https://www.google.com/"), pattern: "google.com/maps"))
    }

    func testWildcardMatchesAnyRun() {
        XCTAssertTrue(WebsitePattern.matches(url("https://www.youtube.com/watch?v=abc"), pattern: "youtube.com/watch*"))
        XCTAssertTrue(WebsitePattern.matches(url("https://mail.google.com/"), pattern: "*.google.com"))
        XCTAssertTrue(WebsitePattern.matches(url("https://a.b.example.com/"), pattern: "example.com"))
        XCTAssertFalse(WebsitePattern.matches(url("https://example.com/"), pattern: "example.org*"))
    }

    func testSchemeWWWCaseQueryAndFragmentAreIgnored() {
        XCTAssertTrue(WebsitePattern.matches(url("https://www.Example.COM/Path?q=1#top"), pattern: "HTTPS://EXAMPLE.com/path"))
        XCTAssertTrue(WebsitePattern.matches(url("http://example.com/"), pattern: "https://www.example.com/"))
        XCTAssertTrue(WebsitePattern.matches(url("https://example.com/foo?x=1"), pattern: "example.com/foo?x=2"))
    }

    func testNonPageURLsAndEmptyPatternsDoNotMatch() {
        XCTAssertFalse(WebsitePattern.matches(url("about:blank"), pattern: "example.com"))
        XCTAssertFalse(WebsitePattern.matches(url("https://example.com/"), pattern: "   "))
        XCTAssertFalse(WebsitePattern.matches(url("https://example.com/"), pattern: "https://"))
    }

    func testSuggestionUsesHostAndFirstPathSegment() {
        XCTAssertEqual(WebsitePattern.suggestion(for: url("https://www.google.com/maps/@37.7,-122.4,15z")), "google.com/maps")
        XCTAssertEqual(WebsitePattern.suggestion(for: url("https://example.com/")), "example.com")
        XCTAssertEqual(WebsitePattern.suggestion(for: url("https://example.com/a/b?x=1")), "example.com/a")
        XCTAssertNil(WebsitePattern.suggestion(for: url("about:blank")))
    }
}
