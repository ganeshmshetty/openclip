import XCTest
import AppKit
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

    func testFactoryRoutesServiceToNamedServiceAction() async throws {        let factory = DefaultActionFactory()
        let meta = ExtensionActionMetadata(title: "Share", type: "service", serviceName: "Look Up in Dictionary")
        let manifest = ExtensionMetadata(identifier: "com.test.service", name: "Service Test", actions: [meta])

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let action = await factory.createAction(metadata: meta, manifest: manifest, directoryURL: tempDir, index: 0)
        guard var service = action as? NamedServiceAction else {
            return XCTFail("Expected NamedServiceAction, got \(String(describing: action))")
        }
        XCTAssertEqual(service.serviceName, "Look Up in Dictionary")

        // 1. Successful NSPerformService returns .none
        final class CalledBox: @unchecked Sendable { var value = false }
        let box = CalledBox()
        service.performService = { name, pboard in
            box.value = true
            XCTAssertEqual(name, "Look Up in Dictionary")
            XCTAssertEqual(pboard.string(forType: .string), "selected text")
            return true
        }
        let result = try await service.perform(makeContext(text: "selected text"))
        XCTAssertTrue(box.value)
        guard case .none = result else {
            return XCTFail("Expected .none result for successful service invocation, got \(result)")
        }

        // 2. Failed NSPerformService throws error
        service.performService = { _, _ in false }
        do {
            _ = try await service.perform(makeContext(text: "text"))
            XCTFail("Expected perform to throw when service fails")
        } catch {
            let nsErr = error as NSError
            XCTAssertEqual(nsErr.domain, Constants.actionErrorDomain)
        }

        // 3. Unnamed service falls back to .showServices
        let unnamedService = NamedServiceAction(id: "com.test.unnamed", title: "Unnamed", serviceName: nil)
        let unnamedResult = try await unnamedService.perform(makeContext(text: "text"))
        guard case .showServices(let text2) = unnamedResult else {
            return XCTFail("Expected .showServices result, got \(unnamedResult)")
        }
        XCTAssertEqual(text2, "text")

        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - service isolation

    func testNamedServiceExecutionPreservesGlobalClipboard() async throws {
        // Live integration: directly exercising the named-service flow must not touch
        // NSPasteboard.general (which holds the user's real clipboard).
        let changeCountBefore = NSPasteboard.general.changeCount

        var service = NamedServiceAction(id: "com.test.isolated", title: "Service", serviceName: "com.apple.text.input")
        final class SeenBox: @unchecked Sendable { var name = "" }
        let seen = SeenBox()
        service.performService = { name, pboard in
            seen.name = pboard.name.rawValue
            XCTAssertEqual(pboard.string(forType: .string), "selected text")
            return true
        }

        let result = try await service.perform(makeContext(text: "selected text"))
        guard case .none = result else {
            return XCTFail("Expected .none result, got \(result)")
        }

        XCTAssertFalse(seen.name.isEmpty)
        XCTAssertNotEqual(seen.name, NSPasteboard.general.name.rawValue, "Service should receive an isolated pasteboard, not NSPasteboard.general")
        XCTAssertEqual(NSPasteboard.general.changeCount, changeCountBefore, "Global clipboard must remain unchanged")
    }

    // MARK: - canvas (removed)

    /// The canvas feature was removed: `type: "canvas"` is no longer a recognized kind, so the
    /// factory must NOT produce a canvas runtime. With only `scriptCode` (no URL/script file) the
    /// generic script path finds nothing runnable and the action is dropped.
    @MainActor
    func testFactoryNoLongerProducesCanvasAction() async throws {
        let factory = DefaultActionFactory()
        let meta = ExtensionActionMetadata(title: "Canvas", icon: "symbol(paintbrush)", type: "canvas", scriptCode: "const ui = () => h('text', {});", isAsync: true)
        let manifest = ExtensionMetadata(identifier: "com.test.canvas", name: "Canvas Test", actions: [meta])

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let action = await factory.createAction(metadata: meta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertNil(action, "canvas-type metadata must not produce an action after canvas removal")
    }

    /// A canvas manifest with a `.js` script file degrades to the generic JS runtime (still
    /// rejected at validation, but never a canvas action).
    @MainActor
    func testFactoryRoutesCanvasScriptFileToPlainJavaScriptAction() async throws {
        let factory = DefaultActionFactory()
        let scriptCode = "function action() { return 'ok'; }"
        let meta = ExtensionActionMetadata(title: "Canvas File", script: "main.js", type: "canvas")
        let manifest = ExtensionMetadata(identifier: "com.test.filecanvas", name: "File Canvas Test", actions: [meta])

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try scriptCode.write(to: tempDir.appendingPathComponent("main.js"), atomically: true, encoding: .utf8)

        let action = await factory.createAction(metadata: meta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertTrue(action is JavaScriptAction, "canvas script files degrade to the plain JS runtime, got \(String(describing: action))")
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

    // MARK: - expression DSL compilation

    @MainActor
    func testFactoryCompilesExpressionIntoRulesAndGatesActions() async throws {
        let factory = DefaultActionFactory()
        let meta = ExtensionActionMetadata(
            title: "Exp",
            url: "https://example.com/?q={text}",
            type: "url",
            requirements: ActionRequirements(expression: "length(text) >= 5")
        )
        let manifest = ExtensionMetadata(identifier: "com.test.exp", name: "Exp Test", actions: [meta])

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let action = await factory.createAction(metadata: meta, manifest: manifest, directoryURL: tempDir, index: 0)
        guard let urlAction = action as? URLTemplateAction else {
            return XCTFail("Expected URLTemplateAction, got \(String(describing: action))")
        }
        XCTAssertNotNil(urlAction.rules?.compiledExpression)
        XCTAssertTrue(urlAction.isEnabled(for: makeContext(text: "12345")))
        XCTAssertFalse(urlAction.isEnabled(for: makeContext(text: "hi")))
    }

    @MainActor
    func testFactoryMalformedExpressionFailsOpen() async throws {
        let factory = DefaultActionFactory()
        let meta = ExtensionActionMetadata(
            title: "Bad",
            url: "https://example.com/?q={text}",
            type: "url",
            requirements: ActionRequirements(expression: "isEmail(text) &&")
        )
        let manifest = ExtensionMetadata(identifier: "com.test.bad", name: "Bad Test", actions: [meta])

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let action = await factory.createAction(metadata: meta, manifest: manifest, directoryURL: tempDir, index: 0)
        let urlAction = action as? URLTemplateAction
        XCTAssertNotNil(urlAction)
        XCTAssertNil(urlAction?.rules?.compiledExpression) // malformed -> nil -> behaves as today
        XCTAssertTrue(urlAction?.isEnabled(for: makeContext(text: "anything")) == true)
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

    // MARK: - JS module package directory

    @MainActor
    func testFactoryRoutesScriptFileToJavaScriptActionWithPackageDirectory() async throws {
        let factory = DefaultActionFactory()
        let meta = ExtensionActionMetadata(title: "File", script: "main.js", type: "js")
        let manifest = ExtensionMetadata(identifier: "com.test.file", name: "File Test", actions: [meta])

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try "function action(){ return 'x'; }".write(to: tempDir.appendingPathComponent("main.js"), atomically: true, encoding: .utf8)

        let action = await factory.createAction(metadata: meta, manifest: manifest, directoryURL: tempDir, index: 0)
        guard let js = action as? JavaScriptAction else {
            return XCTFail("Expected JavaScriptAction, got \(String(describing: action))")
        }
        XCTAssertEqual(js.packageDirectory, tempDir)
        XCTAssertEqual(js.entryDirectory?.path, tempDir.path)
    }

    @MainActor
    func testFactoryNestedScriptSetsEntryDirectory() async throws {
        let factory = DefaultActionFactory()
        let meta = ExtensionActionMetadata(title: "Nested", script: "src/main.js", type: "javascript")
        let manifest = ExtensionMetadata(identifier: "com.test.nested", name: "Nested Test", actions: [meta])

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let srcDir = tempDir.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try "function action(){ return 'x'; }".write(to: srcDir.appendingPathComponent("main.js"), atomically: true, encoding: .utf8)

        let action = await factory.createAction(metadata: meta, manifest: manifest, directoryURL: tempDir, index: 0)
        guard let js = action as? JavaScriptAction else {
            return XCTFail("Expected JavaScriptAction, got \(String(describing: action))")
        }
        XCTAssertEqual(js.packageDirectory, tempDir)
        XCTAssertEqual(js.entryDirectory?.path, srcDir.path)
    }

    @MainActor
    func testFactoryInlineScriptCodeHasNilPackageDirectory() async throws {
        let factory = DefaultActionFactory()
        let meta = ExtensionActionMetadata(title: "Inline", type: "javascript", scriptCode: "function action(){ return 'x'; }")
        let manifest = ExtensionMetadata(identifier: "com.test.inline", name: "Inline Test", actions: [meta])

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let action = await factory.createAction(metadata: meta, manifest: manifest, directoryURL: tempDir, index: 0)
        guard let js = action as? JavaScriptAction else {
            return XCTFail("Expected JavaScriptAction, got \(String(describing: action))")
        }
        XCTAssertNil(js.packageDirectory)
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