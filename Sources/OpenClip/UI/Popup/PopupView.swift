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
    @State private var isShowingCompletions: Bool = true
    @State private var hoveredButtonID: String?
    @State private var hoverFrames: [String: CGRect] = [:]

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

    private var displayActions: [any Action] {
        actions.filter { $0.id != "builtin.completion" && !$0.id.hasPrefix("builtin.transform.") }
    }

    private var pagedActions: [any Action] {
        let list = displayActions
        guard list.count > pageSize else { return list }
        let start = currentPage * pageSize
        let end = min(start + pageSize, list.count)
        guard start < list.count else { return Array(list.prefix(pageSize)) }
        return Array(list[start..<end])
    }

    private var totalPages: Int {
        max(1, Int(ceil(Double(displayActions.count) / Double(pageSize))))
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
            ChevronButtonView(systemImage: "chevron.up", width: chevronWidth, isHovered: hoveredButtonID == "completion-chevron") {
                isShowingCompletions = false
            }
            .popupHoverTarget("completion-chevron")
            
            // Horizontal Completion Word Items
            let list = availableCompletions
            ForEach(Array(list.enumerated()), id: \.offset) { index, word in
                let isLast = index == list.count - 1
                CompletionButtonView(word: word, selectedTheme: selectedTheme, buttonWidth: buttonWidth, showDivider: !isLast, isHovered: hoveredButtonID == "completion-\(index)", onResult: onResult)
                    .popupHoverTarget("completion-\(index)")
            }
        }
        .trackedPopupBar(onMove: updateHoveredButton, onExit: { hoveredButtonID = nil })
        .onPreferenceChange(PopupHoverFramePreferenceKey.self) { hoverFrames = $0 }
    }

    // MARK: - Normal Actions Bar Layout

    private var actionsHStack: some View {
        HStack(spacing: 0) {
            // If completions exist but user toggled to normal actions, show Down Arrow button on left
            if hasCompletions {
                ChevronButtonView(systemImage: "chevron.down", width: chevronWidth, isHovered: hoveredButtonID == "actions-chevron-down") {
                    isShowingCompletions = true
                }
                .popupHoverTarget("actions-chevron-down")
            } else if hasLeftChevron {
                ChevronButtonView(systemImage: "chevron.left", width: chevronWidth, isHovered: hoveredButtonID == "actions-chevron-left") { currentPage -= 1 }
                    .popupHoverTarget("actions-chevron-left")
            }

            ForEach(Array(pagedActions.enumerated()), id: \.offset) { index, action in
                let isLast = index == pagedActions.count - 1
                let showDivider = !isLast || hasRightChevron
                ActionButtonView(
                    action: action,
                    context: context,
                    selectedTheme: selectedTheme,
                    buttonWidth: buttonWidth,
                    showDivider: showDivider,
                    isHovered: hoveredButtonID == "action-\(index)",
                    enabledTransformCases: enabledTransformCases,
                    onResult: onResult
                )
                .popupHoverTarget("action-\(index)")
            }

            if !hasCompletions && hasRightChevron {
                ChevronButtonView(systemImage: "chevron.right", width: chevronWidth, isHovered: hoveredButtonID == "actions-chevron-right") { currentPage += 1 }
                    .popupHoverTarget("actions-chevron-right")
            }
        }
        .trackedPopupBar(onMove: updateHoveredButton, onExit: { hoveredButtonID = nil })
        .onPreferenceChange(PopupHoverFramePreferenceKey.self) { hoverFrames = $0 }
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

    private func updateHoveredButton(at location: CGPoint) {
        let nextID = hoverFrames.first { $0.value.contains(location) }?.key
        guard nextID != hoveredButtonID else { return }
        hoveredButtonID = nextID
    }
}

private struct PopupHoverFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension View {
    func popupHoverTarget(_ id: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PopupHoverFramePreferenceKey.self,
                    value: [id: proxy.frame(in: .named("popupHoverBar"))]
                )
            }
        }
    }

    func trackedPopupBar(onMove: @escaping (CGPoint) -> Void, onExit: @escaping () -> Void) -> some View {
        coordinateSpace(name: "popupHoverBar")
            .background(
                BarHoverTrackingView(
                    onMove: onMove,
                    onExit: onExit
                )
            )
            .fixedSize()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Subviews

struct CompletionButtonView: View {
    let word: String
    let selectedTheme: String
    let buttonWidth: CGFloat
    let showDivider: Bool
    let isHovered: Bool
    let onResult: (ActionResult) -> Void
    
    var body: some View {
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
    }
}

struct ActionButtonView: View {
    let action: any Action
    let context: ActionContext
    let selectedTheme: String
    let buttonWidth: CGFloat
    let showDivider: Bool
    let isHovered: Bool
    let enabledTransformCases: [TransformCase]
    let onResult: (ActionResult) -> Void
    
    var body: some View {
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

        let labelView = PopupIconView(icon: action.icon)
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
        }
    }
}

struct ChevronButtonView: View {
    let systemImage: String
    let width: CGFloat
    let isHovered: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isHovered ? .white : .secondary)
                .frame(width: width, height: 28)
                .background(isHovered ? Color.accentColor : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Icon Helper

struct PopupIconView: View {
    let icon: ActionIcon
    
    var body: some View {
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
        }
    }
}

// MARK: - Native AppKit Bar Hover Tracking

private struct BarHoverTrackingView: NSViewRepresentable {
    let onMove: (CGPoint) -> Void
    let onExit: () -> Void

    func makeNSView(context: Context) -> TrackingNSView {
        let view = TrackingNSView()
        view.onMove = onMove
        view.onExit = onExit
        return view
    }

    func updateNSView(_ nsView: TrackingNSView, context: Context) {
        nsView.onMove = onMove
        nsView.onExit = onExit
    }

    final class TrackingNSView: NSView {
        var onMove: ((CGPoint) -> Void)?
        var onExit: (() -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let existing = trackingArea {
                removeTrackingArea(existing)
            }
            let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeAlways]
            let newArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(newArea)
            self.trackingArea = newArea
        }

        override func mouseEntered(with event: NSEvent) {
            reportLocation(event)
        }

        override func mouseMoved(with event: NSEvent) {
            reportLocation(event)
        }

        override func mouseExited(with event: NSEvent) {
            onExit?()
        }

        private func reportLocation(_ event: NSEvent) {
            onMove?(convert(event.locationInWindow, from: nil))
        }
    }
}
