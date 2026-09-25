import SwiftUI
import AppKit
import QuickLookUI

struct QuickLookPreviewView: NSViewRepresentable {
    let url: URL

    final class Coordinator {
        var url: URL?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        guard let view = QLPreviewView(frame: NSRect(x: 0, y: 0, width: 320, height: 200), style: .normal) else {
            return NSView()
        }
        view.autostarts = true
        view.shouldCloseWithWindow = false
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let preview = nsView as? QLPreviewView, context.coordinator.url != url else { return }
        context.coordinator.url = url
        preview.previewItem = url as NSURL
        preview.refreshPreviewItem()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        (nsView as? QLPreviewView)?.close()
    }
}
