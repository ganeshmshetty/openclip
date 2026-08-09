// LegacyContentBridge.swift
// OpenClip
//
// TEMPORARY bridge (deleted in Task 21) that keeps the legacy PopupContent producers alive by
// mapping a PopupContent into a native CanvasSession tree, rendered by CanvasSessionView. The
// `.showContent(PopupContent)` ActionResult and the `ResultContentProviding`/menu producers all
// keep emitting the old model; `PopupWindowController.enterContent` routes them through here
// instead of the deleted `PopupContentView`. Pure Core-value functions — no AppKit/SwiftUI, no
// @MainActor.
import Foundation
import Core

enum LegacyContentBridge {
    /// The chrome header for the bridged session: title + icon straight from the legacy content.
    static func header(for content: PopupContent) -> CanvasHeader {
        CanvasHeader(title: content.title ?? "", icon: content.icon)
    }

    /// Converts a legacy `PopupContent` into a canvas component tree. Every bridged node carries
    /// `id: nil` — legacy content is fully replaced on re-render (matching the old PopupContentView
    /// behavior, no identity-matched animations needed). Dead producers in the bridged path
    /// (`.run`/`.showSubMenu`/`.perform(.showContent...)`/presentation results) are dropped rather
    /// than invented; Task 19 fully removes `ContentOutcome`.
    static func tree(for content: PopupContent) -> CanvasComponent {
        switch content.emphasis {
        case .info:
            return .text(CanvasTextProps(content: content.subtitle ?? content.title ?? "",
                                         style: .caption, color: .primary))
        case .result:
            return resultTree(for: content)
        case .menu:
            return menuTree(for: content)
        }
    }

    private static func resultTree(for content: PopupContent) -> CanvasComponent {
        var children: [CanvasComponent] = []

        if let title = content.title, !title.isEmpty {
            children.append(.text(CanvasTextProps(content: title, style: .title, color: .primary)))
        }
        if let subtitle = content.subtitle {
            children.append(.text(CanvasTextProps(content: subtitle, style: .caption, color: .secondary)))
        }

        let bodyText = rowsText(content.rows)
        if !bodyText.isEmpty {
            children.append(.text(CanvasTextProps(content: bodyText, style: .body, selectable: true)))
        }

        let footers = content.footer
        if !footers.isEmpty {
            let buttons = footers.enumerated().map { index, option in
                CanvasButtonProps(
                    title: option.title,
                    icon: option.icon.map(CanvasIconSource.symbol),
                    style: index == 0 ? .accent : .plain,
                    handler: bridgeHandler(for: option.outcome)
                )
            }
            children.append(.stack(CanvasStackProps(orientation: .horizontal, spacing: 8), buttons.map(CanvasComponent.button)))
        }

        return .stack(CanvasStackProps(orientation: .vertical), children)
    }

    private static func menuTree(for content: PopupContent) -> CanvasComponent {
        var children: [CanvasComponent] = []
        if let title = content.title, !title.isEmpty {
            children.append(.text(CanvasTextProps(content: title, style: .caption, color: .secondary)))
        }
        for row in content.rows {
            switch row {
            case .text(let header):
                children.append(.text(CanvasTextProps(content: header, style: .caption, color: .secondary)))
            case .option(let option):
                if let handler = bridgeHandler(for: option.outcome) {
                    children.append(.button(CanvasButtonProps(
                        title: option.title,
                        icon: option.icon.flatMap(CanvasIconSource.symbol),
                        style: .plain,
                        handler: handler
                    )))
                }
            }
        }
        return .stack(CanvasStackProps(orientation: .vertical, spacing: 2), children)
    }

    private static func rowsText(_ rows: [ContentRow]) -> String {
        rows.compactMap { row in
            if case .text(let text) = row { return text }
            return nil
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    /// Maps a legacy `ContentOption` to a `.button` node's handler. Only leaf effects reach the
    /// canvas renderer; presentation/flow outcomes (`.run`, `.showSubMenu`, `.perform(.showContent…)`,
    /// `.perform` of non-leaf presentation results) are dead in the bridged path and dropped —
    /// Task 19 fully removes `ContentOutcome`.
    private static func bridgeHandler(for outcome: ContentOutcome) -> CanvasHandler? {
        guard case .perform(let result) = outcome else { return nil }
        switch result {
        case .paste(let text): return .effect(.paste(text))
        case .copy(let text): return .effect(.copy(text))
        case .cut(let text): return .effect(.cut(text))
        case .openURL(let url): return .effect(.openURL(url))
        case .keyPress(let spec): return .effect(.keyPress(spec))
        case .simulatePaste: return .effect(.simulatePaste)
        case .showServices(let text): return .effect(.showServices(text))
        case .runShortcut(let name, let input): return .effect(.runShortcut(name: name, input: input))
        case .notify(let title, let body): return .effect(.notify(title: title, body: body))
        // Presentation/flow results have no canvas equivalent: dropped as dead producers.
        default: return nil
        }
    }
}