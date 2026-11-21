import Vision
import XCTest
@testable import OpenClip

final class RecognizedTextLayoutTests: XCTestCase {
    private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 0.3, height: CGFloat = 0.05) -> RecognizedTextLayout.Line {
        RecognizedTextLayout.Line(text: text, box: CGRect(x: x, y: y, width: width, height: height))
    }

    func testKeepsVisionColumnOrderInsteadOfInterleavingRows() {
        let lines = [
            line("LEFT one", x: 0.05, y: 0.80), line("LEFT two", x: 0.05, y: 0.70),
            line("RIGHT one", x: 0.55, y: 0.80), line("RIGHT two", x: 0.55, y: 0.70),
        ]
        XCTAssertEqual(RecognizedTextLayout.join(lines), "LEFT one\nLEFT two\nRIGHT one\nRIGHT two")
    }

    func testJoinsAFragmentThatContinuesTheSameLine() {
        let lines = [line("Name:", x: 0.05, y: 0.50, width: 0.1), line("Ada", x: 0.40, y: 0.505, width: 0.1)]
        XCTAssertEqual(RecognizedTextLayout.join(lines), "Name: Ada")
    }

    func testNextLineBelowStartsANewLine() {
        let lines = [line("first", x: 0.05, y: 0.50), line("second", x: 0.40, y: 0.40)]
        XCTAssertEqual(RecognizedTextLayout.join(lines), "first\nsecond")
    }

    func testEmptyInputIsEmpty() {
        XCTAssertEqual(RecognizedTextLayout.join([]), "")
    }

    func testFailuresMapToTheirOwnMessages() {
        XCTAssertEqual(CaptureFailure(SystemRegionSelector.SelectionError.unreadableImage), .captureFailed)
        XCTAssertEqual(CaptureFailure(NSError(domain: VNErrorDomain, code: 9)), .recognitionFailed)
        XCTAssertEqual(CaptureFailure(NSError(domain: "other", code: 1)), .captureFailed)
    }
}
