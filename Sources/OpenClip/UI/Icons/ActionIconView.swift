// ActionIconView.swift
// OpenClip
//
// Renders action icons dynamically across SF Symbols, custom images, remote URLs, and text representations,
// applying smart optical normalization so line icons, solid shapes, SVGs, and glyphs maintain balanced visual weight.
import SwiftUI
import SDWebImage
import SDWebImageSVGCoder
import Core

/// Fetches a remote monochrome (`currentColor`) SVG and renders it as an AppKit
/// template image so it inherits the environment tint and adapts to light/dark —
/// the same decode pipeline as `IconifySVGView`, generalized to arbitrary URLs.
/// Used for extension-store/onboarding icons sourced from the publish pipeline's
/// normalized SVGs. Results are cached per URL for the session.
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

/// Session cache for decoded template images keyed by absolute URL.
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
            // Decode off-main: SDImageSVGCoder produces an NSImage from raw SVG data.
            let decoded = await Task.detached(priority: .utility) { () -> NSImage? in
                SDImageSVGCoder.shared.decodedImage(with: data, options: nil)
            }.value
            guard let decoded else { return nil }
            // Template mode → AppKit renders it as a mask tinted by foregroundColor,
            // which is what makes currentColor-style icons theme-adaptive.
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
                    // Iconify SVGs usually have internal padding in their viewBox; scale up so optical weight matches SF Symbols.
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
                if text.count <= 2 {
                    Text(text)
                        .font(.system(size: targetDimension * 0.90, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .frame(minWidth: targetDimension, minHeight: targetDimension, alignment: .center)
                } else {
                    Text(text)
                        .font(.system(size: 13 * scale, weight: .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 118 * scale)
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
                        .renderingMode(.template)
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
