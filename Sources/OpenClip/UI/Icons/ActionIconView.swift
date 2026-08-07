// ActionIconView.swift
// OpenClip
//
// Renders action icons dynamically across SF Symbols, custom images, remote URLs, and text representations.
import SwiftUI
import Core

public struct ActionIconView: View {
    public let icon: ActionIcon
    public let size: CGFloat

    public init(icon: ActionIcon, size: CGFloat = 16) {
        self.icon = icon
        self.size = size
    }

    public var body: some View {
        switch icon {
        case .symbol(let name):
            if name.contains(":") {
                IconifySVGView(iconId: name)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: name.isEmpty ? "star" : name)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            }
        case .text(let text):
            Text(text)
                .font(.system(size: size * 0.75, weight: .bold))
                .frame(width: size, height: size)
        case .url(let url):
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                ProgressView().frame(width: size, height: size)
            }
            .frame(width: size, height: size)
        case .local(let url):
            if let nsImage = LocalIconCache.shared.image(for: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "questionmark.square")
                    .frame(width: size, height: size)
            }
        }
    }
}
