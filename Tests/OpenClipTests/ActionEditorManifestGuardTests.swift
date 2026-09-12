// ActionEditorManifestGuardTests.swift
// OpenClip
//
// Pins the Customize outline's node identity (a hot-reloaded manifest that adds options must
// re-render the row) and the action editor's guard against rewriting the parent group's manifest
// entry when the editor was opened for a nested sub-action.
import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class ActionEditorManifestGuardTests: XCTestCase {
    private let packageID = "io.appwrite.openclip.function-runner"
    private var groupID: String { "\(packageID).appwrite" }

    private func subActionNode(_ action: any Action) -> OutlineNode {
        OutlineNode(id: action.id, kind: .extensionSubAction(action: action, parentGroupID: groupID))
    }

    private func endpointOption() -> ExtensionOption {
        ExtensionOption(identifier: "endpoint", label: "Endpoint", defaultValue: "https://cloud.appwrite.io/v1")
    }

    func testSubActionOptionsChangeTheNodeSignature() {
        // A hot-reloaded manifest that adds options must re-render the row, so options are part
        // of the node identity even when title and icon are unchanged.
        let customization = ActionCustomizationManager(settingsStore: MemorySettingsStore())
        let plain = OptionedAction(id: "\(groupID).execute", packageID: packageID, options: [])
        let optioned = OptionedAction(id: "\(groupID).execute", packageID: packageID, options: [endpointOption()])
        let before = OutlineNode(id: plain.id, kind: .extensionSubAction(action: plain, parentGroupID: groupID), customization: customization)
        let after = OutlineNode(id: optioned.id, kind: .extensionSubAction(action: optioned, parentGroupID: groupID), customization: customization)
        XCTAssertNotEqual(before.signature, after.signature)
    }

    func testSubActionOptionIdentifierChangesChangeTheNodeSignature() {
        // A hot-reloaded manifest that replaces options with a different schema of the same count
        // must re-render the row so stale option fields are not retained.
        let customization = ActionCustomizationManager(settingsStore: MemorySettingsStore())
        let first = OptionedAction(id: "\(groupID).execute", packageID: packageID, options: [endpointOption()])
        let second = OptionedAction(
            id: "\(groupID).execute",
            packageID: packageID,
            options: [ExtensionOption(identifier: "apiKey", label: "API Key", type: .secret)]
        )
        let node1 = OutlineNode(id: first.id, kind: .extensionSubAction(action: first, parentGroupID: groupID), customization: customization)
        let node2 = OutlineNode(id: second.id, kind: .extensionSubAction(action: second, parentGroupID: groupID), customization: customization)
        XCTAssertNotEqual(node1.signature, node2.signature)
    }

    // MARK: - Action editor manifest-save guard

    private func groupManifest() -> ExtensionMetadata {
        let sub = ExtensionActionMetadata(id: "execute", title: "Execute Function", script: "main.js", type: "javascript")
        let group = ExtensionActionMetadata(id: "appwrite", title: "Appwrite", type: "group", subActions: [sub])
        return ExtensionMetadata(identifier: packageID, name: "Appwrite Function Runner", actions: [group], options: nil)
    }


    func testLocatedEntryBacksTopLevelAction() {
        let state = LocatedManifest(manifestURL: URL(fileURLWithPath: "/tmp/openclip.json"), manifest: groupManifest(), targetIndex: 0)
        XCTAssertTrue(ActionEditorPage.locatedEntryBacks(actionID: groupID, in: state))
    }

    func testLocatedEntryDoesNotBackNestedSubAction() {
        // The locator resolves a sub-action to its parent's index; saving there would rename the group.
        let state = LocatedManifest(manifestURL: URL(fileURLWithPath: "/tmp/openclip.json"), manifest: groupManifest(), targetIndex: 0)
        XCTAssertFalse(ActionEditorPage.locatedEntryBacks(actionID: "\(groupID).execute", in: state))
    }

    func testLocateManifestResolvesSubActionToParentEntryThatDoesNotBackIt() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let packageDir = tempDir.appendingPathComponent("AppwriteFunctionRunner.openclipext")
        try FileManager.default.createDirectory(at: packageDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try ExtensionManifestStore.writeManifest(groupManifest(), to: packageDir.appendingPathComponent(Constants.manifestFileName))

        let subAction = OptionedAction(id: "\(groupID).execute", packageID: packageID, options: [endpointOption()])
        let located = try XCTUnwrap(ActionEditorPage.locateManifest(for: subAction, in: tempDir))
        XCTAssertEqual(located.targetIndex, 0)
        XCTAssertFalse(ActionEditorPage.locatedEntryBacks(actionID: subAction.id, in: located))
    }
}

/// A sub-action-shaped test double that declares options, mirroring a `javascript` command inside
/// an extension `group` (the factory stamps `.standard` chrome sourced from the package).
private struct OptionedAction: Action, Sendable {
    let id: String
    let title: String = "Execute Function"
    var icon: ActionIcon { .symbol("bolt") }
    let chrome: ActionChrome
    let actionOptions: [ExtensionOption]

    init(id: String, packageID: String, options: [ExtensionOption]) {
        self.id = id
        self.chrome = ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: packageID))
        self.actionOptions = options
    }

    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .none }
}
