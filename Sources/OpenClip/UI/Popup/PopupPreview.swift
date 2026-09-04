// PopupPreview.swift
// OpenClip
//
// Static visual preview of the popup bar rendered with a fixed action set
// (Search, Copy, Cut, Paste, Share + AI), mirroring how the real bar will look
// for the currently selected theme. It is intentionally decoupled from the live
// action registry so it always shows the same canonical actions. Used by the
// Preferences Appearance tab.
import SwiftUI
import AppKit
import Core

@MainActor
struct PopupPreview: View {
    /// The canonical action set shown in the preview, independent of what the user
    /// has enabled/reordered in the real popup.
    private static let previewActions: [any Action] = [
        SearchAction(),
        CopyAction(),
        CutAction(),
        PasteAction(),
        AIToolsAction()
    ]

    /// The preview observes its own hover state (and ignores hover entirely), so it
    /// never reacts to — or leaks into — the real popup's shared hover state.
    private static let previewHoverState = PopupHoverState()

    private var mockContext: ActionContext {
        let app = NSRunningApplication.current
        let context = SelectionContext(
            text: "OpenClip Preview",
            sourceApp: AppIdentity(app),
            cursorPosition: .zero,
            selectionBounds: nil,
            timestamp: Date(),
            appPolicy: .default
        )
        return ActionContext(selection: context, modifiers: [])
    }

    @AppStorage(SettingKey.popupScale.name) private var popupScale: Int = SettingKey.popupScale.defaultValue
    @AppStorage(SettingKey.popupVerticalPosition.name) private var popupVerticalPosition: String = SettingKey.popupVerticalPosition.defaultValue

    private var previewModeStore: PopupModeStore {
        let store = PopupModeStore()
        let pos = PopupVerticalPosition(rawValue: popupVerticalPosition) ?? .auto
        store.subBarAbove = (pos != .below)
        return store
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Popup Preview")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            PopupView(
                actions: Self.previewActions,
                context: mockContext,
                hoverState: Self.previewHoverState,
                isStatic: true,
                modeStore: previewModeStore
            ) { _ in }
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
