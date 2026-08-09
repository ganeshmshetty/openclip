import XCTest
@testable import Core
@testable import OpenClip

fileprivate func makeContext(text: String = "hello", bundleID: String = "com.test.app") -> ActionContext {
    ActionContext(
        selection: SelectionContext(
            text: text,
            sourceApp: AppIdentity(bundleIdentifier: bundleID, localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        ),
        modifiers: []
    )
}

final class NewExtensionKindTests: XCTestCase {
    // MARK: - keyPress

    func testFactoryRoutesKeyPressToKeyPressAction() async throws {
        let factory = DefaultActionFactory()
        let meta = ExtensionActionMetadata(title: "Key", type: "keypress", keyPress: "command+shift+v")
        let manifest = ExtensionMetadata(identifier: "com.test.keypress", name: "KeyPress Test", actions: [meta])

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let action = await factory.createAction(metadata: meta, manifest: manifest, directoryURL: tempDir, index: 0)
        guard let keyPress = action as? KeyPressAction else {
            return XCTFail("Expected KeyPressAction, got \(String(describing: action))")
        }
        XCTAssertEqual(keyPress.spec.key, "v")
        XCTAssertEqual(keyPress.spec.modifiers, [.command, .shift])

        let result = try await keyPress.perform(makeContext())
        guard case .keyPress(let spec) = result else {
            return XCTFail("Expected .keyPress result, got \(result)")
        }
        XCTAssertEqual(spec.key, "v")
        XCTAssertEqual(spec.modifiers, [.command, .shift])

        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - shortcut

    func testFactoryRoutesShortcutToShortcutAction() async throws {
        let factory = DefaultActionFactory()
        let meta = ExtensionActionMetadata(title: "Shortcut", type: "shortcut", shortcutName: "Trim Whitespace")
        let manifest = ExtensionMetadata(identifier: "com.test.shortcut", name: "Shortcut Test", actions: [meta])

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let action = await factory.createAction(metadata: meta, manifest: manifest, directoryURL: tempDir, index: 0)
        guard let shortcut = action as? ShortcutAction else {
            return XCTFail("Expected ShortcutAction, got \(String(describing: action))")
        }
        XCTAssertEqual(shortcut.shortcutName, "Trim Whitespace")

        let result = try await shortcut.perform(makeContext(text: "some text"))
        guard case .runShortcut(let name, let input) = result else {
            return XCTFail("Expected .runShortcut result, got \(result)")
        }
        XCTAssertEqual(name, "Trim Whitespace")
        XCTAssertEqual(input, "some text")

        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - service

    func testFactoryRoutesServiceToNamedServiceAction() async throws {
        let factory = DefaultActionFactory()
        let meta = ExtensionActionMetadata(title: "Share", type: "service", serviceName: "Share Selection")
        let manifest = ExtensionMetadata(identifier: "com.test.service", name: "Service Test", actions: [meta])

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let action = await factory.createAction(metadata: meta, manifest: manifest, directoryURL: tempDir, index: 0)
        guard let service = action as? NamedServiceAction else {
            return XCTFail("Expected NamedServiceAction, got \(String(describing: action))")
        }
        XCTAssertEqual(service.serviceName, "Share Selection")

        let result = try await service.perform(makeContext(text: "text"))
        guard case .showServices(let text) = result else {
            return XCTFail("Expected .showServices result, got \(result)")
        }
        XCTAssertEqual(text, "text")

        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - canvas

    @MainActor
    func testFactoryRoutesCanvasToJavaScriptCanvasAction() async throws {
        let factory = DefaultActionFactory()
        let scriptCode = "const ui = () => h('text', {});"
        let meta = ExtensionActionMetadata(title: "Canvas", icon: "symbol(paintbrush)", type: "canvas", scriptCode: scriptCode, isAsync: true)
        let manifest = ExtensionMetadata(identifier: "com.test.canvas", name: "Canvas Test", actions: [meta])

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let action = await factory.createAction(metadata: meta, manifest: manifest, directoryURL: tempDir, index: 0)
        guard let canvas = action as? JavaScriptCanvasAction else {
            try? FileManager.default.removeItem(at: tempDir)
            return XCTFail("Expected JavaScriptCanvasAction, got \(String(describing: action))")
        }
        XCTAssertEqual(canvas.id, "com.test.canvas.action.0")
        XCTAssertEqual(canvas.title, "Canvas")
        XCTAssertEqual(canvas.icon, .symbol("paintbrush"))
        XCTAssertEqual(canvas.scriptCode, scriptCode)
        XCTAssertTrue(canvas.isAsync)

        let result = try await canvas.perform(makeContext(text: "hello"))
        guard case .showCanvas(let request, let header) = result else {
            try? FileManager.default.removeItem(at: tempDir)
            return XCTFail("Expected .showCanvas result, got \(result)")
        }
        XCTAssertEqual(request.scriptCode, scriptCode)
        XCTAssertEqual(request.input, "hello")
        XCTAssertEqual(request.optionValues, [:])
        XCTAssertEqual(header.title, "Canvas")
        XCTAssertEqual(header.icon, "paintbrush")

        try? FileManager.default.removeItem(at: tempDir)
    }

    @MainActor
    func testCanvasActionMissingRequiredOptionsReturnsConfiguration() async throws {
        let factory = DefaultActionFactory()
        let meta = ExtensionActionMetadata(
            title: "Canvas",
            type: "canvas",
            scriptCode: "const ui = () => h('text', {});",
            requirements: ActionRequirements(requiredOptions: ["prefix"]),
            options: [ExtensionOptionMetadata(identifier: "prefix", label: "Prefix", type: "string")]
        )
        let manifest = ExtensionMetadata(identifier: "com.test.canvasopt", name: "Canvas Opt Test", actions: [meta])

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let action = await factory.createAction(metadata: meta, manifest: manifest, directoryURL: tempDir, index: 0)
        guard let canvas = action as? JavaScriptCanvasAction else {
            try? FileManager.default.removeItem(at: tempDir)
            return XCTFail("Expected JavaScriptCanvasAction, got \(String(describing: action))")
        }

        let result = try await canvas.perform(makeContext(text: "hello"))
        guard case .openConfiguration(let config) = result else {
            try? FileManager.default.removeItem(at: tempDir)
            return XCTFail("Expected .openConfiguration result, got \(result)")
        }
        XCTAssertEqual(config.actionID, "com.test.canvasopt.action.0")
        XCTAssertEqual(config.missingOptionIDs, ["prefix"])

        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - KeyPressSpec parsing

    func testKeyPressSpecManifestParsing() {
        XCTAssertEqual(KeyPressSpec(manifestString: "cmd+option+q")?.key, "q")
        XCTAssertEqual(KeyPressSpec(manifestString: "cmd+option+q")?.modifiers, [.command, .option])
        XCTAssertEqual(KeyPressSpec(manifestString: "return")?.key, "return")
        XCTAssertEqual(KeyPressSpec(manifestString: "return")?.modifiers, [])
        XCTAssertEqual(KeyPressSpec(manifestString: "control+shift+T")?.key, "T")
        XCTAssertEqual(KeyPressSpec(manifestString: "control+shift+T")?.modifiers, [.control, .shift])
        XCTAssertEqual(KeyPressSpec(manifestString: "  command + space ")?.key, "space")
        XCTAssertEqual(KeyPressSpec(manifestString: "  command + space ")?.modifiers, [.command])

        XCTAssertNil(KeyPressSpec(manifestString: ""))
        XCTAssertNil(KeyPressSpec(manifestString: "+"))
        XCTAssertNil(KeyPressSpec(manifestString: "cmd++"))
        XCTAssertNil(KeyPressSpec(manifestString: "nonsense+key"))
    }

    // MARK: - groups

    func testGroupFlattensToRowAndSubActions() async throws {
        let factory = DefaultActionFactory()
        let groupMeta = ExtensionActionMetadata(
            id: "tools",
            title: "Tools",
            type: "group",
            subActions: [
                ExtensionActionMetadata(id: "upper", title: "Upper", url: "https://example.com/?q={text}", type: "url"),
                ExtensionActionMetadata(id: "trim", title: "Trim", type: "keypress", keyPress: "command+k")
            ]
        )
        let manifest = ExtensionMetadata(identifier: "pkg", name: "Pkg", actions: [groupMeta])

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let flattened = await factory.createActions(metadata: groupMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertEqual(flattened.count, 3, "row + 2 sub-actions")

        guard let row = flattened.first as? GroupAction else {
            return XCTFail("First entry must be GroupAction")
        }
        XCTAssertEqual(row.id, "pkg.tools")
        XCTAssertEqual(row.chrome.popupBehavior, .showSubActions)
        XCTAssertEqual(row.chrome.rowStyle, .actionGroup)

        let rowResult = try await row.perform(makeContext())
        guard case .none = rowResult else {
            return XCTFail("GroupAction.perform must be .none, got \(rowResult)")
        }

        XCTAssertEqual(flattened[1].id, "pkg.tools.upper")
        XCTAssertEqual(flattened[2].id, "pkg.tools.trim")

        // The single-action seam still treats groups as schema-only.
        let single = await factory.createAction(metadata: groupMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertNil(single)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @MainActor
    func testGroupActionHonoursRules() {
        let group = GroupAction(
            id: "pkg.group",
            title: "G",
            icon: .symbol("folder"),
            chrome: ActionChrome(badge: .none, rowStyle: .actionGroup, popupBehavior: .showSubActions, source: .extensionPkg(packageID: "pkg")),
            rules: ExtensionActionRules(requirements: ActionRequirements(apps: ["com.allowed"], appsMode: .allow))
        )
        XCTAssertTrue(group.isEnabled(for: makeContext(bundleID: "com.allowed")))
        XCTAssertFalse(group.isEnabled(for: makeContext(bundleID: "com.other")))
    }
}