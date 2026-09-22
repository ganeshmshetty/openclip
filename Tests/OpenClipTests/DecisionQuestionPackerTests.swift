// DecisionQuestionPackerTests.swift
// OpenClipTests

import XCTest
@testable import Core

final class DecisionQuestionPackerTests: XCTestCase {
    func testPacksNoulAndChoice() throws {
        let request = DecisionQuestionPacker.pack(
            state: "Ship Friday?",
            questions: [
                .noul(id: "q1", prompt: "Safe to share?"),
                .choice(id: "q2", prompt: "Bucket?", options: ["Urgent", "Later"])
            ],
            toolID: "smart_action"
        )
        let data = try DecisionQuestionPacker.encodeRequest(request)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"state\":\"Ship Friday?\""))
        XCTAssertTrue(json.contains("\"type\":\"noul\""))
        XCTAssertTrue(json.contains("\"type\":\"choice\""))
        XCTAssertFalse(json.contains("\"min\""), "score bounds are gone from the wire format")
        XCTAssertTrue(json.contains("\"tool_id\":\"smart_action\""))
        XCTAssertTrue(json.contains("Urgent"))
    }

    func testEmptyStateStillEncodes() throws {
        let request = DecisionQuestionPacker.pack(state: "  ", questions: [.noul(id: "a", prompt: "x")])
        let data = try DecisionQuestionPacker.encodeRequest(request)
        XCTAssertFalse(data.isEmpty)
    }
}
