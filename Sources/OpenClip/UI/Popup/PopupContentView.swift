// PopupContentView.swift
// OpenClip
//
// The single reusable renderer for the popup content canvas: renders a PopupContent with one of
// three emphasis styles — .info (small dim card), .result (standard card with header and delivery
// buttons), or .menu (vertical option rows). The canvas header shows the content title and a back
// chevron when `onBack` is provided. Also renders an optional top-trailing status badge (decision
// 10) driven by StatusBadgeModel, so a status that arrives while a card is already open is surfaced
// as a corner badge rather than replacing the card.
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

    @ObservedObject public var statusBadgeModel: StatusBadgeModel = .shared

    @AppStorage("popupTheme") private var selectedTheme: String = "classic"
    @AppStorage("popupThemeColor") private var themeColor: String = "system"
    @Environment(\.colorScheme) private var colorScheme

    public init(
        content: PopupContent,
        onBack: (() -> Void)? = nil,
        onOutcome: @escaping (ContentOutcome) -> Void
    ) {
        self.content = content
        self.onBack = onBack
        self.onOutcome = onOutcome
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
            .padding(.top, content.emphasis == .result ? 38 : 4)
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
            .padding(content.emphasis == .info ? 12 : 16)
            .frame(minWidth: content.emphasis == .info ? 120 : 220,
                   idealWidth: content.emphasis == .info ? 160 : 300,
                   maxWidth: content.emphasis == .info ? 240 : 360)

        let cornerRadius: CGFloat = content.emphasis == .info ? 8 : 10

        let styled = Group {
            if effectiveTheme == "glass" {
                if #available(macOS 26, *) {
                    base
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(cardBorder, lineWidth: 1.0)
                        )
                        .shadow(color: .black.opacity(shadowOpacity), radius: 10, x: 0, y: 4)
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
                        .shadow(color: .black.opacity(shadowOpacity), radius: 10, x: 0, y: 4)
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
                    .shadow(color: .black.opacity(shadowOpacity), radius: content.emphasis == .info ? 6 : 10, x: 0, y: 4)
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
            infoContent
        case .result:
            resultContent
        case .menu:
            menuContent
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

    private var resultContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let icon = content.icon {
                    Label(content.title ?? "", systemImage: icon)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                } else if let title = content.title {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                }
                Spacer()
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Back")
                    .accessibilityLabel("Back")
                }
            }

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
