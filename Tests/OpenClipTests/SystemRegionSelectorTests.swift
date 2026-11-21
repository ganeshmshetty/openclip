import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OpenClip

final class SystemRegionSelectorTests: XCTestCase {
    func testSystemFailureDescriptionUsesScreencaptureMessage() {
        let reported = SystemRegionSelector.SelectionError.systemFailed(status: 1, message: "cannot write file")
        XCTAssertEqual(reported.errorDescription, "cannot write file")

        let silent = SystemRegionSelector.SelectionError.systemFailed(status: 1, message: "")
        XCTAssertEqual(silent.errorDescription, "screencapture exited with status 1")
    }

    func testDecodedSelectionPixelsSurviveTempFileDeletion() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclip-region-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        let width = 16
        let height = 16
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let sourceContext = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        sourceContext.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        sourceContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let sourceImage = try XCTUnwrap(sourceContext.makeImage())

        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, sourceImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let decoded = try XCTUnwrap(SystemRegionSelector.loadImage(url))
        try FileManager.default.removeItem(at: url)

        let readContext = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        readContext.draw(decoded, in: CGRect(x: 0, y: 0, width: width, height: height))
        let data = try XCTUnwrap(readContext.data).assumingMemoryBound(to: UInt8.self)
        XCTAssertGreaterThan(data[0], 200)
        XCTAssertLessThan(data[1], 60)
        XCTAssertLessThan(data[2], 60)
    }
}
