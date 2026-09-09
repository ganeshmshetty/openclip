// PopupResizeHandles.swift
// OpenClip
//
// The resize handles shared by the popup's resizable surfaces — the result card and the
// action-search palette: invisible strips along the right and bottom edges plus a visible grip in
// the bottom-right corner. They are SwiftUI gestures because the borderless panel has no AppKit
// resize edges, and an AppKit handle would never see the `mouseDown` (`NSHostingView` answers
// `hitTest` with itself for the whole surface — see `ResultCardDragPhase`). The handles only
// report phases; the owner (`PopupWindowController.handleResize`) computes the size from the
// absolute cursor position, resizes the panel, and remembers the result.
import SwiftUI
import AppKit

/// The handle a resize drag started on. A surface's top-left corner stays fixed (the card's
/// header is its move handle; the palette is anchored on the bar), so only the right edge, the
/// bottom edge and the corner joining them resize.
public enum PopupResizeEdge: Sendable, Equatable {
    case right
    case bottom
    case bottomRight

    public var resizesWidth: Bool { self != .bottom }
    public var resizesHeight: Bool { self != .right }
}

struct PopupResizeHandles: View {
    /// Color of the grip glyph — the surface's resting foreground, dimmed until hovered.
    let tint: Color
    /// Accessibility label of the grip, naming the surface it resizes.
    let accessibilityLabel: String
    /// Phases mirror the card's header drag; `.began` is reported exactly once per drag.
    let onResize: @MainActor (PopupResizeEdge, ResultCardDragPhase) -> Void

    /// The handle under the pointer, driving the cursor and the grip's emphasis.
    @State private var hoveredEdge: PopupResizeEdge?
    /// The handle being dragged, from the gesture crossing its threshold to its end.
    @State private var activeEdge: PopupResizeEdge?

    private static let edgeThickness: CGFloat = 5.0
    private static let gripHitSize: CGFloat = 16.0
    private static let gripGlyphSize: CGFloat = 9.0
    private static let gripInset: CGFloat = 5.0

    /// The strips are thin so they stay clear of footer buttons and result rows and leave most of
    /// a body's overlay scrollbar grabbable; the grip is drawn last so it wins where it overlaps
    /// the strips.
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            strip(.right)
                .frame(width: Self.edgeThickness)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            strip(.bottom)
                .frame(height: Self.edgeThickness)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            grip
        }
    }

    private func strip(_ edge: PopupResizeEdge) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onHover { setHover(edge, $0) }
            .gesture(gesture(edge))
    }

    private var grip: some View {
        gripGlyph
            .padding([.bottom, .trailing], Self.gripInset)
            .frame(width: Self.gripHitSize, height: Self.gripHitSize, alignment: .bottomTrailing)
            .contentShape(Rectangle())
            .onHover { setHover(.bottomRight, $0) }
            .gesture(gesture(.bottomRight))
            .help(String(localized: "Drag to resize"))
            .accessibilityLabel(accessibilityLabel)
    }

    /// Three diagonal strokes hugging the corner, longest outermost — the classic grip.
    private var gripGlyph: some View {
        let size = Self.gripGlyphSize
        let isEmphasized = hoveredEdge == .bottomRight || activeEdge == .bottomRight
        return Path { path in
            for offset in stride(from: size / 3, through: size, by: size / 3) {
                path.move(to: CGPoint(x: size, y: size - offset))
                path.addLine(to: CGPoint(x: size - offset, y: size))
            }
        }
        .stroke(tint.opacity(isEmphasized ? 0.75 : 0.35), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        .frame(width: size, height: size)
    }

    /// A tiny threshold so a plain click on a handle is not a resize; `.began` is reported once,
    /// on the first update past it.
    private func gesture(_ edge: PopupResizeEdge) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { _ in
                if activeEdge == nil {
                    activeEdge = edge
                    updateCursor()
                    onResize(edge, .began)
                }
                onResize(edge, .changed)
            }
            .onEnded { _ in
                guard activeEdge == edge else { return }
                activeEdge = nil
                onResize(edge, .ended)
                updateCursor()
            }
    }

    private func setHover(_ edge: PopupResizeEdge, _ hovering: Bool) {
        if hovering {
            hoveredEdge = edge
        } else if hoveredEdge == edge {
            hoveredEdge = nil
        }
        updateCursor()
    }

    /// The cursor follows the hovered handle and stays for the whole drag, even when a fast pull
    /// carries the pointer off the thin strip. `PopupPanel.ContentView` forces the arrow whenever
    /// the pointer enters the panel, so the handles set the cursor themselves rather than relying
    /// on cursor rects.
    private func updateCursor() {
        if let edge = activeEdge ?? hoveredEdge {
            Self.cursor(for: edge).set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private static func cursor(for edge: PopupResizeEdge) -> NSCursor {
        switch edge {
        case .right:
            return .resizeLeftRight
        case .bottom:
            return .resizeUpDown
        case .bottomRight:
            if #available(macOS 15, *) {
                return .frameResize(position: .bottomRight, directions: .all)
            }
            // No public diagonal resize cursor before macOS 15; the grip glyph carries the hint.
            return .arrow
        }
    }
}
