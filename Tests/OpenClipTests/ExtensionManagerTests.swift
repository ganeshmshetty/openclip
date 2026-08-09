import XCTest
@testable import OpenClip
@testable import Core

final class ExtensionManagerTests: XCTestCase {
    var tempDir: URL!
    var sourceDir: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
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
    func testLoadManifestRejectsUnknownActionKind() async throws {
        let extDir = tempDir.appendingPathComponent("bad_kind.openclipext")
        try FileManager.default.createDirectory(at: extDir, withIntermediateDirectories: true)

        let manifestPath = extDir.appendingPathComponent("openclip.json")
        let manifestContent = """
        {
            "identifier": "com.test.badkind",
            "name": "Bad Kind",
            "actions": [
                {
                    "title": "Mistyped",
                    "type": "banana",
                    "url": "https://example.com/{query}"
                }
            ]
        }
        """
        try manifestContent.write(to: manifestPath, atomically: true, encoding: .utf8)

        let manager = ExtensionManager.shared
        await manager.loadExtensions(from: tempDir)

        XCTAssertEqual(manager.loadedActions.count, 0, "Unknown action kind must reject the whole package, not silently load as url")
    }

    @MainActor
    func testLoadManifestRejectsDeclaredCapability() async throws {
        let extDir = tempDir.appendingPathComponent("declared_cap.openclipext")
        try FileManager.default.createDirectory(at: extDir, withIntermediateDirectories: true)

        let manifestPath = extDir.appendingPathComponent("openclip.json")
        let manifestContent = """
        {
            "identifier": "com.test.cap",
            "name": "Cap",
            "capabilities": ["network"],
            "actions": [
                {
                    "title": "URL",
                    "type": "url",
                    "url": "https://example.com/{query}"
                }
            ]
        }
        """
        try manifestContent.write(to: manifestPath, atomically: true, encoding: .utf8)

        let manager = ExtensionManager.shared
        await manager.loadExtensions(from: tempDir)

        XCTAssertEqual(manager.loadedActions.count, 0, "Any declared capability is outside the empty known set and must reject the manifest")
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
        
        guard let actionID = installed.first?.id else {
            XCTFail("Expected installed action")
            return
        }
        XCTAssertTrue(installed.contains(where: { $0.id == actionID }))
        
        // Verify file was copied to targetDir
        let expectedTarget = tempDir.appendingPathComponent("Installable.openclipext")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedTarget.path))
        
        // Test uninstall
        try await manager.uninstallExtension(actionID: actionID, targetDir: tempDir)
        XCTAssertFalse(manager.loadedActions.contains(where: { $0.id == actionID }))
    }

    @MainActor
    func testUninstallUnknownActionThrowsNotFoundAndKeepsRegistry() async throws {
        let extDir = sourceDir.appendingPathComponent("Keepable.openclipext")
        try FileManager.default.createDirectory(at: extDir, withIntermediateDirectories: true)
        let manifestPath = extDir.appendingPathComponent("manifest.json")
        let manifestContent = """
        {
            "Identifier": "com.test.keepable",
            "Name": "Keepable Extension",
            "Actions": [
                {
                    "Title": "Keepable Action",
                    "URL": "https://google.com/search?q={text}"
                }
            ]
        }
        """
        try manifestContent.write(to: manifestPath, atomically: true, encoding: .utf8)

        let manager = ExtensionManager.shared
        let installed = try await manager.installExtension(from: extDir, targetDir: tempDir)
        let actionID = try XCTUnwrap(installed.first?.id)

        // Unknown actionID must throw before touching registry state.
        do {
            try await manager.uninstallExtension(actionID: "com.test.doesnotexist.action.0", targetDir: tempDir)
            XCTFail("Expected not-found error for unknown actionID")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "ExtensionManager")
            XCTAssertEqual(nsError.code, 404)
        }
        XCTAssertTrue(manager.loadedActions.contains(where: { $0.id == actionID }), "registry must be unchanged when nothing was removed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: extDir.path), "extension must still be on disk")
    }
}
