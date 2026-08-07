import XCTest
@testable import Core
@testable import OpenClip

/// In-memory option store injected into the factory so the JS option override test never
/// touches UserDefaults.standard. All access happens on the MainActor.
fileprivate final class MemoryOptionStore: ActionOptionReading, ActionOptionWriting, @unchecked Sendable {
    private var values: [String: String] = [:]

    func stringValue(actionID: String, option: ExtensionOption) -> String {
        let name = SettingKey.actionOption(actionID: actionID, optionID: option.identifier).name
        return values[name] ?? (option.defaultValue ?? "")
    }

    func setStringValue(_ value: String, actionID: String, option: ExtensionOption) {
        values[SettingKey.actionOption(actionID: actionID, optionID: option.identifier).name] = value
    }

    func clearValue(actionID: String, option: ExtensionOption) {
        values[SettingKey.actionOption(actionID: actionID, optionID: option.identifier).name] = ""
    }
}

private extension ActionContext {
    init(selectedText: String, denyFormatting: Bool = false) {
        let policy = AppPolicyContext(
            denyFormatting: denyFormatting,
            denyProbe: false,
            denyPreprobe: false,
            grabPasteboard: false,
            assumePaste: false
        )
        let selection = SelectionContext(
            text: selectedText,
            sourceApp: AppIdentity(bundleIdentifier: "com.golden.testapp", localizedName: "GoldenTestApp"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: policy
        )
        self.init(selection: selection)
    }
}

final class GoldenExtensionPlatformTests: XCTestCase {
    var tempDir: URL!
    fileprivate var optionStore: MemoryOptionStore!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        TestIsolation.reset()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        optionStore = MemoryOptionStore()
        ExtensionManager.shared.actionFactory = DefaultActionFactory(optionStore: optionStore)
        // Make this test self-contained: mirror the production callback wiring
        // (ActionCoordinator.loadInitialState) so loaded extensions register into the shared
        // registry here rather than depending on state leaked from an earlier test class.
        ExtensionManager.shared.onRegister = { [registry = ActionRegistry.shared] action in
            registry.register(action: action)
        }
    }

