import XCTest
@testable import Core
@testable import OpenClip

final class CustomActionManifestWriterTests: XCTestCase {
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
    func testWriterWritesSingleActionManifestPackage() throws {
        let action = CustomAction(
            id: "com.custom.abc123",
            title: "Test Web Search",
            iconName: "magnifyingglass",
            type: .webSearch(urlTemplate: "https://example.com/?q={text}")
        )
        let manifestURL = try CustomActionManifestWriter.write(action: action, to: tempDir)
        
        // The package folder is named by the action id and holds openclip.json.
        XCTAssertEqual(manifestURL.deletingLastPathComponent().lastPathComponent, action.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))
        
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(ExtensionMetadata.self, from: data)
        XCTAssertEqual(manifest.identifier, action.id)
        XCTAssertEqual(manifest.actions.count, 1)
        XCTAssertEqual(manifest.actions[0].title, "Test Web Search")
        XCTAssertEqual(manifest.actions[0].type, "url")
        XCTAssertEqual(manifest.actions[0].url, "https://example.com/?q={text}")
    }
    
    @MainActor
    func testWriterRoundTripLoadsActionViaExtensionManager() async throws {
        let action = CustomAction(
            id: "com.custom.roundtrip1",
            title: "Round Trip Web",
            iconName: "magnifyingglass",
            type: .webSearch(urlTemplate: "https://example.com/search?q={text}")
        )
        try CustomActionManifestWriter.write(action: action, to: tempDir)
        
        let manager = ExtensionManager.shared
        manager.actionFactory = DefaultActionFactory()
        defer { manager.actionFactory = nil }
        
        await manager.loadExtensions(from: tempDir)
        
        let loaded = manager.loadedActions.first(where: { $0.id == action.id })
        XCTAssertNotNil(loaded, "Expected the written action to reload with its id")
        
        // The reloaded id follows the uniform rule: explicit dot-containing id round-trips verbatim.
        XCTAssertEqual(loaded?.id, ExtensionManager.uniformActionID(
            metadata: manifestAction(for: action),
            manifest: ExtensionMetadata(identifier: action.id, name: action.title, actions: [manifestAction(for: action)]),
            index: 0
        ))
        // A manifest URL action rehydrates as URLTemplateAction with the template and extension chrome.
        guard let urlAction = loaded as? URLTemplateAction else {
            XCTFail("Expected the webSearch action to load as URLTemplateAction")
            return
        }
        XCTAssertEqual(urlAction.urlTemplate, "https://example.com/search?q={text}")
        XCTAssertEqual(urlAction.chrome.source, .extensionPkg(packageID: action.id))
    }
    
    @MainActor
    func testWriterRoundTripsTextSnippetAndShellScript() async throws {
        let snippet = CustomAction(
            id: "com.custom.snippet1",
            title: "Snippet",
            iconName: "doc.text",
            type: .textSnippet(template: "Hello {text}!")
        )
        let shell = CustomAction(
            id: "com.custom.shell1",
            title: "Shell",
            iconName: "terminal",
            type: .shellScript(script: "echo \"$OPENCLIP_TEXT\"", replaceSelection: true)
        )
        try CustomActionManifestWriter.write(action: snippet, to: tempDir)
        try CustomActionManifestWriter.write(action: shell, to: tempDir)
        
        let manager = ExtensionManager.shared
        manager.actionFactory = DefaultActionFactory()
        defer { manager.actionFactory = nil }
        
        await manager.loadExtensions(from: tempDir)
        
        let loadedSnippet = manager.loadedActions.first(where: { $0.id == snippet.id }) as? CustomAction
        XCTAssertEqual(loadedSnippet?.type, snippet.type)
        XCTAssertEqual(loadedSnippet?.chrome.source, .extensionPkg(packageID: snippet.id))
        
        let loadedShell = manager.loadedActions.first(where: { $0.id == shell.id }) as? CustomAction
        XCTAssertEqual(loadedShell?.type, shell.type)
        XCTAssertEqual(loadedShell?.chrome.source, .extensionPkg(packageID: shell.id))
    }
    
    private func manifestAction(for action: CustomAction) -> ExtensionActionMetadata {
        CustomActionManifestWriter.metadata(for: action).actions[0]
    }
}
