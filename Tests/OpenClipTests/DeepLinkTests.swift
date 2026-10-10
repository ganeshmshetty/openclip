import XCTest
@testable import Core
@testable import OpenClip

final class DeepLinkTests: XCTestCase {

    // MARK: - Parsing

    func testParsesInstall() {
        let url = URL(string: "openclip://install?id=com.test.app&name=Test&url=https%3A%2F%2Fopenclip.app%2Ftest.zip")!
        guard case .install(let id, let name, let downloadURL)? = OpenClipDeepLink.parse(url) else {
            return XCTFail("expected an install deep link")
        }
        XCTAssertEqual(id, "com.test.app")
        XCTAssertEqual(name, "Test")
        XCTAssertEqual(downloadURL.absoluteString, "https://openclip.app/test.zip")
    }

    func testParsesCommand() {
        let url = URL(string: "openclip://command/open-settings")!
        guard case .command(let command)? = OpenClipDeepLink.parse(url) else {
            return XCTFail("expected a command deep link")
        }
        XCTAssertEqual(command, .openSettings)
    }

    // MARK: - Rejections

    func testRejectsUnknownHostAndScheme() {
        XCTAssertNil(OpenClipDeepLink.parse(URL(string: "openclip://frobnicate")!))
        XCTAssertNil(OpenClipDeepLink.parse(URL(string: "https://openclip.app/settings")!))
    }

    func testRejectsUnknownCommand() {
        XCTAssertNil(OpenClipDeepLink.parse(URL(string: "openclip://command/self-destruct")!))
    }

    /// The settings read/write routes and the `reset-appearance` command were removed: a URL scheme
    /// is unauthenticated and must not expose or mutate configuration.
    func testRejectsSettingsRoutes() {
        XCTAssertNil(OpenClipDeepLink.parse(URL(string: "openclip://settings")!))
        XCTAssertNil(OpenClipDeepLink.parse(URL(string: "openclip://set?popupTheme=glass")!))
        XCTAssertNil(OpenClipDeepLink.parse(URL(string: "openclip://command/reset-appearance")!))
    }
}
