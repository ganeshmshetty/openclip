import XCTest
@testable import OpenClip

final class AppFilterTests: XCTestCase {
    func testExcludedApps() {
        XCTAssertTrue(AppFilter.isExcluded(bundleID: "com.adobe.photoshop"))
        XCTAssertTrue(AppFilter.isExcluded(bundleID: "com.adobe.aerendercore"))
        XCTAssertTrue(AppFilter.isExcluded(bundleID: "com.apple.dock"))
        XCTAssertTrue(AppFilter.isExcluded(bundleID: "com.jetbrains.intellij"))
        XCTAssertFalse(AppFilter.isExcluded(bundleID: "com.apple.Safari"))
        XCTAssertFalse(AppFilter.isExcluded(bundleID: "com.google.Chrome"))
    }
}
