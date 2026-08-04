import XCTest
@testable import Core
@testable import OpenClip

/// Verifies the uniform action-ID rule (Phase 1), per-action option `values` decoding, and the
/// schema-only `group` kind across the full load pipeline.
final class MultiActionExtensionTests: XCTestCase {
    var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        await MainActor.run {
            ExtensionManager.shared.actionFactory = DefaultActionFactory()
        }
    }

    override func tearDown() async throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        await MainActor.run {
            ExtensionManager.shared.actionFactory = nil
        }
        try await super.tearDown()
    }

    @MainActor
    func testManifestWithThreeActionsRegistersUniformIDs() async throws {
        let bundle = tempDir.appendingPathComponent("Pkg.openclipext")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let manifest = """
        {
            "identifier": "pkg",
            "name": "Pkg",
            "actions": [
                { "id": "a", "title": "Action A", "url": "https://example.com/a?q={query}" },
                { "id": "b", "title": "Action B", "url": "https://example.com/b?q={query}" },
                { "title": "Action C", "url": "https://example.com/c?q={query}" }
            ]
        }
        """
        try manifest.write(to: bundle.appendingPathComponent("openclip.json"), atomically: true, encoding: .utf8)

        await ExtensionManager.shared.loadExtensions(from: tempDir)
        let actions = ExtensionManager.shared.loadedActions

        XCTAssertEqual(actions.count, 3)
        XCTAssertEqual(actions.map(\.id).sorted(), ["pkg.a", "pkg.action.2", "pkg.b"])
    }

    func testOptionValuesDecodeFromValuesKey() throws {
        let json = """
        { "identifier": "choice", "label": "Pick", "type": "select", "values": ["a", "b", "c"] }
        """
        let option = try JSONDecoder().decode(ExtensionOptionMetadata.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(option.values, ["a", "b", "c"])
    }

    func testOptionValuesDecodeFromOptionsKey() throws {
        let json = """
        { "identifier": "choice", "label": "Pick", "type": "select", "options": ["a", "b"] }
        """
        let option = try JSONDecoder().decode(ExtensionOptionMetadata.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(option.values, ["a", "b"])
    }

    func testOptionValuesDecodeFromLegacyOptionsKey() throws {
        let json = """
        { "identifier": "choice", "label": "Pick", "type": "select", "Options": ["a", "b"] }
        """
        let option = try JSONDecoder().decode(ExtensionOptionMetadata.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(option.values, ["a", "b"])
    }

    func testPerActionOptionsDecode() throws {
        let json = """
        {
            "identifier": "pkg",
            "name": "Pkg",
            "actions": [
                {
                    "id": "a",
                    "title": "Action A",
                    "type": "js",
                    "scriptCode": "function action(t) { return t; }",
                    "options": [
                        { "identifier": "prefix", "label": "Prefix", "type": "string", "default": "P:" }
                    ]
                }
            ]
        }
        """
        let manifest = try JSONDecoder().decode(ExtensionMetadata.self, from: json.data(using: .utf8)!)
        let action = try XCTUnwrap(manifest.actions.first)
        XCTAssertEqual(action.options?.count, 1)
        XCTAssertEqual(action.options?.first?.identifier, "prefix")
        XCTAssertEqual(action.options?.first?.defaultValue, "P:")
    }

    func testGroupManifestDecodesNestedSubActions() throws {
        let json = """
        {
            "identifier": "pkg",
            "name": "Pkg",
            "actions": [
                {
                    "id": "grp",
                    "title": "Group",
                    "type": "group",
                    "subActions": [
                        { "id": "s1", "title": "Sub 1", "url": "https://example.com/1?q={query}" },
                        { "id": "s2", "title": "Sub 2", "url": "https://example.com/2?q={query}" }
                    ]
                }
            ]
        }
        """
        let manifest = try JSONDecoder().decode(ExtensionMetadata.self, from: json.data(using: .utf8)!)
        let group = try XCTUnwrap(manifest.actions.first)
        XCTAssertEqual(group.kind, .group)
        XCTAssertEqual(group.subActions?.count, 2)
        XCTAssertEqual(group.subActions?.first?.id, "s1")
        XCTAssertEqual(group.subActions?.first?.kind, .url)
    }

    @MainActor
    func testGroupIsNotRegisteredAsRunnableWhenLoaded() async throws {
        let bundle = tempDir.appendingPathComponent("GroupPkg.openclipext")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let manifest = """
        {
            "identifier": "grppkg",
            "name": "Group Pkg",
            "actions": [
                {
                    "id": "grp",
                    "title": "Group",
                    "type": "group",
                    "subActions": [
                        { "id": "s1", "title": "Sub 1", "url": "https://example.com/1?q={query}" }
                    ]
                },
                { "id": "run", "title": "Runnable", "url": "https://example.com/r?q={query}" }
            ]
        }
        """
        try manifest.write(to: bundle.appendingPathComponent("openclip.json"), atomically: true, encoding: .utf8)

        await ExtensionManager.shared.loadExtensions(from: tempDir)
        let actions = ExtensionManager.shared.loadedActions

        // Phase 8: a group flattens into a structural GroupAction row (not runnable) plus its
        // sub-actions under the ID-prefix convention, alongside the top-level runnable.
        XCTAssertEqual(actions.count, 3)
        XCTAssertEqual(actions.map(\.id), ["grppkg.grp", "grppkg.grp.s1", "grppkg.run"])
        guard let group = actions.first(where: { $0.id == "grppkg.grp" }) else {
            return XCTFail("Group row should be materialized")
        }
        XCTAssertTrue(group is GroupAction, "Group row must be a structural GroupAction, not a runnable action")
        XCTAssertEqual(group.chrome.popupBehavior, .showTransformMenu)
    }
}
