// GroupSubActionBarView.swift
// OpenClip
//
// Renders the horizontal sub-bar for a group action's children. Themed identically to the
// main action bar (glass/classic), with pagination chevrons when the sub-action count
// exceeds the user-configured page size. Each button uses the same sizing, icon rendering,
// local hover fallback, and hover tracking as main bar buttons.
import SwiftUI
import Core

@MainActor
public struct GroupSubActionBarView: View {
    public let subActions: [any Action]
    public let onResult: @MainActor (ActionResult) -> Void
    public let onRunAI: @MainActor (String) -> Void
    public let onRunLoadingAction: @MainActor (any Action, ActionResultDelivery.ClickIntent) -> Void
    public let onWillPerformAction: @MainActor (any Action, ActionResultDelivery.ClickIntent) -> Void
    public let onActionPerformed: @MainActor (String) -> Void
    public let onClickIntent: @MainActor () -> ActionResultDelivery.ClickIntent
    public let onHoverTarget: @MainActor (PopupHoverTarget, Bool) -> Void
    public let onPaginationAnchor: (@MainActor (PopupPanel.HorizontalAnchor) -> Void)?
    public let context: ActionContext
    public let presenter: any ActionPresenting
    public let effectiveTheme: String
    public let hoveredTarget: PopupHoverTarget?
    public let scale: CGFloat
    @Binding public var currentPage: Int
    private let hoverState: SubBarHoverState
    /// Shared popup mode store: the sub-bar reads `inlineResults` from it so a child action with
    /// `chrome.isInlineResult` shows its computed text in place of its icon, exactly like the main bar.
    @ObservedObject private var modeStore: PopupModeStore

    @Setting(SettingKey.popupBarWidth) private var barWidthLevel

    private var buttonWidth: CGFloat { PopupMetrics.actionButtonWidth * scale }
    private var barButtonHeight: CGFloat { PopupMetrics.barButtonHeight * scale }
    private var cornerRadius: CGFloat { PopupMetrics.popupCornerRadius * scale }

    public init(
        subActions: [any Action],
        currentPage: Binding<Int>,
        hoverState: SubBarHoverState = .shared,
        modeStore: PopupModeStore = PopupModeStore(),
        onResult: @escaping @MainActor (ActionResult) -> Void,
        onRunAI: @escaping @MainActor (String) -> Void,
        onRunLoadingAction: @escaping @MainActor (any Action, ActionResultDelivery.ClickIntent) -> Void,
        onWillPerformAction: @escaping @MainActor (any Action, ActionResultDelivery.ClickIntent) -> Void,
        onActionPerformed: @escaping @MainActor (String) -> Void,
        onClickIntent: @escaping @MainActor () -> ActionResultDelivery.ClickIntent,
        onHoverTarget: @escaping @MainActor (PopupHoverTarget, Bool) -> Void = { _, _ in },
        onPaginationAnchor: (@MainActor (PopupPanel.HorizontalAnchor) -> Void)? = nil,
        context: ActionContext,
        presenter: any ActionPresenting,
        effectiveTheme: String,
        hoveredTarget: PopupHoverTarget?,
        scale: CGFloat
    ) {
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
    }

    // MARK: - Width-Budgeted Pagination helpers

    public static func estimatedButtonWidth(
        for action: any Action,
        inlineResult: String? = nil,
        scale: CGFloat = 1.0,
        presenter: any ActionPresenting = ActionCustomizationManager.shared
    ) -> CGFloat {
        PopupPageLayout.estimatedItemWidth(for: action, inlineResult: inlineResult, scale: scale, presenter: presenter)
    }

    public static func computePages(
        actions: [any Action],
        inlineResults: [String: String] = [:],
        maxBudget: CGFloat,
        scale: CGFloat = 1.0,
        presenter: any ActionPresenting = ActionCustomizationManager.shared
    ) -> [[any Action]] {
        PopupPageLayout.computePages(actions: actions, inlineResults: inlineResults, leadingWidth: 0, trailingWidth: 0, maxBudget: maxBudget, scale: scale, presenter: presenter)
    }

    public static func measuredPageWidth(
        actions: [any Action],
        inlineResults: [String: String] = [:],
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
        PopupMetrics.barWidth(for: barWidthLevel) * scale
    }

    private var pages: [[any Action]] {
        // Inline children re-pack at their rendered text width once a preview lands, mirroring the
        // main bar; reading `modeStore.inlineResults` is what makes the view re-evaluate.
        PopupPageLayout.computePages(actions: subActions, inlineResults: modeStore.inlineResults, leadingWidth: 0, trailingWidth: 0, maxBudget: maxSubBarBudget, scale: scale, presenter: presenter)
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
            // Identity by action id (not slot position): a page turn must replace rows rather than
            // keep a slot's identity and animate it from one action to the next, which cross-faded
            // the inline preview and resized the button mid-page-change. See PopupView for detail.
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
        .fixedSize()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onChange(of: totalPages) { _, count in
            // A preview widening a child can shrink the page count; keep `currentPage` in range.
            if currentPage > count - 1 { currentPage = max(0, count - 1) }
        }
    }

