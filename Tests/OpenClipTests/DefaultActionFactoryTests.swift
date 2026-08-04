import XCTest
@testable import Core
@testable import OpenClip

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
}
