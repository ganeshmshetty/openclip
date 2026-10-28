import XCTest
@testable import Core

final class InlinePreviewTests: XCTestCase {
    func testPlainStringPreviewIsUnchanged() {
        let preview = InlinePreview.resolve(returnedText: "144")

        XCTAssertEqual(preview, InlinePreview(text: "144"))
        XCTAssertEqual(preview.transportText, "144")
        XCTAssertTrue(preview.acceptsActivation)
        XCTAssertEqual(preview.highlightFlags(hovered: true, selected: true).hovered, true)
        XCTAssertEqual(preview.highlightFlags(hovered: true, selected: true).selected, true)
        XCTAssertFalse(preview.highlightFlags(hovered: false, selected: false).hovered)
    }

    func testColorParsesHexForms() {
        XCTAssertEqual(InlinePreviewColor.parse("#abc"), InlinePreviewColor.parse("#AABBCC"))
        XCTAssertEqual(InlinePreviewColor.parse("  #fff ")?.hex, "#FFFFFF")
        XCTAssertEqual(InlinePreviewColor.parse("#3B82F6")?.hex, "#3B82F6")
        XCTAssertEqual(InlinePreviewColor.parse("3B82F6")?.hex, "#3B82F6")
        XCTAssertEqual(InlinePreviewColor.parse("#F008")?.hex, "#FF000088")
        XCTAssertEqual(InlinePreviewColor.parse("#80ff00cc")?.hex, "#80FF00CC")
    }

    func testBadColorAndUnknownToneFallBackToPlainText() {
        let preview = InlinePreview.parse(
            text: "hello",
            color: "not-a-color",
            tone: "info",
            icon: "not a symbol!",
            actionable: nil
        )

        XCTAssertEqual(preview?.text, "hello")
        XCTAssertNil(preview?.color)
        XCTAssertEqual(preview?.tone, .default)
        XCTAssertNil(preview?.icon)
        XCTAssertEqual(preview?.acceptsActivation, true)
    }

    func testInvalidColorsAreRejected() {
        XCTAssertNil(InlinePreviewColor.parse("red"))
        XCTAssertNil(InlinePreviewColor.parse("rgb(255, 0, 0)"))
        XCTAssertNil(InlinePreviewColor.parse("#gg0000"))
        XCTAssertNil(InlinePreviewColor.parse("#12"))
        XCTAssertNil(InlinePreviewColor.parse("#"))
        XCTAssertNil(InlinePreviewColor.parse(""))
        XCTAssertNil(InlinePreviewColor.parse("blue"))
    }

    func testToneNames() {
        XCTAssertEqual(InlinePreviewTone.parse("success"), .success)
        XCTAssertEqual(InlinePreviewTone.parse("ERROR"), .error)
        XCTAssertEqual(InlinePreviewTone.parse(" warning "), .warning)
        XCTAssertEqual(InlinePreviewTone.parse("default"), .default)
        XCTAssertEqual(InlinePreviewTone.parse("green"), .default)
        XCTAssertEqual(InlinePreviewTone.parse("info"), .default)
        XCTAssertEqual(InlinePreviewTone.parse(nil), .default)
        XCTAssertEqual(InlinePreviewTone.parse(""), .default)
    }

    func testIconAcceptsSymbolOrEmoji() {
        XCTAssertEqual(InlinePreviewIcon.parse("paintpalette"), .symbol("paintpalette"))
        XCTAssertEqual(InlinePreviewIcon.parse("symbol:checkmark.circle.fill"), .symbol("checkmark.circle.fill"))
        XCTAssertEqual(InlinePreviewIcon.parse("1.circle"), .symbol("1.circle"))
        XCTAssertEqual(InlinePreviewIcon.parse("🎨"), .emoji("🎨"))
        XCTAssertEqual(InlinePreviewIcon.parse(" ✅ "), .emoji("✅"))
        XCTAssertNil(InlinePreviewIcon.parse("symbol:"))
        XCTAssertNil(InlinePreviewIcon.parse("symbol:bad name"))
        XCTAssertNil(InlinePreviewIcon.parse("not a symbol!"))
        XCTAssertNil(InlinePreviewIcon.parse("hello world"))
        XCTAssertNil(InlinePreviewIcon.parse(""))
        XCTAssertNil(InlinePreviewIcon.parse(nil))
    }

    func testBlankTextIsNotAPreview() {
        XCTAssertNil(InlinePreview.parse(text: nil, color: "#fff", tone: "success", icon: "star", actionable: false))
        XCTAssertNil(InlinePreview.parse(text: " \n\t ", color: "#fff", tone: nil, icon: nil, actionable: false))
    }

    func testViewOnlyPreviewDoesNotActivateOrHighlight() {
        let preview = InlinePreview(text: "12 words", actionable: false)

        XCTAssertFalse(preview.acceptsActivation)
        let flags = preview.highlightFlags(hovered: true, selected: true)
        XCTAssertFalse(flags.hovered)
        XCTAssertFalse(flags.selected)
    }

    func testActionablePreviewKeepsHighlight() {
        let preview = InlinePreview(text: "12 words", actionable: true)

        XCTAssertTrue(preview.acceptsActivation)
        XCTAssertEqual(preview.highlightFlags(hovered: true, selected: false).hovered, true)
        XCTAssertEqual(preview.highlightFlags(hovered: false, selected: true).selected, true)
        XCTAssertFalse(preview.highlightFlags(hovered: true, selected: false).selected)
    }

    func testRichPreviewRoundTripsThroughTransport() throws {
        let original = try XCTUnwrap(InlinePreview.parse(
            text: "#3B82F6",
            color: "#3b82f6",
            tone: "success",
            icon: "paintpalette",
            actionable: false
        ))

        let again = InlinePreview.resolve(returnedText: original.transportText)

        XCTAssertEqual(again, original)
        XCTAssertNotEqual(original.transportText, original.text)
        XCTAssertFalse(again.acceptsActivation)
        XCTAssertFalse(again.highlightFlags(hovered: true, selected: true).selected)
    }

    func testEmojiIconRoundTrips() throws {
        let original = try XCTUnwrap(InlinePreview.parse(
            text: "4 words",
            color: nil,
            tone: "warning",
            icon: "📝",
            actionable: nil
        ))

        XCTAssertEqual(original.icon, .emoji("📝"))
        XCTAssertEqual(original.tone, .warning)
        XCTAssertTrue(original.acceptsActivation)
        XCTAssertEqual(InlinePreview.resolve(returnedText: original.transportText), original)
    }

    func testCorruptTransportFallsBackToPlainText() throws {
        let wire = try XCTUnwrap(InlinePreview.parse(text: "ok", color: nil, tone: "error", icon: nil, actionable: nil)).transportText
        let broken = String(wire.dropLast())

        let preview = InlinePreview.resolve(returnedText: broken)

        XCTAssertEqual(preview.text, broken)
        XCTAssertEqual(preview.tone, .default)
        XCTAssertNil(preview.color)
        XCTAssertNil(preview.icon)
        XCTAssertTrue(preview.acceptsActivation)
    }
}