    @MainActor
    override func tearDown() async throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        ExtensionManager.shared.actionFactory = nil
        try await super.tearDown()
    }
    
    @MainActor
    func testAllFourRuntimesLoadAndExecuteInRegistry() async throws {
        // 1. Synthetic JS Extension
        let jsBundle = tempDir.appendingPathComponent("JSExt.openclipext")
        try FileManager.default.createDirectory(at: jsBundle, withIntermediateDirectories: true)
        let jsManifest = """
        {
            "identifier": "com.golden.js",
            "name": "JS Golden Extension",
            "options": [
                {
                    "identifier": "prefix",
                    "label": "Prefix Text",
                    "type": "string",
                    "default": "JS_DEFAULT: "
                }
            ],
            "actions": [
                {
                    "id": "com.golden.js.action",
                    "title": "JS Action",
                    "script": "main.js"
                }
            ]
        }
        """
        try jsManifest.write(to: jsBundle.appendingPathComponent("openclip.json"), atomically: true, encoding: .utf8)
        let jsCode = """
        function action(text, options) {
            var pref = options.prefix || "";
            return pref + text.toUpperCase();
        }
        """
        try jsCode.write(to: jsBundle.appendingPathComponent("main.js"), atomically: true, encoding: .utf8)
        
        // 2. Synthetic AppleScript Extension
        let asBundle = tempDir.appendingPathComponent("AppleScriptExt.openclipext")
        try FileManager.default.createDirectory(at: asBundle, withIntermediateDirectories: true)
        let asManifest = """
        {
            "identifier": "com.golden.applescript",
            "name": "AppleScript Golden Extension",
            "actions": [
                {
                    "id": "com.golden.applescript.action",
                    "title": "AppleScript Action",
                    "script": "script.applescript"
                }
            ]
        }
        """
        try asManifest.write(to: asBundle.appendingPathComponent("openclip.json"), atomically: true, encoding: .utf8)
        let asCode = """
        return "AS:" & OPENCLIP_TEXT
        """
        try asCode.write(to: asBundle.appendingPathComponent("script.applescript"), atomically: true, encoding: .utf8)
        
        // 3. Synthetic Shell Extension
        let shBundle = tempDir.appendingPathComponent("ShellExt.openclipext")
        try FileManager.default.createDirectory(at: shBundle, withIntermediateDirectories: true)
        let shManifest = """
        {
            "identifier": "com.golden.shell",
            "name": "Shell Golden Extension",
            "actions": [
                {
                    "id": "com.golden.shell.action",
                    "title": "Shell Action",
                    "script": "run.sh"
                }
            ]
        }
        """
        try shManifest.write(to: shBundle.appendingPathComponent("openclip.json"), atomically: true, encoding: .utf8)
        let shCode = """
        #!/bin/bash
        echo "SH:$OPENCLIP_TEXT"
        """
        let shScriptURL = shBundle.appendingPathComponent("run.sh")
        try shCode.write(to: shScriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shScriptURL.path)
        
        // 4. Synthetic URL Extension
        let urlBundle = tempDir.appendingPathComponent("URLExt.openclipext")
        try FileManager.default.createDirectory(at: urlBundle, withIntermediateDirectories: true)
        let urlManifest = """
        {
            "identifier": "com.golden.url",
            "name": "URL Golden Extension",
            "actions": [
                {
                    "id": "com.golden.url.action",
                    "title": "URL Action",
                    "url": "https://example.com/search?q={text}",
                    "regex": "^[a-zA-Z0-9]+$"
                }
            ]
        }
        """
        try urlManifest.write(to: urlBundle.appendingPathComponent("openclip.json"), atomically: true, encoding: .utf8)
        
        // --- End-to-End Loading ---
        await ExtensionManager.shared.loadExtensions(from: tempDir)
        let loadedActions = ExtensionManager.shared.loadedActions
        
        XCTAssertEqual(loadedActions.count, 4, "Should load exactly 4 actions across JS, AppleScript, Shell, and URL runtimes")
        
        guard let jsAction = loadedActions.first(where: { $0.id == "com.golden.js.action" }) as? JavaScriptAction else {
            XCTFail("Missing JavaScriptAction for com.golden.js.action")
            return
        }
        guard let asAction = loadedActions.first(where: { $0.id == "com.golden.applescript.action" }) as? AppleScriptAction else {
            XCTFail("Missing AppleScriptAction for com.golden.applescript.action")
            return
        }
        guard let shAction = loadedActions.first(where: { $0.id == "com.golden.shell.action" }) as? ScriptAction else {
            XCTFail("Missing ScriptAction for com.golden.shell.action")
            return
        }
        guard let urlAction = loadedActions.first(where: { $0.id == "com.golden.url.action" }) as? URLTemplateAction else {
            XCTFail("Missing URLTemplateAction for com.golden.url.action")
            return
        }
        
        // --- Options Binding Verification ---
        XCTAssertEqual(jsAction.actionOptions.count, 1)
        XCTAssertEqual(jsAction.actionOptions.first?.identifier, "prefix")
        XCTAssertEqual(jsAction.actionOptions.first?.defaultValue, "JS_DEFAULT: ")
        
        // Test JS Default Options Execution
        let sampleContext = ActionContext(selectedText: "SampleInput")
        let defaultJSResult = try await jsAction.perform(sampleContext)
        if case .copy(let text) = defaultJSResult {
            XCTAssertEqual(text, "JS_DEFAULT: SAMPLEINPUT")
        } else {
            XCTFail("Expected .copy result for JS action, got \(defaultJSResult)")
        }
        
        // Test JS Custom Option Override via the injected option store
        let jsOption = jsAction.actionOptions.first(where: { $0.identifier == "prefix" })!
        optionStore.setStringValue("CUSTOM_PREFIX: ", actionID: "com.golden.js.action", option: jsOption)
        
        let customJSResult = try await jsAction.perform(sampleContext)
        if case .copy(let text) = customJSResult {
            XCTAssertEqual(text, "CUSTOM_PREFIX: SAMPLEINPUT")
        } else {
            XCTFail("Expected .copy result with custom option override, got \(customJSResult)")
        }
        
        // --- Execution Verification for Other Runtimes ---
        
        // AppleScript Execution
        let asResult = try await asAction.perform(sampleContext)
        if case .copy(let text) = asResult {
            XCTAssertEqual(text, "AS:SampleInput")
        } else {
            XCTFail("Expected .copy result for AppleScript action, got \(asResult)")
        }
        
        // Shell Execution
        let shResult = try await shAction.perform(sampleContext)
        if case .paste(let text) = shResult {
            XCTAssertEqual(text.trimmingCharacters(in: .whitespacesAndNewlines), "SH:SampleInput")
        } else {
            XCTFail("Expected .paste result for Shell action, got \(shResult)")
        }
        
        // URL Execution
        let urlResult = try await urlAction.perform(sampleContext)
        if case .openURL(let targetURL) = urlResult {
            XCTAssertEqual(targetURL.absoluteString, "https://example.com/search?q=SampleInput")
        } else {
            XCTFail("Expected .openURL result for URL action, got \(urlResult)")
        }
        
        // --- Registry Registration & Filtering Verification ---
        let registry = ActionRegistry.shared
        XCTAssertTrue(registry.actions.contains(where: { $0.id == "com.golden.js.action" }))
        XCTAssertTrue(registry.actions.contains(where: { $0.id == "com.golden.applescript.action" }))
        XCTAssertTrue(registry.actions.contains(where: { $0.id == "com.golden.shell.action" }))
        XCTAssertTrue(registry.actions.contains(where: { $0.id == "com.golden.url.action" }))
        
        // Matching regex context ("SampleInput" matches ^[a-zA-Z0-9]+$)
        let availableMatching = registry.availableActions(for: sampleContext)
        XCTAssertTrue(availableMatching.contains(where: { $0.id == "com.golden.js.action" }))
        XCTAssertTrue(availableMatching.contains(where: { $0.id == "com.golden.applescript.action" }))
        XCTAssertTrue(availableMatching.contains(where: { $0.id == "com.golden.shell.action" }))
        XCTAssertTrue(availableMatching.contains(where: { $0.id == "com.golden.url.action" }))
        
        // Non-matching regex context ("Sample Input!" has spaces and special characters)
        let nonMatchingContext = ActionContext(selectedText: "Sample Input!")
        let availableNonMatching = registry.availableActions(for: nonMatchingContext)
        XCTAssertTrue(availableNonMatching.contains(where: { $0.id == "com.golden.js.action" }))
        XCTAssertTrue(availableNonMatching.contains(where: { $0.id == "com.golden.applescript.action" }))
        XCTAssertTrue(availableNonMatching.contains(where: { $0.id == "com.golden.shell.action" }))
        XCTAssertFalse(availableNonMatching.contains(where: { $0.id == "com.golden.url.action" }), "URL action with regex should be filtered out when regex doesn't match")
        
        // Disabled action filtering via an isolated registry + memory store (no real preferences
        // touched): same four actions on a fresh registry, one disabled in the store.
        let disabledStore = MemorySettingsStore()
        let isolatedRegistry = ActionRegistry(settingsStore: disabledStore)
        isolatedRegistry.register(builtIns: [jsAction, asAction, shAction, urlAction])
        disabledStore.set(.disabledActionIDs, value: Set(["com.golden.js.action"]))

        let availableWithDisabled = isolatedRegistry.availableActions(for: sampleContext)
        XCTAssertFalse(availableWithDisabled.contains(where: { $0.id == "com.golden.js.action" }), "Disabled action should be filtered out by registry")
        XCTAssertTrue(availableWithDisabled.contains(where: { $0.id == "com.golden.shell.action" }), "Enabled actions in the same registry remain available")
    }

    /// Exit criterion: a JS extension calling openclip.showContent(...) produces a `.showContent`
    /// result through the full load → factory → host pipeline.
    @MainActor
    func testJSContentExtensionProducesShowContent() async throws {
        let jsBundle = tempDir.appendingPathComponent("JSContentExt.openclipext")
        try FileManager.default.createDirectory(at: jsBundle, withIntermediateDirectories: true)
        let jsManifest = """
        {
            "identifier": "com.golden.jscontent",
            "name": "JS Content Golden Extension",
            "actions": [
                {
                    "id": "com.golden.jscontent.action",
                    "title": "JS Content Action",
                    "script": "content.js"
                }
            ]
        }
        """
        try jsManifest.write(to: jsBundle.appendingPathComponent("openclip.json"), atomically: true, encoding: .utf8)
        let jsCode = """
        function action(text, options) {
            openclip.showContent({ title: "Processed", body: "Hello " + text, footer: ["paste", "copy"] });
            return null;
        }
        """
        try jsCode.write(to: jsBundle.appendingPathComponent("content.js"), atomically: true, encoding: .utf8)

        await ExtensionManager.shared.loadExtensions(from: tempDir)
        let loadedActions = ExtensionManager.shared.loadedActions

        guard let action = loadedActions.first(where: { $0.id == "com.golden.jscontent.action" }) as? JavaScriptAction else {
            XCTFail("Missing JavaScriptAction for com.golden.jscontent.action")
            return
        }

        let result = try await action.perform(ActionContext(selectedText: "World"))
        guard case .showContent(let content) = result else {
            return XCTFail("Expected .showContent, got \(result)")
        }
        XCTAssertEqual(content.title, "Processed")
        XCTAssertEqual(content.rows.count, 1)
        guard case .text(let rowText) = content.rows[0] else {
            return XCTFail("Expected text row")
        }
        XCTAssertEqual(rowText, "Hello World")
        XCTAssertEqual(content.footer.count, 2)
        XCTAssertEqual(content.footer[0].title, "Paste")
        guard case .perform(.paste("Hello World")) = content.footer[0].outcome else {
            return XCTFail("Expected Paste footer performing .paste(Hello World)")
        }
        XCTAssertEqual(content.footer[1].title, "Copy")
        guard case .perform(.copy("Hello World")) = content.footer[1].outcome else {
            return XCTFail("Expected Copy footer performing .copy(Hello World)")
        }
    }
}
