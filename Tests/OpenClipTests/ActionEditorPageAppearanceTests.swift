import XCTest
@testable import OpenClip
@testable import Core

/// Regression coverage for the edit-actions sheet's appearance save logic: editing only the title
/// must never replace an action's real icon (package file / remote image / text glyph) with the
/// icon picker's placeholder, and legacy overrides written by that old bug heal on the next save.
@MainActor
final class ActionEditorPageAppearanceTests: XCTestCase {
    private let localIcon = ActionIcon.local(URL(fileURLWithPath: "/tmp/pkg/icon.svg"))

    // MARK: - resolvedSymbolOverride

    func testTitleOnlyEditDoesNotClobberNonSymbolIcon() {
        // Non-symbol-representable icons leave the field empty ("untouched"); saving must not
        // invent a symbol override.
        XCTAssertNil(ActionEditorPage.resolvedSymbolOverride(current: "", initial: "", stored: nil))
    }

    func testUnchangedFieldRoundTripsPreviouslyStoredSymbol() {
        XCTAssertEqual(
            ActionEditorPage.resolvedSymbolOverride(current: "heart.fill", initial: "heart.fill", stored: "heart.fill"),
            "heart.fill"
        )
    }

    func testPickedReplacementSymbolWinsOverStoredOne() {
        XCTAssertEqual(
            ActionEditorPage.resolvedSymbolOverride(current: "bolt.fill", initial: "heart.fill", stored: "heart.fill"),
            "bolt.fill"
        )
    }

    func testPickedSymbolOnNonSymbolBaselinePersists() {
        XCTAssertEqual(
            ActionEditorPage.resolvedSymbolOverride(current: "bolt.fill", initial: "", stored: nil),
            "bolt.fill"
        )
    }

    // MARK: - initialDisplayMode

    func testInitialDisplayModeDefaultsToTextForTextGlyphIcons() {
        XCTAssertEqual(ActionEditorPage.initialDisplayMode(override: nil, actionIcon: .text("Copy")), 1)
    }

    func testInitialDisplayModeDefaultsToIconForSymbolIcons() {
        XCTAssertEqual(ActionEditorPage.initialDisplayMode(override: nil, actionIcon: .symbol("star")), 0)
    }

    func testInitialDisplayModeStoredTextOverrideWins() {
        let override = ActionOverride(customIconSymbol: "doc.on.doc", customIconText: "Copy")
        XCTAssertEqual(ActionEditorPage.initialDisplayMode(override: override, actionIcon: .text("Copy")), 1)
    }

    func testInitialDisplayModeStoredSymbolOverrideKeepsIconModeForTextGlyphBuiltins() {
        // Regression: Copy/Cut/Paste saved in Show Icon mode must reopen in Show Icon, not flip
        // back to Show Text just because their own icon is a text glyph.
        let override = ActionOverride(customIconSymbol: "doc.on.doc")
        XCTAssertEqual(ActionEditorPage.initialDisplayMode(override: override, actionIcon: .text("Copy")), 0)
    }

    func testInitialDisplayModeStoredSymbolOverrideKeepsIconModeForSymbolIcons() {
        let override = ActionOverride(customIconSymbol: "heart.fill")
        XCTAssertEqual(ActionEditorPage.initialDisplayMode(override: override, actionIcon: .symbol("star")), 0)
    }

    // MARK: - iconModeFallbackSymbol

    func testIconModeFallbackSymbolForTextGlyphBuiltins() {
        XCTAssertEqual(ActionEditorPage.iconModeFallbackSymbol(for: CopyAction()), "doc.on.doc")
        XCTAssertEqual(ActionEditorPage.iconModeFallbackSymbol(for: CutAction()), "scissors")
        XCTAssertEqual(ActionEditorPage.iconModeFallbackSymbol(for: PasteAction()), "doc.on.clipboard")
        XCTAssertNil(ActionEditorPage.iconModeFallbackSymbol(for: TextGlyphExtensionAction()))
        XCTAssertNil(ActionEditorPage.iconModeFallbackSymbol(for: SearchAction()))
    }

    // MARK: - resolvedIconModeSymbolOverride (Show Icon mode on text-glyph builtins)

    func testShowIconModePersistsBuiltinPreferenceSymbolForTextGlyphBuiltins() {
        // Copy/Cut/Paste carry `.text` icons by default; switching them to Show Icon must persist
        // their hand-written preference symbol so popupIcon stops resolving the text glyph.
        XCTAssertEqual(
            ActionEditorPage.resolvedIconModeSymbolOverride(displayMode: 0, current: "", initial: "", stored: nil, action: CopyAction()),
            "doc.on.doc"
        )
        XCTAssertEqual(
            ActionEditorPage.resolvedIconModeSymbolOverride(displayMode: 0, current: "", initial: "", stored: nil, action: CutAction()),
            "scissors"
        )
        XCTAssertEqual(
            ActionEditorPage.resolvedIconModeSymbolOverride(displayMode: 0, current: "", initial: "", stored: nil, action: PasteAction()),
            "doc.on.clipboard"
        )
    }

