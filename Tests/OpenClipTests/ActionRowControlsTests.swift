// ActionRowControlsTests.swift
// OpenClip
//
// Pins which trailing controls an Actions-tab row exposes. A command inside a multi-command
// extension (an extension-group sub-action) gets the settings cog when — and only when — it
// declares options, and never the delete control. It also pins the edit sheet's guard against
// rewriting the parent group's manifest entry when the sheet was opened for a nested sub-action.
import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class ActionRowControlsTests: XCTestCase {
    private let packageID = "io.appwrite.openclip.function-runner"
    private var groupID: String { "\(packageID).appwrite" }

    private func subActionNode(_ action: any Action) -> OutlineNode {
        OutlineNode(id: action.id, kind: .extensionSubAction(action: action, parentGroupID: groupID))
    }

    private func endpointOption() -> ExtensionOption {
        ExtensionOption(identifier: "endpoint", label: "Endpoint", defaultValue: "https://cloud.appwrite.io/v1")
    }

    // MARK: - Sub-action rows

    func testSubActionWithOptionsShowsSettingsButNotDelete() {
        let action = OptionedAction(id: "\(groupID).execute", packageID: packageID, options: [endpointOption()])
        let controls = subActionNode(action).rowControls
        XCTAssertTrue(controls.contains(.settings), "A command that declares options needs the settings cog")
        XCTAssertFalse(controls.contains(.delete), "A command is removed with its package, never on its own")
    }

    func testSubActionWithoutOptionsShowsSettingsButNotDelete() {
        let action = OptionedAction(id: "\(groupID).plain", packageID: packageID, options: [])
        let controls = subActionNode(action).rowControls
        XCTAssertTrue(controls.contains(.settings), "A command without options still needs settings for custom title/icon")
        XCTAssertFalse(controls.contains(.delete), "A command is removed with its package, never on its own")
    }

    func testDecoratedSubActionForwardsOptionsToControls() {
        // The factory wraps sub-actions that declare keywords / delivery / menu relevance; the cog
        // decision must see the options through the wrapper.
        let base = OptionedAction(id: "\(groupID).execute", packageID: packageID, options: [endpointOption()])
        let wrapped = KeywordDecoratedAction(base: base, keywords: ["run"])
        XCTAssertTrue(subActionNode(wrapped).rowControls.contains(.settings))
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

    // MARK: - Other rows

    func testTopLevelRowsKeepBothControls() {
        let standalone = OptionedAction(id: "\(packageID).single", packageID: packageID, options: [])
        XCTAssertEqual(OutlineNode(id: standalone.id, kind: .standaloneAction(standalone)).rowControls, .all)

        let group = GroupAction(
            id: groupID,
            title: "Appwrite",
            icon: .symbol("bolt"),
            chrome: ActionChrome(rowStyle: .actionGroup, popupBehavior: .showSubActions, source: .extensionPkg(packageID: packageID))
        )
        XCTAssertEqual(OutlineNode(id: group.id, kind: .extensionGroup(group)).rowControls, .all)
    }

    func testPackageHeaderHasNoControls() {
        let node = OutlineNode(id: "header:\(packageID)", kind: .packageHeader(packageID: packageID, title: "Appwrite", gatedReason: nil))
        XCTAssertTrue(node.rowControls.isEmpty)
    }

    // MARK: - Edit sheet manifest-save guard

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
