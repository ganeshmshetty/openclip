// CanvasHeaderView.swift
// OpenClip
//
// The chrome header for the content-canvas surface, ported from PopupContentView.resultHeader: a
// full-width strip with a small non-accent title on the left (with an optional leading icon), a
// hover-capable Esc keycap on the right (when `onBack` is provided), and a hairline divider
// spanning the full card width — overlaid on the top or bottom edge depending on whether the
// header sits above or below the canvas body (`searchResultsAbove`). Hover follows the same
// mechanism as the bar and the search palette: the AX global-mouse location hit-tested against
// registered frames, with an `.onHover` fallback when global monitoring is unavailable.
import SwiftUI

@MainActor
public struct CanvasHeaderView: View {
    public let title: String?
    public let icon: String?
    public let onBack: (() -> Void)?
    public let searchResultsAbove: Bool
    /// Deliberately *not* `@ObservedObject`: `location` publishes at event-monitor rate, and
    /// observing the whole object re-evaluates the entire header body per mouse move. Only
    /// `hoverState.$location` is subscribed to via `.onReceive`.
    private let hoverState: PopupHoverState
    private let isStatic: Bool
    @State private var hoverFrames: [CanvasHoverTarget: CGRect] = [:]
    @State private var hoveredTarget: CanvasHoverTarget?

    public init(
        title: String?,
        icon: String?,
        onBack: (() -> Void)?,
        searchResultsAbove: Bool,
        hoverState: PopupHoverState = .shared,
        isStatic: Bool = false
    ) {
        self.title = title
        self.icon = icon
        self.onBack = onBack
        self.searchResultsAbove = searchResultsAbove
        self.hoverState = hoverState
        self.isStatic = isStatic
    }

    public var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 15)
            }
            Text(title ?? "")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if let onBack {
                let isHovered = hoveredTarget == .esc
                Button(action: onBack) {
                    Text("esc")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isHovered ? .white : .secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            isHovered ? Color.accentColor : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color.secondary.opacity(0.45), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help("Back (Esc)")
                .accessibilityLabel("Back")
                .canvasHoverTarget(.esc)
                .onHover { hovering in
                    useLocalHoverFallback(for: .esc, isHovering: hovering)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(alignment: searchResultsAbove ? .top : .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
        .onPreferenceChange(CanvasHoverFramePreferenceKey.self) { frames in
            hoverFrames = frames
            updateHoveredTarget(for: hoverState.location)
        }
        .onReceive(hoverState.$location) { location in
            updateHoveredTarget(for: location)
        }
    }

    private func updateHoveredTarget(for location: CGPoint?) {
        guard !isStatic else { return }
        let target = location.flatMap { point in
            hoverFrames.first(where: { $0.value.contains(point) })?.key
        }
        guard target != hoveredTarget else { return }
        hoveredTarget = target
    }

    /// Local `.onHover` fallback used whenever hover state updates (instant, reliable fallback).
    private func useLocalHoverFallback(for target: CanvasHoverTarget, isHovering: Bool) {
        guard !isStatic else { return }
        if isHovering {
            guard hoveredTarget != target else { return }
            hoveredTarget = target
        } else if hoveredTarget == target {
            hoveredTarget = nil
        }
    }
}
