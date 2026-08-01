import SwiftUI
import AppKit
import CoreGraphics
import Core

// MARK: - Popup View

public struct PopupView: View {
    public let actions: [any Action]
    public let context: ActionContext
    public let onResult: @MainActor (ActionResult) -> Void

    @AppStorage("popupTheme") private var selectedTheme: String = "system"
    @Environment(\.colorScheme) private var colorScheme
    
    private var effectiveTheme: String {
        if selectedTheme == "system" {
            return colorScheme == .dark ? "dark" : "light"
        }
        return selectedTheme
    }
    
    @State private var currentPage = 0
    @ObservedObject private var hoverState = PopupHoverState.shared
    @State private var hoveredTarget: PopupHoverTarget?
    @State private var hoverFrames: [PopupHoverTarget: CGRect] = [:]
    @State private var isShowingCompletions: Bool = true
    @State private var isShowingAIMode: Bool = false
    @State private var aiResultText: String? = nil

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

    private var hasCompletions: Bool {
        return !availableCompletions.isEmpty
    }

    private var inCompletionMode: Bool {
        return hasCompletions && isShowingCompletions
    }

    private var enabledTransformCases: [TransformCase] {
        actions.compactMap { ($0 as? TransformSubAction)?.transformCase }
    }

    private var displayActions: [any Action] {
        actions.filter { $0.id != "builtin.completion" && !$0.id.hasPrefix("builtin.transform.") }
    }

    private var totalPages: Int {
        guard !displayActions.isEmpty else { return 1 }
        return Int(ceil(Double(displayActions.count) / Double(pageSize)))
    }

    private var pagedActions: [any Action] {
        let list = displayActions
        let startIndex = currentPage * pageSize
        guard startIndex < list.count else { return [] }
        let endIndex = min(startIndex + pageSize, list.count)
        return Array(list[startIndex..<endIndex])
    }

    private var hasLeftChevron: Bool { currentPage > 0 }
    private var hasRightChevron: Bool { currentPage < totalPages - 1 }

    public var body: some View {
        barContent
            .padding(12)
            .coordinateSpace(name: "popupHoverSpace")
            .onPreferenceChange(PopupHoverFramePreferenceKey.self) { frames in
                hoverFrames = frames
                updateHoveredTarget(for: hoverState.location)
            }
            .onReceive(hoverState.$location) { location in
                updateHoveredTarget(for: location)
            }
    }

    // MARK: - Unified Bar Container

