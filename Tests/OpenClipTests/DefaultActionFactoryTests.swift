import XCTest
@testable import Core
@testable import OpenClip

fileprivate struct MockApp: AppIdentifying {
    let bundleIdentifier: String?
    let localizedName: String?
}

final class DefaultActionFactoryTests: XCTestCase {
    func testFactoryRoutesJavaScriptFileToJavaScriptAction() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(title: "JS Action", icon: "symbol:code", script: "test.js", url: nil, regex: nil)
        let manifest = ExtensionMetadata(identifier: "com.test.js", name: "JS Test", actions: [actionMeta], options: nil)
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let jsFile = tempDir.appendingPathComponent("test.js")
        try? "console.log('hello');".write(to: jsFile, atomically: true, encoding: .utf8)
        
        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertTrue(action is JavaScriptAction)
        
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testFactoryRoutesAppleScriptFileToAppleScriptAction() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(title: "AppleScript Action", icon: "symbol:applescript", script: "test.applescript", url: nil, regex: nil)
        let manifest = ExtensionMetadata(identifier: "com.test.applescript", name: "AppleScript Test", actions: [actionMeta], options: nil)
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let scriptFile = tempDir.appendingPathComponent("test.applescript")
        try? "return \"hello\"".write(to: scriptFile, atomically: true, encoding: .utf8)
        
        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertTrue(action is AppleScriptAction)
        
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testFactoryRoutesURLTemplateToURLTemplateAction() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(title: "URL Action", icon: "symbol:link", script: nil, url: "https://example.com/{query}", regex: ".*")
        let manifest = ExtensionMetadata(identifier: "com.test.url", name: "URL Test", actions: [actionMeta], options: nil)
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertTrue(action is URLTemplateAction)
        
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testFactoryRoutesDefaultScriptToScriptAction() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(title: "Shell Action", icon: "symbol:terminal", script: "test.sh", url: nil, regex: nil)
        let manifest = ExtensionMetadata(identifier: "com.test.sh", name: "Shell Test", actions: [actionMeta], options: nil)
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let scriptFile = tempDir.appendingPathComponent("test.sh")
        try? "#!/bin/sh\necho hi".write(to: scriptFile, atomically: true, encoding: .utf8)
        
        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertTrue(action is ScriptAction)
        
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testUniformIDBareSlugExpandsWithManifestIdentifier() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(id: "a", title: "Action A", icon: "symbol:link", script: nil, url: "https://example.com/a?q={query}", regex: nil)
        let manifest = ExtensionMetadata(identifier: "pkg", name: "Pkg", actions: [actionMeta], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertEqual(action?.id, "pkg.a")

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testUniformIDFullIDUsedVerbatim() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(id: "com.custom.namespaced.action", title: "Action", icon: "symbol:link", script: nil, url: "https://example.com?q={query}", regex: nil)
        let manifest = ExtensionMetadata(identifier: "pkg", name: "Pkg", actions: [actionMeta], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertEqual(action?.id, "com.custom.namespaced.action")

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testUniformIDIndexFallbackIgnoresTitle() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(title: "Some Title", icon: "symbol:link", script: nil, url: "https://example.com?q={query}", regex: nil)
        let manifest = ExtensionMetadata(identifier: "pkg", name: "Pkg", actions: [actionMeta], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 2)
        XCTAssertEqual(action?.id, "pkg.action.2")

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testGroupActionIsNotRegisteredAsRunnable() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(
            title: "Group",
            type: "group",
            subActions: [
                ExtensionActionMetadata(id: "sub", title: "Sub Action", url: "https://example.com?q={query}", type: "url")
            ]
        )
        let manifest = ExtensionMetadata(identifier: "pkg", name: "Pkg", actions: [actionMeta], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        XCTAssertNil(action)

        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Rules attachment (Phase 4 visibility)

    @MainActor
    func testFactoryAttachesRulesToURLAction() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(
            title: "URL Action",
            icon: "symbol:link",
            url: "https://example.com/?q={text}",
            regex: "^[a-z]+$",
            requirements: ActionRequirements(apps: ["com.allowed"], appsMode: .allow),
            after: .showResult,
            stayVisible: true
        )
        let manifest = ExtensionMetadata(identifier: "com.test.rules", name: "Rules Test", actions: [actionMeta], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        guard let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0) as? URLTemplateAction else {
            XCTFail("Expected URLTemplateAction")
            try? FileManager.default.removeItem(at: tempDir)
            return
        }
        XCTAssertEqual(action.rules?.legacyRegex, "^[a-z]+$")
        XCTAssertEqual(action.rules?.requirements?.apps, ["com.allowed"])
        XCTAssertEqual(action.rules?.after, .showResult)
        XCTAssertTrue(action.rules?.stayVisible ?? false)

        // Allow-list filtering flows through ActionVisibility.
        let allowedContext = ActionContext(
            selection: SelectionContext(text: "hello", sourceApp: MockApp(bundleIdentifier: "com.allowed", localizedName: "Allowed"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        let deniedContext = ActionContext(
            selection: SelectionContext(text: "hello", sourceApp: MockApp(bundleIdentifier: "com.other", localizedName: "Other"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertTrue(action.isEnabled(for: allowedContext))
        XCTAssertFalse(action.isEnabled(for: deniedContext))

        try? FileManager.default.removeItem(at: tempDir)
    }

    @MainActor
    func testFactoryAttachesRulesToScriptFileAction() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(
            title: "Shell Action",
            icon: "symbol:terminal",
            script: "test.sh",
            requirements: ActionRequirements(regex: "^[0-9]+$")
        )
        let manifest = ExtensionMetadata(identifier: "com.test.shell", name: "Shell Test", actions: [actionMeta], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let scriptFile = tempDir.appendingPathComponent("test.sh")
        try? "#!/bin/sh\necho hi".write(to: scriptFile, atomically: true, encoding: .utf8)

        guard let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0) as? ScriptAction else {
            XCTFail("Expected ScriptAction")
            try? FileManager.default.removeItem(at: tempDir)
            return
        }
        XCTAssertEqual(action.rules?.requirements?.regex, "^[0-9]+$")

        let context = ActionContext(
            selection: SelectionContext(text: "123", sourceApp: MockApp(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertTrue(action.isEnabled(for: context))

        try? FileManager.default.removeItem(at: tempDir)
    }

    @MainActor
    func testFactoryAttachesRulesToShellInlineCustomAction() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(
            title: "Shell Inline",
            icon: "symbol:terminal",
            type: "shell",
            scriptCode: "echo hi",
            requirements: ActionRequirements(apps: ["com.allowed"], appsMode: .deny)
        )
        let manifest = ExtensionMetadata(identifier: "com.test.shellinline", name: "Shell Inline Test", actions: [actionMeta], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        guard let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0) as? CustomAction else {
            XCTFail("Expected CustomAction")
            try? FileManager.default.removeItem(at: tempDir)
            return
        }
        XCTAssertNotNil(action.rules)
        XCTAssertEqual(action.rules?.requirements?.appsMode, .deny)

        // Deny-list filtering flows through ActionVisibility on the shellInline path too.
        let deniedContext = ActionContext(
            selection: SelectionContext(text: "hello", sourceApp: MockApp(bundleIdentifier: "com.allowed", localizedName: "Allowed"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        let allowedContext = ActionContext(
            selection: SelectionContext(text: "hello", sourceApp: MockApp(bundleIdentifier: "com.other", localizedName: "Other"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertFalse(action.isEnabled(for: deniedContext))
        XCTAssertTrue(action.isEnabled(for: allowedContext))

        try? FileManager.default.removeItem(at: tempDir)
    }
}
