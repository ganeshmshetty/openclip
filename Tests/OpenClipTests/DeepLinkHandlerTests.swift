import XCTest
@testable import Core
@testable import OpenClip

final class DeepLinkHandlerTests: XCTestCase {
    func testParseOpenClipInstallURL() {
        let url = URL(string: "openclip://install?id=com.test.app&name=TestApp&url=https%3A%2F%2Fopenclip.app%2Ftest.zip")!
        let params = AppDelegate.parseDeepLinkURL(url)
        
        XCTAssertEqual(params?["id"], "com.test.app")
        XCTAssertEqual(params?["name"], "TestApp")
        XCTAssertEqual(params?["url"], "https://openclip.app/test.zip")
    }

    func testInvalidSchemeReturnsNil() {
        let url = URL(string: "https://openclip.app/install?id=com.test.app")!
        XCTAssertNil(AppDelegate.parseDeepLinkURL(url))
    }
}