    @ViewBuilder
    private var barContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if effectiveTheme == "glass" {
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
                            .stroke(opaqueBorder, lineWidth: 1.0)
                    )
                    .shadow(color: .black.opacity(effectiveTheme == "light" ? 0.16 : 0.32), radius: 10, x: 0, y: 4)
            }
            
            if let result = aiResultText {
                AIResultOverlayView(
                    resultText: result,
                    onReplace: {
                        onResult(.paste(result))
                        aiResultText = nil
                    },
                    onCopy: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result, forType: .string)
                        aiResultText = nil
                    },
                    onClose: {
                        aiResultText = nil
                    }
                )
            }
        }
    }

    // MARK: - Unified HStack Layout

    @ViewBuilder
    private var unifiedHStack: some View {
        if isShowingAIMode {
            aiHStack
        } else if inCompletionMode {
            completionHStack
        } else {
            actionsHStack
        }
    }

    // MARK: - AI Mode Bar Layout

    private var aiHStack: some View {
        HStack(spacing: 0) {
            chevronButton(systemImage: "chevron.left") {
                isShowingAIMode = false
            }
            
            let aiPresets = [
                ("Fix", "Proofread and fix grammar"),
                ("Summarize", "Summarize text"),
                ("Translate", "Translate text to English"),
                ("Explain", "Explain concept or code")
            ]
            
            ForEach(Array(aiPresets.enumerated()), id: \.offset) { index, preset in
                let (title, prompt) = preset
                let isLast = index == aiPresets.count - 1
                
                Button(action: {
                    Task {
                        do {
                            let provider = AIServiceManager.shared.currentProvider
                            let response = try await provider.process(prompt: prompt, text: context.selection.text)
                            if provider.type != .browser {
                                aiResultText = response
                            }
                        } catch {
                            aiResultText = "AI Error: \(error.localizedDescription)"
                        }
                    }
                }) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 10)
                        .frame(minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .trailing) {
                    if !isLast {
                        Rectangle()
                            .fill(Color.primary.opacity(0.12))
                            .frame(width: 0.6, height: 28)
                    }
                }
            }
        }
        .fixedSize()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                let isHovered = hoveredTarget == .completion(index)
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
                let showDivider = true
                let isHovered = hoveredTarget == .action(index)
                actionButton(action: action, index: index, isHovered: isHovered, showDivider: showDivider)
            }

            // Sparkles AI Button (if enabled)
            if AIServiceManager.shared.isAIEnabled {
                Button(action: {
                    isShowingAIMode = true
                }) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.accentColor)
                        .frame(width: buttonWidth, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open AI Tools")
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
            switch effectiveTheme {
            case "light": return .black.opacity(0.85)
            case "dark": return .white.opacity(0.90)
            default: return .primary
            }
        }()

        let dividerColor: Color = {
            switch effectiveTheme {
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
        .popupHoverTarget(.completion(index))
        .onHover { isHovering in
            useLocalHoverFallback(for: .completion(index), isHovering: isHovering)
        }
    }

    // MARK: - Unified Action Button

    @ViewBuilder
    private func actionButton(action: any Action, index: Int, isHovered: Bool, showDivider: Bool) -> some View {
        let restForeground: Color = {
            switch effectiveTheme {
            case "light": return .black.opacity(0.85)
            case "dark": return .white.opacity(0.90)
            default: return .primary
            }
        }()
        
        let dividerColor: Color = {
            switch effectiveTheme {
            case "light": return .black.opacity(0.12)
            case "dark": return .white.opacity(0.14)
            default: return .white.opacity(0.20)
            }
        }()

        let labelView = iconView(for: action.displayIcon)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(isHovered ? .white : restForeground)
            .padding(.horizontal, {
                if case .text = action.displayIcon { return 7.0 }
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
            Button {
                showTransformMenu(selectionText: context.selection.text)
            } label: {
                labelView
            }
            .buttonStyle(.plain)
            .help(action.displayTitle)
            .popupHoverTarget(.action(index))
            .onHover { isHovering in
                useLocalHoverFallback(for: .action(index), isHovering: isHovering)
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
            .popupHoverTarget(.action(index))
            .onHover { isHovering in
                useLocalHoverFallback(for: .action(index), isHovering: isHovering)
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
        .popupHoverTarget(.chevron)
        .onHover { isHovering in
            useLocalHoverFallback(for: .chevron, isHovering: isHovering)
        }
    }

    // MARK: - Opaque Background Helpers

    @ViewBuilder
    private var opaqueBackground: some View {
        switch effectiveTheme {
        case "dark":
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.20, green: 0.20, blue: 0.22))
        default:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.98, green: 0.98, blue: 0.99))
        }
    }

    private var opaqueBorder: Color {
        effectiveTheme == "light" ? Color.black.opacity(0.20) : Color.white.opacity(0.22)
    }

    private func updateHoveredTarget(for location: CGPoint?) {
        let target = location.flatMap { point in
            hoverFrames.first(where: { $0.value.contains(point) })?.key
        }
        guard target != hoveredTarget else { return }
        hoveredTarget = target
    }

    private func useLocalHoverFallback(for target: PopupHoverTarget, isHovering: Bool) {
        guard !hoverState.usesGlobalMouseMonitoring else { return }
        if isHovering {
            hoveredTarget = target
        } else if hoveredTarget == target {
            hoveredTarget = nil
        }
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

    private func showTransformMenu(selectionText: String) {
        let menu = NSMenu(title: "Text Transformations")
        
        for category in TransformCategory.allCases {
            let catCases = enabledTransformCases.filter { $0.category == category }
            if !catCases.isEmpty {
                let header = NSMenuItem(title: category.rawValue, action: nil, keyEquivalent: "")
                header.isEnabled = false
                menu.addItem(header)
                
                for tCase in catCases {
                    let item = NSMenuItem(title: "  \(tCase.displayName)", action: #selector(MenuItemTarget.trigger), keyEquivalent: "")
                    let target = MenuItemTarget {
                        let res = tCase.transform(selectionText)
                        self.onResult(.paste(res))
                    }
                    item.target = target
                    objc_setAssociatedObject(item, &MenuItemTarget.assocKey, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                    menu.addItem(item)
                }
                menu.addItem(NSMenuItem.separator())
            }
        }
        
        if menu.items.last?.isSeparatorItem == true {
            menu.items.removeLast()
        }
        
        let mouseLoc = NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: mouseLoc, in: nil)
    }
}

@MainActor
final class PopupHoverState: ObservableObject {
    static let shared = PopupHoverState()

    @Published var location: CGPoint?
    @Published var usesGlobalMouseMonitoring = false

    private init() {}
}

private enum PopupHoverTarget: Hashable {
    case action(Int)
    case completion(Int)
    case chevron
}

private struct PopupHoverFramePreferenceKey: PreferenceKey {
    static let defaultValue: [PopupHoverTarget: CGRect] = [:]

    static func reduce(value: inout [PopupHoverTarget: CGRect], nextValue: () -> [PopupHoverTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension View {
    func popupHoverTarget(_ target: PopupHoverTarget) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PopupHoverFramePreferenceKey.self,
                    value: [target: proxy.frame(in: .named("popupHoverSpace"))]
                )
            }
        }
    }
}

private class MenuItemTarget: NSObject {
    nonisolated(unsafe) static var assocKey: UInt8 = 0
    let handler: () -> Void
    
    init(handler: @escaping () -> Void) {
        self.handler = handler
    }
    
    @objc func trigger() {
        handler()
    }
}
