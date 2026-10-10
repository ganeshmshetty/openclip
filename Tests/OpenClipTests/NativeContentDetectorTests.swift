import XCTest
@testable import Core

final class NativeContentDetectorTests: XCTestCase {
    func testURLsAreCollectedThroughoutTextInOccurrenceOrder() {
        let text = "😀 Read https://example.com/docs, then www.github.com; repeat https://example.com/docs."
        XCTAssertEqual(NativeContentDetector.detect(text, type: .url).urls,
                       ["https://example.com/docs", "https://www.github.com", "https://example.com/docs"])
    }

    func testURLsBeyondFormerScanLimitAreIncluded() {
        let text = String(repeating: "words ", count: 800) + "https://example.com/end"
        XCTAssertEqual(NativeContentDetector.urls(in: text).map(\.absoluteString), ["https://example.com/end"])
    }

    func testLocalEndpointsAndOverlappingDetectors() {
        let text = "Visit localhost:3000/api and 192.168.1.1:8080/docs then https://example.com."
        XCTAssertEqual(NativeContentDetector.urls(in: text).map(\.absoluteString),
                       ["http://localhost:3000/api", "http://192.168.1.1:8080/docs", "https://example.com"])
        XCTAssertEqual(NativeContentDetector.urls(in: "localhost").map(\.absoluteString), ["http://localhost"])
    }

    func testBareDomainsPunctuationAndAllowedSchemes() {
        XCTAssertEqual(NativeContentDetector.urls(in: "Read <https://example.com/a(b)> and github.com/docs.").map(\.absoluteString),
                       ["https://example.com/a(b)", "https://github.com/docs"])
        XCTAssertTrue(NativeContentDetector.urls(in: "mailto:user@example.com ftp://example.com file:///tmp/a tel:12345").isEmpty)
    }

    func testEmailsDoNotBecomeWebURLs() {
        let cache = ContentDetectionCache(text: "Contact first@example.com and second@example.org; see https://example.com.")
        XCTAssertEqual(cache.detect([.email]).emails, ["first@example.com", "second@example.org"])
        XCTAssertTrue(cache.detect([.email]).urls.isEmpty)
        XCTAssertEqual(cache.detect([.url]).urls, ["https://example.com"])
        XCTAssertTrue(cache.detect([.url]).emails.isEmpty)
    }

    func testPhonesAndAddressesAreDetectedInProse() {
        let phones = NativeContentDetector.detect("Call +1 415-555-2671 or +1 650-555-0100 today.", type: .phone).phones
        XCTAssertEqual(phones.count, 2)
        guard phones.count == 2 else { return }
        XCTAssertTrue(phones[0].contains("415"))
        XCTAssertTrue(phones[1].contains("650"))
        let addresses = NativeContentDetector.detect("Meet at 1 Infinite Loop, Cupertino, CA 95014 tomorrow.", type: .address).addresses
        XCTAssertEqual(addresses.count, 1)
        guard addresses.count == 1 else { return }
        XCTAssertTrue(addresses[0].text.contains("Infinite Loop"))
        XCTAssertEqual(addresses[0].components["city"], "Cupertino")
    }

    func testMultipleDatesHaveStructuredNativeValues() {
        let dates = NativeContentDetector.detect("Meet on December 12, 2030 at 10am, then December 15, 2030 at 2pm.", type: .date).dates
        XCTAssertEqual(dates.count, 2)
        guard dates.count == 2 else { return }
        XCTAssertLessThan(dates[0].date, dates[1].date)
        XCTAssertTrue(dates[0].text.contains("December 12"))
    }

    func testPathsIncludeQuotedSpacesTildeAndFileURLsWithoutFilesystemProbes() {
        let text = #"Read \"/tmp/first file.txt\" then ~/second.txt and file:///tmp/third%20file.txt."#
            .replacingOccurrences(of: #"\""#, with: "\"")
        XCTAssertEqual(NativeContentDetector.paths(in: text),
                       ["/tmp/first file.txt", ("~/second.txt" as NSString).expandingTildeInPath, "/tmp/third file.txt"])
        XCTAssertEqual(NativeContentDetector.paths(in: "Error in /tmp/source.swift:12:3 and /tmp/other.swift:5"),
                       ["/tmp/source.swift", "/tmp/other.swift"])
        XCTAssertEqual(NativeContentDetector.paths(in: #"Open /tmp/escaped\ file.txt then /tmp/plain"#),
                       ["/tmp/escaped file.txt", "/tmp/plain"])
        XCTAssertTrue(NativeContentDetector.paths(in: "https://example.com/path ordinary text").isEmpty)
    }

    func testEmptyInputAndCacheReuseAcrossSelectionCopies() {
        let empty = ContentDetectionCache(text: "").detect(ContentType.allCases)
        XCTAssertTrue(ContentType.allCases.allSatisfy { !empty.hasItems($0) })
        let selection = SelectionContext(text: "Tomorrow at 10am", cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let detected = selection.detectedContent(for: [.date])
        XCTAssertFalse(detected.dates.isEmpty)
        XCTAssertEqual(selection.with(cursorPosition: CGPoint(x: 10, y: 20)).detectedContent(for: [.date]), detected)
        XCTAssertEqual(selection.with(isEditable: true).detectedContent(for: [.date]), detected)
    }
}
