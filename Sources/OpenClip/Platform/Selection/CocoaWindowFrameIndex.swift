import CoreGraphics

/// Precomputed window geometry used to keep AX probes away from OpenClip's own surfaces.
/// Frames and points are in Cocoa screen coordinates: origin at the bottom-left of the primary
/// display, y increasing upward, the convention `NSWindow.frame` and `NSEvent.mouseLocation` use.
internal struct CocoaWindowFrameIndex: Sendable {
    let cocoaFrames: [CGRect]

    init(cocoaFrames: [CGRect]) {
        self.cocoaFrames = cocoaFrames.filter { !$0.isEmpty }
    }

    func contains(cocoaPoint point: CGPoint) -> Bool {
        cocoaFrames.contains { $0.contains(point) }
    }
}
