import XCTest
@testable import OpenClip
@testable import Core

final class AppFilterTests: XCTestCase {
    /// AppFilter is the never-target tier: system chrome, input methods, OpenClip itself, and
    /// conflicting clipboard managers. App categories live in the default `disabled` rule so a
    /// user can re-enable them.
    func testNeverTargetIdentitiesAreExcluded() {
        XCTAssertTrue(AppFilter.isExcluded(bundleID: "com.apple.dock"))
        XCTAssertTrue(AppFilter.isExcluded(bundleID: "com.apple.systemuiserver"))
        XCTAssertTrue(AppFilter.isExcluded(bundleID: "com.apple.CharacterPaletteIM"))
        XCTAssertTrue(AppFilter.isExcluded(bundleID: "com.openclip.app"))
        XCTAssertTrue(AppFilter.isExcluded(bundleID: "com.pilotmoon.popclip"))

        XCTAssertFalse(AppFilter.isExcluded(bundleID: "com.adobe.photoshop"))
        XCTAssertFalse(AppFilter.isExcluded(bundleID: "com.google.android.emulator"))
        XCTAssertFalse(AppFilter.isExcluded(bundleID: "com.parallels.desktop.console"))
        XCTAssertFalse(AppFilter.isExcluded(bundleID: "com.jetbrains.intellij"))
        XCTAssertFalse(AppFilter.isExcluded(bundleID: "com.apple.Safari"))
    }
}
