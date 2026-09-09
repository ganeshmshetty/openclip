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
}
