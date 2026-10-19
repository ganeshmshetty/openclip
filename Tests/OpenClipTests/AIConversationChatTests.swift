import XCTest
@testable import OpenClip

final class AIConversationChatTests: XCTestCase {
    private func conversation(steps: Int) -> AIConversation {
        var c = AIConversation(original: "orig", steps: [.init(instruction: "ACTION", result: "r0")])
        for i in 1..<max(steps, 1) { c = c.appending(instruction: "i\(i)", result: "r\(i)") }
        return c
    }

    func testFirstResultAlternatesOriginalResultInstruction() {
        let messages = conversation(steps: 1).chatMessages(instruction: "shorter")
        XCTAssertEqual(messages.map(\.role), [.user, .assistant, .user])
        XCTAssertEqual(messages[0].content, "<text>\norig\n</text>")
        XCTAssertEqual(messages[1].content, "<result>\nr0\n</result>")
        XCTAssertEqual(messages[2].content, "shorter")
    }

    func testLaterStepsAddTurnsInOrder() {
        let messages = conversation(steps: 3).chatMessages(instruction: "now")
        XCTAssertEqual(messages.map(\.role), [.user, .assistant, .user, .assistant, .user, .assistant, .user])
        XCTAssertEqual(messages[2].content, "i1")
        XCTAssertEqual(messages.last?.content, "now")
    }

    func testOverBudgetDropsOldestStepsButKeepsLatest() {
        let big = String(repeating: "x", count: 9_000)
        var c = AIConversation(original: big, steps: [.init(instruction: "ACTION", result: big)])
        c = c.appending(instruction: "i1", result: big).appending(instruction: "i2", result: "tail")
        let messages = c.chatMessages(instruction: "now")
        XCTAssertLessThanOrEqual(messages.reduce(0) { $0 + $1.content.count }, AIConversation.maxChatCharacters)
        XCTAssertEqual(messages.map(\.role).first, .user)
        XCTAssertTrue(messages.contains { $0.content.contains("tail") })
        XCTAssertTrue(messages[0].content.hasSuffix("\n\ni2") || messages[0].content.contains("i1"))
        XCTAssertEqual(messages.last?.content, "now")
    }

    func testRequestUsesActionPromptAsTaskAndNilWithoutSteps() {
        let c = conversation(steps: 2)
        let request = c.followUpRequest(instruction: "x", customGuidelines: nil)
        XCTAssertTrue(request?.system.contains("ACTION") == true)
        XCTAssertTrue(request?.system.contains("follow-up instruction") == true)
        XCTAssertNil(AIConversation(original: "o", steps: []).followUpRequest(instruction: "x", customGuidelines: nil))
    }
}
