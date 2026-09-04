import XCTest
@testable import Core
@testable import OpenClip

/// Covers the curated search-engine presets powering the Search action's preset picker: catalog
/// invariants, exact-match resolution, custom fallback, and the single source of truth for the
/// default template.
final class SearchEnginePresetTests: XCTestCase {

    func testAllPresetsAreWellFormedAndUnique() {
        let ids = SearchEnginePreset.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Preset ids must be unique")

        for preset in SearchEnginePreset.all {
            XCTAssertFalse(preset.displayName.isEmpty, "\(preset.id) must have a display name")
            XCTAssertTrue(preset.urlTemplate.hasPrefix("https://"), "\(preset.id) must be an https template")
            XCTAssertTrue(preset.urlTemplate.contains("{query}"), "\(preset.id) template must contain {query}")
        }
    }

    /// The issue-suggested preset catalog, in order. Asserts on stable ids (display names are
    /// localized and may vary with the test host's locale).
    func testCatalogMatchesRequestedPresets() {
        let ids = SearchEnginePreset.all.map(\.id)
        XCTAssertEqual(ids, ["google", "duckduckgo", "kagi", "brave", "bing", "ecosia", "baidu", "yahoojapan"])
        let templates = SearchEnginePreset.all.map(\.urlTemplate)
        XCTAssertEqual(templates, [
            "https://www.google.com/search?q={query}",
            "https://duckduckgo.com/?q={query}",
            "https://kagi.com/search?q={query}",
            "https://search.brave.com/search?q={query}",
            "https://www.bing.com/search?q={query}",
            "https://www.ecosia.org/search?q={query}",
            "https://www.baidu.com/s?wd={query}",
            "https://search.yahoo.co.jp/search?p={query}"
        ])
    }

    func testPresetMatchingReturnsPresetForExactTemplate() {
        for preset in SearchEnginePreset.all {
            XCTAssertEqual(SearchEnginePreset.preset(matching: preset.urlTemplate), preset)
        }
    }

    func testPresetMatchingReturnsNilForCustomTemplate() {
        // Self-hosted / internal endpoints and empty values never match a preset.
        XCTAssertNil(SearchEnginePreset.preset(matching: "https://search.mysite.dev/search?q={query}"))
        XCTAssertNil(SearchEnginePreset.preset(matching: ""))
    }

    func testPresetMatchingIsExactAndDoesNotSnapBackHandEditedVariants() {
        // A user's tweaked variant must stay Custom, not silently reset to the preset.
        XCTAssertNil(SearchEnginePreset.preset(matching: "https://www.google.com/search?q={query}&hl=en"))
        XCTAssertNil(SearchEnginePreset.preset(matching: "https://www.bing.com/search?q={query}&cc=us"))
        XCTAssertNil(SearchEnginePreset.preset(matching: "https://duckduckgo.com/?q={query}&ia=web"))
    }

    func testPresetLookupByStableID() {
        // Stable id and template are locale-independent; display names are localized.
        XCTAssertEqual(SearchEnginePreset.preset(id: "google")?.id, "google")
        XCTAssertEqual(SearchEnginePreset.preset(id: "kagi")?.urlTemplate, "https://kagi.com/search?q={query}")
        XCTAssertEqual(SearchEnginePreset.preset(id: "bing")?.displayName, String(localized: "Bing"))
        XCTAssertNil(SearchEnginePreset.preset(id: "nonexistent"))
    }

    func testDefaultTemplateIsGoogle() {
        XCTAssertEqual(SearchEnginePreset.defaultURLTemplate, SearchEnginePreset.google.urlTemplate)
        XCTAssertEqual(SearchEnginePreset.defaultURLTemplate, "https://www.google.com/search?q={query}")
    }

    @MainActor
    func testSearchActionDefaultUsesPresetTemplate() {
        let action = SearchAction()
        let urlOption = action.actionOptions.first { $0.identifier == "url" }
        XCTAssertEqual(urlOption?.defaultValue, SearchEnginePreset.defaultURLTemplate)
    }
}
