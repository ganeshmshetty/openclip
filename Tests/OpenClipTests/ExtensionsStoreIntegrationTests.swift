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
        XCTAssertEqual(url?.host, "getopenclip.vercel.app")
    }

    func testIconifyURLQueryEncodingAndTimeout() {
        var components = URLComponents(string: "https://api.iconify.design/search")
        let query = "symbol & test=1"
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: "80"),
            URLQueryItem(name: "palette", value: "false")
        ]
        guard let url = components?.url else {
            return XCTFail("Failed to construct URL")
        }
        XCTAssertTrue(url.absoluteString.contains("query=symbol%20%26%20test%3D1"))
        XCTAssertTrue(url.absoluteString.contains("palette=false"))
        
        let request = URLRequest(url: url, timeoutInterval: 10)
        XCTAssertEqual(request.timeoutInterval, 10)
    }

    func testExtensionInstalledActionMatchingLogic() {
        let itemID = "com.example.foo"
        
        let exactMatch = "com.example.foo"
        let subActionMatch = "com.example.foo.action.1"
        let prefixSibling = "com.example.foobar"
        let shorterPrefix = "com.example"
        
        func isMatch(_ actID: String) -> Bool {
            let act = actID.lowercased()
            let item = itemID.lowercased()
            return act == item || act.hasPrefix(item + ".")
        }
        
        XCTAssertTrue(isMatch(exactMatch))
        XCTAssertTrue(isMatch(subActionMatch))
        XCTAssertFalse(isMatch(prefixSibling))
        XCTAssertFalse(isMatch(shorterPrefix))
    }
}

