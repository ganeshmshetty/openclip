// PopupPreview.swift
// OpenClip
//
// Static visual previews of the popup bar and of the action-search palette, rendered with a
// fixed action set (Search, Copy, Cut, Paste + AI Tools), mirroring how each will look for the
// currently selected theme. They are intentionally decoupled from the live action registry so
// they always show the same canonical actions. Used by the Appearance settings page, which draws
// the stage around them and the switch between them.
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
        PopupView(
            actions: Self.previewActions,
            context: mockContext,
            hoverState: Self.previewHoverState,
            isStatic: true,
            modeStore: previewModeStore
        ) { _ in }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 96)
    }
}

/// Static preview of the action-search palette (the ⌘ view), drawn by the real palette in its
/// static mode with the same canonical actions as the bar preview. You can type into it to see
/// filtering and the row styles; nothing runs.
@MainActor
struct PalettePreview: View {
    private static let previewActions: [any Action] = [
        SearchAction(),
        CopyAction(),
        CutAction(),
        PasteAction(),
        AIToolsAction()
    ]

    /// Its own hover state, so the preview never reacts to — or leaks into — the real popup's.
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

    var body: some View {
        PopupSearchView(
            catalog: Self.previewActions,
            context: mockContext,
            modeStore: PopupModeStore(),
            onResult: { _ in },
            onExit: {},
            aiEnabled: false,
            hoverState: Self.previewHoverState,
            isStatic: true
        )
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
}
