// QuickLookPresenter.swift
// OpenClip
//
// Manages system Quick Look previewing (QLPreviewPanel) for action result files and snippets.
import Foundation
import AppKit
import QuickLookUI
import Core

public final class QuickLookPresenter: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate, @unchecked Sendable {
    public static let shared = QuickLookPresenter()

    private let lock = NSLock()
    private var _currentURL: URL?

    public var currentURL: URL? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _currentURL
        }
        set {
            lock.lock()
            _currentURL = newValue
            lock.unlock()
        }
    }

    @MainActor
    public func toggle(url: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible && currentURL == url {
            panel.orderOut(nil)
            currentURL = nil
        } else {
            show(url: url)
        }
    }

    @MainActor
    public func show(url: URL) {
        self.currentURL = url
        guard let panel = QLPreviewPanel.shared() else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        if NSClassFromString("XCTestCase") == nil {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    @MainActor
    public func previewText(_ text: String, title: String? = nil) {
        let safeTitle = (title ?? "Result").replacingOccurrences(of: "/", with: "-")
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeTitle).txt")
        do {
            try text.write(to: tempURL, atomically: true, encoding: .utf8)
            show(url: tempURL)
        } catch {
            Log.resultHandler.error("Failed to write Quick Look temporary text file: \(error.localizedDescription)")
        }
    }

    @MainActor
    public func close() {
        if let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
        }
        currentURL = nil
    }

    // MARK: - QLPreviewPanelDataSource

    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        currentURL != nil ? 1 : 0
    }

    public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard let url = currentURL else {
            return NSURL(fileURLWithPath: "")
        }
        return url as NSURL
    }
}
