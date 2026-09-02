// PopupPageLayout.swift
// OpenClip
//
// Pure presentation layout engine for width-budgeted page packing across the main popup bar
// and group sub-bar. Dynamically measures item widths (icon-only, text buttons, end caps, chevrons)
// against a configurable max width budget.
import Foundation
import CoreGraphics
import Core

@MainActor
public enum PopupPageLayout {
    /// Chevron button width (normalized baseline at 1.0 scale).
    public static let chevronWidth: CGFloat = 29.0

    /// Estimates the horizontal width of a single action button in points at the given scale.
    public static func estimatedItemWidth(
        for action: any Action,
        scale: CGFloat = 1.0,
        presenter: any ActionPresenting = ActionCustomizationManager.shared
    ) -> CGFloat {
        let icon = action.displayIcon(using: presenter)
        if case .text(let text) = icon, text.count > 2 {
            let charWidth: CGFloat = 7.8 * scale
            let horizontalPadding: CGFloat = 22.0 * scale
            let estimated = CGFloat(text.count) * charWidth + horizontalPadding
            return max(PopupMetrics.actionButtonWidth * scale, min(125.0 * scale, estimated))
        }
        return PopupMetrics.actionButtonWidth * scale
    }

    /// Computes width-budgeted pages for a list of actions.
    ///
    /// - Parameters:
    ///   - actions: The action items to distribute across pages.
    ///   - leadingWidth: Width reserved for leading persistent controls (e.g. completion chevron).
    ///   - trailingWidth: Width reserved for trailing persistent controls (e.g. search button).
    ///   - maxBudget: Maximum allowable content width for any single page.
    ///   - scale: Current popup scale factor.
    ///   - presenter: Customization presenter for resolving display icons.
    /// - Returns: Array of action pages.
    public static func computePages(
        actions: [any Action],
        leadingWidth: CGFloat = 0,
        trailingWidth: CGFloat = 0,
        maxBudget: CGFloat,
        scale: CGFloat = 1.0,
        presenter: any ActionPresenting = ActionCustomizationManager.shared
    ) -> [[any Action]] {
        guard !actions.isEmpty else { return [[]] }

        let effectiveChevron = chevronWidth * scale
        let totalActionsWidth = actions.reduce(CGFloat(0)) { sum, action in
            sum + estimatedItemWidth(for: action, scale: scale, presenter: presenter)
        }

        // Single page optimization: if everything fits without pagination chevrons, return one page.
        if leadingWidth + trailingWidth + totalActionsWidth <= maxBudget {
            return [actions]
        }

        var pages: [[any Action]] = []
        var currentPage: [any Action] = []
        var currentActionsWidth: CGFloat = 0

        for (index, action) in actions.enumerated() {
            let itemWidth = estimatedItemWidth(for: action, scale: scale, presenter: presenter)
            let isFirstInPage = currentPage.isEmpty
            let hasLeft = !pages.isEmpty
            let remainingAfterThis = actions.count - 1 - index
            let neededChevrons = (hasLeft ? effectiveChevron : 0) + (remainingAfterThis > 0 ? effectiveChevron : 0)
            let pageFixedOverhead = leadingWidth + trailingWidth + neededChevrons

            if !isFirstInPage && (currentActionsWidth + itemWidth + pageFixedOverhead > maxBudget) {
                pages.append(currentPage)
                currentPage = [action]
                currentActionsWidth = itemWidth
            } else {
                currentPage.append(action)
                currentActionsWidth += itemWidth
            }
        }

        if !currentPage.isEmpty {
            pages.append(currentPage)
        }

        return pages.isEmpty ? [[]] : pages
    }

    /// Measures the total horizontal width in points for a given page configuration.
    public static func measuredBarWidth(
        actions: [any Action],
        hasLeftChevron: Bool,
        hasRightChevron: Bool,
        leadingWidth: CGFloat = 0,
        trailingWidth: CGFloat = 0,
        scale: CGFloat = 1.0,
        presenter: any ActionPresenting = ActionCustomizationManager.shared
    ) -> CGFloat {
        let actionsWidth = actions.reduce(CGFloat(0)) { sum, action in
            sum + estimatedItemWidth(for: action, scale: scale, presenter: presenter)
        }
        let chevronsWidth = (hasLeftChevron ? chevronWidth * scale : 0) + (hasRightChevron ? chevronWidth * scale : 0)
        return leadingWidth + trailingWidth + actionsWidth + chevronsWidth
    }
}
