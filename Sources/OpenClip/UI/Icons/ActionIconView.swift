// ActionIconView.swift
// OpenClip
//
// Renders action icons (SF Symbols, Iconify, remote and local images, text) with optical normalization.
import SwiftUI
import SDWebImage
import SDWebImageSVGCoder
import Core

/// Remote monochrome SVG rendered as a template image so it adopts the environment tint.
@MainActor
struct RemoteTemplateIcon: View {
    let url: URL?
    private enum LoadState {
        case loading
        case loaded(NSImage)
        case failed
    }
    @State private var state: LoadState = .loading

    var body: some View {
        Group {
            switch state {
            case .loaded(let img):
                Image(nsImage: img)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
            case .loading:
                Color.primary.opacity(0.08)
                    .overlay(ProgressView().controlSize(.mini))
            case .failed:
                // Terminal state: a failed fetch must never spin forever.
                Image(systemName: "questionmark.square")
                    .resizable()
                    .scaledToFit()
                    .opacity(0.5)
            }
        }
        .task(id: url?.absoluteString) {
            state = .loading
            guard let url else {
                state = .failed
                return
            }
            if let decoded = await RemoteTemplateIconCache.shared.image(for: url) {
                state = .loaded(decoded)
            } else {
                state = .failed
            }
        }
    }
}

actor RemoteTemplateIconCache {
    static let shared = RemoteTemplateIconCache()
    private let cache = NSCache<NSString, Box>()

    final class Box: @unchecked Sendable {
        let image: NSImage
        init(_ image: NSImage) { self.image = image }
    }

    func image(for url: URL) async -> NSImage? {
        if let hit = cache.object(forKey: url.absoluteString as NSString) {
            return hit.image
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // Decode off the main actor.
            let decoded = await Task.detached(priority: .utility) { () -> NSImage? in
                SDImageSVGCoder.shared.decodedImage(with: data, options: nil)
            }.value
            guard let decoded else { return nil }
            // Template mode lets AppKit tint the mask with foregroundColor.
            decoded.isTemplate = true
            decoded.size = NSSize(width: 64, height: 64)
            let box = Box(decoded)
            cache.setObject(box, forKey: url.absoluteString as NSString)
            return decoded
        } catch {
            return nil
        }
    }
}

/// Per-symbol optical correction so the sidebar icon column reads evenly; unknown symbols use `classify`.
public enum IconOpticalCategory: Sendable {
    case solidOrFilled
    case thinLine
    case wideAspect
    case standard

    /// Keys are lower-cased symbol names.
    private static let known: [String: IconOpticalCategory] = [
        // Thin, open strokes read small for their size, so they grow.
        "sparkle": .thinLine,
        "sparkles": .thinLine,
        "link": .thinLine,
        "magnifyingglass": .thinLine,
        "equal.circle": .thinLine,
        "character.book.closed": .thinLine,
        "pencil": .thinLine,
        "plus": .thinLine,
        "wand.and.stars": .thinLine,
        "command": .thinLine,
        "shield.checkered": .thinLine,
        // Wide glyphs already fill the box sideways, so they shrink to match the column.
        "doc.on.doc": .wideAspect,
        "doc.on.clipboard": .wideAspect,
        "folder": .wideAspect,
        "scissors": .wideAspect,
        "text.badge.plus": .wideAspect,
        // Solid or compact shapes read heavy for their size.
        "gearshape.fill": .solidOrFilled,
        "bag.fill": .solidOrFilled,
        "paintbrush.fill": .solidOrFilled,
        "info.circle.fill": .solidOrFilled,
        "puzzlepiece.extension.fill": .solidOrFilled,
        "bolt.fill": .solidOrFilled,
        // The settings sidebar's compact leftovers.
        "slider.horizontal.3": .standard,
        "calendar.badge.plus": .standard,
    ]

    public static func classify(symbolName: String) -> IconOpticalCategory {
        if let known = known[symbolName.lowercased()] { return known }

        let name = symbolName.lowercased()
        if name.contains(".fill") || name.contains("square.fill") || name.contains("circle.fill") {
            return .solidOrFilled
        }
        if name.contains("doc.on.") || name.contains("rectangle") || name.contains("folder")
            || name.contains("arrow.left.arrow.right") || name.contains("text.align")
            || name.contains("calendar") || name.contains("tablecells") || name.contains("scissors") {
            return .wideAspect
        }
        if name.contains("circle") || name.contains("magnifyingglass") || name.contains("link")
            || name.contains("sparkle") || name.contains("pencil") || name.contains("wand")
            || name.contains("book") || name.contains("character") || name.contains("textformat") {
            return .thinLine
        }
        return .standard
    }

