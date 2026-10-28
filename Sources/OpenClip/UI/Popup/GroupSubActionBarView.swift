// GroupSubActionBarView.swift
// OpenClip
//
// Horizontal sub-bar for a group action's children, styled and sized like the main bar, with pagination.
import SwiftUI
import Core

@MainActor
public struct GroupSubActionBarView: View {
    public let subActions: [any Action]
    public let onResult: @MainActor (ActionResult) -> Void
    public let onRunAI: @MainActor (String) -> Void
    public let onRunLoadingAction: @MainActor (any Action, ActionResultDelivery.ClickIntent) -> Void
    public let onWillPerformAction: @MainActor (any Action, ActionResultDelivery.ClickIntent) -> Bool
    public let onActionPerformed: @MainActor (String) -> Void
    public let onClickIntent: @MainActor () -> ActionResultDelivery.ClickIntent
    public let onHoverTarget: @MainActor (PopupHoverTarget, Bool) -> Void
    public let onPaginationAnchor: (@MainActor (PopupPanel.HorizontalAnchor) -> Void)?
    public let context: ActionContext
    public let presenter: any ActionPresenting
    public let effectiveTheme: String
    public let hoveredTarget: PopupHoverTarget?
    public let scale: CGFloat
    @Environment(\.colorScheme) private var effectiveColorScheme
    @Binding public var currentPage: Int
    private let hoverState: SubBarHoverState
    /// Inline children show computed text in place of their icon, as on the main bar.
    @ObservedObject private var modeStore: PopupModeStore

    @Setting(SettingKey.popupPageSize) private var pageSize

    @Namespace private var hoverHighlightNamespace

    private var buttonWidth: CGFloat { PopupMetrics.actionButtonWidth * scale }
    private var barButtonHeight: CGFloat { PopupMetrics.barButtonHeight * scale }
    private var cornerRadius: CGFloat { PopupMetrics.popupCornerRadius * scale }

    public let screenWidth: CGFloat?

    public init(
        settingsStore: SettingsStore = DefaultSettingsStore.shared,
        subActions: [any Action],
        currentPage: Binding<Int>,
        hoverState: SubBarHoverState = .shared,
        modeStore: PopupModeStore = PopupModeStore(),
        onResult: @escaping @MainActor (ActionResult) -> Void,
        onRunAI: @escaping @MainActor (String) -> Void,
        onRunLoadingAction: @escaping @MainActor (any Action, ActionResultDelivery.ClickIntent) -> Void,
        onWillPerformAction: @escaping @MainActor (any Action, ActionResultDelivery.ClickIntent) -> Bool,
        onActionPerformed: @escaping @MainActor (String) -> Void,
        onClickIntent: @escaping @MainActor () -> ActionResultDelivery.ClickIntent,
        onHoverTarget: @escaping @MainActor (PopupHoverTarget, Bool) -> Void = { _, _ in },
        onPaginationAnchor: (@MainActor (PopupPanel.HorizontalAnchor) -> Void)? = nil,
        context: ActionContext,
        presenter: any ActionPresenting,
        effectiveTheme: String,
        hoveredTarget: PopupHoverTarget?,
        scale: CGFloat,
        screenWidth: CGFloat? = nil
    ) {
        _pageSize = Setting(SettingKey.popupPageSize, store: settingsStore)
        self.subActions = subActions
        self._currentPage = currentPage
        self.hoverState = hoverState
        self._modeStore = ObservedObject(wrappedValue: modeStore)
        self.onResult = onResult
        self.onRunAI = onRunAI
        self.onRunLoadingAction = onRunLoadingAction
        self.onWillPerformAction = onWillPerformAction
        self.onActionPerformed = onActionPerformed
        self.onClickIntent = onClickIntent
        self.onHoverTarget = onHoverTarget
        self.onPaginationAnchor = onPaginationAnchor
        self.context = context
        self.presenter = presenter
        self.effectiveTheme = effectiveTheme
        self.hoveredTarget = hoveredTarget
        self.scale = scale
        self.screenWidth = screenWidth
    }

