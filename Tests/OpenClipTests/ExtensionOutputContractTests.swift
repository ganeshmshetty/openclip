// ExtensionOutputContractTests.swift
// OpenClipTests
//
// Comprehensive tests for the extension output contract:
// 1. Manifest parsing & validation (compatibility, warnings, unknown strings failing open, package inheritance).
// 2. Default result inference & script sniffing fallback.
// 3. ActionResultDelivery resolution with the universal secondary-click Clipboard Invariant.
// 4. Builtin action contracts (DefineAction, CalculateAction).

import XCTest
@testable import Core
@testable import OpenClip

final class ExtensionOutputContractTests: XCTestCase {

    /// Asserts `result` equals `expected` by pattern matching (ActionResult is not Equatable).
    private func assertCase(_ result: ActionResult, _ expected: ActionResult, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        switch (result, expected) {
        case (.paste(let a), .paste(let b)): XCTAssertEqual(a, b, message, file: file, line: line)
        case (.copy(let a), .copy(let b)): XCTAssertEqual(a, b, message, file: file, line: line)
        case (.text(let a), .text(let b)): XCTAssertEqual(a, b, message, file: file, line: line)
        case (.cut(let a), .cut(let b)): XCTAssertEqual(a, b, message, file: file, line: line)
        case (.openURL(let a), .openURL(let b)): XCTAssertEqual(a, b, message, file: file, line: line)
        case (.file(let a), .file(let b)): XCTAssertEqual(a.url, b.url, message, file: file, line: line)
        case (.copyFile(let a), .copyFile(let b)): XCTAssertEqual(a, b, message, file: file, line: line)
        case (.saveFile(let a), .saveFile(let b)): XCTAssertEqual(a, b, message, file: file, line: line)
        case (.success, .success), (.none, .none): XCTAssertTrue(true, message, file: file, line: line)
        default: XCTFail(message.isEmpty ? "unexpected result \(result)" : "\(message): unexpected result \(result)", file: file, line: line)
        }
    }

    // MARK: - Contract Compatibility & Defaults

    func testCompatibilityRules() {
        // Text outputs
        XCTAssertTrue(ExtensionOutputContract.isCompatible(output: .text, result: .preview))
        XCTAssertTrue(ExtensionOutputContract.isCompatible(output: .text, result: .paste))
        XCTAssertTrue(ExtensionOutputContract.isCompatible(output: .text, result: .copy))
        XCTAssertTrue(ExtensionOutputContract.isCompatible(output: .text, result: .pasteOrCopy))
        XCTAssertFalse(ExtensionOutputContract.isCompatible(output: .text, result: .open))
        XCTAssertFalse(ExtensionOutputContract.isCompatible(output: .text, result: .save))

        // File outputs
        XCTAssertTrue(ExtensionOutputContract.isCompatible(output: .file, result: .preview))
        XCTAssertTrue(ExtensionOutputContract.isCompatible(output: .file, result: .save))
        XCTAssertTrue(ExtensionOutputContract.isCompatible(output: .file, result: .open))
        XCTAssertTrue(ExtensionOutputContract.isCompatible(output: .file, result: .copy))
        XCTAssertFalse(ExtensionOutputContract.isCompatible(output: .file, result: .paste))
        XCTAssertFalse(ExtensionOutputContract.isCompatible(output: .file, result: .pasteOrCopy))

        // None output
        XCTAssertFalse(ExtensionOutputContract.isCompatible(output: .none, result: .copy))
        XCTAssertFalse(ExtensionOutputContract.isCompatible(output: .none, result: .paste))
        XCTAssertFalse(ExtensionOutputContract.isCompatible(output: .none, result: .preview))

        // Dynamic output
        XCTAssertTrue(ExtensionOutputContract.isCompatible(output: .dynamic, result: .preview))
        XCTAssertTrue(ExtensionOutputContract.isCompatible(output: .dynamic, result: .paste))
        XCTAssertTrue(ExtensionOutputContract.isCompatible(output: .dynamic, result: .save))
    }

    func testDefaultResults() {
        XCTAssertEqual(ExtensionOutputContract.defaultResult(for: .text), .pasteOrCopy)
        XCTAssertEqual(ExtensionOutputContract.defaultResult(for: .file), .preview)
        XCTAssertNil(ExtensionOutputContract.defaultResult(for: .none))
        XCTAssertEqual(ExtensionOutputContract.defaultResult(for: .dynamic), .preview)
    }

