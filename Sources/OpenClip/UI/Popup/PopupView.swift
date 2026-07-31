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
    @State private var isPressed = false

    public init(action: any Action, context: ActionContext, onResult: @escaping @MainActor (ActionResult) -> Void) {
        self.action = action
        self.context = context
        self.onResult = onResult
    }

    public var body: some View {
        Button {
            isPressed = true
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
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isHovered ? .white : .primary.opacity(0.88))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(isHovered ? Color.accentColor : Color.primary.opacity(0.07))
                )
                .scaleEffect(isHovered ? 1.10 : (isPressed ? 0.88 : 1.0))
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isHovered)
                .animation(.spring(response: 0.12, dampingFraction: 0.5), value: isPressed)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
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
        HStack(spacing: 6) {
            // Left chevron
            if totalPages > 1 && currentPage > 0 {
                chevronButton(systemImage: "chevron.left") {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { currentPage -= 1 }
                }
            }

            // Action buttons
            ForEach(pagedActions, id: \.id) { action in
                ActionButton(action: action, context: context, onResult: onResult)
            }

            // Right chevron
            if totalPages > 1 && currentPage < totalPages - 1 {
                chevronButton(systemImage: "chevron.right") {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { currentPage += 1 }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(themeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(themeBorder, lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 5)
        .padding(10)  // gives the shadow room inside the panel
    }

    // MARK: - Theming

    @ViewBuilder
    private var themeBackground: some View {
        switch selectedTheme {
        case "dark":
            // True OLED-dark background with heavy material tint
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.96)))
        case "light":
            // Crisp white with very subtle blur
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        default: // "glass"
            // Ultra-thin vibrancy — picks up the wallpaper colour underneath
            RoundedRectangle(cornerRadius: 14, style: .continuous)
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
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 28)
        }
        .buttonStyle(.plain)
    }
}