    // MARK: - Width-Budgeted Pagination helpers

    public static func estimatedButtonWidth(
        for action: any Action,
        inlineResult: InlinePreview? = nil,
        scale: CGFloat = 1.0,
        presenter: any ActionPresenting = ActionCustomizationManager.shared
    ) -> CGFloat {
        PopupPageLayout.estimatedItemWidth(for: action, inlineResult: inlineResult, scale: scale, presenter: presenter)
    }

    public static func computePages(
        actions: [any Action],
        inlineResults: [String: InlinePreview] = [:],
        maxBudget: CGFloat,
        scale: CGFloat = 1.0,
        presenter: any ActionPresenting = ActionCustomizationManager.shared
    ) -> [[any Action]] {
        PopupPageLayout.computePages(actions: actions, inlineResults: inlineResults, leadingWidth: 0, trailingWidth: 0, maxBudget: maxBudget, scale: scale, presenter: presenter)
    }

    public static func measuredPageWidth(
        actions: [any Action],
        inlineResults: [String: InlinePreview] = [:],
        hasLeftChevron: Bool,
        hasRightChevron: Bool,
        scale: CGFloat = 1.0,
        presenter: any ActionPresenting = ActionCustomizationManager.shared
    ) -> CGFloat {
        PopupPageLayout.measuredBarWidth(actions: actions, inlineResults: inlineResults, hasLeftChevron: hasLeftChevron, hasRightChevron: hasRightChevron, leadingWidth: 0, trailingWidth: 0, scale: scale, presenter: presenter)
    }

    public static func totalPages(actionCount: Int, pageSize: Int) -> Int {
        max(1, Int(ceil(Double(actionCount) / Double(max(1, pageSize)))))
    }

    public static func pagedSlice(of ids: [String], page: Int, pageSize: Int) -> [String] {
        let ps = max(1, pageSize)
        let start = page * ps
        let end = min(start + ps, ids.count)
        guard start < ids.count else { return [] }
        return Array(ids[start..<end])
    }

    private var maxSubBarBudget: CGFloat {
        // Reserve the end inset: padding is added to the HStack but not to the estimator.
        (screenWidth ?? NSScreen.main?.visibleFrame.width ?? 1440.0) * PopupMetrics.maxScreenFraction
            - 2 * PopupMetrics.subBarEndInset * scale
    }

    private var pages: [[any Action]] {
        // Reading `modeStore.inlineResults` makes this re-evaluate when previews land.
        PopupPageLayout.computePages(
            actions: subActions,
            inlineResults: modeStore.inlineResults,
            leadingWidth: 0,
            trailingWidth: 0,
            maxBudget: maxSubBarBudget,
            maxItemsPerPage: max(2, min(24, pageSize)),
            scale: scale,
            presenter: presenter
        )
    }

    private var totalPages: Int {
        max(1, pages.count)
    }

    private var pagedSubActions: [any Action] {
        let p = pages
        let clamped = max(0, min(currentPage, p.count - 1))
        guard clamped < p.count else { return [] }
        return p[clamped]
    }

    private var hasLeftChevron: Bool { currentPage > 0 }
    private var hasRightChevron: Bool { currentPage < totalPages - 1 }

