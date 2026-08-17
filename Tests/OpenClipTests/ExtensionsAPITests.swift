import XCTest
@testable import Core

final class ExtensionsAPITests: XCTestCase {
    func testDecodeExtensionsPageResponse() throws {
        let json = """
        {
          "extensions": [
            {
              "id": "com.test.youtube",
              "name": "YouTube Search",
              "description": "Search YouTube directly",
              "author": "OpenClip",
              "icon": "play.circle",
              "category": "productivity",
              "downloadCount": 1250,
              "downloadURL": "https://openclip.app/packages/youtube.openclipext.zip"
            }
          ],
          "page": 1,
          "totalPages": 3,
          "totalCount": 35
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ExtensionsPageResponse.self, from: json)
        XCTAssertEqual(response.extensions.count, 1)
        XCTAssertEqual(response.extensions.first?.name, "YouTube Search")
        XCTAssertEqual(response.extensions.first?.downloadCount, 1250)
    }

    func testExtensionsAPIClientConstructsURLWithQueryAndPage() {
        let client = ExtensionsAPIClient(baseURL: URL(string: "https://openclip.app/api/v1/extensions")!)
        let url = client.buildURL(query: "search", page: 2, limit: 12)
        
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertEqual(url?.host, "openclip.app")
        XCTAssertTrue(url?.absoluteString.contains("q=search") == true)
        XCTAssertTrue(url?.absoluteString.contains("page=2") == true)
    }
}
