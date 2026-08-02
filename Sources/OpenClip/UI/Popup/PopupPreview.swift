// PopupPreview.swift
// OpenClip
//
// Live preview of the popup bar rendered with a small mock action set, mirroring how
// the real bar will look for the currently selected theme. Shared by the Preferences
// Appearance tab and the onboarding Finish step.
import SwiftUI
import AppKit
import Core

@MainActor
struct PopupPreview: View {
    @ObservedObject private var coordinator = ActionCoordinator.shared

    private var mockContext: ActionContext {
        let app = NSRunningApplication.current
        let context = SelectionContext(
            text: "OpenClip Preview",
            sourceApp: app,
            cursorPosition: .zero,
            selectionBounds: nil,
            timestamp: Date(),
            appPolicy: .default
        )
        return ActionContext(selection: context, modifiers: [])
    }

    private var mockActions: [any Action] {
        let available = coordinator.resolveActions(for: mockContext)
        // Show up to 5 actions in the preview to look clean
        return Array(available.prefix(5))
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Live Popup Preview")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            PopupView(actions: mockActions, context: mockContext) { _ in }
                .scaleEffect(1.1)
                .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