    public var body: some View {
        HStack(spacing: 0) {
            // Identity by action id, not slot: page turns must replace rows, not cross-fade them.
            ForEach(Array(pagedSubActions.enumerated()), id: \.element.id) { index, action in
                let isHovered = hoveredTarget == .subAction(index)
                subActionButton(action: action, index: index, isHovered: isHovered)
            }

            if hasLeftChevron {
                let isHovered = hoveredTarget == .chevron("chevron.left.sub")
                chevronButton(systemImage: "chevron.left", targetKey: "chevron.left.sub",
                              label: "Previous page", isHovered: isHovered) {
                    onPaginationAnchor?(.right)
                    currentPage -= 1
                }
            }
            if hasRightChevron {
                let isHovered = hoveredTarget == .chevron("chevron.right.sub")
                chevronButton(systemImage: "chevron.right", targetKey: "chevron.right.sub",
                              label: "Next page", isHovered: isHovered) {
                    onPaginationAnchor?(.right)
                    currentPage += 1
                }
            }
        }
        .padding(.horizontal, PopupMetrics.subBarEndInset * scale)
        .fixedSize()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onChange(of: totalPages) { _, count in
            // A preview widening a child can shrink the page count; keep `currentPage` in range.
            if currentPage > count - 1 { currentPage = max(0, count - 1) }
        }
    }

    @ViewBuilder
    private func subActionButton(action: any Action, index: Int, isHovered: Bool) -> some View {
        let inlinePreview = action.chrome.isInlineResult ? modeStore.inlineResults[action.id] : nil
        let isHovered = inlinePreview?.highlightFlags(hovered: isHovered, selected: false).hovered ?? isHovered
        let restForeground = PopupThemeModel.restForeground(for: effectiveTheme)
        let foregroundColor: Color = isHovered ? .white : restForeground
        let backgroundColor: Color = isHovered ? PopupThemeModel.barHoverFill : Color.clear

        // Inline results replace the icon once InlineResultEvaluator publishes a value.
        let labelView = Group {
            if action.chrome.isInlineResult, let resolved = modeStore.inlineResults[action.id] {
                InlinePreviewLabel(preview: resolved, fontSize: 15, scale: scale, foreground: foregroundColor)
                    .frame(maxWidth: PopupMetrics.inlineResultMaxWidth * scale)
                    .padding(.horizontal, PopupMetrics.inlineResultHorizontalPadding * scale)
                    .frame(minWidth: buttonWidth, minHeight: barButtonHeight)
                    .popupBarHighlight(backgroundColor, scale: scale, isText: true, leadingEdge: index == 0, trailingEdge: index == pagedSubActions.count - 1 && !hasLeftChevron && !hasRightChevron, outerInset: 3 - PopupMetrics.subBarEndInset, isHovered: isHovered, namespace: hoverHighlightNamespace)
                    .transition(.opacity)
            } else {
                ActionIconView(icon: action.displayIcon(using: presenter), size: 15.5, scale: scale)
                    .foregroundColor(foregroundColor)
                    .padding(.horizontal, {
                        if case .text = action.displayIcon(using: presenter) { return 11.5 * scale }
                        return 0.0
                    }())
                    .frame(minWidth: buttonWidth, maxWidth: 150 * scale, minHeight: barButtonHeight)
                    .popupBarHighlight(backgroundColor, scale: scale, isText: { if case .text = action.displayIcon(using: presenter) { return true }; return false }(), leadingEdge: index == 0, trailingEdge: index == pagedSubActions.count - 1 && !hasLeftChevron && !hasRightChevron, outerInset: 3 - PopupMetrics.subBarEndInset, isHovered: isHovered, namespace: hoverHighlightNamespace)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())

        Group {
            if inlinePreview?.acceptsActivation == false {
                labelView
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(subActionAccessibilityLabel(action))
                    .popupHoverTarget(.subAction(index))
                    .onHover { isHovering in
                        useLocalHoverFallback(for: .subAction(index), isHovering: isHovering)
                    }
            } else {
        Button {
            guard action.isEnabled(for: context) else { return }
            // Capture intent once, synchronously, so perform context and delivery agree.
            let clickIntent = onClickIntent()
            if ActionIdentity.isAIPreset(action) {
                onRunAI(action.id)
                return
            }
            if action.chrome.showsLoading {
                onRunLoadingAction(action, clickIntent)
                return
            }
            if action.chrome.isInlineResult, let resolved = modeStore.inlineResults[action.id] {
                guard resolved.acceptsActivation else { return }
                guard onWillPerformAction(action, clickIntent) else { return }
                onActionPerformed(action.id)
                onResult(.text(resolved.text))
                return
            }
            // Join an in-flight inline evaluation rather than re-running it; empty falls back to perform.
            if action.chrome.isInlineResult, let inFlight = InlineResultEvaluator.shared.runningTask(for: action.id) {
                Task {
                    do {
                        if let preview = await inFlight.value {
                            guard preview.acceptsActivation else { return }
                            let trimmed = preview.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                guard onWillPerformAction(action, clickIntent) else { return }
                                onActionPerformed(action.id)
                                onResult(.text(preview.text))
                                return
                            }
                        }
                        guard onWillPerformAction(action, clickIntent) else { return }
                        onActionPerformed(action.id)
                        let match = action.matchInfo(for: context)
                        let performContext = ActionContext(
                            selection: context.selection,
                            modifiers: context.modifiers,
                            isSecondaryClick: clickIntent == .secondary,
                            match: match
                        )
                        let result = try await action.perform(performContext)
                        onResult(result)
                    } catch {
                        Log.presentation.error("Sub-bar action failed (id \(action.id, privacy: .public)): \(error.localizedDescription)")
                        onResult(.toast(StatusFeedback(error: error)))
                    }
                }
                return
            }
            Task {
                do {
                    guard onWillPerformAction(action, clickIntent) else { return }
                    onActionPerformed(action.id)
                    let match = action.matchInfo(for: context)
                    let performContext = ActionContext(
                        selection: context.selection,
                        modifiers: context.modifiers,
                        isSecondaryClick: clickIntent == .secondary,
                        match: match
                    )
                    let result = try await action.perform(performContext)
                    onResult(result)
                } catch {
                    Log.presentation.error("Sub-bar action failed (id \(action.id, privacy: .public)): \(error.localizedDescription)")
                    onResult(.toast(StatusFeedback(error: error)))
                }
            }
        } label: {
            labelView
        }
        .buttonStyle(.plain)
        .accessibilityLabel({
            let title = action.displayTitle(using: presenter)
            if action.chrome.isInlineResult, let resolved = modeStore.inlineResults[action.id] {
                return "\(title): \(resolved.text)"
            }
            return title
        }())
        .popupHoverTarget(.subAction(index))
        .onHover { isHovering in
            useLocalHoverFallback(for: .subAction(index), isHovering: isHovering)
        }
            }
        }
        .animation(
            PopupMetrics.inlineSpring,
            value: modeStore.inlineResults[action.id]
        )
    }