    func testInferredOutput() {
        XCTAssertEqual(ExtensionOutputContract.inferredOutput(for: .preview), .text)
        XCTAssertEqual(ExtensionOutputContract.inferredOutput(for: .paste), .text)
        XCTAssertEqual(ExtensionOutputContract.inferredOutput(for: .pasteOrCopy), .text)
        XCTAssertEqual(ExtensionOutputContract.inferredOutput(for: .copy), .text)
        XCTAssertEqual(ExtensionOutputContract.inferredOutput(for: .open), .file)
        XCTAssertEqual(ExtensionOutputContract.inferredOutput(for: .save), .file)
    }

    // MARK: - Manifest Decoding & Safe Fail-Open

    func testManifestDecodingExplicitOutputAndResult() throws {
        let json = """
        {
            "identifier": "com.test.contract",
            "name": "Contract Test",
            "output": "text",
            "result": "preview",
            "actions": [
                {
                    "id": "act1",
                    "title": "Act 1",
                    "type": "js",
                    "scriptCode": "return 'hello'",
                    "output": "text",
                    "result": "copy"
                },
                {
                    "id": "act2",
                    "title": "Act 2",
                    "type": "js",
                    "scriptCode": "return 'hello'"
                }
            ]
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(ExtensionMetadata.self, from: json)
        XCTAssertEqual(manifest.output, .text)
        XCTAssertEqual(manifest.result, .preview)

        let act1 = manifest.actions[0]
        XCTAssertEqual(act1.output, .text)
        XCTAssertEqual(act1.result, .copy)

        let act2 = manifest.actions[1]
        XCTAssertNil(act2.output)
        XCTAssertNil(act2.result)

        // Inheritance resolution
        let resolvedAct1 = ExtensionOutputContract.resolveEffective(action: act1, package: manifest)
        XCTAssertEqual(resolvedAct1.output, .text)
        XCTAssertEqual(resolvedAct1.result, .copy)

        let resolvedAct2 = ExtensionOutputContract.resolveEffective(action: act2, package: manifest)
        XCTAssertEqual(resolvedAct2.output, .text)
        XCTAssertEqual(resolvedAct2.result, .preview, "act2 inherits package-level result")
    }

    func testUnknownEnumStringsFailOpen() throws {
        let json = """
        {
            "id": "act",
            "title": "Act",
            "type": "js",
            "scriptCode": "return 'hello'",
            "output": "future-magic-output",
            "result": "future-telepathy"
        }
        """.data(using: .utf8)!

        let action = try JSONDecoder().decode(ExtensionActionMetadata.self, from: json)
        XCTAssertNil(action.output, "unknown output string fails open to nil")
        XCTAssertNil(action.result, "unknown result string fails open to nil")
    }

    // MARK: - Validation & Incompatible Pairs

    func testIncompatiblePairDropsResultAndRecordsWarning() throws {
        let json = """
        {
            "identifier": "com.test.incompatible",
            "name": "Incompatible Test",
            "actions": [
                {
                    "id": "bad1",
                    "title": "Bad 1",
                    "type": "url",
                    "url": "https://example.com",
                    "output": "none",
                    "result": "copy"
                }
            ]
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(ExtensionMetadata.self, from: json)
        let record = ManifestValidator.shared.validate(manifest, data: json)

        XCTAssertTrue(record.isValid, "incompatible output/result must NOT invalidate the manifest")
        XCTAssertEqual(record.warnings.count, 1)
        XCTAssertTrue(record.warnings[0].description.contains("incompatible output \"none\" and result \"copy\""))

        // Effective resolution drops the incompatible result and falls back to default for output (.none -> nil)
        let resolved = ExtensionOutputContract.resolveEffective(action: manifest.actions[0], package: manifest)
        XCTAssertEqual(resolved.output, .none)
        XCTAssertNil(resolved.result, "incompatible result must be dropped")
    }

    // MARK: - Script Sniffing Fallbacks

    func testScriptSniffingFallback() {
        XCTAssertTrue(ScriptOutputSniffers.jsProducesText(code: "function action(text) { return text.toUpperCase(); }"))
        XCTAssertFalse(ScriptOutputSniffers.jsProducesText(code: "function action(text) { console.log(text); }"))

        XCTAssertTrue(ScriptOutputSniffers.appleScriptProducesText(code: "tell application \"Finder\"\nreturn name\nend tell"))
        XCTAssertFalse(ScriptOutputSniffers.appleScriptProducesText(code: "say \"Hello World\""))
        XCTAssertFalse(ScriptOutputSniffers.appleScriptProducesText(code: "tell application \"System Events\"\nkeystroke \"c\" using command down\nend tell"))

        XCTAssertTrue(ScriptOutputSniffers.shellProducesText(code: "echo 'Hello World'"))
        XCTAssertFalse(ScriptOutputSniffers.shellProducesText(code: "qlmanage -p /tmp/preview.png"))
        XCTAssertFalse(ScriptOutputSniffers.shellProducesText(code: "open -a Calculator"))
    }

    // MARK: - Delivery Resolution & Universal Secondary-Click Clipboard Invariant

    func testPrimaryPreviewSecondaryCopies() {
        let raw = ActionResult.text("sample output")
        let (primary, _) = ActionResultDelivery.resolve(
            raw: raw,
            clickIntent: .primary,
            canPaste: true,
            delivery: .none,
            preference: nil,
            recommendedResult: .preview,
            outputKind: .text
        )
        // Primary with preview recommendation stays .text (rendered in card)
        assertCase(primary, .text("sample output"))

        let (secondary, toast) = ActionResultDelivery.resolve(
            raw: raw,
            clickIntent: .secondary,
            canPaste: true,
            delivery: .none,
            preference: nil,
            recommendedResult: .preview,
            outputKind: .text
        )
        // Secondary click on text: universal Clipboard Invariant delivers .copy
        assertCase(secondary, .copy("sample output"))
        XCTAssertEqual(toast?.message, String(localized: "Copied"))
    }

    func testPrimaryPasteSecondaryCopies() {
        let raw = ActionResult.text("paste me")
        let (primary, _) = ActionResultDelivery.resolve(
            raw: raw,
            clickIntent: .primary,
            canPaste: true,
            delivery: .none,
            preference: nil,
            recommendedResult: .paste,
            outputKind: .text
        )
        assertCase(primary, .paste("paste me"))

        let (secondary, toast) = ActionResultDelivery.resolve(
            raw: raw,
            clickIntent: .secondary,
            canPaste: true,
            delivery: .none,
            preference: nil,
            recommendedResult: .paste,
            outputKind: .text
        )
        assertCase(secondary, .copy("paste me"))
        XCTAssertEqual(toast?.message, String(localized: "Copied"))
    }

    func testPrimaryCopySecondaryPreviews() {
        let raw = ActionResult.text("copy me")
        let (primary, toast) = ActionResultDelivery.resolve(
            raw: raw,
            clickIntent: .primary,
            canPaste: true,
            delivery: .none,
            preference: nil,
            recommendedResult: .copy,
            outputKind: .text
        )
        assertCase(primary, .copy("copy me"))
        XCTAssertEqual(toast?.message, String(localized: "Copied"))

        let (secondary, _) = ActionResultDelivery.resolve(
            raw: raw,
            clickIntent: .secondary,
            canPaste: true,
            delivery: .none,
            preference: nil,
            recommendedResult: .copy,
            outputKind: .text
        )
        // When primary is copy, secondary delivers preview (.text)
        assertCase(secondary, .text("copy me"))
    }

    func testFileOutputResolutions() {
        let fileURL = URL(fileURLWithPath: "/tmp/sample.png")
        let payload = FileOutputPayload(url: fileURL, mimeType: "image/png")
        let raw = ActionResult.file(payload)

        // Preview recommended
        let (previewPrimary, _) = ActionResultDelivery.resolve(
            raw: raw,
            clickIntent: .primary,
            canPaste: true,
            delivery: .none,
            recommendedResult: .preview,
            outputKind: .file
        )
        assertCase(previewPrimary, raw)

        let (previewSecondary, _) = ActionResultDelivery.resolve(
            raw: raw,
            clickIntent: .secondary,
            canPaste: true,
            delivery: .none,
            recommendedResult: .preview,
            outputKind: .file
        )
        assertCase(previewSecondary, .copyFile(fileURL))

        // Save recommended
        let (savePrimary, _) = ActionResultDelivery.resolve(
            raw: raw,
            clickIntent: .primary,
            canPaste: true,
            delivery: .none,
            recommendedResult: .save,
            outputKind: .file
        )
        assertCase(savePrimary, .saveFile(fileURL))

        // Open recommended
        let (openPrimary, _) = ActionResultDelivery.resolve(
            raw: raw,
            clickIntent: .primary,
            canPaste: true,
            delivery: .none,
            recommendedResult: .open,
            outputKind: .file
        )
        assertCase(openPrimary, .openURL(fileURL))
    }

    func testUserOverridePrecedence() {
        let raw = ActionResult.text("hello")
        // Author recommends preview, but user set override to .paste
        let (primary, _) = ActionResultDelivery.resolve(
            raw: raw,
            clickIntent: .primary,
            canPaste: true,
            delivery: .none,
            preference: .paste,
            recommendedResult: .preview,
            outputKind: .text
        )
        assertCase(primary, .paste("hello"), "user override must win over author recommendation")

        // Secondary click still copies under the Clipboard Invariant
        let (secondary, _) = ActionResultDelivery.resolve(
            raw: raw,
            clickIntent: .secondary,
            canPaste: true,
            delivery: .none,
            preference: .paste,
            recommendedResult: .preview,
            outputKind: .text
        )
        assertCase(secondary, .copy("hello"))
    }

    func testDeclaredSecondaryBeatsClipboardInvariant() {
        let raw = ActionResult.text("hello")
        let customURL = URL(string: "https://custom")!
        let declared = ActionDelivery(secondary: .openURL(customURL))

        let (secondary, _) = ActionResultDelivery.resolve(
            raw: raw,
            clickIntent: .secondary,
            canPaste: true,
            delivery: declared,
            recommendedResult: .paste,
            outputKind: .text
        )
        assertCase(secondary, .openURL(customURL), "declared secondary outcome must always win")
    }

    // MARK: - Builtin Action Output Contracts

    func testBuiltinDefineActionContract() {
        let define = DefineAction()
        XCTAssertEqual(define.chrome.outputKind, .text)
        XCTAssertEqual(define.chrome.recommendedResult, .preview)
    }

    func testBuiltinCalculateActionContract() {
        let calc = CalculateAction()
        XCTAssertEqual(calc.chrome.outputKind, .text)
        XCTAssertEqual(calc.chrome.recommendedResult, .pasteOrCopy)
        XCTAssertTrue(calc.chrome.isInlineResult)
    }

    // MARK: - Script Output Sniffers

    func testJSSnifferEntryDetectionAndIsolation() {
        // Var / let / const declarations
        XCTAssertTrue(ScriptOutputSniffers.jsProducesText(code: "var action = () => { return 'hi'; }"))
        XCTAssertTrue(ScriptOutputSniffers.jsProducesText(code: "let main = function() { return 'hi'; }"))
        XCTAssertTrue(ScriptOutputSniffers.jsProducesText(code: "const action = text => text.toUpperCase()"))

        // Entry function has no return, helper function has return -> must isolate entry function
        let helperWithReturn = """
        function action() {
            openclip.toast("done");
        }
        function helper() {
            return "unrelated text";
        }
        """
        XCTAssertFalse(ScriptOutputSniffers.jsProducesText(code: helperWithReturn), "helper return should not pollute action")

        // Entry function with side effects only
        XCTAssertFalse(ScriptOutputSniffers.jsProducesText(code: "function action() { openclip.toast('hi'); }"))
    }

    func testAppleScriptExplicitReturnOverridesSideEffects() {
        let sayWithReturn = """
        say "Starting"
        return "done"
        """
        XCTAssertTrue(ScriptOutputSniffers.appleScriptProducesText(code: sayWithReturn))

        let keystrokeWithReturn = """
        tell application "System Events"
            keystroke "c" using {command down}
        end tell
        return "done"
        """
        XCTAssertTrue(ScriptOutputSniffers.appleScriptProducesText(code: keystrokeWithReturn))

        XCTAssertFalse(ScriptOutputSniffers.appleScriptProducesText(code: "say \"Starting\""))
        XCTAssertFalse(ScriptOutputSniffers.appleScriptProducesText(code: "return \"\""))
    }

    func testShellSnifferStdoutAfterGUICommands() {
        let qlWithEcho = """
        qlmanage -p file.png
        echo "done"
        """
        XCTAssertTrue(ScriptOutputSniffers.shellProducesText(code: qlWithEcho))
        XCTAssertFalse(ScriptOutputSniffers.shellProducesText(code: "qlmanage -p file.png"))

        let swiftWithPrintf = """
        swift main.swift
        printf "success\\n"
        """
        XCTAssertTrue(ScriptOutputSniffers.shellProducesText(code: swiftWithPrintf))
        XCTAssertFalse(ScriptOutputSniffers.shellProducesText(code: "swift main.swift >/dev/null"))
    }
}

