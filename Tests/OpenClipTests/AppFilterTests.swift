import XCTest
@testable import OpenClip
@testable import Core

final class AppFilterTests: XCTestCase {
    func testExcludedApps() {
        XCTAssertTrue(AppFilter.isExcluded(bundleID: "com.adobe.photoshop"))
        XCTAssertTrue(AppFilter.isExcluded(bundleID: "com.adobe.aerendercore"))
        XCTAssertTrue(AppFilter.isExcluded(bundleID: "com.apple.dock"))
        XCTAssertFalse(AppFilter.isExcluded(bundleID: "com.jetbrains.intellij"))
        XCTAssertFalse(AppFilter.isExcluded(bundleID: "org.vim.MacVim"))
        XCTAssertFalse(AppFilter.isExcluded(bundleID: "com.apple.Safari"))
        XCTAssertFalse(AppFilter.isExcluded(bundleID: "com.google.Chrome"))
    }
}
