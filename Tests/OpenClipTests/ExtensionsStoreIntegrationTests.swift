import XCTest
@testable import Core
@testable import OpenClip

final class ExtensionsStoreIntegrationTests: XCTestCase {
    func testEndToEndDeepLinkExtensionInstall() async throws {
        let deepLinkURL = URL(string: "openclip://install?id=com.golden.remote&name=RemoteApp&url=https%3A%2F%2Fexample.com%2Fremote.zip")!
        let params = AppDelegate.parseDeepLinkURL(deepLinkURL)
        
        XCTAssertNotNil(params)
        XCTAssertEqual(params?["id"], "com.golden.remote")
        XCTAssertEqual(params?["name"], "RemoteApp")
        XCTAssertEqual(params?["url"], "https://example.com/remote.zip")
    }

    func testExtensionsAPIClientURLBuilding() {
        let client = ExtensionsAPIClient.shared
        let url = client.buildURL(query: "search", category: "Developer", page: 1, limit: 12)
        XCTAssertNotNil(url)
        XCTAssertTrue(url?.absoluteString.contains("openclip.app") == true)
    }
}
