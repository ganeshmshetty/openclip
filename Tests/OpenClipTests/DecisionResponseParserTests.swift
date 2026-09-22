// DecisionResponseParserTests.swift
// OpenClipTests

import XCTest
@testable import Core

final class DecisionResponseParserTests: XCTestCase {
    func testParsesAnswersWithConfidenceAndProbabilities() throws {
        let json = """
        {
          "confidence": 0.81,
          "answers": [
            {
              "id": "share.safe",
              "noul": true,
              "confidence": 0.9,
              "probabilities": {"yes": 0.9, "no": 0.1}
            }
          ]
        }
        """
        let response = try DecisionResponseParser.parse(jsonString: json)
        XCTAssertEqual(response.confidence, 0.81)
        let answer = try XCTUnwrap(response.answer(for: "share.safe"))
        XCTAssertEqual(answer.value, .noul(true))
        XCTAssertEqual(answer.confidence, 0.9)
        XCTAssertEqual(answer.probabilities["yes"], 0.9)
    }

    func testParsesChoiceShorthandAndNumbersAsLabels() throws {
        let json = """
        {"answers":[
          {"id":"a","choice":"Urgent"},
          {"id":"b","value":4},
          {"id":"c","choices":["A","B"]}
        ]}
        """
        let response = try DecisionResponseParser.parse(jsonString: json)
        XCTAssertEqual(response.answers[0].value, .choice(["Urgent"]))
        XCTAssertEqual(response.answers[1].value, .choice(["4"]), "a bare number reads as a label now that score is gone")
        XCTAssertEqual(response.answers[2].value, .choice(["A", "B"]))
    }

    func testParsesNestedDataEnvelope() throws {
        let json = """
        {"data":{"answers":[{"id":"x","value":false}],"confidence":0.55}}
        """
        let response = try DecisionResponseParser.parse(jsonString: json)
        XCTAssertEqual(response.confidence, 0.55)
        XCTAssertEqual(response.answers.first?.value, .noul(false))
    }

    func testUnreadableThrows() {
        XCTAssertThrowsError(try DecisionResponseParser.parse(jsonString: "not-json"))
    }
}
