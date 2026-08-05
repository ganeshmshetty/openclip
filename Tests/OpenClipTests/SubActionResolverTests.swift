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
}