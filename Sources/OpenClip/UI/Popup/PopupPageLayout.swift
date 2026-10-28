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
    public static let chevronWidth: CGFloat = 33.5

    /// Per-character width estimate at the popup's 15 pt regular label font.
    private static let estimatedGlyphWidth: CGFloat = 9.0
    /// CJK, emoji and other full-width characters are about one em wide at 15 pt.
    private static let estimatedWideGlyphWidth: CGFloat = 15.0

    /// Width of one action button. Inline-result actions size to their rendered preview text (capped), so pages
    /// never overflow once previews land; before a result lands the button packs at icon width.
    public static func estimatedItemWidth(
        for action: any Action,
        inlineResult: InlinePreview? = nil,
        scale: CGFloat = 1.0,
        presenter: any ActionPresenting = ActionCustomizationManager.shared
    ) -> CGFloat {
        if action.chrome.isInlineResult, let inlineResult, !inlineResult.text.isEmpty {
            let textWidth = estimatedTextWidth(inlineResult.text, scale: scale)
            let content = min(textWidth + inlineChromeWidth(inlineResult, scale: scale),
                              PopupMetrics.inlineResultMaxWidth * scale)
            let padded = content + 2 * PopupMetrics.inlineResultHorizontalPadding * scale
            return max(PopupMetrics.actionButtonWidth * scale, padded)
        }
        let icon = action.displayIcon(using: presenter)
        if case .text(let text) = icon, !text.isEmpty, !ActionTextIconStyle.isCompactGlyph(text) {
            let estimated = estimatedTextWidth(text, scale: scale) + 25.0 * scale
            return max(PopupMetrics.actionButtonWidth * scale, min(144.0 * scale, estimated))
        }
        return PopupMetrics.actionButtonWidth * scale
    }

    /// Icon and swatch sit beside the text, inside the same max width, so a short label grows and a long one still truncates.
    private static func inlineChromeWidth(_ preview: InlinePreview, scale: CGFloat) -> CGFloat {
        var width: CGFloat = 0
        var accessories = 0
        if preview.icon != nil {
            width += 15 * scale
            accessories += 1
        }
        if preview.color != nil {
            width += PopupMetrics.inlineSwatchSide * scale
            accessories += 1
        }
        if accessories > 0 {
            width += CGFloat(accessories) * PopupMetrics.inlinePreviewSpacing * scale
        }
        return width
    }

    /// Estimated intrinsic width of a one-line label at the popup font, before any max-width clamp.
    private static func estimatedTextWidth(_ text: String, scale: CGFloat) -> CGFloat {
        let width = text.reduce(CGFloat(0)) { sum, character in
            sum + (ActionTextIconStyle.rendersFullWidth(character) ? estimatedWideGlyphWidth : estimatedGlyphWidth)
        }
        return width * scale
    }

    /// Computes width-budgeted pages. Passing `inlineResults` sizes inline buttons at their rendered width.
    /// Leading and trailing widths are reserved for persistent controls.
    public static func computePages(
        actions: [any Action],
        inlineResults: [String: InlinePreview] = [:],
        leadingWidth: CGFloat = 0,
        trailingWidth: CGFloat = 0,
        maxBudget: CGFloat,
        maxItemsPerPage: Int = Int.max,
        scale: CGFloat = 1.0,
        presenter: any ActionPresenting = ActionCustomizationManager.shared
    ) -> [[any Action]] {
        guard !actions.isEmpty else { return [[]] }

        let effectiveMaxItems: Int
        if maxItemsPerPage == Int.max {
            effectiveMaxItems = Int.max
        } else if maxItemsPerPage <= 0 {
            effectiveMaxItems = 6
        } else {
            effectiveMaxItems = max(1, maxItemsPerPage)
        }

        let effectiveChevron = chevronWidth * scale
        let totalActionsWidth = actions.reduce(CGFloat(0)) { sum, action in
            sum + estimatedItemWidth(for: action, inlineResult: inlineResults[action.id], scale: scale, presenter: presenter)
        }

        // Everything fits on one page: no pagination chevrons needed.
        if actions.count <= effectiveMaxItems && (leadingWidth + trailingWidth + totalActionsWidth <= maxBudget) {
            return [actions]
        }

        var pages: [[any Action]] = []
        var currentPage: [any Action] = []
        var currentActionsWidth: CGFloat = 0

        for (index, action) in actions.enumerated() {
            let itemWidth = estimatedItemWidth(for: action, inlineResult: inlineResults[action.id], scale: scale, presenter: presenter)
            let isFirstInPage = currentPage.isEmpty
            let hasLeft = !pages.isEmpty
            let remainingAfterThis = actions.count - 1 - index
            let neededChevrons = (hasLeft ? effectiveChevron : 0) + (remainingAfterThis > 0 ? effectiveChevron : 0)
            let pageFixedOverhead = leadingWidth + trailingWidth + neededChevrons

            let wouldExceedBudget = currentActionsWidth + itemWidth + pageFixedOverhead > maxBudget
            let wouldExceedCount = currentPage.count >= effectiveMaxItems

            if !isFirstInPage && (wouldExceedBudget || wouldExceedCount) {
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
        inlineResults: [String: InlinePreview] = [:],
        hasLeftChevron: Bool,
        hasRightChevron: Bool,
        leadingWidth: CGFloat = 0,
        trailingWidth: CGFloat = 0,
        scale: CGFloat = 1.0,
        presenter: any ActionPresenting = ActionCustomizationManager.shared
    ) -> CGFloat {
        let actionsWidth = actions.reduce(CGFloat(0)) { sum, action in
            sum + estimatedItemWidth(for: action, inlineResult: inlineResults[action.id], scale: scale, presenter: presenter)
        }
        let chevronsWidth = (hasLeftChevron ? chevronWidth * scale : 0) + (hasRightChevron ? chevronWidth * scale : 0)
        return leadingWidth + trailingWidth + actionsWidth + chevronsWidth
    }
}
