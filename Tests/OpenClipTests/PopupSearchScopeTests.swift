import XCTest
import AppKit
import SwiftUI
@testable import OpenClip
@testable import Core

/// Minimal fake action for palette-scope tests (no real builtin dependencies).
private struct GroupScopeAction: Action {
    let id: String
    var title: String { id }
    var icon: ActionIcon { .symbol("gearshape") }
    var chrome: ActionChrome { ActionChrome(source: .builtin) }
    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .success }
}

@MainActor
final class PopupSearchScopeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TestIsolation.reset()
    }

    func testScopedPaletteBuildsResultsFromChildrenOnly() {
        // Exercise the same path PopupView uses: SubActionResolver over a catalog, wrapped in SearchScope.
        let group = GroupAction(id: "com.pkg.g", title: "G", icon: .symbol("folder"), chrome: ActionChrome(popupBehavior: .showSubActions))
        let catalog: [any Action] = [
            group,
            GroupScopeAction(id: "com.pkg.g.a"),
            GroupScopeAction(id: "com.other.x")
        ]
        let children = SubActionResolver().subActions(of: group, in: catalog)
        XCTAssertEqual(children.map(\.id), ["com.pkg.g.a"])
    }

    @MainActor
    func testScopedViewHostsWithoutCrash() throws {
        let group = GroupAction(id: "com.pkg.g", title: "G", icon: .symbol("folder"), chrome: ActionChrome(popupBehavior: .showSubActions))
        let children = [GroupScopeAction(id: "com.pkg.g.a")]
        let app = AppIdentity(NSRunningApplication.current)
        let context = ActionContext(
            selection: SelectionContext(text: "hi", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default)
        )
        let view = PopupSearchView(
            catalog: [group],
            context: context,
            resultsAbove: false,
            scope: SearchScope(parent: group, children: children),
            onResult: { _ in },
            onExit: {},
            onExitScope: {},
            onRunAI: { _ in }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertNotNil(hosting.rootView) // built without crash
    }

    @MainActor
    func testCustomGroupKeywordsIndexMembersByGroupTitle() {
        let copyAction = GroupScopeAction(id: "builtin.copy")
        let pasteAction = GroupScopeAction(id: "builtin.paste")
        let customGroup = CustomGroupAction(
            id: "vgroup.custom1",
            title: "Clipboard Helpers",
            iconName: "folder",
            memberActionIDs: ["builtin.copy", "builtin.paste"]
        )
        let catalog: [any Action] = [customGroup, copyAction, pasteAction]
        let app = AppIdentity(NSRunningApplication.current)
        let context = ActionContext(
            selection: SelectionContext(text: "hi", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default)
        )
        let view = PopupSearchView(
            catalog: catalog,
            context: context,
            resultsAbove: false,
            scope: nil,
            onResult: { _ in },
            onExit: {},
            onExitScope: {},
            onRunAI: { _ in }
        )
        // Rebuild index and search for "Clipboard"
        let index = PopupSearchView.buildIndex(
            catalog: catalog,
            scope: nil,
            usageRecency: [:],
            presenter: ActionCustomizationManager.shared
        )
        let results = ActionSearch.search("Clipboard", in: index)
        let resultIDs = Set(results.map { $0.id })
        XCTAssertTrue(resultIDs.contains("builtin.copy"), "Custom group member 'builtin.copy' must be found when searching by custom group title")
        XCTAssertTrue(resultIDs.contains("builtin.paste"), "Custom group member 'builtin.paste' must be found when searching by custom group title")
    }

    @MainActor
    func testAIPresetTableIconUsesSparklesSymbol() {
        let aiAction = AIAction(presetID: "proofread", title: "Proofread")
        let presentation = ActionCustomizationManager.shared.presented(aiAction, surface: .table)
        XCTAssertEqual(presentation.icon, .symbol(Constants.defaultAIIconSymbol))
    }
}