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
    public let onRunLoadingAction: @MainActor (any Action) -> Void
    public let onWillPerformAction: @MainActor (any Action) -> Void
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

    @AppStorage(SettingKey.popupBarWidth.name) private var barWidthLevel: Int = SettingKey.popupBarWidth.defaultValue

    private var buttonWidth: CGFloat { PopupMetrics.actionButtonWidth * scale }
    private var barButtonHeight: CGFloat { PopupMetrics.barButtonHeight * scale }
    private var cornerRadius: CGFloat { PopupMetrics.popupCornerRadius * scale }

    public init(
        subActions: [any Action],
        currentPage: Binding<Int>,
        hoverState: SubBarHoverState = .shared,
        onResult: @escaping @MainActor (ActionResult) -> Void,
        onRunAI: @escaping @MainActor (String) -> Void,
        onRunLoadingAction: @escaping @MainActor (any Action) -> Void,
        onWillPerformAction: @escaping @MainActor (any Action) -> Void,
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
        scale: CGFloat = 1.0,
        presenter: any ActionPresenting = ActionCustomizationManager.shared
    ) -> CGFloat {
        PopupPageLayout.estimatedItemWidth(for: action, scale: scale, presenter: presenter)
    }

    public static func computePages(
        actions: [any Action],
        maxBudget: CGFloat,
        scale: CGFloat = 1.0,
        presenter: any ActionPresenting = ActionCustomizationManager.shared
    ) -> [[any Action]] {
        PopupPageLayout.computePages(actions: actions, leadingWidth: 0, trailingWidth: 0, maxBudget: maxBudget, scale: scale, presenter: presenter)
    }

    public static func measuredPageWidth(
        actions: [any Action],
        hasLeftChevron: Bool,
        hasRightChevron: Bool,
        scale: CGFloat = 1.0,
        presenter: any ActionPresenting = ActionCustomizationManager.shared
    ) -> CGFloat {
        PopupPageLayout.measuredBarWidth(actions: actions, hasLeftChevron: hasLeftChevron, hasRightChevron: hasRightChevron, leadingWidth: 0, trailingWidth: 0, scale: scale, presenter: presenter)
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
        PopupPageLayout.computePages(actions: subActions, leadingWidth: 0, trailingWidth: 0, maxBudget: maxSubBarBudget, scale: scale, presenter: presenter)
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
            ForEach(Array(pagedSubActions.enumerated()), id: \.offset) { index, action in
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
    }

    @ViewBuilder
    private func subActionButton(action: any Action, index: Int, isHovered: Bool) -> some View {
        let restForeground = PopupThemeModel.restForeground(for: effectiveTheme)

        Button {
            if ActionIdentity.isAIPreset(action) {
                onRunAI(action.id)
                return
            }
            if action.chrome.showsLoading {
                onRunLoadingAction(action)
                return
            }
            Task {
                do {
                    onWillPerformAction(action)
                    onActionPerformed(action.id)
                    let match = action.matchInfo(for: context)
                    let performContext = ActionContext(
                        selection: context.selection,
                        modifiers: context.modifiers,
                        isSecondaryClick: onClickIntent() == .secondary,
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
            ActionIconView(icon: action.displayIcon(using: presenter), size: 13.5, scale: scale)
                .foregroundColor(isHovered ? .white : restForeground)
                .padding(.horizontal, {
                    if case .text = action.displayIcon(using: presenter) { return 10.0 * scale }
                    return 0.0
                }())
                .frame(minWidth: buttonWidth, maxWidth: 130 * scale, minHeight: barButtonHeight)
                .background(isHovered ? Color.accentColor : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.displayTitle(using: presenter))
        .popupHoverTarget(.subAction(index))
        .onHover { isHovering in
            useLocalHoverFallback(for: .subAction(index), isHovering: isHovering)
        }
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
