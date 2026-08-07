// PopupContentView.swift
// OpenClip
//
// The single reusable renderer for the popup content canvas: renders a PopupContent with one of
// three emphasis styles — .info (small dim card), .result (standard card with a fixed chrome header
// strip above the content body), or .menu (vertical option rows). The .result header is styled like
// a command palette: a small non-accent title on the left and an Esc keycap affordance on the right
// (when `onBack` is provided), sitting in its own full-width strip separated from the canvas body by
// a hairline divider. The header is fixed popup chrome, distinct from the body below, so a future
// SDK-driven canvas can host/replace only the body while the header stays. Also renders an optional
// top-trailing status badge (decision 10) driven by StatusBadgeModel, so a status that arrives while
// a card is already open is surfaced as a corner badge rather than replacing the card.
import SwiftUI
import Core

/// Shared observable holding the status badge shown on the currently open content canvas. Presenter
/// code (PopupWindowController) writes it; PopupContentView observes it, so a status arriving after
/// the canvas mounted still appears. Mirrors the shared-singleton pattern of PopupHoverState.
@MainActor
public final class StatusBadgeModel: ObservableObject {
    public static let shared = StatusBadgeModel()

    @Published public var currentStatusBadge: StatusFeedback?

    private init() {}
}

@MainActor
public struct PopupContentView: View {
    public let content: PopupContent
    public let onOutcome: (ContentOutcome) -> Void
    public let onBack: (() -> Void)?
    /// When true (popup sits at the bottom of the screen) the chrome header renders at the card's
    /// bottom edge — near the cursor — and the canvas body grows upward above it, mirroring how the
    /// search palette keeps its field fixed and grows results above.
    public let searchResultsAbove: Bool

    @ObservedObject public var statusBadgeModel: StatusBadgeModel = .shared

    @AppStorage("popupTheme") private var selectedTheme: String = "classic"
    @AppStorage("popupThemeColor") private var themeColor: String = "system"
    @Environment(\.colorScheme) private var colorScheme

    /// Hover follows the same mechanism as the search palette and the bar: the AX global-mouse
    /// location hit-tested against registered frames (instant), with an `.onHover` fallback when
    /// global monitoring is unavailable — matching the command-palette hover, not SwiftUI's
    /// delayed `.onHover`-only path. Deliberately *not* `@ObservedObject`: `location` publishes at
    /// event-monitor rate, and observing the whole object re-evaluates the entire card body per
    /// mouse move. Only `hoverState.$location` is subscribed to via `.onReceive`.
    private let hoverState = PopupHoverState.shared
    @State private var hoverFrames: [CanvasHoverTarget: CGRect] = [:]
    @State private var hoveredTarget: CanvasHoverTarget?

    public init(
        content: PopupContent,
        onBack: (() -> Void)? = nil,
        onOutcome: @escaping (ContentOutcome) -> Void,
        searchResultsAbove: Bool = false
    ) {
        self.content = content
        self.onBack = onBack
        self.onOutcome = onOutcome
        self.searchResultsAbove = searchResultsAbove
    }

    private var themeCategory: PopupThemeModel.Category {
        PopupThemeModel.category(fromStored: selectedTheme)
    }

    /// The color scheme the card content should render as — matching the effective theme
    /// (classic or glass) so `.primary`/`.secondary` and the material agree with the chosen
    /// appearance even when the system is the opposite.
    private var effectiveColorScheme: ColorScheme {
        PopupThemeModel.effectiveScheme(appearance: themeColor, systemIsDark: colorScheme == .dark)
    }

    private var effectiveTheme: String {
        if themeCategory == .glass { return "glass" }
        return PopupThemeModel.classicToken(appearance: themeColor, systemIsDark: colorScheme == .dark)
    }

    public var body: some View {
        cardContainer
            .overlay(alignment: .topTrailing) {
                statusBadgeOverlay
            }
    }

    // MARK: - Status Badge (decision 10)

