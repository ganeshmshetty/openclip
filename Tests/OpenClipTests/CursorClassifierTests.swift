import XCTest
import AppKit
@testable import OpenClip

final class CursorClassifierTests: XCTestCase {
    func testBlankImageClassifiesUnknown() {
        let blank = makeCursorImage(width: 16, height: 16) { _, _ in false }
        XCTAssertEqual(CursorClassifier.classify(blank), .unknown)
    }

    func testBeamShapeClassifiesBeam() {
        // I-beam: a thin vertical bar with small horizontal caps at top and bottom.
        let beam = makeCursorImage(width: 16, height: 32) { x, y in
            if y < 3 || y >= 29 {
                return x >= 5 && x <= 10
            }
            return x >= 7 && x <= 8
        }
        XCTAssertEqual(CursorClassifier.classify(beam), .beam)
    }

    func testArrowShapeClassifiesArrow() {
        // Diagonal wedge: pointy at the top (the hot spot), widening toward the bottom tail.
        let arrow = makeCursorImage(width: 16, height: 16) { x, y in
            x <= y
        }
        XCTAssertEqual(CursorClassifier.classify(arrow), .arrow)
    }

    func testPointingHandShapeClassifiesPointingHand() {
        // Pear silhouette: narrow finger up top, widest in the middle, narrow wrist below.
        let widths = [3, 4, 5, 6, 9, 12, 14, 14, 14, 13, 12, 10, 8, 7, 6, 5]
        let hand = makeCursorImage(width: 16, height: 16) { x, y in
            let w = widths[y]
            let start = (16 - w) / 2
            return x >= start && x < start + w
        }
        XCTAssertEqual(CursorClassifier.classify(hand), .pointingHand)
    }

    func testRealSystemPointingHandClassifiesPointingHand() {
        // The system pointing-hand cursor ships a real bitmap, unlike arrow/iBeam.
        XCTAssertEqual(CursorClassifier.classify(NSCursor.pointingHand.image), .pointingHand)
    }

    func testSystemArrowAndIBeamCursorsDegradeSafely() {
        // Whether these system cursors expose a bitmap is host-dependent: when one is available
        // the classifier must recognize the real shape, and when not it must return `.unknown`
        // rather than guess or crash.
        let arrow = CursorClassifier.classify(NSCursor.arrow.image)
        XCTAssertTrue(arrow == .arrow || arrow == .unknown, "unexpected arrow classification \(arrow)")
        let beam = CursorClassifier.classify(NSCursor.iBeam.image)
        XCTAssertTrue(beam == .beam || beam == .unknown, "unexpected beam classification \(beam)")
    }

    // MARK: - Fixture builder

    /// Builds a small cursor-shaped `NSImage` from an opaque-pixel predicate so the
    /// classifier's alpha-mask analysis is fully deterministic.
    private func makeCursorImage(width: Int, height: Int, opaque: (Int, Int) -> Bool) -> NSImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        for y in 0..<height {
            for x in 0..<width where opaque(x, y) {
                let offset = y * bytesPerRow + x * 4
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = 255
            }
        }
        let context = pixels.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }
        let cgImage = context!.makeImage()!
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
}