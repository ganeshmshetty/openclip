import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class ExtensionUninstallOptionsTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
    }

    func testUninstallFromChildClearsNamedIndexedAndDottedSubactionOptions() async throws {
        try await assertUninstallClearsOptions(
            groupID: "tools", expectedGroupID: "com.test.uninstall.tools",
            uninstallID: "com.test.uninstall.tools.named"
        )
    }

    func testUninstallClearsGeneratedGroupOptionsWithoutLoadedActions() async throws {
        try await assertUninstallClearsOptions(
            groupID: nil, expectedGroupID: "com.test.uninstall.action.0",
            uninstallID: "com.test.uninstall", unloadFirst: true
        )
    }

    func testUninstallClearsOptionsForGroupOutsidePackageNamespace() async throws {
        try await assertUninstallClearsOptions(
            groupID: "org.vendor.tools", expectedGroupID: "org.vendor.tools",
            uninstallID: "org.vendor.tools"
        )
    }

    private func assertUninstallClearsOptions(
        groupID: String?, expectedGroupID: String, uninstallID: String, unloadFirst: Bool = false
    ) async throws {
        let manager = ExtensionManager.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("openclip-uninstall-\(UUID())")
        let source = root.appendingPathComponent("source/Fixture.openclipext")
        let installedDirectory = root.appendingPathComponent("installed")
        let secretsURL = root.appendingPathComponent("secrets.json")
        SecretStore.setFileURLForTesting(secretsURL)
        defer {
            TestIsolation.reset()
            SecretStore.setFileURLForTesting(Constants.secretsFileURL)
            try? FileManager.default.removeItem(at: root)
        }

        let sharedOptions: [[String: Any]] = [
            ["identifier": "sharedEndpoint", "label": "Shared endpoint", "type": "string", "default": "DEFAULT"],
            ["identifier": "sharedToken", "label": "Shared token", "type": "secret"]
        ]
        let actionOptions: [[String: Any]] = [
            ["identifier": "endpoint", "label": "Endpoint", "type": "string", "default": "DEFAULT"],
            ["identifier": "apiKey", "label": "API key", "type": "secret"]
        ]
        func command(id: String? = nil) -> [String: Any] {
            var value: [String: Any] = [
                "title": "Command", "type": "javascript", "output": "text",
                "scriptCode": "function action() { return 'fixture'; }", "options": actionOptions
            ]
            if let id { value["id"] = id }
            return value
        }
        var group: [String: Any] = [
            "title": "Tools", "type": "group",
            "subActions": [command(id: "named"), command(), command(id: "vendor.command")]
        ]
        if let groupID { group["id"] = groupID }
        let manifest: [String: Any] = [
            "identifier": "com.test.uninstall", "name": "Uninstall fixture",
            "options": sharedOptions, "actions": [group, command(id: "standalone")]
        ]
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: manifest).write(to: source.appendingPathComponent("openclip.json"))

        let settings = MemorySettingsStore()
        let options = SecretActionOptionStore(settingsStore: settings)
        manager.actionFactory = DefaultActionFactory(optionStore: options)
        manager.optionReader = options
        manager.optionWriter = options
        let installed = try await manager.installExtension(from: source, targetDir: installedDirectory)
        let configuredActions = installed.filter { !$0.actionOptions.isEmpty }
        XCTAssertEqual(Set(configuredActions.map(\.id)), Set([
            "\(expectedGroupID).named", "\(expectedGroupID).1", "\(expectedGroupID).vendor.command",
            "com.test.uninstall.standalone"
        ]))
        for action in configuredActions {
            XCTAssertEqual(Set(action.actionOptions.map(\.identifier)), Set(["sharedEndpoint", "sharedToken", "endpoint", "apiKey"]))
            for option in action.actionOptions {
                let value = "saved-\(action.id)-\(option.identifier)"
                options.setStringValue(value, actionID: action.id, option: option)
                XCTAssertEqual(options.stringValue(actionID: action.id, option: option), value)
            }
        }

        let unrelatedID = "com.test.uninstall.neighbor.tools.named"
        let unrelatedOptions = try XCTUnwrap(configuredActions.first).actionOptions
        for option in unrelatedOptions {
            options.setStringValue("keep", actionID: unrelatedID, option: option)
        }
        XCTAssertTrue(SecretStore.set("keep-cloud-key", account: "aiCloudAPIKey"))

        if unloadFirst {
            manager.reset()
            manager.optionWriter = options
        }
        try await manager.uninstallExtension(actionID: uninstallID, targetDir: installedDirectory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: installedDirectory.appendingPathComponent(source.lastPathComponent).path))
        for action in configuredActions {
            for option in action.actionOptions {
                XCTAssertEqual(options.stringValue(actionID: action.id, option: option), option.defaultValue ?? "", "\(action.id):\(option.identifier)")
                if option.type == .secret {
                    XCTAssertNil(SecretStore.get(account: ActionOptionKey.defaultsKey(actionID: action.id, optionID: option.identifier)))
                }
            }
        }
        for option in unrelatedOptions {
            XCTAssertEqual(options.stringValue(actionID: unrelatedID, option: option), "keep")
        }
        XCTAssertEqual(SecretStore.get(account: "aiCloudAPIKey"), "keep-cloud-key")
        let remainingSecrets = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: secretsURL)) as? [String: String])
        let expectedSecretKeys = unrelatedOptions.filter { $0.type == .secret }.map {
            ActionOptionKey.defaultsKey(actionID: unrelatedID, optionID: $0.identifier)
        } + ["aiCloudAPIKey"]
        XCTAssertEqual(Set(remainingSecrets.keys), Set(expectedSecretKeys))

        manager.actionFactory = DefaultActionFactory(optionStore: options)
        let reinstalled = try await manager.installExtension(from: source, targetDir: installedDirectory)
        for action in reinstalled {
            for option in action.actionOptions {
                XCTAssertEqual(options.stringValue(actionID: action.id, option: option), option.defaultValue ?? "")
            }
        }
    }
}
