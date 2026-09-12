// ActionEditorPresenter.swift
// OpenClip
//
// Routes the per-row settings editors of the Actions preferences tab to a single window sheet.
//
// This replaces the previous `ActionSettingsPopover`, an `.applicationDefined` `NSPopover` that
// floated the editor over the list. That popover had to opt out of every dismissal rule the system
// provides — it survived clicks in the list, Escape, and switching preference tabs — and because an
// `NSPopover` is its own window, anything the editor presented on top of it (the icon picker, the AI
// preset editor) became a second floating layer or a sheet that dimmed three windows at once.
//
// A sheet is the native fit: the editors are modal by construction (they have Cancel / Save
// Changes), a sheet is anchored to the Preferences window so it can never outlive the tab it was
// opened from, and macOS gives Escape, focus and window ordering for free.

import SwiftUI
import Core

/// Which per-row editor the Actions tab should present.
enum ActionEditorRoute: Identifiable, Hashable {
    case action(id: String)
    case group(id: String)

    var id: String {
        switch self {
        case .action(let id): return "action:\(id)"
        case .group(let id): return "group:\(id)"
        }
    }

    var actionID: String {
        switch self {
        case .action(let id), .group(let id): return id
        }
    }
}

/// Shared presentation state for the Actions tab's row editors.
///
/// The rows are hosted inside an `NSOutlineView`, which rebuilds its cell views on every model
/// change, so the "which editor is open" state cannot live in a row's `@State` — it has to outlive
/// the row. A single observable object owned by the tab does that without the row needing to reach
/// into SwiftUI's environment across the AppKit boundary.
@MainActor
final class ActionEditorPresenter: ObservableObject {
    static let shared = ActionEditorPresenter()

    @Published var route: ActionEditorRoute?

    private init() {}

    func present(_ route: ActionEditorRoute) {
        self.route = route
    }

    func dismiss() {
        route = nil
    }
}
