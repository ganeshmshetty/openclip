// CursorClassifier.swift
// OpenClip
//
// Best-effort classification of a cursor image into `CursorClass`.
import AppKit
import Core

public struct CursorClassifier {
    /// Maps a known beam/arrow/pointing-hand cursor bitmap to its class. Anything unrecognized
    /// returns `.unknown`; `.unknown` is never a reason to block retrieval — the default
    /// `SelectionGatePolicy` explicitly allows it, and gating lives in the coordinator.
    public static func classify(_ image: NSImage) -> CursorClass {
        guard let mask = alphaMask(of: image), let metrics = shapeMetrics(of: mask) else {
            return .unknown
        }

        // Beam: a tall, thin stick (the I-beam). No other cursor shape is this narrow
        // for its height.
        if metrics.aspect >= 1.4, Double(metrics.maxRowWidth) <= 0.45 * Double(metrics.bboxHeight) {
            return .beam
        }

        // Arrow: a diagonal wedge whose widest rows sit in the bottom third (the tail),
        // pointy at the top where the hot spot sits.
        if metrics.aspect >= 0.7, metrics.aspect <= 1.3,
            metrics.maxRowIndex >= 0.65,
            metrics.topAvg <= 0.5 * Double(metrics.maxRowWidth),
            metrics.bottomAvg >= 0.7 * Double(metrics.maxRowWidth) {
            return .arrow
        }

        // Pointing hand: a solid "pear" — pointed finger on top, widest in the middle,
        // wrist below.
        if metrics.aspect >= 0.95, metrics.aspect <= 1.5,
            metrics.medianRowWidth >= 0.6 * Double(metrics.maxRowWidth),
            metrics.maxRowIndex >= 0.35, metrics.maxRowIndex <= 0.65,
            metrics.topAvg <= 0.6 * Double(metrics.maxRowWidth),
            metrics.bottomAvg <= 0.9 * Double(metrics.maxRowWidth) {
            return .pointingHand
        }

        return .unknown
    }

    /// The cursor currently shown by the system.
    public static var current: CursorClass {
        classify(NSCursor.current.image)
    }

    // MARK: - Shape analysis

    /// Opacity mask of the image's alpha channel; `nil` when the image has no readable 32-bit
    /// bitmap (e.g. system cursors like the plain arrow expose an empty image).
    private static func alphaMask(of image: NSImage) -> [[Bool]]? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            cgImage.bitsPerPixel == 32,
            let data = cgImage.dataProvider?.data,
            let pixels = CFDataGetBytePtr(data) else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        guard width > 0, height > 0 else { return nil }
        var mask = [[Bool]](repeating: [Bool](repeating: false, count: width), count: height)
        for y in 0..<height {
            for x in 0..<width where pixels[y * bytesPerRow + x * 4 + 3] > 24 {
                mask[y][x] = true
            }
        }
        return mask
    }

    /// Row-profile metrics that describe the cursor's silhouette.
    private struct ShapeMetrics {
        let bboxWidth: Int
        let bboxHeight: Int
        let aspect: Double
        let maxRowWidth: Int
        let medianRowWidth: Double
        let maxRowIndex: Double
        let topAvg: Double
        let bottomAvg: Double
    }

    private static func shapeMetrics(of mask: [[Bool]]) -> ShapeMetrics? {
        let height = mask.count
        guard height > 0 else { return nil }
        let width = mask[0].count
        var area = 0
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where mask[y][x] {
                area += 1
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard area > 0 else { return nil }

        let bboxWidth = maxX - minX + 1
        let bboxHeight = maxY - minY + 1

        var rowWidths = [Int](repeating: 0, count: bboxHeight)
        for y in minY...maxY {
            var count = 0
            for x in minX...maxX where mask[y][x] { count += 1 }
            rowWidths[y - minY] = count
        }

        let maxRowWidth = rowWidths.max() ?? 0
        guard maxRowWidth > 0 else { return nil }

        let maxRowIndex = Double(rowWidths.firstIndex(of: maxRowWidth) ?? 0) / Double(bboxHeight)
        let sorted = rowWidths.sorted()
        let medianRowWidth = Double(sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) / 2

        let edgeCount = max(bboxHeight / 4, 1)
        let topAvg = Double(rowWidths[0..<edgeCount].reduce(0, +)) / Double(edgeCount)
        let bottomAvg = Double(rowWidths[(bboxHeight - edgeCount)..<bboxHeight].reduce(0, +)) / Double(edgeCount)

        return ShapeMetrics(
            bboxWidth: bboxWidth,
            bboxHeight: bboxHeight,
            aspect: Double(bboxHeight) / Double(bboxWidth),
            maxRowWidth: maxRowWidth,
            medianRowWidth: medianRowWidth,
            maxRowIndex: maxRowIndex,
            topAvg: topAvg,
            bottomAvg: bottomAvg
        )
    }
}