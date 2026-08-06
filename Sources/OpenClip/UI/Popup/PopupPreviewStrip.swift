// PopupPreviewStrip.swift
// OpenClip
//
// The compact inline hover-preview strip shown in the popup bar when the pointer rests on an
// action that conforms to PreviewProviding. The bar stays visible; the panel grows to fit the
// strip (data-driven via PopupView's size preference). Pure SwiftUI view — no AppKit.
import SwiftUI
import Core

public struct PopupPreviewStrip: View {
    public let content: PopupContent

    public init(content: PopupContent) {
        self.content = content
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let icon = content.icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Text(content.subtitle ?? content.title ?? "")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
