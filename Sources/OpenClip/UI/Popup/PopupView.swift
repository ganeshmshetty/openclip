import SwiftUI
import AppKit
import CoreGraphics
import Core
import SDWebImageSwiftUI

// MARK: - Popup View

public struct PopupView: View {
    public let actions: [any Action]
    public let context: ActionContext
    public let onResult: @MainActor (ActionResult) -> Void
    public let onContentSizeChange: (@MainActor (CGSize) -> Void)?
    /// active=true when AI is running or showing result; cardAboveBar=true when the card should render above the bar
    public let onAIStateChange: (@MainActor (Bool, Bool) -> Void)?
    /// Called with (resultText, isError) when the AI result is ready to show in a separate overlay panel
    public let onAIResult: (@MainActor (String, Bool) -> Void)?
    /// Called when the AI overlay should be dismissed
    public let onAIDismiss: (@MainActor () -> Void)?

    @AppStorage("popupTheme") private var selectedTheme: String = "system"
    @Environment(\.colorScheme) private var colorScheme
    
    private var effectiveTheme: String {
        if selectedTheme == "system" {
            return colorScheme == .dark ? "dark" : "light"
        }
        return selectedTheme
    }
    
    @AppStorage("completionCopyToClipboard") private var completionCopyToClipboard: Bool = false
    
    @State private var currentPage = 0
    @ObservedObject private var hoverState = PopupHoverState.shared
    @State private var hoveredTarget: PopupHoverTarget?
    @State private var hoverFrames: [PopupHoverTarget: CGRect] = [:]
    @State private var isShowingCompletions: Bool = true
    @State private var isShowingAIMode: Bool = false
    @State private var aiOverlay: AIOverlayState? = nil
    @State private var isProcessingAI: Bool = false
    @State private var aiTask: Task<Void, Never>? = nil
    /// Captured once when the popup appears — never re-read from mouse location to avoid jitter.
    @State private var aiCardAboveBar: Bool = false
    @State private var glowOffset: CGFloat = -1.0

    private let buttonWidth: CGFloat = 36
    private let chevronWidth: CGFloat = 26
    private let pageSize = 8


    public init(
        actions: [any Action],
        context: ActionContext,
        initialAICardAboveBar: Bool = false,
        onResult: @escaping @MainActor (ActionResult) -> Void,
        onContentSizeChange: (@MainActor (CGSize) -> Void)? = nil,
        onAIStateChange: (@MainActor (Bool, Bool) -> Void)? = nil,
        onAIResult: (@MainActor (String, Bool) -> Void)? = nil,
        onAIDismiss: (@MainActor () -> Void)? = nil
    ) {
        self.actions = actions
        self.context = context
        self.onResult = onResult
        self.onContentSizeChange = onContentSizeChange
        self.onAIStateChange = onAIStateChange
        self.onAIResult = onAIResult
        self.onAIDismiss = onAIDismiss
        self._aiCardAboveBar = State(initialValue: initialAICardAboveBar)
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
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: PopupContentSizePreferenceKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(PopupHoverFramePreferenceKey.self) { frames in
                hoverFrames = frames
                updateHoveredTarget(for: hoverState.location)
            }
            .onPreferenceChange(PopupContentSizePreferenceKey.self) { size in
                guard size.width > 0, size.height > 0 else { return }
                onContentSizeChange?(size)
            }
            .onReceive(hoverState.$location) { location in
                updateHoveredTarget(for: location)
            }
            .onChange(of: aiOverlay != nil || isProcessingAI) { active in
                onAIStateChange?(active, aiCardAboveBar)
            }
            .onDisappear {
                cancelAITask()
            }
    }

    // MARK: - Unified Bar Container

    @ViewBuilder
    private var barContent: some View {
        // Bar only — AI overlay lives in its own separate NSPanel managed by PopupWindowController
        mainBarStyled
    }


