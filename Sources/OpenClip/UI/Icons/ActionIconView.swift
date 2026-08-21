// ActionIconView.swift
// OpenClip
//
// Renders action icons dynamically across SF Symbols, custom images, remote URLs, and text representations,
// applying smart optical normalization so line icons, solid shapes, SVGs, and glyphs maintain balanced visual weight.
import SwiftUI
import Core

public enum IconOpticalCategory: Sendable {
    case solidOrFilled
    case thinLine
    case wideAspect
    case standard

    public static func classify(symbolName: String) -> IconOpticalCategory {
        let name = symbolName.lowercased()
        if name.contains(".fill") || name.contains("circle.fill") || name.contains("square.fill") || name.contains("character.book") || name.contains("equal.circle") {
            return .solidOrFilled
        }
        if name.contains("doc.on.doc") || name.contains("rectangle") || name.contains("arrow.left.arrow.right") || name.contains("text.align") {
            return .wideAspect
        }
        if name.contains("scissors") || name.contains("pencil") || name.contains("wand") || name.contains("magnifyingglass") || name.contains("sparkles") || name.contains("link") {
            return .thinLine
        }
        return .standard
    }

    public var opticalMultiplier: CGFloat {
        switch self {
        case .solidOrFilled: return 0.88
        case .thinLine:       return 1.05
        case .wideAspect:     return 1.04
        case .standard:       return 1.0
        }
    }

    public var symbolWeight: Font.Weight {
        switch self {
        case .solidOrFilled: return .regular
        case .thinLine:       return .medium
        case .wideAspect:     return .medium
        case .standard:       return .medium
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
        ZStack(alignment: .center) {
            switch icon {
            case .symbol(let name):
                if name.contains(":") {
                    let isBrand = name.hasPrefix("simple-icons:") || name.hasPrefix("logos:") || name.hasPrefix("cib:") || name.contains("brand")
                    let opticalFactor: CGFloat = isBrand ? 0.88 : 1.0
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
                if text.count <= 2 {
                    Text(text)
                        .font(.system(size: targetDimension * 0.95, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .frame(minWidth: targetDimension, minHeight: targetDimension, alignment: .center)
                } else {
                    Text(text)
                        .font(.system(size: 14 * scale, weight: .regular))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            case .url(let url):
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: targetDimension, maxHeight: targetDimension)
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
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: targetDimension, maxHeight: targetDimension)
                } else {
                    Image(systemName: "questionmark.square")
                        .font(.system(size: targetDimension, weight: .regular))
                }
            }
        }
        .frame(minHeight: targetDimension, alignment: .center)
    }
}
