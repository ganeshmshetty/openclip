// PopupPreviewStrip.swift
// OpenClip
//
// The compact inline hover-preview strip shown in the popup bar when the pointer rests on an
// action that conforms to PreviewProviding. The bar stays visible; the panel grows to fit the
// strip (data-driven via PopupView's size preference). Renders a single non-keyed, non-focusable
// text node from the store's preview `CanvasComponent` (the controller always supplies a `.text`
// node) — hovering a bar row never steals focus or enters key mode, so the strip never becomes a
// session. Nil renders `EmptyView()` → zero height. Pure SwiftUI view — no AppKit.
import SwiftUI
import Core

public struct PopupPreviewStrip: View {
    public let component: CanvasComponent?

    public init(component: CanvasComponent?) {
        self.component = component
    }

    public var body: some View {
        switch component {
        case .text(let props)?:
            Text(props.content)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        default:
            EmptyView()
        }
    }
}