    @ViewBuilder
    private var mainBarStyled: some View {
        let baseView = Group {
            if effectiveTheme == "glass" {
                let glassBorderColor: Color = colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.20)
                
                if #available(macOS 26, *) {
                    unifiedHStack
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(glassBorderColor, lineWidth: 1.0)
                        )
                        .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 4)
                } else {
                    unifiedHStack
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(glassBorderColor, lineWidth: 1.0)
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
        }

        baseView.overlay(processingGlowBorder)
    }

    @ViewBuilder
    private var processingGlowBorder: some View {
        if isProcessingAI {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.blue.opacity(0.3),
                            Color.blue,
                            Color.cyan,
                            Color.blue,
                            Color.blue.opacity(0.3),
                            Color.clear
                        ],
                        startPoint: UnitPoint(x: glowOffset, y: 0.5),
                        endPoint: UnitPoint(x: glowOffset + 1.2, y: 0.5)
                    ),
                    lineWidth: 2.0
                )
                .shadow(color: Color.blue.opacity(0.8), radius: 6, x: 0, y: 0)
                .onAppear {
                    glowOffset = -1.0
                    withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                        glowOffset = 1.0
                    }
                }
        }
    }

    @ViewBuilder
    private var aiSubCard: some View {
        if isProcessingAI {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Working…")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
                Button("Cancel") {
                    cancelAITask()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minWidth: 200)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
        } else if let overlay = aiOverlay {
            AIResultOverlayView(
                resultText: overlay.text,
                isError: overlay.isError,
                onReplace: {
                    onResult(.paste(overlay.text))
                    clearAIOverlay()
                },
                onCopy: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(overlay.text, forType: .string)
                    clearAIOverlay()
                },
                onClose: {
                    clearAIOverlay()
                }
            )
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
                exitAIMode()
            }
            
            let aiPresets = [
                ("Proofread", "Fix spelling and grammar errors"),
                ("Rewrite", "Rephrase and polish text"),
                ("Summarize", "Summarize text into key points")
            ]
            
            ForEach(Array(aiPresets.enumerated()), id: \.offset) { index, preset in
                let (title, prompt) = preset
                let isLast = index == aiPresets.count - 1
                let isHovered = hoveredTarget == .aiPreset(index)
                
                let restForeground: Color = {
                    switch effectiveTheme {
                    case "light": return .black.opacity(0.85)
                    case "dark": return .white.opacity(0.90)
                    default: return .primary
                    }
                }()
                
                Button(action: {
                    runAIPreset(prompt: prompt)
                }) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isHovered ? .white : restForeground)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 28)
                        .background(isHovered ? Color.accentColor : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isProcessingAI)
                .help(prompt)
                .popupHoverTarget(.aiPreset(index))
                .onHover { isHovering in
                    useLocalHoverFallback(for: .aiPreset(index), isHovering: isHovering)
                }
                .overlay(alignment: .trailing) {
                    if !isLast && !isHovered {
                        Rectangle()
                            .fill(Color.primary.opacity(0.12))
                            .frame(width: 0.6, height: 28)
                    }
                }
            }
        }
        .fixedSize()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(isProcessingAI ? 0.7 : 1.0)
    }

    // MARK: - AI Helpers

    private func runAIPreset(prompt: String) {
        cancelAITask()
        onAIDismiss?()

        let selectionText = context.selection.text
        aiTask = Task { @MainActor in
            isProcessingAI = true
            defer {
                if !Task.isCancelled {
                    isProcessingAI = false
                }
            }

            do {
                let provider = AIServiceManager.shared.currentProvider
                let response = try await provider.process(prompt: prompt, text: selectionText)
                guard !Task.isCancelled else { return }

                if provider.type == .browser || response.isEmpty {
                    if response.isEmpty { onResult(.success) }
                } else {
                    onAIResult?(response, false)
                }
            } catch is CancellationError {
                // no-op
            } catch let error as AIError where error == .cancelled {
                // no-op
            } catch {
                guard !Task.isCancelled else { return }
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                onAIResult?(message, true)
            }
        }
    }

    private func exitAIMode() {
        cancelAITask()
        isShowingAIMode = false
        onAIDismiss?()
    }

    private func cancelAITask() {
        aiTask?.cancel()
        aiTask = nil
        isProcessingAI = false
    }

    private func clearAIOverlay() {
        onAIDismiss?()
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
                let isHovered = hoveredTarget == .sparkles
                Button(action: {
                    isShowingAIMode = true
                }) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isHovered ? .white : .accentColor)
                        .frame(width: buttonWidth, height: 28)
                        .background(isHovered ? Color.accentColor : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open AI Tools")
                .popupHoverTarget(.sparkles)
                .onHover { isHovering in
                    useLocalHoverFallback(for: .sparkles, isHovering: isHovering)
                }
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
            if name.contains(":") {
                // Iconify format "prefix:name" — render via SDWebImage + SVGCoder
                AnyIconView(iconId: name)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: name)
            }
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
    case sparkles
    case aiPreset(Int)
}

private struct AIOverlayState: Equatable {
    let text: String
    let isError: Bool
}

private struct PopupHoverFramePreferenceKey: PreferenceKey {
    static let defaultValue: [PopupHoverTarget: CGRect] = [:]

    static func reduce(value: inout [PopupHoverTarget: CGRect], nextValue: () -> [PopupHoverTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct PopupContentSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
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
