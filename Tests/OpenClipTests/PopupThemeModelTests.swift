import XCTest
@testable import OpenClip

/// The resolution rules the Appearance swatches render through. Pure, so the "what does this
/// choice look like" answer is pinned without a live popup.
final class PopupThemeModelTests: XCTestCase {

    func testCategoryMapsStoredValuesIncludingLegacy() {
        XCTAssertEqual(PopupThemeModel.category(fromStored: "glass"), .glass)
        XCTAssertEqual(PopupThemeModel.category(fromStored: "classic"), .classic)
        // Legacy stored colors meant the solid-color (classic) themes were active.
        XCTAssertEqual(PopupThemeModel.category(fromStored: "system"), .classic)
        XCTAssertEqual(PopupThemeModel.category(fromStored: "light"), .classic)
        XCTAssertEqual(PopupThemeModel.category(fromStored: "dark"), .classic)
        XCTAssertEqual(PopupThemeModel.category(fromStored: "nonsense"), .classic)
    }

    func testClassicTokenResolvesSystemAgainstTheSystemScheme() {
        XCTAssertEqual(PopupThemeModel.classicToken(appearance: "system", systemIsDark: true), "dark")
        XCTAssertEqual(PopupThemeModel.classicToken(appearance: "system", systemIsDark: false), "light")
        XCTAssertEqual(PopupThemeModel.classicToken(appearance: "light", systemIsDark: true), "light")
        XCTAssertEqual(PopupThemeModel.classicToken(appearance: "dark", systemIsDark: false), "dark")
    }

    func testEffectiveSchemePinsLightAndDarkAndFollowsSystem() {
        XCTAssertEqual(PopupThemeModel.effectiveScheme(appearance: "light", systemIsDark: true), .light)
        XCTAssertEqual(PopupThemeModel.effectiveScheme(appearance: "dark", systemIsDark: false), .dark)
        XCTAssertEqual(PopupThemeModel.effectiveScheme(appearance: "system", systemIsDark: true), .dark)
        XCTAssertEqual(PopupThemeModel.effectiveScheme(appearance: "system", systemIsDark: false), .light)
    }

    /// The two axes are independent: a theme swatch is previewed in the current color mode, and a
    /// color-mode swatch in the current theme. Glass always resolves to "glass" regardless of the
    /// color mode, while Classic folds the mode in.
    func testGlassIgnoresColorModeButClassicHonorsIt() {
        func swatchTheme(category: PopupThemeModel.Category, appearance: String, systemIsDark: Bool) -> String {
            if category == .glass { return "glass" }
            return PopupThemeModel.classicToken(appearance: appearance, systemIsDark: systemIsDark)
        }
        XCTAssertEqual(swatchTheme(category: .glass, appearance: "light", systemIsDark: false), "glass")
        XCTAssertEqual(swatchTheme(category: .glass, appearance: "dark", systemIsDark: true), "glass")
        XCTAssertEqual(swatchTheme(category: .classic, appearance: "dark", systemIsDark: false), "dark")
        XCTAssertEqual(swatchTheme(category: .classic, appearance: "light", systemIsDark: true), "light")
    }
}
