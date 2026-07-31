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
    @State private var hoveredIndex: Int? = nil

    private let buttonWidth: CGFloat = 36
    private let chevronWidth: CGFloat = 26
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

    private var hasLeftChevron: Bool { totalPages > 1 && currentPage > 0 }
    private var hasRightChevron: Bool { totalPages > 1 && currentPage < totalPages - 1 }

    public var body: some View {
        if selectedTheme == "glass" {
            if #available(macOS 26, *) {
                liquidGlassBar
            } else {
                legacyGlassBar
            }
        } else {
            legacyPopupBar
        }
    }

    // MARK: - Native Liquid Glass bar (glass theme, macOS 26+)

    @available(macOS 26, *)
    private var liquidGlassBar: some View {
        // GlassEffectContainer lets adjacent .glassEffect() capsules merge and morphing
        // into each other fluidly as the hovered button changes — Apple recommended pattern
        GlassEffectContainer {
            HStack(spacing: 0) {
                if hasLeftChevron {
                    liquidChevronButton(systemImage: "chevron.left") { currentPage -= 1 }
                }
                ForEach(Array(pagedActions.enumerated()), id: \.offset) { index, action in
                    liquidActionButton(action: action, index: index)
                }
                if hasRightChevron {
                    liquidChevronButton(systemImage: "chevron.right") { currentPage += 1 }
                }
            }
        }
        .fixedSize()
        .onContinuousHover { phase in
            updateHover(phase: phase)
        }
        .padding(18)
    }

    @available(macOS 26, *)
    @ViewBuilder
    private func liquidActionButton(action: any Action, index: Int) -> some View {
        let isHovered = hoveredIndex == index
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
                .frame(width: buttonWidth, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Each button gets its own glass capsule; GlassEffectContainer merges adjacent ones
        // .regular = solid glass highlight when hovered, .clear = invisible otherwise
        .glassEffect(isHovered ? .regular.interactive() : .clear, in: .capsule)
        .help(action.title)
    }

    @available(macOS 26, *)
    @ViewBuilder
    private func liquidChevronButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: chevronWidth, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: - Legacy glass bar (glass theme, macOS < 26)

    private var legacyGlassBar: some View {
        legacyHStack
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 4)
            .padding(18)
    }

    // MARK: - Legacy dark/light bar

    private var legacyPopupBar: some View {
        legacyHStack
            .background(legacyBackground)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(legacyBorder, lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(selectedTheme == "light" ? 0.16 : 0.32), radius: 10, x: 0, y: 4)
            .padding(18)
    }

    private var legacyHStack: some View {
        HStack(spacing: 0) {
            if hasLeftChevron {
                legacyChevronButton(systemImage: "chevron.left") { currentPage -= 1 }
            }
            ForEach(Array(pagedActions.enumerated()), id: \.offset) { index, action in
                let isLast = index == pagedActions.count - 1
                let showDivider = !isLast || hasRightChevron
                let isHovered = hoveredIndex == index
                legacyActionButton(action: action, index: index, isHovered: isHovered, showDivider: showDivider)
            }
            if hasRightChevron {
                legacyChevronButton(systemImage: "chevron.right") { currentPage += 1 }
            }
        }
        .fixedSize()
        .onContinuousHover { phase in
            updateHover(phase: phase)
        }
    }

    // MARK: - Shared hover logic

    private func updateHover(phase: HoverPhase) {
        switch phase {
        case .active(let location):
            let xOffset = location.x - (hasLeftChevron ? chevronWidth : 0)
            let idx = Int(xOffset / buttonWidth)
            hoveredIndex = (xOffset >= 0 && idx >= 0 && idx < pagedActions.count) ? idx : nil
        case .ended:
            hoveredIndex = nil
        }
    }

    // MARK: - Legacy action button

    @ViewBuilder
    private func legacyActionButton(action: any Action, index: Int, isHovered: Bool, showDivider: Bool) -> some View {
        let restForeground: Color = selectedTheme == "light" ? .black.opacity(0.85) : .white.opacity(0.90)
        let dividerColor: Color = selectedTheme == "light" ? .black.opacity(0.12) : .white.opacity(0.14)

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
                .frame(width: buttonWidth, height: 32)
                .background(isHovered ? Color.accentColor : Color.clear)
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
        .help(action.title)
    }

    @ViewBuilder
    private func legacyChevronButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: chevronWidth, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Legacy theming

    @ViewBuilder
    private var legacyBackground: some View {
        switch selectedTheme {
        case "dark":
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
        default:
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(red: 0.98, green: 0.98, blue: 0.99))
        }
    }

    private var legacyBorder: Color {
        selectedTheme == "light" ? Color.black.opacity(0.12) : Color.white.opacity(0.14)
    }

    // MARK: - Icon helper

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
