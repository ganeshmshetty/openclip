// CursorClassifier.swift
// OpenClip
//
// Fast, best-effort classification of macOS cursors into `CursorClass`.
import AppKit
import Core

public struct CursorClassifier {
    /// Maps the current system cursor to its `CursorClass`. Resolves known system cursor singletons
    /// in O(1) without bitmap decoding, falling back to lightweight silhouette analysis for custom cursors.
    @MainActor
    public static var current: CursorClass {
        let cursor = NSCursor.current
        if cursor == .iBeam || cursor == .iBeamCursorForVerticalLayout {
            return .beam
        }
        if cursor == .arrow {
            return .arrow
        }
        if cursor == .pointingHand {
            return .pointingHand
        }
        if cursor == .operationNotAllowed || cursor == .disappearingItem {
            return .other
        }
        return classify(cursor.image)
    }

    /// Classifies a cursor image based on its alpha silhouette.
    public static func classify(_ image: NSImage) -> CursorClass {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cgImage.bitsPerPixel == 32,
              cgImage.bitsPerComponent == 8,
              let data = cgImage.dataProvider?.data,
              let pixels = CFDataGetBytePtr(data),
              let alphaOffset = alphaByteOffset(cgImage) else {
            return .unknown
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        guard width > 0, height > 0 else { return .unknown }

        var minX = width, maxX = -1, minY = height, maxY = -1
        var rowWidths = [Int](repeating: 0, count: height)

        for y in 0..<height {
            let rowOffset = y * bytesPerRow
            for x in 0..<width {
                if pixels[rowOffset + x * 4 + alphaOffset] > 24 {
                    rowWidths[y] += 1
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }

        guard maxX >= minX, maxY >= minY else { return .unknown }

        let bboxWidth = maxX - minX + 1
        let bboxHeight = maxY - minY + 1
        let aspect = Double(bboxHeight) / Double(bboxWidth)
        let activeRows = Array(rowWidths[minY...maxY])
        let maxRowWidth = activeRows.max() ?? 0
        guard maxRowWidth > 0 else { return .unknown }

        // I-beam: tall, thin vertical silhouette
        if aspect >= 1.4, Double(maxRowWidth) <= 0.45 * Double(bboxHeight) {
            return .beam
        }

        let maxRowIndex = Double(activeRows.firstIndex(of: maxRowWidth) ?? 0) / Double(bboxHeight)
        let edgeCount = max(bboxHeight / 4, 1)
        let topAvg = Double(activeRows.prefix(edgeCount).reduce(0, +)) / Double(edgeCount)
        let bottomAvg = Double(activeRows.suffix(edgeCount).reduce(0, +)) / Double(edgeCount)

        // Arrow: diagonal wedge wider at the bottom
        if aspect >= 0.7, aspect <= 1.3,
           maxRowIndex >= 0.65,
           topAvg <= 0.5 * Double(maxRowWidth),
           bottomAvg >= 0.7 * Double(maxRowWidth) {
            return .arrow
        }

        // Pointing hand: pear silhouette (pointed finger at top, widest in middle, wrist below)
        let sorted = activeRows.sorted()
        let medianRowWidth = Double(sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) / 2.0
        if aspect >= 0.95, aspect <= 1.5,
           medianRowWidth >= 0.6 * Double(maxRowWidth),
           maxRowIndex >= 0.35, maxRowIndex <= 0.65,
           topAvg <= 0.6 * Double(maxRowWidth),
           bottomAvg <= 0.9 * Double(maxRowWidth) {
            return .pointingHand
        }

        return .unknown
    }

    private static func alphaByteOffset(_ cgImage: CGImage) -> Int? {
        switch (cgImage.alphaInfo, cgImage.byteOrderInfo) {
        case (.first, .orderDefault), (.first, .order32Big),
             (.premultipliedFirst, .orderDefault), (.premultipliedFirst, .order32Big):
            return 0  // ARGB (big-endian): alpha first.
        case (.last, .orderDefault), (.last, .order32Big),
             (.premultipliedLast, .orderDefault), (.premultipliedLast, .order32Big):
            return 3  // RGBA (big-endian): alpha last.
        case (.first, .order32Little), (.premultipliedFirst, .order32Little):
            return 3  // BGRA (little-endian): alpha last in memory.
        case (.last, .order32Little), (.premultipliedLast, .order32Little):
            return 0  // ABGR (little-endian): alpha first in memory.
        default:
            return nil
        }
    }
}