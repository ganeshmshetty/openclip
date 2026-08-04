import XCTest
@testable import Core
@testable import OpenClip

fileprivate struct MockApp: AppIdentifying {
    let bundleIdentifier: String? = "com.host.test"
    let localizedName: String? = "HostTestApp"
}

/// In-memory option store for host tests; never touches UserDefaults. All access happens on the
/// MainActor in these tests, so the plain dictionary is safe.
fileprivate final class MemoryOptionStore: ActionOptionReading, ActionOptionWriting, @unchecked Sendable {
    private var values: [String: String] = [:]

    func stringValue(actionID: String, option: ExtensionOption) -> String {
        values[SettingKey.actionOption(actionID: actionID, optionID: option.identifier).name]
            ?? (option.defaultValue ?? "")
    }

    func setStringValue(_ value: String, actionID: String, option: ExtensionOption) {
        values[SettingKey.actionOption(actionID: actionID, optionID: option.identifier).name] = value
    }

    func clearValue(actionID: String, option: ExtensionOption) {
        values[SettingKey.actionOption(actionID: actionID, optionID: option.identifier).name] = ""
    }
}

@MainActor
final class OpenClipJSHostTests: XCTestCase {
    private var host: OpenClipJSHost!
    private var optionStore: MemoryOptionStore!

    override func setUp() async throws {
        try await super.setUp()
        host = OpenClipJSHost()
        optionStore = MemoryOptionStore()
    }

    private func makeContext(selectedText: String = "hello", match: ActionMatchInfo? = nil) -> ActionContext {
        let selection = SelectionContext(
            text: selectedText,
            sourceApp: MockApp(),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        return ActionContext(selection: selection, match: match)
    }

    private func makeRequest(
        script: String,
        options: [ExtensionOption] = [],
        rules: ExtensionActionRules = ExtensionActionRules()
    ) -> OpenClipJSHost.Request {
        OpenClipJSHost.Request(
            actionID: "test.action",
            scriptCode: script,
            context: makeContext(),
            options: options,
            optionStore: optionStore,
            rules: rules
        )
    }

    func testPasteEffectReturnsPaste() throws {
        let result = try host.run(makeRequest(script: "openclip.paste('Hello World');"))
        guard case .paste(let text) = result else {
            return XCTFail("Expected .paste, got \(result)")
        }
        XCTAssertEqual(text, "Hello World")
    }

    func testCopyEffectReturnsCopy() throws {
        let result = try host.run(makeRequest(script: "openclip.copy('Copied');"))
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "Copied")
    }

    func testShowBubbleReturnsBubbleWithFooterPresets() throws {
        let script = "openclip.showBubble({ title: 'T', body: 'Hello', footer: ['paste', 'copy'] });"
        let result = try host.run(makeRequest(script: script))
        guard case .showBubble(let content) = result else {
            return XCTFail("Expected .showBubble, got \(result)")
        }
        XCTAssertEqual(content.title, "T")
        XCTAssertEqual(content.rows.count, 1)
        guard case .text(let rowText) = content.rows[0] else {
            return XCTFail("Expected a text row")
        }
        XCTAssertEqual(rowText, "Hello")
        XCTAssertEqual(content.footer.count, 2)
        XCTAssertEqual(content.footer[0].title, "Paste")
        guard case .perform(.paste(let pasteText)) = content.footer[0].outcome else {
            return XCTFail("Expected paste footer outcome")
        }
        XCTAssertEqual(pasteText, "Hello")
        XCTAssertEqual(content.footer[1].title, "Copy")
        guard case .perform(.copy(let copyText)) = content.footer[1].outcome else {
            return XCTFail("Expected copy footer outcome")
        }
        XCTAssertEqual(copyText, "Hello")
    }

    func testRequireConfigurationReturnsOpenConfiguration() throws {
        let script = "openclip.requireConfiguration({ reason: 'Add your API key', missing: ['apiKey'] });"
        let result = try host.run(makeRequest(script: script))
        guard case .openConfiguration(let config) = result else {
            return XCTFail("Expected .openConfiguration, got \(result)")
        }
        XCTAssertEqual(config.actionID, "test.action")
        XCTAssertEqual(config.reason, "Add your API key")
        XCTAssertEqual(config.missingOptionIDs, ["apiKey"])
    }

    func testKeepVisibleWrapsCopyUnconditionally() throws {
        let script = "openclip.keepVisible(); openclip.copy('keep');"
        let result = try host.run(makeRequest(script: script))
        guard case .keepVisible(.copy(let text)) = result else {
            return XCTFail("Expected .keepVisible(.copy), got \(result)")
        }
        XCTAssertEqual(text, "keep")
    }

