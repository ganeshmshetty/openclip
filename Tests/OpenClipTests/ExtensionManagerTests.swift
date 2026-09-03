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
    func testLoadManifestRejectsScriptPathTraversal() async throws {
        let extDir = tempDir.appendingPathComponent("evil_traversal.openclipext")
        try FileManager.default.createDirectory(at: extDir, withIntermediateDirectories: true)

        let manifestPath = extDir.appendingPathComponent("openclip.json")
        let manifestContent = """
        {
            "identifier": "com.test.traversal",
            "name": "Evil Traversal",
            "actions": [
                {
                    "title": "Evil Shell",
                    "type": "scriptfile",
                    "script": "../../../../bin/zsh"
                }
            ]
        }
        """
        try manifestContent.write(to: manifestPath, atomically: true, encoding: .utf8)

        let manager = ExtensionManager.shared
        await manager.loadExtensions(from: tempDir)

        XCTAssertEqual(manager.loadedActions.count, 0, "Script path traversal escaping package directory must reject the manifest")
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
    func testReloadPreservesActionOrderForRetainedActionIDs() async throws {
        let extDir = tempDir.appendingPathComponent("order_ext.openclipext")
        try FileManager.default.createDirectory(at: extDir, withIntermediateDirectories: true)
        let manifestPath = extDir.appendingPathComponent("manifest.json")
        let manifestContent = """
        {
            "identifier": "com.test.order",
            "name": "Order Ext",
            "actions": [
                { "title": "Keep Me", "url": "https://example.com" }
            ]
        }
        """
        try manifestContent.write(to: manifestPath, atomically: true, encoding: .utf8)

        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)
        let manager = ExtensionManager.shared
        manager.onRegister = { registry.register(action: $0) }
        manager.onUnregister = { registry.unregister(actionID: $0) }

        await manager.loadExtensions(from: tempDir)
        let actionID = try XCTUnwrap(manager.loadedActions.first?.id)
        store.set(.actionOrder, value: [actionID, "other.action"])

        // Reload with the same extension still present: the ID is retained, so its .actionOrder
        // entry must survive instead of being pruned by an unregister-then-register cycle.
        await manager.loadExtensions(from: tempDir)

        XCTAssertTrue(store.get(.actionOrder).contains(actionID),
                      "reload must preserve .actionOrder for a retained action ID")
        XCTAssertTrue(registry.actions.contains { $0.id == actionID },
                      "retained action must remain registered after reload")
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

    /// Regression: uninstall matched loose scripts by raw filename substring
    /// (`actionID.contains(stem)`), so uninstalling `com.custom.alpha.sh` deleted the
    /// unrelated `a.sh` whenever directory order listed it first.
    @MainActor
    func testUninstallStandaloneScriptDoesNotDeleteSubstringNeighbors() async throws {
        let manager = ExtensionManager.shared

        for name in ["a.sh", "alpha.sh"] {
            let path = tempDir.appendingPathComponent(name)
            try "#!/bin/bash\n# Title: Script \(name)\necho ok".write(to: path, atomically: true, encoding: .utf8)
        }

        await manager.loadExtensions(from: tempDir)
        XCTAssertEqual(manager.loadedActions.count, 2, "both loose scripts must load")

        // Uninstall alpha.sh; a.sh (whose stem is a substring of alpha's action id) must survive.
        try await manager.uninstallExtension(actionID: "com.custom.alpha.sh", targetDir: tempDir)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("a.sh").path),
                      "substring-adjacent script must not be deleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("alpha.sh").path),
                       "the requested script must be removed")
        XCTAssertFalse(manager.loadedActions.contains { $0.id == "com.custom.alpha.sh" })
        XCTAssertTrue(manager.loadedActions.contains { $0.id == "com.custom.a.sh" },
                      "surviving script must stay loaded")
    }

    /// Regression: scripts declaring an `// Identifier:` header get an action id unrelated to
    /// their filename, so the old filename-substring match never found them and uninstall 404'd.
    @MainActor
    func testUninstallHeaderIdentifiedStandaloneScript() async throws {
        let manager = ExtensionManager.shared
        let path = tempDir.appendingPathComponent("totally-unrelated-filename.sh")
        try """
        #!/bin/bash
        # Title: My Tool
        # Identifier: com.example.mytool
        echo ok
        """.write(to: path, atomically: true, encoding: .utf8)

        await manager.loadExtensions(from: tempDir)
        XCTAssertTrue(manager.loadedActions.contains { $0.id == "com.example.mytool" })

        try await manager.uninstallExtension(actionID: "com.example.mytool", targetDir: tempDir)

        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path),
                       "header-identified script must be deletable by its declared id")
        XCTAssertFalse(manager.loadedActions.contains { $0.id == "com.example.mytool" })
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

    @MainActor
    func testUninstallPurgesOptionsAndPrunesActionOrder() async throws {
        let extDir = sourceDir.appendingPathComponent("Purgeable.openclipext")
        try FileManager.default.createDirectory(at: extDir, withIntermediateDirectories: true)
        let manifestPath = extDir.appendingPathComponent("manifest.json")
        let manifestContent = """
        {
            "identifier": "com.test.purgeable",
            "name": "Purgeable Extension",
            "options": [
                { "identifier": "apiKey", "label": "API Key", "type": "secret" }
            ],
            "actions": [
                { "id": "act1", "title": "Action 1", "url": "https://example.com" }
            ]
        }
        """
        try manifestContent.write(to: manifestPath, atomically: true, encoding: .utf8)

        final class MockOptionWriter: ActionOptionWriting, @unchecked Sendable {
            var cleared: [String] = []
            func setStringValue(_ value: String, actionID: String, option: ExtensionOption) {}
            func clearValue(actionID: String, option: ExtensionOption) {
                cleared.append("\(actionID):\(option.identifier)")
            }
        }

        let writer = MockOptionWriter()
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)

        let manager = ExtensionManager.shared
        manager.optionWriter = writer
        manager.onRegister = { registry.register(action: $0) }
        manager.onUnregister = { registry.unregister(actionID: $0) }

        let installed = try await manager.installExtension(from: extDir, targetDir: tempDir)
        let actionID = try XCTUnwrap(installed.first?.id)
        XCTAssertTrue(registry.actions.contains { $0.id == actionID }, "onRegister must register the installed action")

        store.set(.actionOrder, value: [actionID, "other.action"])

        try await manager.uninstallExtension(actionID: actionID, targetDir: tempDir)

        XCTAssertTrue(writer.cleared.contains("\(actionID):apiKey"), "optionWriter must clear configured options on uninstall")
        XCTAssertFalse(store.get(.actionOrder).contains(actionID), "actionOrder must be pruned of uninstalled actionID")
        XCTAssertFalse(registry.actions.contains { $0.id == actionID }, "onUnregister must unregister the action")
    }

    func testValidateZipEntriesAcceptsSafePaths() async throws {
        let zipPath = tempDir.appendingPathComponent("valid.zip")
        let sourceFile = tempDir.appendingPathComponent("payload.txt")
        try "content".write(to: sourceFile, atomically: true, encoding: .utf8)

        _ = try await ShellProcessRunner.run(ShellProcessRunner.Invocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-q", "-j", zipPath.path, sourceFile.path],
            environment: [:]
        ))

        let stagingDir = tempDir.appendingPathComponent("staging")
        try await ExtensionManager.validateZipEntries(at: zipPath, stagingDir: stagingDir)
    }

    func testValidateZipEntriesRejectsTraversalPaths() async throws {
        let zipPath = tempDir.appendingPathComponent("traversal.zip")

        // The `zip` CLI strips `..` path components, so craft the traversal entry with python3's
        // zipfile (python3 ships with Xcode CLT, which these tests already require for zip/unzip).
        _ = try await ShellProcessRunner.run(ShellProcessRunner.Invocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: ["-c", "import zipfile,sys; zipfile.ZipFile(sys.argv[1], 'w').writestr('../payload.txt', 'content')", zipPath.path],
            environment: [:]
        ))

        let stagingDir = tempDir.appendingPathComponent("staging")
        do {
            try await ExtensionManager.validateZipEntries(at: zipPath, stagingDir: stagingDir)
            XCTFail("Expected validateZipEntries to throw for a traversal entry")
        } catch let error as NSError {
            XCTAssertTrue(error.localizedDescription.contains("unsafe entry path"),
                          "Expected an unsafe-entry-path rejection, got: \(error.localizedDescription)")
        }
    }

    func testValidateZipEntriesRejectsSymlinkEntries() async throws {
        let zipPath = tempDir.appendingPathComponent("symlink.zip")

        // The `zip` CLI strips symlinks, so craft a symbolic-link entry (S_IFLNK | 0777 mode) plus
        // a later entry that writes through it, with python3's zipfile.
        _ = try await ShellProcessRunner.run(ShellProcessRunner.Invocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: ["-c", "import zipfile,stat,sys; z=zipfile.ZipFile(sys.argv[1],'w'); zi=zipfile.ZipInfo('link'); zi.external_attr=(stat.S_IFLNK|0o777)<<16; zi.create_system=3; z.writestr(zi,'/etc/passwd'); z.writestr('link/pwned.txt','pwned'); z.close()", zipPath.path],
            environment: [:]
        ))

        let stagingDir = tempDir.appendingPathComponent("staging")
        do {
            try await ExtensionManager.validateZipEntries(at: zipPath, stagingDir: stagingDir)
            XCTFail("Expected validateZipEntries to throw for a symbolic-link entry")
        } catch let error as NSError {
            XCTAssertTrue(error.localizedDescription.contains("symbolic-link"), "Expected a symbolic-link rejection, got: \(error.localizedDescription)")
        }
    }
}

