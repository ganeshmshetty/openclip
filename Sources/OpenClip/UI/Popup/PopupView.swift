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
        if #available(macOS 26.0, *) {
            liquidGlassBody
        } else {
            legacyBody
        }
    }

    // MARK: - Liquid Glass (macOS 26+)

    @available(macOS 26.0, *)
    private var liquidGlassBody: some View {
        // GlassEffectContainer lets all child glass shapes morph into each other — fluid hover transitions.
        GlassEffectContainer {
            HStack(spacing: 0) {
                if hasLeftChevron {
                    chevronButtonGlass(systemImage: "chevron.left") { currentPage -= 1 }
                    Divider().frame(height: 18).opacity(0.4)
                }

                ForEach(Array(pagedActions.enumerated()), id: \.offset) { index, action in
                    let isHovered = hoveredIndex == index
                    let isLast = index == pagedActions.count - 1
                    let showDivider = (!isLast || hasRightChevron) && !isHovered
                    actionButtonGlass(action: action, index: index, isHovered: isHovered, showDivider: showDivider)
                }

                if hasRightChevron {
                    Divider().frame(height: 18).opacity(0.4)
                    chevronButtonGlass(systemImage: "chevron.right") { currentPage += 1 }
                }
            }
            .fixedSize()
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                let xOffset = location.x - (hasLeftChevron ? chevronWidth + 1 : 0)
                let idx = Int(xOffset / buttonWidth)
                hoveredIndex = (xOffset >= 0 && idx >= 0 && idx < pagedActions.count) ? idx : nil
            case .ended:
                hoveredIndex = nil
            }
        }
        // Native Liquid Glass pill — handles blur, refraction, adaptivity automatically
        .glassEffect(.regular.interactive(), in: .capsule)
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 5)
        .padding(18)
    }

    @available(macOS 26.0, *)
    @ViewBuilder
    private func actionButtonGlass(action: any Action, index: Int, isHovered: Bool, showDivider: Bool) -> some View {
        let btn = Button {
            Task {
                do { let result = try await action.perform(context); onResult(result) }
                catch { print("Action failed: \(error)") }
            }
        } label: {
            iconView(for: action.icon)
                .font(.system(size: 14, weight: .medium))
                .frame(width: buttonWidth, height: 32)
                .contentShape(Rectangle())
                .overlay(alignment: .trailing) {
                    if showDivider {
                        Rectangle()
                            .fill(.primary.opacity(0.12))
                            .frame(width: 0.6, height: 20)
                    }
                }
        }
        // glassProminent = filled accent glass on hover; glass = subtle rest state
        // Must be separate branches since two ButtonStyle types can't be inferred from ternary
        if isHovered {
            btn.buttonStyle(.glassProminent).help(action.title)
        } else {
            btn.buttonStyle(.glass).help(action.title)
        }
    }

    @available(macOS 26.0, *)
    @ViewBuilder
    private func chevronButtonGlass(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: chevronWidth, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.glass)
    }

    // MARK: - Legacy fallback (macOS 14–25)

    private var legacyBody: some View {
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
            switch phase {
            case .active(let location):
                let xOffset = location.x - (hasLeftChevron ? chevronWidth + 1 : 0)
                let idx = Int(xOffset / buttonWidth)
                hoveredIndex = (xOffset >= 0 && idx >= 0 && idx < pagedActions.count) ? idx : nil
            case .ended:
                hoveredIndex = nil
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 4)
        .padding(18)
    }

    @ViewBuilder
    private func legacyActionButton(action: any Action, index: Int, isHovered: Bool, showDivider: Bool) -> some View {
        Button {
            Task {
                do { let result = try await action.perform(context); onResult(result) }
                catch { print("Action failed: \(error)") }
            }
        } label: {
            iconView(for: action.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isHovered ? .white : .primary.opacity(0.85))
                .frame(width: buttonWidth, height: 32)
                .background(isHovered ? Color.accentColor : Color.clear)
                .overlay(alignment: .trailing) {
                    if showDivider && !isHovered {
                        Rectangle().fill(.primary.opacity(0.15)).frame(width: 0.6, height: 32)
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

    // MARK: - Shared helpers

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
