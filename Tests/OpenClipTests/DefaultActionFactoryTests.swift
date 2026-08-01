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
        
        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir)
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
        
        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir)
        XCTAssertTrue(action is AppleScriptAction)
        
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testFactoryRoutesURLTemplateToURLTemplateAction() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(title: "URL Action", icon: "symbol:link", script: nil, url: "https://example.com/{query}", regex: ".*")
        let manifest = ExtensionMetadata(identifier: "com.test.url", name: "URL Test", actions: [actionMeta], options: nil)
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir)
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
        
        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir)
        XCTAssertTrue(action is ScriptAction)
        
        try? FileManager.default.removeItem(at: tempDir)
    }
}
