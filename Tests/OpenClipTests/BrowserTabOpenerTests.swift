import XCTest
@testable import OpenClip

@MainActor
final class BrowserTabOpenerTests: XCTestCase {
    private final class Calls: @unchecked Sendable {
        var launched: [(URL, String)] = []
        var launchServices: [(URL, String)] = []
        var scripts = 0
    }

    private func opener(private isPrivate: Bool, launchSucceeds: Bool = true, calls: Calls) -> BrowserTabOpener {
        var opener = BrowserTabOpener()
        opener.runAppleScript = { _, _ in calls.scripts += 1; throw NSError(domain: "test", code: 1) }
        opener.openWithApplication = { url, id in calls.launchServices.append((url, id)); return true }
        opener.openDefault = { _ in XCTFail("unexpected default open") }
        opener.isPrivateWindow = { _ in isPrivate }
        opener.launchPrivateWindow = { url, id in calls.launched.append((url, id)); return launchSucceeds }
        return opener
    }

    private let url = URL(string: "https://example.com/?q=a%20b")!

    func testPrivateFirefoxUsesPrivateWindowLaunch() async {
        let calls = Calls()
        await opener(private: true, calls: calls).open(url, inApp: "org.mozilla.firefox")
        XCTAssertEqual(calls.launched.map(\.0), [url])
        XCTAssertEqual(calls.launched.map(\.1), ["org.mozilla.firefox"])
        XCTAssertTrue(calls.launchServices.isEmpty)
        XCTAssertEqual(calls.scripts, 0)
    }

    func testNonPrivateFirefoxKeepsExistingPath() async {
        let calls = Calls()
        await opener(private: false, calls: calls).open(url, inApp: "org.mozilla.firefox")
        XCTAssertTrue(calls.launched.isEmpty)
        XCTAssertEqual(calls.scripts, 1)
        XCTAssertEqual(calls.launchServices.map(\.1), ["org.mozilla.firefox"])
    }

    func testNonFirefoxBrowserIgnoresPrivateCheck() async {
        let calls = Calls()
        await opener(private: true, calls: calls).open(url, inApp: "com.google.Chrome")
        XCTAssertTrue(calls.launched.isEmpty)
        XCTAssertEqual(calls.scripts, 1)
        XCTAssertEqual(calls.launchServices.map(\.1), ["com.google.Chrome"])
    }

    func testPrivateLaunchFailureFallsBack() async {
        let calls = Calls()
        await opener(private: true, launchSucceeds: false, calls: calls).open(url, inApp: "org.mozilla.firefox")
        XCTAssertEqual(calls.launched.count, 1)
        XCTAssertEqual(calls.scripts, 1)
        XCTAssertEqual(calls.launchServices.map(\.1), ["org.mozilla.firefox"])
    }
}
