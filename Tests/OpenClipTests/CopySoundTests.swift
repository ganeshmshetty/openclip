import XCTest
@testable import OpenClip

final class CopySoundTests: XCTestCase {
    func testUnknownStoredNameFallsBackToDefault() {
        XCTAssertEqual(CopySound(stored: "nope"), .swoosh)
        XCTAssertEqual(CopySound(stored: "zip"), .swoosh, "The retired Zip sound maps to the default")
        XCTAssertEqual(CopySound(stored: "glass"), .glass)
    }

    func testEverySoundIsShortAudibleAndBounded() {
        for sound in CopySound.allCases {
            let samples = sound.samples()
            XCTAssertGreaterThan(samples.count, 1_000, sound.rawValue)
            XCTAssertLessThan(samples.count, 44_100, sound.rawValue)
            XCTAssertTrue(samples.allSatisfy { abs($0) <= 1 }, sound.rawValue)
            XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 0.05, sound.rawValue)
            XCTAssertEqual(sound.samples(), samples, "Synthesis must be deterministic")
        }
    }
}