    func testInputCapturesExposed() throws {
        let match = ActionMatchInfo(text: "a b", matchedText: "b", captures: ["c1", "c2"], sourceBundleID: nil)
        let request = OpenClipJSHost.Request(
            actionID: "test.action",
            scriptCode: "return openclip.input.captures.join(',');",
            context: makeContext(selectedText: "a b", match: match),
            options: [],
            optionStore: optionStore,
            rules: ExtensionActionRules()
        )
        let result = try host.run(request)
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "c1,c2")
    }

    func testInputMatchedTextAndAppExposed() throws {
        let match = ActionMatchInfo(text: "full text", matchedText: "text", captures: [], sourceBundleID: nil)
        let script = "return openclip.input.matchedText + '|' + openclip.input.app.bundleID + '|' + openclip.input.app.name;"
        let request = OpenClipJSHost.Request(
            actionID: "test.action",
            scriptCode: script,
            context: makeContext(selectedText: "full text", match: match),
            options: [],
            optionStore: optionStore,
            rules: ExtensionActionRules()
        )
        let result = try host.run(request)
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "text|com.host.test|HostTestApp")
    }

    func testFunctionStringReturnBecomesCopy() throws {
        let result = try host.run(makeRequest(script: "function action() { return 'result'; }"))
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "result")
    }

    func testAdapterAppliesAfterToFunctionStringReturn() throws {
        let raw = try host.run(makeRequest(script: "function action() { return 'result'; }"))
        let applied = ActionResultAdapter.apply(
            raw: raw,
            after: .pasteResult,
            stayVisible: false,
            title: "T",
            icon: nil
        )
        guard case .paste(let text) = applied else {
            return XCTFail("Expected .paste after paste-result, got \(applied)")
        }
        XCTAssertEqual(text, "result")
    }

    func testExceptionReturnsErrorStatus() throws {
        let result = try host.run(makeRequest(script: "throw new Error('boom');"))
        guard case .showStatus(let feedback) = result else {
            return XCTFail("Expected .showStatus, got \(result)")
        }
        XCTAssertEqual(feedback.style, .error)
        XCTAssertTrue(feedback.message.contains("boom"))
    }

    func testNotifyEffectReturnsNotify() throws {
        let result = try host.run(makeRequest(script: "openclip.notify('Title', 'Body');"))
        guard case .notify(let title, let body) = result else {
            return XCTFail("Expected .notify, got \(result)")
        }
        XCTAssertEqual(title, "Title")
        XCTAssertEqual(body, "Body")
    }

    func testMultipleEffectsSequenceInCallOrder() throws {
        let script = "openclip.copy('a'); openclip.paste('b');"
        let result = try host.run(makeRequest(script: script))
        guard case .sequence(let items) = result else {
            return XCTFail("Expected .sequence, got \(result)")
        }
        XCTAssertEqual(items.count, 2)
        guard case .copy("a") = items[0], case .paste("b") = items[1] else {
            return XCTFail("Unexpected sequence order \(items)")
        }
    }

    func testStatusOnlySurfacesStatusButStatusWithEffectFallsThrough() throws {
        let statusOnly = try host.run(makeRequest(script: "openclip.showStatus('Done', 'success');"))
        guard case .showStatus(let feedback) = statusOnly else {
            return XCTFail("Expected .showStatus, got \(statusOnly)")
        }
        XCTAssertEqual(feedback.message, "Done")
        XCTAssertEqual(feedback.style, .success)

        let statusWithEffect = try host.run(makeRequest(script: "openclip.showStatus('nope', 'error'); openclip.copy('c');"))
        guard case .copy(let text) = statusWithEffect else {
            return XCTFail("Expected effect to win over status, got \(statusWithEffect)")
        }
        XCTAssertEqual(text, "c")
    }

    func testOptionsReadOnlyViaOptionStore() throws {
        let option = ExtensionOption(identifier: "prefix", label: "Prefix", type: .string, defaultValue: "DEFAULT: ")
        optionStore.setStringValue("SET: ", actionID: "test.action", option: option)
        let script = "return openclip.options.prefix + '|' + openclip.option('prefix');"
        let result = try host.run(makeRequest(script: script, options: [option]))
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "SET: |SET: ")
    }

    // MARK: - Manifest requiredOptions short-circuit (Phase 7)

    /// A required option with no resolved value must short-circuit to `.openConfiguration` BEFORE the
    /// JS body runs — the script would throw if executed, so only the short-circuit path can produce
    /// `.openConfiguration`.
    func testMissingRequiredOptionsShortCircuitsToOpenConfigurationBeforeJSRuns() async throws {
        let option = ExtensionOption(identifier: "apiKey", label: "API Key", type: .secret, defaultValue: nil)
        let rules = ExtensionActionRules(requirements: ActionRequirements(requiredOptions: ["apiKey"]))
        let action = JavaScriptAction(
            id: "test.required",
            title: "Required",
            iconSymbol: "terminal",
            scriptCode: "throw new Error('must not run');",
            options: [option],
            optionStore: MemoryOptionStore(),
            rules: rules
        )

        let result = try await action.perform(makeContext())
        guard case .openConfiguration(let config) = result else {
            return XCTFail("Expected .openConfiguration, got \(result)")
        }
        XCTAssertEqual(config.actionID, "test.required")
        XCTAssertEqual(config.missingOptionIDs, ["apiKey"])
        XCTAssertEqual(config.reason, "Required option not set.")
    }

    /// The same action with the required option set runs normally (`.copy`, not `.openConfiguration`).
    func testMissingRequiredOptionsRunsNormallyWhenStoreSet() async throws {
        let option = ExtensionOption(identifier: "apiKey", label: "API Key", type: .secret, defaultValue: nil)
        let store = MemoryOptionStore()
        store.setStringValue("secret", actionID: "test.required", option: option)
        let rules = ExtensionActionRules(requirements: ActionRequirements(requiredOptions: ["apiKey"]))
        let action = JavaScriptAction(
            id: "test.required",
            title: "Required",
            iconSymbol: "terminal",
            scriptCode: "function action() { return 'ran'; }",
            options: [option],
            optionStore: store,
            rules: rules
        )

        let result = try await action.perform(makeContext())
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "ran")
    }
}