    func testShowTextModeDoesNotPersistBuiltinSymbolForTextGlyphBuiltins() {
        XCTAssertNil(
            ActionEditorPage.resolvedIconModeSymbolOverride(displayMode: 1, current: "", initial: "", stored: nil, action: CopyAction())
        )
    }

    func testShowIconModeKeepsStoredSymbolOverBuiltinFallback() {
        XCTAssertEqual(
            ActionEditorPage.resolvedIconModeSymbolOverride(displayMode: 0, current: "heart.fill", initial: "heart.fill", stored: "heart.fill", action: CopyAction()),
            "heart.fill"
        )
    }

    func testShowIconModePickedSymbolWinsOverBuiltinFallback() {
        XCTAssertEqual(
            ActionEditorPage.resolvedIconModeSymbolOverride(displayMode: 0, current: "bolt.fill", initial: "", stored: nil, action: CopyAction()),
            "bolt.fill"
        )
    }

    func testShowIconModeAddsNoOverrideForSymbolIconedBuiltins() {
        XCTAssertNil(
            ActionEditorPage.resolvedIconModeSymbolOverride(displayMode: 0, current: "magnifyingglass", initial: "magnifyingglass", stored: nil, action: SearchAction())
        )
    }

    func testShowIconModeAddsNoOverrideForNonBuiltinTextGlyphActions() {
        // Extension actions derive preferenceIconName from the icon (the glyph text itself is not a
        // symbol), so Show Icon mode must not invent an override for them.
        XCTAssertNil(
            ActionEditorPage.resolvedIconModeSymbolOverride(displayMode: 0, current: "", initial: "", stored: nil, action: TextGlyphExtensionAction())
        )
    }

    // MARK: - sanitizedStoredSymbol (legacy clobber healing)

    func testLegacyStarPlaceholderOnNonSymbolIconsIsTreatedAsAbsent() {
        XCTAssertNil(ActionEditorPage.sanitizedStoredSymbol("star", actionIcon: localIcon))
        XCTAssertNil(ActionEditorPage.sanitizedStoredSymbol("star", actionIcon: .text("⌘C")))
        XCTAssertNil(ActionEditorPage.sanitizedStoredSymbol("star", actionIcon: .url(URL(string: "https://example.com/i.png")!)))
    }

    func testGenuineStarPickOnStarIconedActionIsKept() {
        XCTAssertEqual(ActionEditorPage.sanitizedStoredSymbol("star", actionIcon: .symbol("star")), "star")
    }

    func testRealCustomizationsAndAbsenceArePreserved() {
        XCTAssertEqual(ActionEditorPage.sanitizedStoredSymbol("heart.fill", actionIcon: localIcon), "heart.fill")
        XCTAssertNil(ActionEditorPage.sanitizedStoredSymbol(nil, actionIcon: localIcon))
        XCTAssertNil(ActionEditorPage.sanitizedStoredSymbol("", actionIcon: localIcon))
    }

    // MARK: - resolvedPreviewIcon (ActionAppearanceFields)

    private func preview(
        displayMode: Int,
        title: String = "",
        iconSymbol: String = "",
        initial: String = "",
        base: ActionIcon? = nil,
        textGlyphFallbackSymbol: String? = nil
    ) -> ActionIcon {
        ActionAppearanceFields.resolvedPreviewIcon(
            displayMode: displayMode,
            title: title,
            displayTextFallback: "Native Title",
            iconSymbol: iconSymbol,
            initialIconSymbol: initial,
            baseIcon: base,
            textGlyphFallbackSymbol: textGlyphFallbackSymbol
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

    func testShowIconModePreviewsBuiltinFallbackSymbolForTextGlyphIcons() {
        XCTAssertEqual(
            preview(displayMode: 0, base: .text("Copy"), textGlyphFallbackSymbol: "doc.on.doc"),
            .symbol("doc.on.doc")
        )
    }

    func testShowIconModeKeepsTextGlyphWithoutFallbackSymbol() {
        XCTAssertEqual(preview(displayMode: 0, base: .text("T")), .text("T"))
    }

    func testShowIconModeFallbackDoesNotOverwritePickedSymbol() {
        XCTAssertEqual(
            preview(displayMode: 0, iconSymbol: "bolt.fill", base: .text("Copy"), textGlyphFallbackSymbol: "doc.on.doc"),
            .symbol("bolt.fill")
        )
    }

    func testShowTextModeIgnoresFallbackSymbol() {
        XCTAssertEqual(
            preview(displayMode: 1, title: "Copy", base: .text("Copy"), textGlyphFallbackSymbol: "doc.on.doc"),
            .text("Copy")
        )
    }
}

private struct TextGlyphExtensionAction: ConfigurableAction {
    let id = "com.example.textglyph"
    let title = "Text Glyph"
    let icon: ActionIcon = .text("T")
    let chrome: ActionChrome = ActionChrome(
        badge: .script,
        rowStyle: .standard,
        popupBehavior: .perform,
        source: .extensionPkg(packageID: "com.example.textglyph")
    )

    func isEnabled(for context: ActionContext) -> Bool { true }
    func perform(_ context: ActionContext) async throws -> ActionResult { .none }
}
