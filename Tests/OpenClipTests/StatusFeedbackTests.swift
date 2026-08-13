// StatusFeedbackTests.swift
// OpenClipTests
//
import XCTest
import Core

final class StatusFeedbackTests: XCTestCase {
    func testDefaultIsLoadingFalse() {
        let feedback = StatusFeedback(message: "Copied", style: .success)
        XCTAssertFalse(feedback.isLoading)
    }

    func testIsLoadingRoundTrips() {
        let feedback = StatusFeedback(message: "Opening…", style: .info, isLoading: true)
        XCTAssertTrue(feedback.isLoading)
    }

    func testErrorFeedbackNotLoading() {
        let feedback = StatusFeedback(error: NSError(domain: "t", code: 1))
        XCTAssertFalse(feedback.isLoading)
        XCTAssertEqual(feedback.style, .error)
    }
}
