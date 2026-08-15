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

    func testKeepVisibleDefaultsToFalse() {
        XCTAssertFalse(StatusFeedback(message: "Copied", style: .success).keepVisible)
        XCTAssertFalse(StatusFeedback(error: NSError(domain: "t", code: 1)).keepVisible)
    }

    func testKeepVisibleRoundTrips() {
        XCTAssertTrue(StatusFeedback(message: "Stick", style: .info, keepVisible: true).keepVisible)
    }

    func testKeepVisibleAffectsEquality() {
        XCTAssertNotEqual(
            StatusFeedback(message: "Stick", style: .info, keepVisible: true),
            StatusFeedback(message: "Stick", style: .info, keepVisible: false)
        )
    }
}