    @ViewBuilder
    private func subActionButton(action: any Action, index: Int, isHovered: Bool) -> some View {
        let restForeground = PopupThemeModel.restForeground(for: effectiveTheme)
        let foregroundColor: Color = isHovered ? .white : restForeground
        let backgroundColor: Color = isHovered ? Color.accentColor : Color.clear

        // Mirrors the main bar: an inline-result action swaps its icon for the computed text once
        // `InlineResultEvaluator` publishes a result, truncating at the shared width cap.
        let labelView = Group {
            if let state = modeStore.decisionStates[action.id] {
                // A Decision tool shows its outcome where its icon was: spinner, then tick / cross / label.
                // A settled outcome sits on a softly tinted button (it wins over the hover accent, the
                // pointer is still on the button that was just clicked); the spinner keeps the normal look.
                DecisionInlineIndicator(state: state, style: .bar, foreground: foregroundColor, scale: scale)
                    .frame(minWidth: buttonWidth, minHeight: barButtonHeight)
                    .background(state.barTint ?? backgroundColor)
                    .transition(.opacity)
            } else if action.chrome.isInlineResult, let resolved = modeStore.inlineResults[action.id] {
                Text(resolved)
                    .font(.system(size: 13 * scale, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(foregroundColor)
                    .frame(maxWidth: PopupMetrics.inlineResultMaxWidth * scale)
                    .padding(.horizontal, PopupMetrics.inlineResultHorizontalPadding * scale)
                    .frame(minWidth: buttonWidth, minHeight: barButtonHeight)
                    .background(backgroundColor)
                    .transition(.opacity)
            } else {
                ActionIconView(icon: action.displayIcon(using: presenter), size: 13.5, scale: scale)
                    .foregroundColor(foregroundColor)
                    .padding(.horizontal, {
                        if case .text = action.displayIcon(using: presenter) { return 10.0 * scale }
                        return 0.0
                    }())
                    .frame(minWidth: buttonWidth, maxWidth: 130 * scale, minHeight: barButtonHeight)
                    .background(backgroundColor)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())

        Button {
            // Capture the intent once, synchronously, so the perform context and the delivery
            // snapshot agree and neither reads live state after an await.
            let clickIntent = onClickIntent()
            if ActionIdentity.isAIPreset(action) {
                onRunAI(action.id)
                return
            }
            if action.chrome.showsLoading {
                onRunLoadingAction(action, clickIntent)
                return
            }
            // An already-computed inline result is delivered directly instead of re-running the action.
            if action.chrome.isInlineResult, let resolved = modeStore.inlineResults[action.id] {
                onWillPerformAction(action, clickIntent)
                onActionPerformed(action.id)
                onResult(.text(resolved))
                return
            }
            // An in-flight inline evaluation (e.g. started before the popup re-opened) is joined
            // rather than re-run, mirroring the main bar; an empty result falls back to perform.
            if action.chrome.isInlineResult, let inFlight = InlineResultEvaluator.shared.runningTask(for: action.id) {
                Task {
                    onWillPerformAction(action, clickIntent)
                    onActionPerformed(action.id)
                    do {
                        if let text = await inFlight.value, !text.isEmpty {
                            onResult(.text(text))
                            return
                        }
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
                    onWillPerformAction(action, clickIntent)
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
                return "\(title): \(resolved)"
            }
            return title
        }())
        .popupHoverTarget(.subAction(index))
        .onHover { isHovering in
            useLocalHoverFallback(for: .subAction(index), isHovering: isHovering)
        }
        .animation(
            .spring(response: PopupMetrics.inlineSpringResponse, dampingFraction: PopupMetrics.inlineSpringDamping),
            value: modeStore.inlineResults[action.id]
        )
        .animation(
            .spring(response: PopupMetrics.inlineSpringResponse, dampingFraction: PopupMetrics.inlineSpringDamping),
            value: modeStore.decisionStates[action.id]
        )
    }

    @ViewBuilder
    private func chevronButton(systemImage: String, targetKey: String, label: String, isHovered: Bool, action: @escaping () -> Void) -> some View {
        let restForeground = PopupThemeModel.restForeground(for: effectiveTheme)
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11 * scale, weight: .semibold))
                .foregroundColor(isHovered ? .white : restForeground)
                .frame(width: 29 * scale, height: barButtonHeight)
                .background(isHovered ? Color.accentColor : Color.clear)
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
