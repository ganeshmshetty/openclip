import XCTest
import AppKit
@testable import Core
@testable import OpenClip

@MainActor
final class TypedInlineResultsTests: XCTestCase {

    // MARK: - Value validation

    func testColorParsingCanonicalizesShorthandAndAlpha() {
        let short = InlineColor(hex: "#f80")
        XCTAssertEqual(short?.hex, "#FF8800")
        XCTAssertEqual(short?.alpha, 1.0)
        XCTAssertEqual(short?.red ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(short?.green ?? 0, 136.0 / 255.0, accuracy: 0.001)

        XCTAssertEqual(InlineColor(hex: "#FFF")?.hex, "#FFFFFF")
        XCTAssertEqual(InlineColor(hex: "#fff8")?.hex, "#FFFFFF88")
        XCTAssertEqual(InlineColor(hex: "#FF880080")?.hex, "#FF880080")
        XCTAssertEqual(InlineColor(hex: "#ff8800")?.hex, "#FF8800")
    }

    func testColorParsingRejectsUnsupportedSyntax() {
        XCTAssertNil(InlineColor(hex: "red"))
        XCTAssertNil(InlineColor(hex: "rgb(255, 0, 0)"))
        XCTAssertNil(InlineColor(hex: "linear-gradient(red, blue)"))
        XCTAssertNil(InlineColor(hex: "#GGG"))
        XCTAssertNil(InlineColor(hex: "#12345"))
        XCTAssertNil(InlineColor(hex: "FF8800"))
    }

    func testEmojiGlyphsAreOrdinaryText() {
        let value = InlineResultValue.makeText("🎉")
        XCTAssertEqual(value, .text("🎉"))
        XCTAssertEqual(value?.rawValue, "🎉")
        XCTAssertEqual(value?.displayText, "🎉")
        XCTAssertEqual(InlineResultValue.makeText("👨‍👩‍👧‍👦")?.rawValue, "👨‍👩‍👧‍👦")
    }

    func testTextPreservesValueButCollapsesDisplayLineBreaks() {
        let value = InlineResultValue.makeText("First\r\nSecond\tThird")
        XCTAssertEqual(value, .text("First\r\nSecond\tThird"))
        XCTAssertEqual(value?.rawValue, "First\r\nSecond\tThird")
        XCTAssertEqual(value?.displayText, "First Second Third")
    }

    func testBlankTextIsNotAnInlineResult() {
        XCTAssertNil(InlineResultValue.makeText(""))
        XCTAssertNil(InlineResultValue.makeText(" \t\n"))
    }

    func testTextBoundsDifferForDisplayOnlyValues() {
        XCTAssertNotNil(InlineResultValue.makeText(String(repeating: "a", count: 300)))
        XCTAssertNil(InlineResultValue.makeText(String(repeating: "a", count: 300), displayOnly: true))

        XCTAssertNil(InlineResultValue.makeText(String(repeating: "a", count: (64 * 1024) + 1)))
        XCTAssertNil(InlineResultValue.makeText(String(repeating: "a", count: (4 * 1024) + 1), displayOnly: true))
    }

    // MARK: - Manifest and output contract

    func testFileOutputRejectsLegacyInlineStrings() {
        XCTAssertNil(InlineResultValue.makeLegacyString("/tmp/file", for: .file, displayOnly: false))
        XCTAssertEqual(InlineResultValue.makeLegacyString("hello", for: .text, displayOnly: false), .text("hello"))
    }

    func testOutputContractSupportsTextAndColor() {
        XCTAssertTrue(ExtensionOutputContract.isCompatible(output: .text, result: .paste))
        XCTAssertTrue(ExtensionOutputContract.isCompatible(output: .text, result: .copy))
        XCTAssertTrue(ExtensionOutputContract.isCompatible(output: .color, result: .preview))
        XCTAssertFalse(ExtensionOutputContract.isCompatible(output: .color, result: .paste))
        XCTAssertFalse(ExtensionOutputContract.isCompatible(output: .color, result: .copy))
        XCTAssertEqual(ExtensionOutputContract.defaultResult(for: .text), .pasteOrCopy)
        XCTAssertEqual(ExtensionOutputContract.defaultResult(for: .color), .preview)
    }

    func testInlineDeclarationPreservesTypedOutputsButStillDefaultsToText() {
        let legacy = ExtensionOutputContract.resolveEffective(declaredOutput: nil, declaredResult: nil, inline: true)
        XCTAssertEqual(legacy.output, .text)

        let color = ExtensionOutputContract.resolveEffective(declaredOutput: .color, declaredResult: .paste, inline: true)
        XCTAssertEqual(color.output, .color)
        XCTAssertEqual(color.result, .preview)
        XCTAssertTrue(color.hadIncompatiblePair)
    }

    func testManifestDecodesDisplayOnlyAndTypedOutput() throws {
        let json = """
        {
            "identifier": "com.test.typed",
            "name": "Typed",
            "minOpenClipVersion": "1.10.0",
            "actions": [
                {
                    "id": "color",
                    "title": "Color",
                    "type": "js",
                    "scriptCode": "return null",
                    "inline": true,
                    "output": "color",
                    "result": "preview"
                },
                {
                    "id": "info",
                    "title": "Info",
                    "type": "js",
                    "scriptCode": "return null",
                    "inline": true,
                    "displayOnly": true
                }
            ]
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(ExtensionMetadata.self, from: json)
        XCTAssertEqual(manifest.actions[0].output, .color)
        XCTAssertEqual(manifest.actions[1].displayOnly, true)
        XCTAssertTrue(ManifestValidator.validate(manifest).isEmpty)
    }

    func testDisplayOnlyRequiresInlineAndMinimumVersion() {
        let invalid = ExtensionMetadata(
            identifier: "com.test.invalid",
            name: "Invalid",
            actions: [ExtensionActionMetadata(
                id: "info",
                title: "Info",
                type: "js",
                scriptCode: "return null",
                displayOnly: true
            )]
        )
        let issues = ManifestValidator.validate(invalid)
        XCTAssertTrue(issues.contains { $0.description.contains("displayOnly") })

        let oldApp = ExtensionMetadata(
            identifier: "com.test.old",
            name: "Old",
            actions: [ExtensionActionMetadata(
                id: "info",
                title: "Info",
                type: "js",
                scriptCode: "return null",
                inline: true,
                displayOnly: true
            )],
            minOpenClipVersion: "1.9.0"
        )
        XCTAssertTrue(ManifestValidator.validate(oldApp).contains {
            $0.description.contains("requires `minOpenClipVersion`")
        })
    }

    func testActionChromeRoundTripsDisplayOnly() throws {
        let chrome = ActionChrome(isInlineResult: true, displayOnly: true, outputKind: .color)
        let data = try JSONEncoder().encode(chrome)
        let decoded = try JSONDecoder().decode(ActionChrome.self, from: data)
        XCTAssertTrue(decoded.displayOnly)
        XCTAssertEqual(decoded.outputKind, .color)
    }

    // MARK: - Delivery

    func testTextUsesExistingDeliveryMatrix() {
        func resolve(_ kind: ExtensionOutputKind, _ intent: ActionResultDelivery.ClickIntent) -> ActionResult {
            ActionResultDelivery.resolve(
                raw: .text("value"),
                clickIntent: intent,
                canPaste: true,
                recommendedResult: .pasteOrCopy,
                outputKind: kind
            ).result
        }

        for kind in [ExtensionOutputKind.text] {
            guard case .paste(let primary) = resolve(kind, .primary) else {
                return XCTFail("primary must paste for \(kind)")
            }
            XCTAssertEqual(primary, "value")
            guard case .copy(let secondary) = resolve(kind, .secondary) else {
                return XCTFail("secondary must copy for \(kind)")
            }
            XCTAssertEqual(secondary, "value")
        }
    }

    func testColorNeverEntersCopyOrPasteDelivery() {
        let color = InlineColor(hex: "#FF8800")!
        for intent in [ActionResultDelivery.ClickIntent.primary, .secondary] {
            let resolved = ActionResultDelivery.resolve(
                raw: .color(color),
                clickIntent: intent,
                canPaste: true,
                preference: .copy,
                recommendedResult: .paste,
                outputKind: .color
            ).result
            guard case .color(let resolvedColor) = resolved else {
                return XCTFail("color must stay typed on \(intent)")
            }
            XCTAssertEqual(resolvedColor, color)
        }
    }

    // MARK: - Display-only policy

    private struct DisplayOnlyAction: Action {
        let id = "test.display-only"
        let title = "Information"
        let icon = ActionIcon.symbol("info.circle")
        let chrome = ActionChrome(isInlineResult: true, displayOnly: true, outputKind: .text)
        func isEnabled(for context: ActionContext) -> Bool { true }
        func perform(_ context: ActionContext) async throws -> ActionResult { .text("never") }
    }

    func testDisplayOnlyActionsAreNotBindable() {
        XCTAssertFalse(ActionIdentity.isBindable(DisplayOnlyAction()))
    }

    func testDisplayOnlyRowsHaveNoCommandDigitHint() {
        XCTAssertNil(PopupSearchView.shortcutHint(forRow: 0, action: DisplayOnlyAction()))

        struct NormalAction: Action {
            let id = "test.normal"
            let title = "Normal"
            let icon = ActionIcon.symbol("doc")
            let chrome = ActionChrome(isInlineResult: true, outputKind: .text)
            func isEnabled(for context: ActionContext) -> Bool { true }
            func perform(_ context: ActionContext) async throws -> ActionResult { .text("x") }
        }
        XCTAssertEqual(PopupSearchView.shortcutHint(forRow: 0, action: NormalAction()), "⌘1")
    }

    func testDisplayOnlyInvocationReturnsNothing() async {
        let evaluator = InlineResultEvaluator()
        let context = ActionContext(selection: SelectionContext(text: "input"))
        let result = await evaluator.invoke(
            action: DisplayOnlyAction(),
            context: context,
            sessionID: UUID()
        )
        XCTAssertNil(result)
    }

    func testColorInlineValueKeepsTypedResult() {
        let color = InlineColor(hex: "#123456")!
        let value = InlineResultValue.color(color)
        guard case .color(let result) = value.inlineActionResult else {
            return XCTFail("color must keep its typed result")
        }
        XCTAssertEqual(result, color)
    }

    func testEmojiGlyphAsTextPastesAndCopiesVerbatim() {
        let primary = ActionResultDelivery.resolve(
            raw: .text("🎉"),
            clickIntent: .primary,
            canPaste: true,
            recommendedResult: .pasteOrCopy,
            outputKind: .text
        ).result
        guard case .paste(let pasted) = primary else {
            return XCTFail("primary text must paste")
        }
        XCTAssertEqual(pasted, "🎉")

        let secondary = ActionResultDelivery.resolve(
            raw: .text("🎉"),
            clickIntent: .secondary,
            canPaste: true,
            recommendedResult: .pasteOrCopy,
            outputKind: .text
        ).result
        guard case .copy(let copied) = secondary else {
            return XCTFail("secondary text must copy")
        }
        XCTAssertEqual(copied, "🎉")
    }

    func testColorExportWritesCanonicalHexText() throws {
        let color = InlineColor(hex: "#ff8800")!
        let url = try XCTUnwrap(InlineColorExport.writeText(color))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "#FF8800\n")
        InlineColorExport.removeStagedFile(url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testInvocationDoesNotJoinAnOlderSelectionsEvaluation() async {
        final class EchoInlineAction: Action, @unchecked Sendable {
            let id = "test.echo"
            let title = "Echo"
            let icon = ActionIcon.symbol("text.alignleft")
            let chrome = ActionChrome(isInlineResult: true, outputKind: .text)

            @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
            @MainActor func perform(_ context: ActionContext) async throws -> ActionResult {
                if context.selection.text == "old" {
                    try await Task.sleep(nanoseconds: 80_000_000)
                }
                return .text(context.selection.text)
            }
        }

        let evaluator = InlineResultEvaluator()
        let session = UUID()
        let action = EchoInlineAction()
        evaluator.startEvaluation(
            action: action,
            context: ActionContext(selection: SelectionContext(text: "old")),
            sessionID: session
        ) { _ in }

        let newer = await evaluator.invoke(
            action: action,
            context: ActionContext(selection: SelectionContext(text: "new")),
            sessionID: session
        )
        XCTAssertEqual(newer, .text("new"), "A newer selection must never receive the older evaluation's value")
    }

    func testCacheIdentityIncludesExposedMarkup() async {
        let evaluator = InlineResultEvaluator()
        let action = makeAction(
            id: "test.markup",
            script: "function action() { return openclip.input.html; }",
            output: .text
        )
        let first = await evaluator.evaluateAsync(
            action: action,
            context: ActionContext(selection: SelectionContext(text: "same", html: "<b>one</b>")),
            timeout: 1.0
        )
        let second = await evaluator.evaluateAsync(
            action: action,
            context: ActionContext(selection: SelectionContext(text: "same", html: "<b>two</b>")),
            timeout: 1.0
        )
        XCTAssertEqual(first, .text("<b>one</b>"))
        XCTAssertEqual(second, .text("<b>two</b>"), "same text with different markup must not reuse the cached value")
    }

    func testInheritedColorOutputWarnsForInlineCopyResult() {
        let manifest = ExtensionMetadata(
            identifier: "com.test.inherit",
            name: "Inherit",
            actions: [ExtensionActionMetadata(
                id: "brand",
                title: "Brand",
                type: "js",
                scriptCode: "return '#f80'",
                inline: true,
                result: .copy
            )],
            output: .color
        )
        XCTAssertTrue(ManifestValidator.validateWarnings(manifest).contains {
            $0.kind == .incompatibleOutputResult(output: .color, result: .copy)
        })
    }

    func testColorCardSwatchScalesWithAvailableBody() {
        let small = ResultCardView.colorSwatchSize(for: CGSize(width: 188, height: 110))
        let large = ResultCardView.colorSwatchSize(for: CGSize(width: 288, height: 170))
        XCTAssertEqual(small, 60, accuracy: 0.001)
        XCTAssertEqual(large, 120, accuracy: 0.001)
        XCTAssertGreaterThan(large, small)
        XCTAssertEqual(ResultCardView.colorSwatchSize(for: CGSize(width: 188, height: 60)), 40)
    }

    func testTypedInlineWidthsAreMeasuredAndBounded() {
        struct InlineStubAction: Action {
            let id: String
            let title = "Inline"
            let icon = ActionIcon.symbol("bolt")
            let chrome = ActionChrome(isInlineResult: true)
            func isEnabled(for context: ActionContext) -> Bool { true }
            func perform(_ context: ActionContext) async throws -> ActionResult { .none }
        }

        let action = InlineStubAction(id: "test.width")
        let color = InlineResultValue.color(InlineColor(hex: "#FF8800")!)
        XCTAssertEqual(
            InlineResultLayout.width(for: color, surface: .bar, scale: 1),
            InlineResultLayout.Surface.bar.swatchSize,
            "Inline color is swatch-only; the hex lives in the card and accessibility value"
        )
        let colorWidth = PopupPageLayout.estimatedItemWidth(for: action, inlineResult: color)
        XCTAssertEqual(colorWidth, PopupMetrics.actionButtonWidth)
        XCTAssertLessThanOrEqual(
            colorWidth,
            PopupMetrics.inlineResultMaxWidth + 2 * PopupMetrics.inlineResultHorizontalPadding + 0.001
        )

        let cjk = InlineResultLayout.width(for: .text("漢字"), surface: .bar, scale: 1)
        let latin = InlineResultLayout.width(for: .text("ab"), surface: .bar, scale: 1)
        XCTAssertGreaterThan(cjk, latin, "CJK glyphs must reserve full-width space")

        let search = InlineResultLayout.width(for: .text(String(repeating: "a", count: 200)), surface: .search, scale: 1)
        XCTAssertLessThanOrEqual(search, PopupMetrics.inlineSearchAccessoryMaxWidth)
    }

    // MARK: - JavaScript host
    func testTypedObjectsAreOnlyDecodedInRestrictedInlineMode() async throws {
        let request = makeRequest(script: "function action() { return { type: 'color', value: '#f80' }; }")
        let result = try await OpenClipJSHost().run(request)
        guard case .success = result else {
            return XCTFail("non-inline actions must keep the old object-return behavior: \(result)")
        }
    }

    func testRestrictedHostDecodesTypedReturns() async throws {        let cases: [(String, InlineResultValue)] = [
            ("return { type: 'text', value: '144' };", .text("144")),
            ("return { type: 'color', value: '#f80' };", .color(InlineColor(hex: "#FF8800")!))
        ]

        for (script, expected) in cases {
            var request = makeRequest(script: "function action() { \(script) }")
            request.restrictedToPreview = true
            let result = try await OpenClipJSHost().run(request)
            guard case .inlineValue(let value) = result else {
                return XCTFail("expected typed value for \(script), got \(result)")
            }
            XCTAssertEqual(value, expected)
        }
    }

    func testRestrictedHostRejectsMalformedTypedObjects() async throws {
        for script in [
            "return { type: 'color', value: 'red' };",
            // Emoji is not an output kind in 1.10; the glyph is ordinary text.
            "return { type: 'emoji', value: '🎉' };",
            "return { type: 'text', value: 144 };",
            "return { type: 'unknown', value: 'x' };",
            "return { type: 42, toString() { return 'unexpected'; } };",
            "return { type: 'file', path: '/tmp/no-file', toString() { return 'unexpected'; } };",
            "return { type: 'copyfile', path: '/tmp/no-file' };",
            "return { type: 'savefile', path: '/tmp/no-file' };"
        ] {
            var request = makeRequest(script: "function action() { \(script) }")
            request.restrictedToPreview = true
            let result = try await OpenClipJSHost().run(request)
            guard case .none = result else {
                return XCTFail("malformed typed object must not become a result: \(script) -> \(result)")
            }
        }
    }

    func testRestrictedHostRemovesEffectCapabilitiesBeforeCodeRuns() async throws {
        for script in [
            "function action() { openclip.copy('leak'); return 'ok'; }",
            "openclip.copy('leak'); function action() { return 'ok'; }",
            "function action() { openclip.file('/tmp/x'); return 'ok'; }",
            "function action() { openclip.notify('t', 'b'); return 'ok'; }",
            "function action() { openclip.toast('t'); return 'ok'; }",
            "function action() { return openclip.pasteboard.text; }"
        ] {
            var request = makeRequest(script: script)
            request.restrictedToPreview = true
            let result = try await OpenClipJSHost().run(request)
            switch result {
            case .copy, .file, .notify, .text:
                XCTFail("restricted preview must not perform effects: \(script) -> \(result)")
            case .toast(let feedback):
                // A forbidden call fails the preview; the error toast is presentation, not the effect.
                XCTAssertEqual(feedback.style, .error, "forbidden call must fail: \(script)")
            default:
                break
            }
        }
    }

    func testRestrictedHostRejectsPromisesWithoutWaiting() async throws {
        var request = makeRequest(script: "function action() { return Promise.resolve({ type: 'text', value: 'late' }); }")
        request.restrictedToPreview = true
        let result = try await OpenClipJSHost().run(request)
        switch result {
        case .success, .none:
            break // no value and no detached wait
        default:
            XCTFail("A promise return must not be awaited in the synchronous preview path: \(result)")
        }
    }

    func testRestrictedHostKeepsSelectionSnapshotAndOptions() async throws {
        var request = makeRequest(script: "function action() { return openclip.input.text; }")
        request.restrictedToPreview = true
        let result = try await OpenClipJSHost().run(request)
        guard case .text(let text) = result else {
            return XCTFail("selection snapshot must remain available, got \(result)")
        }
        XCTAssertEqual(text, "input")
    }

    func testRestrictedPreviewNeverTurnsAFilePathIntoAFileResult() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "contents".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        var request = makeRequest(script: "function action() { return '\(url.path)'; }")
        request.restrictedToPreview = true
        let result = try await OpenClipJSHost().run(request)
        guard case .text(let value) = result else {
            return XCTFail("a restricted preview is value-only; got \(result)")
        }
        XCTAssertEqual(value, url.path)
    }

    // MARK: - Evaluator typed validation

    func testEvaluatorAcceptsMatchingTypedOutputAndRejectsMismatch() async {
        let textAction = makeAction(
            id: "test.text",
            script: "function action() { return { type: 'text', value: '144' }; }",
            output: .text
        )
        let context = ActionContext(selection: SelectionContext(text: "input"))
        let text = await InlineResultEvaluator().evaluateAsync(action: textAction, context: context, timeout: 1.0)
        XCTAssertEqual(text, .text("144"))

        let mismatched = makeAction(
            id: "test.mismatch",
            script: "function action() { return { type: 'text', value: '144' }; }",
            output: .color
        )
        let mismatchedValue = await InlineResultEvaluator().evaluateAsync(action: mismatched, context: context, timeout: 1.0)
        XCTAssertNil(mismatchedValue)
    }

    func testDisplayOnlyEvaluatorAppliesTheTighterTextBound() async {
        let long = String(repeating: "a", count: 300)
        let action = JavaScriptAction(
            id: "test.display-only-long",
            title: "Long",
            scriptCode: "function action() { return { type: 'text', value: '\(long)' }; }",
            chrome: ActionChrome(isInlineResult: true, displayOnly: true, outputKind: .text),
            optionStore: SettingsActionOptionStore(store: MemorySettingsStore())
        )
        let context = ActionContext(selection: SelectionContext(text: "input"))
        let value = await InlineResultEvaluator().evaluateAsync(action: action, context: context, timeout: 1.0)
        XCTAssertNil(value)
    }

    func testEvaluatorReturnsColorForColorOutputOnly() async {
        let colorAction = makeAction(
            id: "test.color",
            script: "function action() { return { type: 'color', value: '#ff8800' }; }",
            output: .color
        )
        let context = ActionContext(selection: SelectionContext(text: "input"))
        let value = await InlineResultEvaluator().evaluateAsync(action: colorAction, context: context, timeout: 1.0)
        XCTAssertEqual(value, .color(InlineColor(hex: "#FF8800")!))
    }

    func testEvaluatorNeverRunsForbiddenEffectsOnInvocation() async {
        let action = makeAction(
            id: "test.effect",
            script: "function action() { openclip.copy('leak'); return 'ok'; }",
            output: .text
        )
        let context = ActionContext(selection: SelectionContext(text: "input"))
        let result = await InlineResultEvaluator().invoke(action: action, context: context, sessionID: UUID())
        XCTAssertNil(result, "invocation must not accept a value whose script performed an effect")
    }

    // MARK: - Helpers

    private func makeAction(id: String, script: String, output: ActionOutputKind) -> JavaScriptAction {
        JavaScriptAction(
            id: id,
            title: id,
            scriptCode: script,
            chrome: ActionChrome(isInlineResult: true, outputKind: output),
            optionStore: SettingsActionOptionStore(store: MemorySettingsStore())
        )
    }

    private func makeRequest(script: String) -> OpenClipJSHost.Request {
        OpenClipJSHost.Request(
            actionID: "test.host",
            scriptCode: script,
            context: ActionContext(selection: SelectionContext(text: "input")),
            options: [],
            optionStore: SettingsActionOptionStore(store: MemorySettingsStore()),
            rules: ExtensionActionRules(),
            timeout: 1.0
        )
    }
}

