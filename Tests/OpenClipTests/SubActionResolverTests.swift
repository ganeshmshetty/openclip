import XCTest
@testable import Core

/// Minimal fake Action so resolver tests don't depend on real builtins.
private struct FakeAction: Action {
    let id: String
    var chrome: ActionChrome
    var title: String { id }
    var icon: ActionIcon { .symbol("gearshape") }
    init(id: String, chrome: ActionChrome = ActionChrome(source: .builtin)) {
        self.id = id
        self.chrome = chrome
    }
    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .success }
}

final class SubActionResolverTests: XCTestCase {

    @MainActor
    func testNonProvidingParentReturnsEmpty() {
        let resolver = SubActionResolver()
        let parent = FakeAction(id: "plain")
        XCTAssertEqual(resolver.subActions(of: parent, in: []).map(\.id), [])
    }

    @MainActor
    func testGroupResolvesChildrenByIDPrefix() {
        let group = GroupAction(id: "com.pkg.group", title: "G", icon: .symbol("folder"), chrome: ActionChrome(popupBehavior: .showSubActions))
        let sub1 = FakeAction(id: "com.pkg.group.a")
        let sub2 = FakeAction(id: "com.pkg.group.b")
        let unrelated = FakeAction(id: "com.other.x")
        // Drop a completion pseudo-action and an AI launcher from the children pool to mirror the
        // real catalog shape.
        let launcher = FakeAction(id: "builtin.aiTools", chrome: ActionChrome(launchesAI: true))
        let resolver = SubActionResolver()

        let ids = resolver.subActions(of: group, in: [group, sub1, sub2, unrelated, launcher]).map(\.id)
        XCTAssertEqual(ids, ["com.pkg.group.a", "com.pkg.group.b"])
    }
}