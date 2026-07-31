import SwiftUI
import AppKit

/// An NSViewRepresentable that attaches an NSTrackingArea with `.activeAlways`
/// to guarantee unthrottled 60fps mouseMoved and mouseEntered/Exited events
/// even when the parent NSPanel is not key/active.
public struct ActiveTrackingAreaView: NSViewRepresentable {
    public var onHover: (HoverPhase) -> Void

    public init(onHover: @escaping (HoverPhase) -> Void) {
        self.onHover = onHover
    }

    public func makeNSView(context: Context) -> TrackingNSView {
        let view = TrackingNSView()
        view.onHover = onHover
        return view
    }

    public func updateNSView(_ nsView: TrackingNSView, context: Context) {
        nsView.onHover = onHover
    }

    public final class TrackingNSView: NSView {
        public var onHover: ((HoverPhase) -> Void)?
        private var trackingArea: NSTrackingArea?

        public override func updateTrackingAreas() {
            super.updateTrackingAreas()

            if let existing = trackingArea {
                removeTrackingArea(existing)
            }

            // .activeAlways forces macOS to send mouse events even when panel is not key!
            let options: NSTrackingArea.Options = [
                .mouseEnteredAndExited,
                .mouseMoved,
                .activeAlways,
                .inVisibleRect
            ]

            let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(area)
            self.trackingArea = area
        }

        public override func mouseEntered(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            onHover?(.active(point))
        }

        public override func mouseMoved(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            onHover?(.active(point))
        }

        public override func mouseExited(with event: NSEvent) {
            onHover?(.ended)
        }
    }
}
