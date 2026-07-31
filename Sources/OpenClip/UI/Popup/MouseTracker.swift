import SwiftUI
import AppKit

/// An invisible overlay view that reports continuous mouse position via an NSTrackingArea
/// with .activeAlways — bypassing SwiftUI's onContinuousHover which uses .activeInKeyWindow
/// and silently fails in non-activating NSPanels.
internal struct MouseTracker: NSViewRepresentable {
    var onMove: (CGPoint?) -> Void  // nil = mouse exited

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.onMove = onMove
        return view
    }

    func updateNSView(_ nsView: TrackerView, context: Context) {
        nsView.onMove = onMove
    }

    final class TrackerView: NSView {
        var onMove: ((CGPoint?) -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let old = trackingArea {
                removeTrackingArea(old)
            }
            // .activeAlways fires even when the window is not key — critical for NSPanel
            let area = NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseMoved(with event: NSEvent) {
            // Convert from window coordinates to this view's local coordinates
            let localPoint = convert(event.locationInWindow, from: nil)
            onMove?(localPoint)
        }

        override func mouseEntered(with event: NSEvent) {
            let localPoint = convert(event.locationInWindow, from: nil)
            onMove?(localPoint)
        }

        override func mouseExited(with event: NSEvent) {
            onMove?(nil)
        }
    }
}
