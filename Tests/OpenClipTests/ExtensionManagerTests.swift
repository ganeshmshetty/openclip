import XCTest
@testable import OpenClip
@testable import Core

final class ExtensionManagerTests: XCTestCase {
    var tempDir: URL!
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    @MainActor
    func testLoadStandaloneScript() async throws {
        let scriptPath = tempDir.appendingPathComponent("test_script.sh")
        let scriptContent = """
        #!/bin/bash
        # Title: Test Script
        # Icon: symbol(test)
        # Identifier: com.test.script
        echo "{\"type\":\"paste\",\"value\":\"test\"}"
        """
        try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
        
        // Make executable
        var attrs = try FileManager.default.attributesOfItem(atPath: scriptPath.path)
        attrs[.posixPermissions] = 0o755
        try FileManager.default.setAttributes(attrs, ofItemAtPath: scriptPath.path)
        
        let manager = ExtensionManager.shared
        await manager.loadExtensions(from: tempDir)
        
        XCTAssertEqual(manager.loadedActions.count, 1)
        let action = manager.loadedActions.first as? ScriptAction
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.title, "Test Script")
        XCTAssertEqual(action?.id, "com.test.script")
    }
    
    @MainActor
    func testLoadManifestExtension() async throws {
        let extDir = tempDir.appendingPathComponent("manifest_ext")
        try FileManager.default.createDirectory(at: extDir, withIntermediateDirectories: true)
        
        let manifestPath = extDir.appendingPathComponent("manifest.json")
        let manifestContent = """
        {
            "Identifier": "com.test.manifest",
            "Name": "Manifest Extension",
            "Actions": [
                {
                    "Title": "Action 1",
                    "Icon": "icon.png",
                    "Script": "action.sh"
                }
            ]
        }
        """
        try manifestContent.write(to: manifestPath, atomically: true, encoding: .utf8)
        
        let scriptPath = extDir.appendingPathComponent("action.sh")
        let scriptContent = """
        #!/bin/bash
        echo "{\"type\":\"paste\",\"value\":\"action\"}"
        """
        try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
        
        // Make executable
        var attrs = try FileManager.default.attributesOfItem(atPath: scriptPath.path)
        attrs[.posixPermissions] = 0o755
        try FileManager.default.setAttributes(attrs, ofItemAtPath: scriptPath.path)
        
        let manager = ExtensionManager.shared
        await manager.loadExtensions(from: tempDir)
        
        XCTAssertEqual(manager.loadedActions.count, 1)
        let action = manager.loadedActions.first as? ScriptAction
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.title, "Action 1")
    }
    
    @MainActor
    func testLoadPlistPopClipExtension() async throws {
        let extDir = tempDir.appendingPathComponent("Wikipedia.popclipext")
        try FileManager.default.createDirectory(at: extDir, withIntermediateDirectories: true)
        
        let plistPath = extDir.appendingPathComponent("Config.plist")
        let plistDict: [String: Any] = [
            "Extension Identifier": "com.pilotmoon.popclip.extension.wikipedia",
            "Extension Name": "Wikipedia",
            "Actions": [
                [
                    "Title": "Wikipedia",
                    "Image File": "w.png",
                    "URL": "https://en.wikipedia.org/w/index.php?search={popclip text}",
                    "Regular Expression": "(?s)^.{1,200}$"
                ]
            ]
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
        try plistData.write(to: plistPath)
        
        let manager = ExtensionManager.shared
        await manager.loadExtensions(from: tempDir)
        
        XCTAssertEqual(manager.loadedActions.count, 1)
        let action = manager.loadedActions.first as? URLTemplateAction
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.title, "Wikipedia")
        
        let dummyApp = NSRunningApplication.current
        let context = ActionContext(selection: SelectionContext(text: "Swift", sourceApp: dummyApp, cursorPosition: .zero, timestamp: Date(), appPolicy: .default))
        
        XCTAssertTrue(action?.isEnabled(for: context) == true)
        let result = try await action?.perform(context)
        if case .openURL(let url)? = result {
            XCTAssertEqual(url.absoluteString, "https://en.wikipedia.org/w/index.php?search=Swift")
        } else {
            XCTFail("Expected openURL result")
        }
    }
}
