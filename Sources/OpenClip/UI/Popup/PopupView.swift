import SwiftUI
import AppKit
import CoreGraphics
import Core

// MARK: - Action Button

public struct ActionButton: View {
    public let action: any Action
    public let context: ActionContext
    public let onResult: @MainActor (ActionResult) -> Void

    @State private var isHovered = false

    public init(action: any Action, context: ActionContext, onResult: @escaping @MainActor (ActionResult) -> Void) {
        self.action = action
        self.context = context
        self.onResult = onResult
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
                .foregroundColor(isHovered ? .white : .primary.opacity(0.80))
                .frame(width: 36, height: 32)
                .background(
                    isHovered
                        ? Color.accentColor
                        : Color.clear
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

// MARK: - Thin divider between buttons

private struct ButtonDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.13))
            .frame(width: 0.6, height: 32)
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
                ButtonDivider()
            }

            // Action buttons with thin dividers between them
            ForEach(Array(pagedActions.enumerated()), id: \.offset) { index, action in
                if index > 0 {
                    ButtonDivider()
                }
                ActionButton(action: action, context: context, onResult: onResult)
            }

            // Right chevron
            if totalPages > 1 && currentPage < totalPages - 1 {
                ButtonDivider()
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
                .stroke(themeBorder, lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 4)
        .padding(10)
    }

    // MARK: - Theming

    @ViewBuilder
    private var themeBackground: some View {
        switch selectedTheme {
        case "dark":
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: NSColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 0.96)))
        case "light":
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.regularMaterial)
        default: // "glass"
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    private var themeBorder: Color {
        switch selectedTheme {
        case "dark":  return Color.white.opacity(0.12)
        case "light": return Color.black.opacity(0.10)
        default:      return Color.primary.opacity(0.10)
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
