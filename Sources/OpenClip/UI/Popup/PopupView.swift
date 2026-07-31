import SwiftUI
import AppKit
import CoreGraphics
import Core

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
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(isHovered ? .primary : .primary.opacity(0.85))
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(isHovered ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.08))
                )
                .scaleEffect(isHovered ? 1.12 : (isPressed ? 0.90 : 1.0))
                .animation(.spring(response: 0.22, dampingFraction: 0.65), value: isHovered)
                .animation(.spring(response: 0.15, dampingFraction: 0.5), value: isPressed)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
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
                    image.resizable().aspectRatio(contentMode: .fit).frame(width: 18, height: 18)
                } else if phase.error != nil {
                    Image(systemName: "exclamationmark.triangle")
                } else {
                    ProgressView().scaleEffect(0.5)
                }
            }
        case .local(let url):
            if let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage).resizable().aspectRatio(contentMode: .fit).frame(width: 18, height: 18)
            } else {
                Image(systemName: "doc")
            }
        }
    }
}

public struct PopupView: View {
    public let actions: [any Action]
    public let context: ActionContext
    public let onResult: @MainActor (ActionResult) -> Void
    
    @AppStorage("popupTheme") private var selectedTheme: String = "glass"
    @State private var currentPage = 0
    
    private let pageSize = 7
    
    public init(actions: [any Action], context: ActionContext, onResult: @escaping @MainActor (ActionResult) -> Void) {
        self.actions = actions
        self.context = context
        self.onResult = onResult
    }
    
    private var pagedActions: [any Action] {
        guard actions.count > pageSize else { return actions }
        let startIndex = currentPage * pageSize
        let endIndex = min(startIndex + pageSize, actions.count)
        guard startIndex < actions.count else { return Array(actions.prefix(pageSize)) }
        return Array(actions[startIndex..<endIndex])
    }
    
    private var totalPages: Int {
        max(1, Int(ceil(Double(actions.count) / Double(pageSize))))
    }
    
    public var body: some View {
        HStack(spacing: 10) {
            if totalPages > 1 && currentPage > 0 {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        currentPage -= 1
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 34)
                }
                .buttonStyle(.plain)
            }
            
            ForEach(pagedActions, id: \.id) { action in
                ActionButton(action: action, context: context, onResult: onResult)
            }
            
            if totalPages > 1 && currentPage < totalPages - 1 {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        currentPage += 1
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 34)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            backgroundForTheme(selectedTheme)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 6)
        .padding(14)
    }
    
    @ViewBuilder
    private func backgroundForTheme(_ theme: String) -> some View {
        switch theme {
        case "dark":
            Color(nsColor: .windowBackgroundColor).opacity(0.92)
        case "light":
            Color.white.opacity(0.95)
        default: // "glass"
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}
