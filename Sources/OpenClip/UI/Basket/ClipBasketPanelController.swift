// ClipBasketPanelController.swift
// OpenClip
//
// Owns the Clip Basket panel's lifecycle, content sizing, placement and draggable position. The
// panel keeps its top-left corner while the pill expands or collapses.
import AppKit
import SwiftUI
import Core

@MainActor
final class ClipBasketPanelController {
    private(set) var panel = ClipBasketPanel()
    private let settingsStore: any SettingsStore

    var isShowing: Bool { panel.isVisible }

    init(settingsStore: any SettingsStore = DefaultSettingsStore.shared) {
        self.settingsStore = settingsStore
    }

    func show(
        store: ClipBasketStore,
        onPasteNext: @escaping @MainActor () -> Void,
        onPasteAll: @escaping @MainActor () -> Void,
        onPasteItem: @escaping @MainActor (UUID) -> Void,
        onClear: @escaping @MainActor () -> Void,
        onClose: @escaping @MainActor () -> Void
    ) {
        let view = ClipBasketView(
            store: store,
            onPasteNext: onPasteNext,
            onPasteAll: onPasteAll,
            onPasteItem: onPasteItem,
            onClear: onClear,
            onClose: onClose,
            onDrag: { [weak self] delta, isFinal in
                self?.movePanel(by: delta, isFinal: isFinal)
            },
            onContentSizeChange: { [weak self] size in
                self?.resizePanel(to: size)
            }
        )

        let hosting = ClipBasketPanel.ContentView(rootView: AnyView(view))
        panel.contentView = hosting
        hosting.layoutSubtreeIfNeeded()

        let size = normalizedSize(hosting.fittingSize)
        let screen = activeScreen()
        let origin = savedOrigin(for: size, screen: screen) ?? defaultOrigin(for: size, screen: screen)
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        panel.orderFrontRegardless()
        Log.basket.debug(
            "panel placed frame=\(NSStringFromRect(self.panel.frame), privacy: .public) visible=\(self.panel.isVisible, privacy: .public) activeSpace=\(self.panel.isOnActiveSpace, privacy: .public)"
        )
    }

    func hide() {
        guard isShowing || panel.contentView != nil else { return }
        panel.orderOut(nil)
        panel.contentView = nil
    }

    func resizePanel(to proposedSize: CGSize) {
        let size = normalizedSize(proposedSize)
        guard panel.isVisible else {
            panel.setFrame(NSRect(origin: panel.frame.origin, size: size), display: false)
            return
        }
        let current = panel.frame
        guard abs(size.width - current.width) > 0.5 || abs(size.height - current.height) > 0.5 else { return }

        var frame = NSRect(
            x: current.minX,
            y: current.maxY - size.height,
            width: size.width,
            height: size.height
        )
        frame.origin = clampedOrigin(for: frame, on: panel.screen ?? activeScreen())
        panel.setFrame(frame, display: true)
    }

    func movePanel(by delta: CGSize, isFinal: Bool) {
        guard panel.isVisible else { return }
        let current = panel.frame
        var frame = current.offsetBy(dx: delta.width, dy: delta.height)
        frame.origin = clampedOrigin(for: frame, on: panel.screen ?? activeScreen())
        panel.setFrame(frame, display: true)
        if isFinal {
            persistOrigin(for: panel.frame, screen: panel.screen ?? activeScreen())
        }
    }

    private func normalizedSize(_ proposed: CGSize) -> CGSize {
        let inset = PopupMetrics.popupShadowInset * 2
        let scale = PopupMetrics.scaleMultiplier(for: settingsStore.get(.popupScale))
        let width = proposed.width > 1
            ? ceil(proposed.width)
            : ClipBasketMetrics.collapsedWidth * scale + inset
        let height = proposed.height > 1
            ? min(ceil(proposed.height), ClipBasketMetrics.maxHeight * scale + inset)
            : ClipBasketMetrics.collapsedHeight * scale + inset
        return CGSize(width: width, height: height)
    }

    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    private func defaultOrigin(for size: CGSize, screen: NSScreen?) -> CGPoint {
        let mouse = NSEvent.mouseLocation
        let frame = NSRect(
            x: mouse.x - size.width / 2,
            y: mouse.y - size.height - 12,
            width: size.width,
            height: size.height
        )
        return clampedOrigin(for: frame, on: screen)
    }

    private func clampedOrigin(for frame: NSRect, on screen: NSScreen?) -> CGPoint {
        guard let visible = screen?.visibleFrame else { return frame.origin }
        let padding = PopupMetrics.popupPadding
        let maxX = visible.maxX - frame.width - padding
        let maxY = visible.maxY - frame.height - padding
        return CGPoint(
            x: min(max(frame.minX, visible.minX + padding), max(maxX, visible.minX + padding)),
            y: min(max(frame.minY, visible.minY + padding), max(maxY, visible.minY + padding))
        )
    }

    private func savedOrigin(for size: CGSize, screen: NSScreen?) -> CGPoint? {
        let raw = settingsStore.get(.clipBasketPanelOrigin)
        guard !raw.isEmpty else { return nil }
        let parts = raw.split(separator: ",")
        guard parts.count == 2,
              let normalizedX = Double(parts[0]),
              let normalizedY = Double(parts[1]),
              let visible = screen?.visibleFrame else { return nil }
        let x = visible.minX + CGFloat(min(max(normalizedX, 0), 1)) * max(visible.width - size.width, 0)
        let y = visible.minY + CGFloat(min(max(normalizedY, 0), 1)) * max(visible.height - size.height, 0)
        return clampedOrigin(for: NSRect(origin: CGPoint(x: x, y: y), size: size), on: screen)
    }

    private func persistOrigin(for frame: NSRect, screen: NSScreen?) {
        guard let visible = screen?.visibleFrame else { return }
        let x = max(visible.width - frame.width, 1)
        let y = max(visible.height - frame.height, 1)
        let normalizedX = (frame.minX - visible.minX) / x
        let normalizedY = (frame.minY - visible.minY) / y
        settingsStore.set(
            .clipBasketPanelOrigin,
            value: "\(String(format: "%.4f", normalizedX)),\(String(format: "%.4f", normalizedY))"
        )
    }
}
