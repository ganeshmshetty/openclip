// ActionIconImageHelper.swift
// OpenClip
//
// Converts domain ActionIcon models into standard NSImage assets for AppKit menus and status items.
import AppKit
import Core

@MainActor
public enum ActionIconImageHelper {
    public static func menuImage(for icon: ActionIcon) -> NSImage? {
        let targetSize = NSSize(width: 14, height: 14)
        switch icon {
        case .symbol(let name):
            let symbolName = name.isEmpty ? "star" : name
            if symbolName.contains(":") {
                let img = NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: nil)
                img?.size = targetSize
                img?.isTemplate = true
                return img
            }
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config)
            img?.size = targetSize
            img?.isTemplate = true
            return img
        case .local(let url):
            if let img = LocalIconCache.shared.image(for: url) {
                let copy = img.copy() as? NSImage ?? img
                copy.size = targetSize
                copy.isTemplate = true
                return copy
            }
            let img = NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: nil)
            img?.size = targetSize
            img?.isTemplate = true
            return img
        case .text(let text):
            let font = NSFont.systemFont(ofSize: 11, weight: .bold)
            let str = NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor
            ])
            let img = NSImage(size: targetSize, flipped: false) { rect in
                let strSize = str.size()
                let drawRect = NSRect(
                    x: (rect.width - strSize.width) / 2,
                    y: (rect.height - strSize.height) / 2,
                    width: strSize.width,
                    height: strSize.height
                )
                str.draw(in: drawRect)
                return true
            }
            img.isTemplate = true
            return img
        case .url:
            let img = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
            img?.size = targetSize
            img?.isTemplate = true
            return img
        }
    }
}
