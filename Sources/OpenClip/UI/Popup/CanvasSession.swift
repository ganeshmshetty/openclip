// CanvasSession.swift
// OpenClip
//
// The observable unit the content-canvas renderer draws: one session owns one component tree plus
// its app-owned session state, the fixed preferred size, the running action's chrome header, and
// the optional scripting engine that evaluates events. One active session is owned by
// CanvasSessionController — the session itself never dispatches, writes state, or mutates the
// tree; state/tree write-back flows through `apply(state:tree:)` and is driven exclusively by the
// controller after a serialized dispatch. `scripting == nil` marks a native/static session (e.g.
// `.showContent`) whose dispatches are no-ops in v1.
//
// Focus is renderer-facing state: `focusedComponentID` is the id the renderer should focus (nil =
// canvas root) and `focusGeneration` bumps on every `requestFocus` call so the renderer re-applies
// focus on the next run loop even when the id is unchanged (e.g. after a key/escape restore
// cycle). All members are @MainActor-isolated; the renderer observes the @Published surface.
import Foundation
import Combine
import Core

@MainActor
public final class CanvasSession: ObservableObject {
    public let id: UUID
    /// Chrome title/icon = the running action (spec §7).
    public let header: CanvasHeader
    /// The selection text (ActionContext.selection.text).
    public let input: String
    /// Fixed for the session; nil → fitting-size.
    public let preferredSize: CanvasSize?
    /// nil for native/static sessions (.showContent) whose dispatches are no-ops in v1.
    public let scripting: (any CanvasScripting)?
    public let isAsync: Bool
    @Published public var tree: CanvasComponent
    @Published public var state: CanvasSessionState
    @Published public private(set) var focusedComponentID: String?   // nil = canvas root
    @Published public private(set) var focusGeneration: Int = 0      // bumped → view re-applies focus next run loop

    public init(id: UUID = UUID(), header: CanvasHeader, input: String, preferredSize: CanvasSize?,
                scripting: (any CanvasScripting)?, isAsync: Bool,
                tree: CanvasComponent, state: CanvasSessionState = CanvasSessionState()) {
        self.id = id
        self.header = header
        self.input = input
        self.preferredSize = preferredSize
        self.scripting = scripting
        self.isAsync = isAsync
        self.tree = tree
        self.state = state
    }

    /// State write-back after a dispatch. The session is a passive unit: only the controller calls
    /// this, and only after a serialized dispatch has committed (or at mount for the initial tree).
    public func apply(state: CanvasSessionState, tree: CanvasComponent) {
        self.state = state
        self.tree = tree
    }

    /// Sets the focus target and bumps the generation. Every call bumps so the renderer re-applies
    /// focus even when `id` is unchanged (key-restore cycles, return-to-focus).
    public func requestFocus(_ id: String?) {
        focusedComponentID = id
        focusGeneration += 1
    }
}
