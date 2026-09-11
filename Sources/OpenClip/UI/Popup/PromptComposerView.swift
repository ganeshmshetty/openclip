// PromptComposerView.swift
// OpenClip
//
// The Ask AI composer: what the "Ask AI" bar button swaps the bar for. One field for a free-form
// instruction about the selected text, with the user's recent instructions listed underneath
// (most recent first, filtered as they type) so a prompt they keep reusing is one arrow key or
// ⌘-digit away, and ⇧⏎ to keep the highlighted instruction as a permanent AI tool. Rows behave
// like palette results: arrows + Return, hover, click, ⌘1…⌘9. It renders inside the popup's
// search mode — a scoped palette whose parent `composesPrompt` — so key mode, field focus,
// placement and Esc all come from the existing palette plumbing (`PopupWindowController.enterSearch`).
import SwiftUI
import AppKit
import Core

/// One row of the composer, in display order.
enum PromptComposerRow: Hashable {
    /// Run the typed text as a new instruction.
    case ask(String)
    /// Run a recent instruction again.
    case recent(String)

    var prompt: String {
        switch self {
        case .ask(let prompt), .recent(let prompt): return prompt
        }
    }
}

/// Pure row rules for the composer, unit-tested without hosting SwiftUI.
enum PromptComposerModel {
    /// The rows for `query`: the query itself first (unless blank, or it is exactly a recent),
    /// then the recents that contain it — every recent for a blank query — most recent first.
    static func rows(query: String, recents: [String]) -> [PromptComposerRow] {
        let instruction = AIPromptText.instruction(from: query)
        let needle = instruction.lowercased()
        let matching = needle.isEmpty ? recents : recents.filter { $0.lowercased().contains(needle) }
        var rows: [PromptComposerRow] = []
        if !instruction.isEmpty, !matching.contains(where: { $0.lowercased() == needle }) {
            rows.append(.ask(instruction))
        }
        rows.append(contentsOf: matching.map { .recent($0) })
        return rows
    }
}

