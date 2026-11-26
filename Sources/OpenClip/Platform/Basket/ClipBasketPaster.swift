// ClipBasketPaster.swift
// OpenClip
//
// Delivers one basket item into the frontmost app. Text goes through OpenSelection's restorable
// replace path; images and file URLs use a bounded pasteboard lease so the user's clipboard is
// restored after the synthetic ⌘V.
import AppKit
import Core
import OpenSelection

@MainActor
protocol ClipBasketPasting: Sendable {
    func paste(_ item: ClipBasketItem, asPlainText: Bool, targetApp: NSRunningApplication?) async throws
}

@MainActor
final class ClipBasketPaster: ClipBasketPasting {
    private let pasteboard: NSPasteboard
    private let keyboardPoster: any KeyboardEventPosting
    private let restoreDelay: TimeInterval

    init(
        pasteboard: NSPasteboard = .general,
        keyboardPoster: any KeyboardEventPosting = SessionEventTapPoster(),
        restoreDelay: TimeInterval = Constants.pasteboardRestoreDelay
    ) {
        self.pasteboard = pasteboard
        self.keyboardPoster = keyboardPoster
        self.restoreDelay = restoreDelay
    }

    func paste(_ item: ClipBasketItem, asPlainText: Bool, targetApp: NSRunningApplication?) async throws {
        switch item.content {
        case .text(let payload):
            let text = payload.plainText ?? ""
            try await OpenSelection.replace(
                with: text,
                html: asPlainText ? nil : payload.html,
                rtf: asPlainText ? nil : payload.rtf,
                flavors: asPlainText ? [] : payload.flavors.map { PasteboardFlavor(type: $0.type, data: $0.data) },
                in: targetApp,
                pasteboard: pasteboard,
                restoreDelay: restoreDelay,
                restorePasteboard: true,
                keyPoster: { [keyboardPoster] keyCode, flags in
                    keyboardPoster.postKey(keyCode: keyCode, flags: flags)
                }
            )

        case .image(let data, let uti, _, _):
            try await pasteMedia {
                let pasteboardItem = NSPasteboardItem()
                let type = NSPasteboard.PasteboardType(uti.isEmpty ? "public.png" : uti)
                pasteboardItem.setData(data, forType: type)
                if let image = NSImage(data: data), let tiff = image.tiffRepresentation, type != .tiff {
                    pasteboardItem.setData(tiff, forType: .tiff)
                }
                pasteboard.writeObjects([pasteboardItem])
            }

        case .files(let urls):
            guard !urls.isEmpty else { return }
            try await pasteMedia {
                pasteboard.writeObjects(urls.map { $0 as NSURL })
            }
        }
    }

    private func pasteMedia(write: () -> Void) async throws {
        let session = try await OpenSelection.ClipboardCoordinator.shared.acquireSession(
            priority: .userAction,
            pasteboard: pasteboard
        )
        defer { session.restoreImmediately() }

        pasteboard.clearContents()
        write()
        OpenSelection.ClipboardCoordinator.shared.markDirty(for: session)

        keyboardPoster.postKey(keyCode: Constants.vVirtualKey, flags: .maskCommand)
        try? await Task.sleep(nanoseconds: UInt64(restoreDelay * 1_000_000_000))
    }
}
