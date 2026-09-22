// DecisionBulkSessionTests.swift
// OpenClipTests
//
// The bulk decision card's model: splitting by row vs word and the item count that follows,
// filing each answer into a category, grouping the categories, and the copy payloads.
import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class DecisionBulkSessionTests: XCTestCase {
    private var previousTools: [DecisionToolPreset]!

    private let yesNoTool = DecisionToolPreset(
        id: "edible",
        title: "Edible?",
        questions: [.noul(id: "q", prompt: "Is this edible?")],
        confirmBelowConfidence: 0.7
    )
    private let choiceTool = DecisionToolPreset(
        id: "team",
        title: "Which team?",
        questions: [.choice(id: "q", prompt: "Which team?", options: ["billing", "engineering", "sales"])],
        confirmBelowConfidence: 0.6
    )

    override func setUp() {
        super.setUp()
        TestIsolation.reset()
        previousTools = DecisionServiceManager.shared.tools
        DecisionServiceManager.shared.tools = [yesNoTool, choiceTool]
    }

    override func tearDown() {
        DecisionServiceManager.shared.tools = previousTools
        TestIsolation.reset()
        super.tearDown()
    }

    // MARK: - Items detected

    func testSwitchingBetweenRowAndWordChangesTheItemCount() {
        let session = DecisionBulkSession(text: "apple pie\nrusty nail\nwild mushroom")
        XCTAssertEqual(session.mode, .row, "rows are the default: a pasted list is the common case")
        XCTAssertEqual(session.units.count, 3)
        XCTAssertEqual(session.units.map(\.text), ["apple pie", "rusty nail", "wild mushroom"])

        session.mode = .word
        XCTAssertEqual(session.units.count, 6)
        XCTAssertEqual(session.units.first?.text, "apple")

        session.mode = .row
        XCTAssertEqual(session.units.count, 3)
        XCTAssertFalse(session.wasTruncated)
    }

    func testItemsAreCappedAndTheSessionSaysSo() {
        let session = DecisionBulkSession(
            text: (1...40).map(String.init).joined(separator: "\n"),
            limits: DecisionBulkLimits(maxUnits: 10, budgetSeconds: 60)
        )
        XCTAssertEqual(session.units.count, 10)
        XCTAssertTrue(session.wasTruncated)
    }

    func testOnlyUsableToolsAreOfferedAndTheFirstIsSelected() {
        DecisionServiceManager.shared.tools = [
            DecisionToolPreset(id: "off", title: "Disabled", questions: [.noul(id: "q", prompt: "?")], isEnabled: false),
            DecisionToolPreset(id: "empty", title: "No question", questions: []),
            yesNoTool,
        ]
        let session = DecisionBulkSession(text: "a\nb")
        XCTAssertEqual(session.availableTools.map(\.id), ["edible"])
        XCTAssertEqual(session.toolID, "edible")
        XCTAssertEqual(session.tool?.id, "edible")
    }

    // MARK: - Categorising

    func testYesNoAnswersFileIntoYesNoAndUnsure() {
        func category(_ value: DecisionAnswerValue, _ confidence: Double) -> String {
            DecisionBulkSession.category(
                for: DecisionResponse(answers: [DecisionAnswer(id: "q", value: value, confidence: confidence)], confidence: confidence),
                tool: yesNoTool
            )
        }
        XCTAssertEqual(category(.noul(true), 0.95), DecisionBulkSession.yesLabel)
        XCTAssertEqual(category(.noul(false), 0.95), DecisionBulkSession.noLabel)
        XCTAssertEqual(category(.noul(true), 0.4), DecisionBulkSession.unsureLabel, "under the tool's threshold")
        XCTAssertEqual(
            DecisionBulkSession.category(for: DecisionResponse(answers: []), tool: yesNoTool),
            DecisionBulkSession.unsureLabel
        )
    }

    func testChoiceAnswersSnapBackToTheDeclaredOptionLabels() {
        func category(_ labels: [String], _ confidence: Double) -> String {
            DecisionBulkSession.category(
                for: DecisionResponse(answers: [DecisionAnswer(id: "q", value: .choice(labels), confidence: confidence)], confidence: confidence),
                tool: choiceTool
            )
        }
        XCTAssertEqual(category(["billing"], 0.9), "billing")
        XCTAssertEqual(category(["BILLING"], 0.9), "billing", "casing from the model must not split a category")
        XCTAssertEqual(category(["billing"], 0.3), DecisionBulkSession.unsureLabel)
        XCTAssertEqual(category(["legal"], 0.9), "legal", "an answer outside the list is kept, never dropped")
    }

    func testCategoryLabelsFollowTheSelectedTool() {
        let session = DecisionBulkSession(text: "a\nb")
        session.toolID = "edible"
        XCTAssertEqual(session.categoryLabels, [DecisionBulkSession.yesLabel, DecisionBulkSession.noLabel, DecisionBulkSession.unsureLabel])

        session.toolID = "team"
        XCTAssertEqual(session.categoryLabels, ["billing", "engineering", "sales", DecisionBulkSession.unsureLabel])
    }

    // MARK: - Sections and copying

    func testSectionsGroupItemsAndCopyPayloadsAreCategorised() async throws {
        let session = DecisionBulkSession(text: "apple\nnail\nmushroom")
        session.toolID = "edible"

        // Drive a run through a mock provider: apple yes, nail no, mushroom unsure (low confidence).
        let answers: [String: (Bool, Double)] = [
            "apple": (true, 0.95),
            "nail": (false, 0.95),
            "mushroom": (true, 0.3),
        ]
        let mock = ScriptedDecisionProvider { state in
            let (value, confidence) = answers[state] ?? (true, 0.9)
            return DecisionResponse(answers: [DecisionAnswer(id: "q", value: .noul(value), confidence: confidence)], confidence: confidence)
        }
        let manager = DecisionServiceManager.shared
        let previousOverride = manager.providerOverride
        manager.providerOverride = mock
        defer { manager.providerOverride = previousOverride }

        session.run()
        try await waitUntil { session.phase == .finished }

        XCTAssertEqual(session.completed, 3)
        XCTAssertEqual(session.progressFraction, 1.0)
        let sections = session.sections
        XCTAssertEqual(sections.map(\.label), [DecisionBulkSession.yesLabel, DecisionBulkSession.noLabel, DecisionBulkSession.unsureLabel])
        XCTAssertEqual(sections[0].items, ["apple"])
        XCTAssertEqual(sections[1].items, ["nail"])
        XCTAssertEqual(sections[2].items, ["mushroom"])

        XCTAssertEqual(session.copyText(for: sections[0]), "apple")
        let all = session.copyAllText()
        XCTAssertTrue(all.contains("## \(DecisionBulkSession.yesLabel) (1)\napple"), all)
        XCTAssertTrue(all.contains("## \(DecisionBulkSession.noLabel) (1)\nnail"), all)
        XCTAssertFalse(all.contains("(0)"), "empty categories stay out of the copied text")
    }

    func testChangingModeOrToolClearsAPreviousRun() async throws {
        let session = DecisionBulkSession(text: "apple\nnail")
        let mock = ScriptedDecisionProvider { _ in
            DecisionResponse(answers: [DecisionAnswer(id: "q", value: .noul(true), confidence: 0.99)], confidence: 0.99)
        }
        let manager = DecisionServiceManager.shared
        let previousOverride = manager.providerOverride
        manager.providerOverride = mock
        defer { manager.providerOverride = previousOverride }

        session.run()
        try await waitUntil { session.phase == .finished }
        XCTAssertEqual(session.completed, 2)

        session.mode = .word
        XCTAssertEqual(session.phase, .idle, "a different split needs a fresh run")
        XCTAssertEqual(session.completed, 0)
        XCTAssertTrue(session.sections.allSatisfy(\.items.isEmpty))
    }

    // MARK: - The entry point

    func testBulkActionOpensTheCardAndNeverDismissesThePopup() async throws {
        let action = DecisionBulkAction()
        XCTAssertEqual(action.id, "builtin.decisionBulk")
        XCTAssertEqual(action.chrome.source, .decision)
        XCTAssertTrue(ActionIdentity.isDecisionPreset(action), "it groups with the Decision tools")

        let context = ActionContext(selection: SelectionContext(text: "a\nb"))
        guard case .decisionBulk(let text) = try await action.perform(context) else {
            return XCTFail("bulk must open the card")
        }
        XCTAssertEqual(text, "a\nb")
        XCTAssertFalse(ActionResult.decisionBulk("a").dismissesPopup)
        XCTAssertFalse(ActionResult.decisionBulk("a").containsToast)
    }

    func testBulkIsTheLastEntryInTheDecisionGroup() {
        let settingsStore = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: settingsStore)
        let coordinator = ActionCoordinator(registry: registry, settingsStore: settingsStore)
        for tool in DecisionServiceManager.shared.tools {
            coordinator.register(action: DecisionAction(toolID: tool.id, title: tool.title, symbolName: tool.symbolName))
        }
        coordinator.register(action: DecisionBulkAction())

        let launcher = DecisionToolsAction()
        let children = launcher.subActions(in: coordinator.actions)
        XCTAssertEqual(children.last?.id, DecisionBulkAction.actionID)
        XCTAssertEqual(children.count, DecisionServiceManager.shared.tools.count + 1)
    }

    // MARK: - Helpers

    private func waitUntil(timeout: TimeInterval = 5, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { throw XCTSkip("timed out waiting for the bulk run") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

/// A provider that answers from a closure keyed on the unit's text, so a bulk run is deterministic.
@MainActor
final class ScriptedDecisionProvider: DecisionProvider {
    let type: DecisionProviderType = .laya
    private let answer: @MainActor (String) -> DecisionResponse

    init(answer: @escaping @MainActor (String) -> DecisionResponse) {
        self.answer = answer
    }

    func availability() async -> DecisionProviderAvailability { .available }

    func decide(_ request: DecisionRequest) async throws -> DecisionResponse {
        answer(request.state)
    }
}
