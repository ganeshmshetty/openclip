import XCTest
@testable import OpenClip
@testable import Core

/// Regression coverage for the edit-actions sheet's appearance save logic: editing only the title
/// must never replace an action's real icon (package file / remote image / text glyph) with the
/// icon picker's placeholder, and legacy overrides written by that old bug heal on the next save.
@MainActor
final class EditActionSheetAppearanceTests: XCTestCase {
    private let localIcon = ActionIcon.local(URL(fileURLWithPath: "/tmp/pkg/icon.svg"))

    // MARK: - resolvedSymbolOverride

    func testTitleOnlyEditDoesNotClobberNonSymbolIcon() {
        // Non-symbol-representable icons leave the field empty ("untouched"); saving must not
        // invent a symbol override.
        XCTAssertNil(EditActionSheet.resolvedSymbolOverride(current: "", initial: "", stored: nil))
    }

    func testUnchangedFieldRoundTripsPreviouslyStoredSymbol() {
        XCTAssertEqual(
            EditActionSheet.resolvedSymbolOverride(current: "heart.fill", initial: "heart.fill", stored: "heart.fill"),
            "heart.fill"
        )
    }

    func testPickedReplacementSymbolWinsOverStoredOne() {
        XCTAssertEqual(
            EditActionSheet.resolvedSymbolOverride(current: "bolt.fill", initial: "heart.fill", stored: "heart.fill"),
            "bolt.fill"
        )
    }

    func testPickedSymbolOnNonSymbolBaselinePersists() {
        XCTAssertEqual(
            EditActionSheet.resolvedSymbolOverride(current: "bolt.fill", initial: "", stored: nil),
            "bolt.fill"
        )
    }

    // MARK: - sanitizedStoredSymbol (legacy clobber healing)

    func testLegacyStarPlaceholderOnNonSymbolIconsIsTreatedAsAbsent() {
        XCTAssertNil(EditActionSheet.sanitizedStoredSymbol("star", actionIcon: localIcon))
        XCTAssertNil(EditActionSheet.sanitizedStoredSymbol("star", actionIcon: .text("⌘C")))
        XCTAssertNil(EditActionSheet.sanitizedStoredSymbol("star", actionIcon: .url(URL(string: "https://example.com/i.png")!)))
    }

    func testGenuineStarPickOnStarIconedActionIsKept() {
        XCTAssertEqual(EditActionSheet.sanitizedStoredSymbol("star", actionIcon: .symbol("star")), "star")
    }

    func testRealCustomizationsAndAbsenceArePreserved() {
        XCTAssertEqual(EditActionSheet.sanitizedStoredSymbol("heart.fill", actionIcon: localIcon), "heart.fill")
        XCTAssertNil(EditActionSheet.sanitizedStoredSymbol(nil, actionIcon: localIcon))
        XCTAssertNil(EditActionSheet.sanitizedStoredSymbol("", actionIcon: localIcon))
    }

    // MARK: - resolvedPreviewIcon (ActionAppearanceFields)

    private func preview(
        displayMode: Int,
        title: String = "",
        iconSymbol: String = "",
        initial: String = "",
        base: ActionIcon? = nil
    ) -> ActionIcon {
        ActionAppearanceFields.resolvedPreviewIcon(
            displayMode: displayMode,
            title: title,
            displayTextFallback: "Native Title",
            iconSymbol: iconSymbol,
            initialIconSymbol: initial,
            baseIcon: base
        )
    }

    func testShowTextModePreviewsEffectiveTitleInsteadOfIcon() {
        XCTAssertEqual(preview(displayMode: 1, title: "  Renamed  ", base: localIcon), .text("Renamed"))
    }

    func testShowTextModeFallsBackToNativeTitleWhenNameFieldEmpty() {
        XCTAssertEqual(preview(displayMode: 1, base: localIcon), .text("Native Title"))
    }

    func testShowIconModeKeepsRealIconUntilReplacementPicked() {
        XCTAssertEqual(preview(displayMode: 0, base: localIcon), localIcon)
        XCTAssertEqual(preview(displayMode: 0, iconSymbol: "bolt.fill", base: localIcon), .symbol("bolt.fill"))
    }

    func testUntouchedSymbolBaselineStillPreviewsRealIcon() {
        XCTAssertEqual(preview(displayMode: 0, iconSymbol: "heart.fill", initial: "heart.fill", base: .text("T")), .text("T"))
    }
}
