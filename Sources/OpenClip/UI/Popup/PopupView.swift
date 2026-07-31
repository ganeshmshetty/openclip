import SwiftUI
import AppKit
import CoreGraphics
import Core

// MARK: - Popup View

public struct PopupView: View {
    public let actions: [any Action]
    public let context: ActionContext
    public let onResult: @MainActor (ActionResult) -> Void

    @AppStorage("popupTheme") private var selectedTheme: String = "glass"
    @State private var currentPage = 0
    /// Single shared hover index — switching buttons is one atomic write, no gap/flicker.
    @State private var hoveredIndex: Int? = nil

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
            if totalPages > 1 && currentPage > 0 {
                chevronButton(systemImage: "chevron.left") { currentPage -= 1 }
            }

            ForEach(Array(pagedActions.enumerated()), id: \.offset) { index, action in
                let isLast = index == pagedActions.count - 1
                let hasRightChevron = totalPages > 1 && currentPage < totalPages - 1
                let showDivider = !isLast || hasRightChevron

                actionButton(action: action, index: index, showDivider: showDivider)
            }

            if totalPages > 1 && currentPage < totalPages - 1 {
                chevronButton(systemImage: "chevron.right") { currentPage += 1 }
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

    // MARK: - Action button with shared hover state

    @ViewBuilder
    private func actionButton(action: any Action, index: Int, showDivider: Bool) -> some View {
        let isHovered = hoveredIndex == index

        let restForeground: Color = selectedTheme == "light"
            ? .black.opacity(0.85)
            : selectedTheme == "dark" ? .white.opacity(0.90) : .primary.opacity(0.85)

        let dividerColor: Color = selectedTheme == "light"
            ? .black.opacity(0.12)
            : selectedTheme == "dark" ? .white.opacity(0.14) : .primary.opacity(0.15)

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
                .foregroundColor(isHovered ? .white : restForeground)
                .frame(width: 36, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered ? Color.accentColor : Color.clear)
                        .padding(.horizontal, 2)
                )
                .overlay(alignment: .trailing) {
                    if showDivider && !isHovered {
                        Rectangle()
                            .fill(dividerColor)
                            .frame(width: 0.6, height: 32)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { entered in
            // Atomically update shared index — entering a new button immediately
            // sets the index before the old button's onHover(false) fires,
            // so there is zero frame where no button is highlighted.
            if entered {
                hoveredIndex = index
            } else if hoveredIndex == index {
                hoveredIndex = nil
            }
        }
        .help(action.title)
    }

    // MARK: - Theming

    @ViewBuilder
    private var themeBackground: some View {
        switch selectedTheme {
        case "dark":
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
        case "light":
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(red: 0.98, green: 0.98, blue: 0.99))
        default:
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
