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

final class PopupSearchScopeTests: XCTestCase {

    @MainActor
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
}