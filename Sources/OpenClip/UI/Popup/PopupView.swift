import SwiftUI
import AppKit
import CoreGraphics
import Core

// MARK: - Action Button

public struct ActionButton: View {
    public let action: any Action
    public let context: ActionContext
    public let showDivider: Bool
    public let theme: String
    public let onResult: @MainActor (ActionResult) -> Void

    @State private var isHovered = false

    public init(
        action: any Action,
        context: ActionContext,
        showDivider: Bool = false,
        theme: String = "glass",
        onResult: @escaping @MainActor (ActionResult) -> Void
    ) {
        self.action = action
        self.context = context
        self.showDivider = showDivider
        self.theme = theme
        self.onResult = onResult
    }

    private var restForegroundColor: Color {
        switch theme {
        case "light":
            return Color.black.opacity(0.85)
        case "dark":
            return Color.white.opacity(0.90)
        default:
            return Color.primary.opacity(0.85)
        }
    }

    private var dividerColor: Color {
        switch theme {
        case "light":
            return Color.black.opacity(0.12)
        case "dark":
            return Color.white.opacity(0.14)
        default:
            return Color.primary.opacity(0.15)
        }
    }

    public var body: some View {
        Button {
            Task {
                do {
                    let result = try await action.perform(context)
                    onResult(result)
                } catch {
                    print("Action failed: \(error)")
                }
            }
        } label: {
            iconView(for: action.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isHovered ? .white : restForegroundColor)
                .frame(width: 36, height: 32)
                .background(
                    isHovered
                        ? Color.accentColor
                        : Color.clear
                )
                .overlay(
                    Group {
                        if showDivider && !isHovered {
                            Rectangle()
                                .fill(dividerColor)
                                .frame(width: 0.6, height: 32)
                        }
                    },
                    alignment: .trailing
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(action.title)
    }

    @ViewBuilder
    private func iconView(for icon: ActionIcon) -> some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
        case .url(let url):
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fit).frame(width: 14, height: 14)
                } else {
                    Image(systemName: phase.error != nil ? "exclamationmark.triangle" : "circle.dashed")
                }
            }
        case .local(let url):
            if let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage).resizable().aspectRatio(contentMode: .fit).frame(width: 14, height: 14)
            } else {
                Image(systemName: "doc")
            }
        }
    }
}

// MARK: - Popup View

public struct PopupView: View {
    public let actions: [any Action]
    public let context: ActionContext
    public let onResult: @MainActor (ActionResult) -> Void

    @AppStorage("popupTheme") private var selectedTheme: String = "glass"
    @State private var currentPage = 0

    private let pageSize = 8

    public init(actions: [any Action], context: ActionContext, onResult: @escaping @MainActor (ActionResult) -> Void) {
        self.actions = actions
        self.context = context
        self.onResult = onResult
    }

    private var pagedActions: [any Action] {
        guard actions.count > pageSize else { return actions }
        let start = currentPage * pageSize
        let end = min(start + pageSize, actions.count)
        guard start < actions.count else { return Array(actions.prefix(pageSize)) }
        return Array(actions[start..<end])
    }

    private var totalPages: Int {
        max(1, Int(ceil(Double(actions.count) / Double(pageSize))))
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Left chevron
            if totalPages > 1 && currentPage > 0 {
                chevronButton(systemImage: "chevron.left") {
                    currentPage -= 1
                }
            }

            // Action buttons touching continuously with zero gap
            ForEach(Array(pagedActions.enumerated()), id: \.offset) { index, action in
                let isLast = index == pagedActions.count - 1
                let hasRightChevron = totalPages > 1 && currentPage < totalPages - 1
                let showDivider = !isLast || hasRightChevron
                
                ActionButton(
                    action: action,
                    context: context,
                    showDivider: showDivider,
                    theme: selectedTheme,
                    onResult: onResult
                )
            }

            // Right chevron
            if totalPages > 1 && currentPage < totalPages - 1 {
                chevronButton(systemImage: "chevron.right") {
                    currentPage += 1
                }
            }
        }
        .fixedSize()
        .background(themeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(themeBorder, lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(selectedTheme == "light" ? 0.16 : 0.32), radius: 10, x: 0, y: 4)
        .padding(18)
    }

    // MARK: - Theming

    @ViewBuilder
    private var themeBackground: some View {
        switch selectedTheme {
        case "dark":
            // OLED Matte Black Pill
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
        case "light":
            // Pure Crisp White Pill
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(red: 0.98, green: 0.98, blue: 0.99))
        default: // "glass"
            // Translucent Frosted Glassmorphism
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    private var themeBorder: Color {
        switch selectedTheme {
        case "dark":  return Color.white.opacity(0.14)
        case "light": return Color.black.opacity(0.12)
        default:      return Color.white.opacity(0.25)
        }
    }

    @ViewBuilder
    private func chevronButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 26, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
