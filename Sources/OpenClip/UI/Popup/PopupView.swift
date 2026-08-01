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
    @State private var hoveredCompletionIndex: Int? = nil
    @State private var isShowingCompletions: Bool = true

    private let buttonWidth: CGFloat = 36
    private let chevronWidth: CGFloat = 26
    private let pageSize = 8

    public init(actions: [any Action], context: ActionContext, onResult: @escaping @MainActor (ActionResult) -> Void) {
        self.actions = actions
        self.context = context
        self.onResult = onResult
    }

    private var availableCompletions: [String] {
        guard let provider = actions.first(where: { $0 is any WordCompletionProviding }) as? any WordCompletionProviding,
              provider.isEnabled(for: context) else { return [] }
        return provider.fetchCompletions(for: context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var hasCompletions: Bool { !availableCompletions.isEmpty }
    private var inCompletionMode: Bool { hasCompletions && isShowingCompletions }

    private var enabledTransformCases: [TransformCase] {
        actions.compactMap { ($0 as? TransformSubAction)?.transformCase }
    }

    private var pagedActions: [any Action] {
        let filtered = actions.filter { $0.id != "builtin.completion" && !$0.id.hasPrefix("builtin.transform.") }
        guard filtered.count > pageSize else { return filtered }
        let start = currentPage * pageSize
        let end = min(start + pageSize, filtered.count)
        guard start < filtered.count else { return Array(filtered.prefix(pageSize)) }
        return Array(filtered[start..<end])
    }

    private var totalPages: Int {
        max(1, Int(ceil(Double(actions.count) / Double(pageSize))))
    }

    private var hasLeftChevron: Bool { totalPages > 1 && currentPage > 0 }
    private var hasRightChevron: Bool { totalPages > 1 && currentPage < totalPages - 1 }

    public var body: some View {
        barContent
            .padding(12)
    }

    // MARK: - Unified Bar Container

    @ViewBuilder
    private var barContent: some View {
        if selectedTheme == "glass" {
            if #available(macOS 26, *) {
                unifiedHStack
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                unifiedHStack
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 4)
            }
        } else {
            unifiedHStack
                .background(opaqueBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(opaqueBorder, lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(selectedTheme == "light" ? 0.16 : 0.32), radius: 10, x: 0, y: 4)
        }
    }

    // MARK: - Unified HStack Layout

    @ViewBuilder
    private var unifiedHStack: some View {
        if inCompletionMode {
            completionHStack
        } else {
            actionsHStack
        }
    }

    // MARK: - Completion Mode Bar Layout

    private var completionHStack: some View {
        HStack(spacing: 0) {
            // Far Left: Up Arrow button toggles to normal actions mode
            chevronButton(systemImage: "chevron.up") {
                isShowingCompletions = false
            }
            
            // Horizontal Completion Word Items
            let list = availableCompletions
            ForEach(Array(list.enumerated()), id: \.offset) { index, word in
                let isLast = index == list.count - 1
                let isHovered = hoveredCompletionIndex == index
                completionButton(word: word, index: index, isHovered: isHovered, showDivider: !isLast)
            }
        }
        .fixedSize()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Normal Actions Bar Layout

    private var actionsHStack: some View {
        HStack(spacing: 0) {
            // If completions exist but user toggled to normal actions, show Down Arrow button on left
            if hasCompletions {
                chevronButton(systemImage: "chevron.down") {
                    isShowingCompletions = true
                }
            } else if hasLeftChevron {
                chevronButton(systemImage: "chevron.left") { currentPage -= 1 }
            }

            ForEach(Array(pagedActions.enumerated()), id: \.offset) { index, action in
                let isLast = index == pagedActions.count - 1
                let showDivider = !isLast || hasRightChevron
                let isHovered = hoveredIndex == index
                actionButton(action: action, index: index, isHovered: isHovered, showDivider: showDivider)
            }

            if !hasCompletions && hasRightChevron {
                chevronButton(systemImage: "chevron.right") { currentPage += 1 }
            }
        }
        .fixedSize()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Completion Button

    @ViewBuilder
    private func completionButton(word: String, index: Int, isHovered: Bool, showDivider: Bool) -> some View {
        let restForeground: Color = {
            switch selectedTheme {
            case "light": return .black.opacity(0.85)
            case "dark": return .white.opacity(0.90)
            default: return .primary
            }
        }()

        let dividerColor: Color = {
            switch selectedTheme {
            case "light": return .black.opacity(0.12)
            case "dark": return .white.opacity(0.14)
            default: return .white.opacity(0.20)
            }
        }()

        Button {
            onResult(.paste(word))
        } label: {
            Text(word)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isHovered ? .white : restForeground)
                .padding(.horizontal, 10)
                .frame(minWidth: buttonWidth, minHeight: 28)
                .background(isHovered ? Color.accentColor : Color.clear)
                .overlay(alignment: .trailing) {
                    if showDivider && !isHovered {
                        Rectangle()
                            .fill(dividerColor)
                            .frame(width: 0.6, height: 28)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering {
                hoveredCompletionIndex = index
            } else if hoveredCompletionIndex == index {
                hoveredCompletionIndex = nil
            }
        }
    }

    // MARK: - Unified Action Button

    @ViewBuilder
    private func actionButton(action: any Action, index: Int, isHovered: Bool, showDivider: Bool) -> some View {
        let restForeground: Color = {
            switch selectedTheme {
            case "light": return .black.opacity(0.85)
            case "dark": return .white.opacity(0.90)
            default: return .primary
            }
        }()
        
        let dividerColor: Color = {
            switch selectedTheme {
            case "light": return .black.opacity(0.12)
            case "dark": return .white.opacity(0.14)
            default: return .white.opacity(0.20)
            }
        }()

        let labelView = iconView(for: action.icon)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(isHovered ? .white : restForeground)
            .padding(.horizontal, {
                if case .text = action.icon { return 7.0 }
                return 0.0
            }())
            .frame(minWidth: buttonWidth, minHeight: 28)
            .background(isHovered ? Color.accentColor : Color.clear)
            .overlay(alignment: .trailing) {
                if showDivider && !isHovered {
                    Rectangle()
                        .fill(dividerColor)
                        .frame(width: 0.6, height: 28)
                }
            }
            .contentShape(Rectangle())

        if action.id == "builtin.transform" {
            Menu {
                ForEach(TransformCategory.allCases, id: \.rawValue) { category in
                    let catCases = enabledTransformCases.filter { $0.category == category }
                    if !catCases.isEmpty {
                        Section(category.rawValue) {
                            ForEach(catCases) { tCase in
                                Button(tCase.displayName) {
                                    let res = tCase.transform(context.selection.text)
                                    onResult(.paste(res))
                                }
                            }
                        }
                    }
                }
            } label: {
                labelView
            }
            .menuStyle(.borderlessButton)
            .help(action.title)
            .onHover { isHovering in
                if isHovering {
                    hoveredIndex = index
                } else if hoveredIndex == index {
                    hoveredIndex = nil
                }
            }
        } else {
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
                labelView
            }
            .buttonStyle(.plain)
            .help(action.title)
            .onHover { isHovering in
                if isHovering {
                    hoveredIndex = index
                } else if hoveredIndex == index {
                    hoveredIndex = nil
                }
            }
        }
    }

    @ViewBuilder
    private func chevronButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: chevronWidth, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Opaque Background Helpers

    @ViewBuilder
    private var opaqueBackground: some View {
        switch selectedTheme {
        case "dark":
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
        default:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.98, green: 0.98, blue: 0.99))
        }
    }

    private var opaqueBorder: Color {
        selectedTheme == "light" ? Color.black.opacity(0.12) : Color.white.opacity(0.14)
    }

    // MARK: - Icon Helper

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
                Image(systemName: "exclamationmark.triangle")
            }
        case .text(let text):
            Text(text)
                .font(.system(size: 13, weight: .medium))
        }
    }
}