    /// Small top-trailing capsule surfacing a transient status on an already-open card. Pushed below
    /// the title/close row on `.result` cards so it never overlaps the close button.
    @ViewBuilder
    private var statusBadgeOverlay: some View {
        if let status = statusBadgeModel.currentStatusBadge {
            HStack(spacing: 4) {
                Image(systemName: status.symbolName ?? Self.symbol(for: status.style))
                    .font(.system(size: 10, weight: .semibold))
                Text(status.message)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundColor(Self.color(for: status.style))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((effectiveColorScheme == .dark ? Color.black : Color.white).opacity(0.75))
            .clipShape(Capsule())
            .padding(.top, content.emphasis == .result ? 44 : 4)
            .padding(.trailing, 6)
        }
    }

    private static func symbol(for style: StatusFeedback.Style) -> String {
        switch style {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private static func color(for style: StatusFeedback.Style) -> Color {
        switch style {
        case .success: return .green
        case .error: return .red
        case .info: return .accentColor
        }
    }

    @ViewBuilder
    private var cardContainer: some View {
        let base = cardContent
            .frame(minWidth: content.emphasis == .info ? 120 : 220,
                   idealWidth: content.emphasis == .info ? 160 : 300,
                   maxWidth: content.emphasis == .info ? 240 : 360)

        let cornerRadius: CGFloat = content.emphasis == .info ? 8 : 10

        let styled = Group {
            if effectiveTheme == "glass" {
                if #available(macOS 26, *) {
                    // glassEffect(.regular) casts an elevation shadow that scales with surface size
                    // and clips on large surfaces; the palette-proven pattern is a material + .clear
                    // glass layer + compositingGroup, then a SwiftUI shadow (AGENTS.md hard rule).
                    // The SwiftUI shadow uses the palette's compact radius (6) so its blur stays
                    // within the 16pt panel padding — a 10pt radius clips in every theme.
                    base
                        .background(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(cardBorder, lineWidth: 1.0)
                        )
                        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .compositingGroup()
                        .shadow(color: .black.opacity(shadowOpacity), radius: 6, x: 0, y: 3)
                } else {
                    base
                        .background(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(cardBorder, lineWidth: 1.0)
                        )
                        .shadow(color: .black.opacity(shadowOpacity), radius: 6, x: 0, y: 3)
                }
            } else {
                let bgFill = effectiveTheme == "dark"
                    ? Color(red: 0.20, green: 0.20, blue: 0.22)
                    : Color(red: 0.91, green: 0.91, blue: 0.93)
                base
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(content.emphasis == .info ? bgFill.opacity(0.9) : bgFill)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(cardBorder, lineWidth: 1.0)
                    )
                    .shadow(color: .black.opacity(shadowOpacity), radius: 6, x: 0, y: 3)
            }
        }

        return styled
            .environment(\.colorScheme, effectiveColorScheme)
    }

    private var cardBorder: Color {
        switch content.emphasis {
        case .info:
            return effectiveColorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.14)
        case .result:
            return effectiveColorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.20)
        case .menu:
            return effectiveColorScheme == .dark ? Color.white.opacity(0.20) : Color.black.opacity(0.18)
        }
    }

    private var shadowOpacity: Double {
        content.emphasis == .info ? 0.16 : (effectiveTheme == "light" ? 0.16 : 0.32)
    }

    // MARK: - Content

    @ViewBuilder
    private var cardContent: some View {
        switch content.emphasis {
        case .info:
            infoContent.padding(12)
        case .result:
            resultContent
        case .menu:
            menuContent.padding(16)
        }
    }

    private var infoContent: some View {
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
        }
    }

    /// Command-palette-style chrome header for the `.result` canvas: a fixed full-width strip with a
    /// small non-accent title on the left, a hover-capable Esc keycap on the right (when `onBack` is
    /// provided), and a hairline divider spanning the full card width below it — visually separating
    /// the header (popup chrome) from the hosted canvas body.
    @ViewBuilder
    private var resultHeader: some View {
        HStack(spacing: 8) {
            if let icon = content.icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 15)
            }
            Text(content.title ?? "")
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

    // MARK: - Hover (same location-based mechanism as the search palette and bar)

    /// The hovered target is derived from the shared mouse location, hit-tested against the frames
    /// each interactive element registers in the popup's named coordinate space.
    private func updateHoveredTarget(for location: CGPoint?) {
        let target = location.flatMap { point in
            hoverFrames.first(where: { $0.value.contains(point) })?.key
        }
        guard target != hoveredTarget else { return }
        hoveredTarget = target
    }

    /// Local `.onHover` fallback used only when the AX global mouse monitor is unavailable;
    /// otherwise the location-driven path above owns hover (instant, no SwiftUI hover delay).
    private func useLocalHoverFallback(for target: CanvasHoverTarget, isHovering: Bool) {
        guard !hoverState.usesGlobalMouseMonitoring else { return }
        if isHovering {
            guard hoveredTarget != target else { return }
            hoveredTarget = target
        } else if hoveredTarget == target {
            hoveredTarget = nil
        }
    }

    private var resultContent: some View {
        VStack(spacing: 0) {
            if searchResultsAbove {
                // Popup at the bottom of the screen: keep the chrome header pinned near the cursor
                // (bottom edge) and let the body grow upward, exactly like the search palette keeps
                // its field fixed and grows results above it.
                resultBody
                resultHeader
            } else {
                resultHeader
                resultBody
            }
        }
    }

    private var resultBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let subtitle = content.subtitle {
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }

            ForEach(Array(rowsContent.enumerated()), id: \.offset) { _, row in
                switch row {
                case .text(let text):
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(text)
                            .font(.system(size: 13, weight: .regular))
                            .lineSpacing(2)
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .padding(.bottom, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 40, maxHeight: 270)
                case .option:
                    EmptyView()
                }
            }

            if !content.footer.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(content.footer.enumerated()), id: \.offset) { index, option in
                        footerButton(option: option, isPrimary: index == 0)
                    }
                }
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func footerButton(option: ContentOption, isPrimary: Bool) -> some View {
        let label = Label(option.title, systemImage: option.icon ?? "arrow.right")
            .font(.caption)
        if isPrimary {
            Button { onOutcome(option.outcome) } label: { label }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel(option.title)
        } else {
            Button { onOutcome(option.outcome) } label: { label }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(option.title)
        }
    }

    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title = content.title {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
            }

            ForEach(Array(content.rows.enumerated()), id: \.offset) { index, row in
                switch row {
                case .text(let header):
                    Text(header)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                        .padding(.bottom, 2)
                case .option(let option):
                    Button {
                        onOutcome(option.outcome)
                    } label: {
                        HStack(spacing: 8) {
                            if let icon = option.icon {
                                Image(systemName: icon)
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(width: 16)
                                    .foregroundColor(.accentColor)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.primary)
                                if let subtitle = option.subtitle {
                                    Text(subtitle)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 8)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                        .background(index.isMultiple(of: 2) ? Color.primary.opacity(0.04) : Color.clear)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.subtitle.map { "\(option.title): \($0)" } ?? option.title)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Row Helpers

    private var rowsContent: [ContentRow] {
        content.rows
    }
}

/// Hover targets within the content canvas chrome (currently just the Esc keycap).
private enum CanvasHoverTarget: Hashable {
    case esc
}

private struct CanvasHoverFramePreferenceKey: PreferenceKey {
    static let defaultValue: [CanvasHoverTarget: CGRect] = [:]

    static func reduce(value: inout [CanvasHoverTarget: CGRect], nextValue: () -> [CanvasHoverTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension View {
    /// Registers the receiver's frame in the popup's named hover space so the location-driven
    /// hit test can resolve it (same pattern as the bar and search palette).
    func canvasHoverTarget(_ target: CanvasHoverTarget) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CanvasHoverFramePreferenceKey.self,
                    value: [target: proxy.frame(in: .named("popupHoverSpace"))]
                )
            }
        }
    }
}
