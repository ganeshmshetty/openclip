import XCTest
@testable import Core

final class AXHelperProtocolTests: XCTestCase {
    func testSelectionPayloadEncodingDecoding() throws {
        let payload = AXSelectionPayload(
            text: "Hello World",
            boundsX: 100,
            boundsY: 200,
            boundsWidth: 300,
            boundsHeight: 400,
            sourceBundleID: "com.apple.Safari"
        )
        
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(AXSelectionPayload.self, from: data)
        
        XCTAssertEqual(decoded.text, "Hello World")
        XCTAssertEqual(decoded.boundsX, 100)
        XCTAssertEqual(decoded.boundsY, 200)
        XCTAssertEqual(decoded.boundsWidth, 300)
        XCTAssertEqual(decoded.boundsHeight, 400)
        XCTAssertEqual(decoded.sourceBundleID, "com.apple.Safari")
    }

    func testKeyCommandPayloadProperties() {
        let cmd = AXKeyCommandPayload(keyCode: 0x08, flagsRaw: 0x100000) // Cmd+C
        XCTAssertEqual(cmd.keyCode, 0x08)
        XCTAssertEqual(cmd.flagsRaw, 0x100000)
    }
}
