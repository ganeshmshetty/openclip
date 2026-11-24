// CoachMarkController.swift
// OpenClip
//
// Post-onboarding coach-mark card anchored under the status item, shown at most once per install.
// Dismissal (timeout, ✕, setup, or the first real selection) persists
// `SettingKey.hasDismissedPostOnboardingCoachMark`.
import AppKit
import SwiftUI
import Core

@MainActor
final class CoachMarkController {
    static let autoDismissNanoseconds: UInt64 = 12_000_000_000

    private let panel = CoachPanel()
    private let settingsStore: any SettingsStore
    private let accessibilityGranted: Bool
    private let onSetupAction: () -> Void
    private var autoDismissTask: Task<Void, Never>?
    private(set) var isShowing = false

    init(settingsStore: any SettingsStore = DefaultSettingsStore.shared,
         accessibilityGranted: Bool,
         onSetupAction: @escaping () -> Void) {
        self.settingsStore = settingsStore
        self.accessibilityGranted = accessibilityGranted
        self.onSetupAction = onSetupAction
    }

    /// Anchored below `anchorFrame`, or top-center when nil. No-op once seen.
    func show(anchorFrame: NSRect?) {
        guard !isShowing, !settingsStore.get(.hasDismissedPostOnboardingCoachMark) else { return }

        let card = CoachMarkCard(
            accessibilityGranted: accessibilityGranted,
            onSetup: { [weak self] in self?.handleSetupTapped() },
            onDismiss: { [weak self] in self?.dismiss() })

        // Measure after a manual layout pass, as ToastPanelController does.
        let hostingView = NSHostingView(rootView: card)
        let container = NSView(frame: .zero)
        container.addSubview(hostingView)
        panel.contentView = container
        hostingView.layoutSubtreeIfNeeded()
        let fit = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: fit)
        container.frame = NSRect(origin: .zero, size: fit)
        place(at: fit, anchoredTo: anchorFrame)
        panel.orderFrontRegardless()
        isShowing = true
        startAutoDismissal()
    }

    /// Hides the card and marks it seen.
    func dismiss() {
        guard isShowing else { return }
        autoDismissTask?.cancel()
        autoDismissTask = nil
        panel.orderOut(nil)
        isShowing = false
        settingsStore.set(.hasDismissedPostOnboardingCoachMark, value: true)
    }

    /// Marks seen first so the nudge never returns, then hands off to the caller's action.
    func handleSetupTapped() {
        dismiss()
        onSetupAction()
    }

    /// Test hook for geometry assertions.
    var panelFrame: NSRect { panel.frame }

    private func startAutoDismissal() {
        autoDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.autoDismissNanoseconds)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// Centred below the anchor, clamped to the visible frame.
    private func place(at size: CGSize, anchoredTo anchorFrame: NSRect?) {
        let screen = anchorFrame.flatMap { anchor in
            NSScreen.screens.first { $0.frame.intersects(anchor) }
        } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let gap: CGFloat = 6
        var origin: CGPoint
        if let anchorFrame {
            origin = CGPoint(x: anchorFrame.midX - size.width / 2,
                             y: anchorFrame.minY - size.height - gap)
        } else {
            origin = CGPoint(x: visible.midX - size.width / 2,
                             y: visible.maxY - size.height - 8)
        }
        origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
        origin.y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

/// Non-activating panel that never becomes key, so clicks do not activate OpenClip.
final class CoachPanel: NSPanel {
    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
    }
}

private struct CoachMarkCard: View {
    let accessibilityGranted: Bool
    let onSetup: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: accessibilityGranted ? "hand.tap" : "gearshape.fill")
                .font(.system(size: 15))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(accessibilityGranted ? String(localized: "Select any text to see OpenClip") : String(localized: "Finish setting up OpenClip"))
                    .font(.system(size: 13, weight: .medium))
                Text(accessibilityGranted
                     ? LocalizedStringKey("A bar with quick actions appears near your cursor.")
                     : PermissionCopy.grantPrompt)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if !accessibilityGranted {
                Button("Open Preferences", action: onSetup)
                    .controlSize(.small)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary.opacity(0.6))
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .fixedSize()
        .accessibilityElement(children: .contain)
    }
}