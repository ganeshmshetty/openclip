import XCTest
@testable import OpenClip
@testable import Core

final class ExtensionManagerTests: XCTestCase {
    var tempDir: URL!
    var sourceDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        sourceDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        try? FileManager.default.removeItem(at: sourceDir)
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
        let extDir = tempDir.appendingPathComponent("manifest_ext.openclipext")
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
    func testInstallAndUninstallExtension() async throws {
        let extDir = sourceDir.appendingPathComponent("Installable.openclipext")
        try FileManager.default.createDirectory(at: extDir, withIntermediateDirectories: true)
        
        let manifestPath = extDir.appendingPathComponent("manifest.json")
        let manifestContent = """
        {
            "Identifier": "com.test.installable",
            "Name": "Installable Extension",
            "Actions": [
                {
                    "Title": "Installed Action",
                    "URL": "https://google.com/search?q={text}"
                }
            ]
        }
        """
        try manifestContent.write(to: manifestPath, atomically: true, encoding: .utf8)
        
        let manager = ExtensionManager.shared
        let installed = try await manager.installExtension(from: extDir, targetDir: tempDir)
        
        XCTAssertTrue(installed.contains(where: { $0.id == "com.test.installable.action.0" }))
        
        // Verify file was copied to targetDir
        let expectedTarget = tempDir.appendingPathComponent("Installable.openclipext")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedTarget.path))
        
        // Test uninstall
        try await manager.uninstallExtension(actionID: "com.test.installable.action.0", targetDir: tempDir)
        XCTAssertFalse(manager.loadedActions.contains(where: { $0.id == "com.test.installable.action.0" }))
    }
}
