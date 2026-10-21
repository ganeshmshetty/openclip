// TooltipPanelController.swift
// OpenClip
//
// Owns the TooltipPanel and its measure → place → show cycle for hover tooltips. A shared
// singleton: the one tooltip surface for both popup bars, hidden by both controllers on teardown.
// A reused panel keeps stale Space membership, so a show replaces it once when it is off-Space.
import AppKit
import SwiftUI
import Core

@MainActor
public final class TooltipPanelController {
    public static let shared = TooltipPanelController()

    /// Transparent ring so the SwiftUI drop shadow is not clipped at the window edge.
    static let shadowInset: CGFloat = 6

    private(set) var panel: TooltipPanel
    private let hostingView: TooltipHostingView
    public private(set) var isShowing = false
    /// Set when a hidden tooltip is ordered front. Hide clears it so a late Space check cannot bring it back.
    private(set) var presentationID: UUID?
    private var hideGeneration = 0
    private var visibilityCheckTask: Task<Void, Never>?
    private var didAttemptSpaceRecovery = false
    var panelFrame: NSRect { panel.frame }

    public init(panel: TooltipPanel = TooltipPanel()) {
        self.panel = panel
        self.hostingView = TooltipHostingView(
            rootView: PopupTooltipView(text: "")
        )
        let container = TooltipContainerView(frame: .zero)
        container.addSubview(hostingView)
        self.panel.contentView = container
    }

    /// Measures, places, and shows the tooltip for a hovered target, avoiding the sibling bar panel.
    public func show(
        text: String,
        targetScreenFrame: CGRect,
        avoidanceRects: [CGRect] = [],
        cursorLocation: CGPoint? = nil,
        effectiveTheme: String = "glass",
        isDark: Bool = true,
        maxWidth: CGFloat? = nil
    ) {
        guard !text.isEmpty, targetScreenFrame.width > 0, targetScreenFrame.height > 0 else {
            hide()
            return
        }

        let cappedWidth = maxWidth.map { max(40, $0) }
        hostingView.rootView = PopupTooltipView(
            text: text,
            effectiveTheme: effectiveTheme,
            isDark: isDark,
            maxWidth: cappedWidth
        )
        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()
        let fit = Self.resolvedTooltipSize(measured: hostingView.fittingSize, text: text, maxWidth: cappedWidth)

        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: targetScreenFrame.midX, y: targetScreenFrame.midY)) }
            ?? NSScreen.screens.first { $0.frame.intersects(targetScreenFrame) }
            ?? NSScreen.main
        let screenBounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)

        let placement = TooltipPlacer.place(
            targetScreenFrame: targetScreenFrame,
            tooltipSize: fit,
            screenBounds: screenBounds,
            avoidanceRects: avoidanceRects,
            cursorLocation: cursorLocation ?? NSEvent.mouseLocation
        )

        hostingView.frame = NSRect(x: Self.shadowInset, y: Self.shadowInset, width: fit.width, height: fit.height)
        panel.contentView?.frame = NSRect(
            origin: .zero,
            size: NSSize(width: fit.width + Self.shadowInset * 2, height: fit.height + Self.shadowInset * 2)
        )
        panel.setFrame(
            NSRect(x: placement.origin.x - Self.shadowInset,
                   y: placement.origin.y - Self.shadowInset,
                   width: fit.width + Self.shadowInset * 2,
                   height: fit.height + Self.shadowInset * 2),
            display: true
        )

        // Moving between buttons keeps the panel up. A hidden or fading panel has to be ordered
        // front again; reading alphaValue == 1 on an ordered-out window is not proof it will draw.
        let alreadyVisible = isShowing && panel.isVisible && panel.alphaValue >= 0.99
        guard !alreadyVisible else { return }

        hideGeneration += 1
        isShowing = true
        if presentationID == nil {
            presentationID = UUID()
            didAttemptSpaceRecovery = false
            scheduleVisibilityCheck()
        }
        setAlpha(0, on: panel)
        panel.orderFrontRegardless()
        let shownPanel = panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            shownPanel.animator().alphaValue = 1
        }
    }

    public func hide() {
        guard isShowing || panel.isVisible else { return }
        isShowing = false
        hideGeneration += 1
        let generation = hideGeneration
        let hidingPanel = panel
        visibilityCheckTask?.cancel()
        visibilityCheckTask = nil
        presentationID = nil
        didAttemptSpaceRecovery = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08
            hidingPanel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // A show() that won the race bumped the generation or swapped the panel.
                guard let self, self.hideGeneration == generation, !self.isShowing, self.panel === hidingPanel else { return }
                guard hidingPanel.alphaValue == 0 else { return }
                hidingPanel.orderOut(nil)
                self.setAlpha(1, on: hidingPanel)
            }
        })
    }

    /// Uses the hosting view's size when it has one. An ordered-out hosting view can report
    /// `{0, 0}` and, if that miss returns before `orderFront`, every later hover misses too.
    static func resolvedTooltipSize(measured: CGSize, text: String, maxWidth: CGFloat?) -> CGSize {
        if measured.width > 0, measured.height > 0 { return measured }
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let measuredText = (text as NSString).size(withAttributes: [.font: font])
        let textWidth = max(1, ceil(measuredText.width))
        let width = maxWidth.map { min(textWidth, max(1, $0)) } ?? textWidth
        return CGSize(width: width + 14, height: max(1, ceil(measuredText.height)) + 6)
    }

    private func scheduleVisibilityCheck() {
        guard let id = presentationID else { return }
        guard NSClassFromString("XCTestCase") == nil else { return }
        visibilityCheckTask?.cancel()
        visibilityCheckTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) }
            catch { return }
            self?.recoverTooltipSpaceIfNeeded(for: id)
        }
    }

    /// A reused window can keep stale Space membership; swap in a fresh panel once, keeping content and frame.
    @discardableResult
    func recoverTooltipSpaceIfNeeded(for id: UUID, makePanel: () -> TooltipPanel = { TooltipPanel() }) -> Bool {
        guard presentationID == id, isShowing, !didAttemptSpaceRecovery,
              !panel.isKeyWindow, !panel.isVisible || !panel.isOnActiveSpace else { return false }
        didAttemptSpaceRecovery = true
        Log.presentation.notice("Recovering tooltip window visible=\(panel.isVisible, privacy: .public) activeSpace=\(panel.isOnActiveSpace, privacy: .public)")
        let frame = panel.frame
        let content = panel.contentView
        let appearance = panel.appearance
        let replacement = makePanel()
        replacement.appearance = appearance
        replacement.ignoresMouseEvents = true
        panel.orderOut(nil)
        panel.contentView = nil
        panel = replacement
        replacement.contentView = content
        replacement.setFrame(frame, display: false)
        setAlpha(1, on: replacement)
        replacement.orderFrontRegardless()
        return true
    }

    private func setAlpha(_ value: CGFloat, on window: NSWindow) {
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        window.alphaValue = value
        NSAnimationContext.endGrouping()
    }
}
