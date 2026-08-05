import XCTest
@testable import OpenClip
@testable import Core

/// Minimal fake action with a configurable chrome source, for AIToolsAction's children resolution.
private struct FakeAIAction: Action {
    let id: String
    var title: String { id }
    var icon: ActionIcon { .symbol("sparkles") }
    var chrome: ActionChrome
    init(id: String, source: ActionChrome.Source = .ai) {
        self.id = id
        self.chrome = ActionChrome(source: source)
    }
    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .success }
}

final class AIToolsActionSubActionTests: XCTestCase {

    @MainActor
    func testAIToolsResolvesAIPresets() {
        let tools = AIToolsAction()
        let preset1 = FakeAIAction(id: "ai.preset.1")
        let preset2 = FakeAIAction(id: "ai.preset.2")
        let other = FakeAIAction(id: "builtin.copy", source: .builtin)
        let ids = tools.subActions(in: [preset1, preset2, other]).map(\.id)
        XCTAssertEqual(ids, ["ai.preset.1", "ai.preset.2"])
    }
}