@MainActor
struct PromptComposerView: View {
    let context: ActionContext
    let recents: [String]
    /// The most room the composer may take (the palette's remembered size); nil = default column.
    let maxSize: CGSize?
    /// Runs the instruction once on the selection (⏎, click, ⌘-digit).
    let onRun: @MainActor (String) -> Void
    /// Saves the instruction as a custom AI tool and runs it (⇧⏎).
    let onSave: @MainActor (String) -> Void
    /// Esc / the esc button: back to the bar.
    let onExit: @MainActor () -> Void
    /// Whether AI is on; off, the composer explains itself instead of listing rows.
    var aiEnabled: Bool = AIServiceManager.shared.isAIEnabled

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var hoveredIndex: Int?
    @State private var isEscHovered = false
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.popupEffectiveTheme) private var effectiveTheme

    private var rows: [PromptComposerRow] {
        aiEnabled ? PromptComposerModel.rows(query: query, recents: recents) : []
    }

    private static let footerHeight: CGFloat = 22

    private var cardWidth: CGFloat {
        min(max(maxSize?.width ?? PopupMetrics.searchPanelContentWidth, PopupMetrics.searchPaletteMinWidth), PopupMetrics.searchPanelContentWidth)
    }

    /// Field inset + rows + the hint footer, floored at the palette minimum and capped at the
    /// palette's default column (or the remembered height), scrolling beyond it.
    private var cardHeight: CGFloat {
        let natural = PopupSearchView.height(forRows: max(rows.count, 1)) + Self.footerHeight
        let cap = (maxSize?.height ?? PopupSearchView.defaultHeight) + Self.footerHeight
        return min(max(natural, PopupMetrics.searchPaletteMinHeight), max(cap, PopupMetrics.searchPaletteMinHeight))
    }

    var body: some View {
        ZStack(alignment: .top) {
            rowsList

            fieldRow
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .top)

            footer
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(CommandDigitCatcher { row in runRow(at: row - 1) })
        .popupCardChrome(cornerRadius: PopupMetrics.searchCornerRadius, effectiveTheme: effectiveTheme, colorScheme: colorScheme)
        .onChange(of: query) { _, _ in selectedIndex = 0 }
        .onAppear { isFocused = true }
    }

    // MARK: Field

    private var fieldRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            TextField(String(localized: "Ask AI to…"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(PopupThemeModel.restForeground(for: effectiveTheme))
                .focused($isFocused)
                .onKeyPress { press in
                    switch press.key {
                    case .escape:
                        onExit()
                        return .handled
                    case .upArrow:
                        moveSelection(by: -1)
                        return .handled
                    case .downArrow:
                        moveSelection(by: 1)
                        return .handled
                    case .return:
                        runSelected(save: press.modifiers.contains(.shift))
                        return .handled
                    default:
                        return .ignored
                    }
                }

            Button(action: onExit) {
                Text("esc")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(isEscHovered ? PopupThemeModel.restForeground(for: effectiveTheme) : PopupThemeModel.restSecondary(for: effectiveTheme))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(isEscHovered ? Color.primary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(isEscHovered ? Color.primary.opacity(0.25) : Color.secondary.opacity(colorScheme == .dark ? 0.35 : 0.22), lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to actions")
            .onHover { isEscHovered = $0 }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 34)
        .background(fieldBackground)
    }

    private var fieldBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let strokeColor = colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12)
        return shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(Color.black.opacity(colorScheme == .dark ? 0.28 : 0.06)))
            .overlay(shape.stroke(strokeColor, lineWidth: 0.5))
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.14), radius: 6, x: 0, y: 2.5)
    }

    // MARK: Rows

    private var rowsList: some View {
        ScrollView {
            if rows.isEmpty {
                VStack(spacing: 4) {
                    Text(aiEnabled
                         ? String(localized: "Type what AI should do with the selected text")
                         : String(localized: "AI is switched off in Preferences"))
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)
                        .foregroundColor(PopupThemeModel.restSecondary(for: effectiveTheme))
                }
                .frame(maxWidth: .infinity, minHeight: cardHeight - 56 - Self.footerHeight)
                .padding(.top, 48)
                .padding(.horizontal, 16)
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                        rowView(row, index: index)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 48)
                .padding(.bottom, Self.footerHeight + 4)
            }
        }
        .frame(height: cardHeight)
    }

    private func rowView(_ row: PromptComposerRow, index: Int) -> some View {
        let isSelected = index == selectedIndex
        let isHovered = hoveredIndex == index
        let shape = RoundedRectangle(cornerRadius: PopupMetrics.searchRowCornerRadius, style: .continuous)
        let foreground = isSelected ? Color.primary : PopupThemeModel.restForeground(for: effectiveTheme)
        let title: String
        let symbol: String
        switch row {
        case .ask(let prompt):
            title = String(localized: "Ask AI: “\(prompt)”")
            symbol = "sparkles"
        case .recent(let prompt):
            title = prompt
            symbol = "clock.arrow.circlepath"
        }

        return Button {
            selectedIndex = index
            runSelected(save: NSEvent.modifierFlags.contains(.shift))
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 18, alignment: .center)
                    .foregroundColor(foreground)
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(foreground)
                Spacer(minLength: 8)
                if let shortcut = PopupSearchView.shortcutHint(forRow: index) {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(isSelected ? PopupThemeModel.restForeground(for: effectiveTheme) : PopupThemeModel.restSecondary(for: effectiveTheme))
                        .accessibilityLabel("Command \(index + 1)")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: PopupMetrics.searchResultRowHeight)
            .background(
                Group {
                    if isSelected {
                        shape.fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
                            .overlay(shape.stroke(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05), lineWidth: 0.5))
                    } else if isHovered {
                        shape.fill(Color.primary.opacity(0.06))
                    } else {
                        Color.clear
                    }
                }
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .onHover { hovering in
            if hovering {
                hoveredIndex = index
                selectedIndex = index
            } else if hoveredIndex == index {
                hoveredIndex = nil
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        Text(String(localized: "⏎ run · ⇧⏎ save as AI tool"))
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundColor(PopupThemeModel.restSecondary(for: effectiveTheme).opacity(0.8))
            .frame(maxWidth: .infinity)
            .frame(height: Self.footerHeight)
            .padding(.bottom, 2)
            .allowsHitTesting(false)
    }

    // MARK: Running

    private func moveSelection(by delta: Int) {
        guard !rows.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), rows.count - 1)
    }

    /// Runs the 1-based row a ⌘-digit points at; false when there is no such row.
    private func runRow(at index: Int) -> Bool {
        guard index >= 0, index < PopupSearchView.maxShortcutRows, rows.indices.contains(index) else { return false }
        selectedIndex = index
        runSelected(save: false)
        return true
    }

    private func runSelected(save: Bool) {
        guard rows.indices.contains(selectedIndex) else { return }
        let prompt = rows[selectedIndex].prompt
        if save { onSave(prompt) } else { onRun(prompt) }
    }
}