    private func subActionAccessibilityLabel(_ action: any Action) -> String {
        let title = action.displayTitle(using: presenter)
        if action.chrome.isInlineResult, let preview = modeStore.inlineResults[action.id] {
            return "\(title): \(preview.text)"
        }
        return title
    }

    @ViewBuilder
    private func chevronButton(systemImage: String, targetKey: String, label: String, isHovered: Bool, action: @escaping () -> Void) -> some View {
        let restForeground = PopupThemeModel.restForeground(for: effectiveTheme)
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12.5 * scale, weight: .semibold))
                .foregroundColor(isHovered ? .white : restForeground)
                .frame(width: PopupPageLayout.chevronWidth * scale, height: barButtonHeight)
                .popupBarHighlight(isHovered ? PopupThemeModel.barHoverFill : .clear, scale: scale, trailingEdge: systemImage == "chevron.right" || !hasRightChevron, outerInset: 3 - PopupMetrics.subBarEndInset, isHovered: isHovered, namespace: hoverHighlightNamespace)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .popupHoverTarget(.chevron(targetKey))
        .onHover { isHovering in
            useLocalHoverFallback(for: .chevron(targetKey), isHovering: isHovering)
        }
    }

    private func useLocalHoverFallback(for target: PopupHoverTarget, isHovering: Bool) {
        guard !hoverState.usesGlobalMouseMonitoring else { return }
        onHoverTarget(target, isHovering)
    }
}