    public var opticalMultiplier: CGFloat {
        switch self {
        case .solidOrFilled: return 0.88
        case .thinLine:      return 1.10
        case .wideAspect:    return 0.92
        case .standard:      return 1.00
        }
    }

    public var symbolWeight: Font.Weight {
        switch self {
        case .solidOrFilled: return .regular
        case .thinLine:      return .medium
        case .wideAspect:    return .medium
        case .standard:      return .medium
        }
    }
}

/// How a `.text` icon renders: a compact glyph badge ("Aa", "#", an emoji) or a regular 15 pt label.
/// One rule shared by the bar, the sub-bar, the width estimator and the preferences preview (#156).
enum ActionTextIconStyle {
    /// Two Latin-ish characters read as a glyph; two CJK characters are a word ("翻译", "粘贴") and must
    /// render like every other text label, or a group mixing 2- and 3-character titles looks uneven.
    static func isCompactGlyph(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= 2 else { return false }
        return !text.unicodeScalars.contains(where: isWide)
    }

    /// Full-width scripts render at roughly one em per character.
    static func isWide(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.isIdeographic { return true }
        switch scalar.value {
        case 0x1100...0x11FF,   // Hangul Jamo
             0x3000...0x30FF,   // CJK punctuation, Hiragana, Katakana
             0x3130...0x318F,   // Hangul compatibility Jamo
             0x31F0...0x31FF,   // Katakana phonetic extensions
             0xAC00...0xD7AF,   // Hangul syllables
             0xFF00...0xFF60,   // Fullwidth forms
             0xFFE0...0xFFE6:
            return true
        default:
            return false
        }
    }
}

public struct ActionIconView: View {
    public let icon: ActionIcon
    public let size: CGFloat
    public let scale: CGFloat

    public init(icon: ActionIcon, size: CGFloat = 14, scale: CGFloat = 1.0) {
        self.icon = icon
        self.size = size
        self.scale = scale
    }

    private var targetDimension: CGFloat {
        size * scale
    }

    public var body: some View {
        let effectiveIcon: ActionIcon = {
            if case .symbol(let name) = icon, name.hasPrefix(Constants.customIconPrefix) {
                return ActionIcon.resolve(from: name)
            }
            return icon
        }()

        ZStack(alignment: .center) {
            switch effectiveIcon {
            case .symbol(let name):
                if name.contains(":") {
                    // Iconify viewBoxes carry padding; scale up to match SF Symbol weight.
                    let isBrand = name.hasPrefix("simple-icons:") || name.hasPrefix("logos:") || name.hasPrefix("cib:") || name.contains("brand")
                    let opticalFactor: CGFloat = isBrand ? 1.08 : 1.20
                    let dim = targetDimension * opticalFactor
                    IconifySVGView(iconId: name)
                        .frame(width: dim, height: dim)
                } else {
                    let category = IconOpticalCategory.classify(symbolName: name)
                    let effectiveFontSize = targetDimension * category.opticalMultiplier
                    Image(systemName: name.isEmpty ? "star" : name)
                        .font(.system(size: effectiveFontSize, weight: category.symbolWeight))
                        .imageScale(.medium)
                }
            case .text(let text):
                if ActionTextIconStyle.isCompactGlyph(text) {
                    Text(text)
                        .font(.system(size: targetDimension * 0.90, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .frame(minWidth: targetDimension, minHeight: targetDimension, alignment: .center)
                } else {
                    Text(text)
                        .font(.system(size: 15 * scale, weight: .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 136 * scale)
                }
            case .url(let url):
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: targetDimension * 1.15, maxHeight: targetDimension * 1.15)
                    } else if phase.error != nil {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: targetDimension * 0.9, weight: .regular))
                    } else {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: targetDimension, height: targetDimension)
                    }
                }
                .frame(minWidth: targetDimension, minHeight: targetDimension, alignment: .center)
            case .local(let url):
                if let nsImage = LocalIconCache.shared.image(for: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .renderingMode(nsImage.isTemplate ? .template : .original)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: targetDimension * 1.18, maxHeight: targetDimension * 1.18)
                } else {
                    Image(systemName: "questionmark.square")
                        .font(.system(size: targetDimension, weight: .regular))
                }
            }
        }
        .frame(minHeight: targetDimension, alignment: .center)
    }
}
