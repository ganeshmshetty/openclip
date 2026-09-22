// DecisionTreeStepperTests.swift
// OpenClipTests

import XCTest
@testable import Core

final class DecisionTreeStepperTests: XCTestCase {
    func testFailClosedOnLowConfidence() {
        let tree = DecisionBuiltinTrees.triage
        let answer = DecisionAnswer(id: "triage.bucket", value: .choice(["Urgent"]), confidence: 0.1)
        let outcome = DecisionTreeStepper.step(tree: tree, currentNodeID: tree.rootID, answer: answer, depth: 0)
        if case .failClosed = outcome {
            // ok
        } else {
            XCTFail("Expected failClosed, got \(outcome)")
        }
    }

    func testCoarseToFineContinue() {
        let tree = DecisionBuiltinTrees.triage
        let answer = DecisionAnswer(id: "triage.bucket", value: .choice(["Urgent"]), confidence: 0.9)
        let outcome = DecisionTreeStepper.step(tree: tree, currentNodeID: tree.rootID, answer: answer, depth: 0)
        XCTAssertEqual(outcome, .continueTo(nodeID: "triage.urgent_detail"))
    }

    func testDepthCap() {
        let tree = DecisionBuiltinTrees.triage
        let answer = DecisionAnswer(id: "triage.bucket", value: .choice(["Urgent"]), confidence: 0.9)
        let outcome = DecisionTreeStepper.step(tree: tree, currentNodeID: tree.rootID, answer: answer, depth: tree.depthCap)
        if case .failClosed = outcome {
            // ok
        } else {
            XCTFail("Expected failClosed at depth cap")
        }
    }

    func testWalkToTerminal() {
        let tree = DecisionBuiltinTrees.triage
        let answers: [String: DecisionAnswer] = [
            "triage.bucket": DecisionAnswer(id: "triage.bucket", value: .choice(["Later"]), confidence: 0.8)
        ]
        let outcome = DecisionTreeStepper.walk(tree: tree, answersByQuestionID: answers)
        XCTAssertEqual(outcome, .terminal(label: "Later"))
    }

    func testNormalizeLabels() {
        XCTAssertEqual(DecisionTreeStepper.normalizeLabel(.noul(true)), "yes")
        XCTAssertEqual(DecisionTreeStepper.normalizeLabel(.noul(false)), "no")
        XCTAssertEqual(DecisionTreeStepper.normalizeLabel(.choice(["Urgent"])), "urgent")
    }
}
