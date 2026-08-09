// CanvasScripting.swift
// OpenClip
//
// The engine-agnostic dispatch boundary between the canvas session and whatever runtime evaluates
// a canvas (spec §5.2). v1 implements this as JavaScriptCanvasEngine (in-process fresh eval); a
// future bounded-session engine (persisted state, mid-flight render(), ticks) or an out-of-process
// engine implements the same protocol — the component model, renderer, and chrome never change.
//
// CanvasMountRequest carries everything the engine needs to produce the initial tree: the source
// (scriptCode) it must compile, the selection input, the producer-resolved optionValues (surfaced
// to the JS context as openclip.options; JSONValue is defined in Task 2), the initial app-owned
// state, and an optional preferredSize declared once at mount and fixed for the session.
// CanvasMountResult adds the preferredSize the author actually declared via openclip.showContent
// (overrides the request value when present); CanvasDispatchResult carries the status feedback a
// handler surfaced via openclip.showStatus. Both fields are additive with defaults so existing init
// call sites keep compiling. CanvasDispatchRequest carries the event and the current state; the
// mount size stays fixed across dispatches. Pure Core — the request/result structs are Sendable
// value types, no AppKit/SwiftUI.
import Foundation

public struct CanvasMountRequest: Sendable {
    public var initialState: CanvasSessionState
    public var input: String
    public var optionValues: [String: JSONValue]
    public var preferredSize: CanvasSize?
    public var scriptCode: String
    public var isAsync: Bool

    public init(
        initialState: CanvasSessionState = CanvasSessionState(),
        input: String,
        optionValues: [String: JSONValue] = [:],
        preferredSize: CanvasSize? = nil,
        scriptCode: String = "",
        isAsync: Bool = false
    ) {
        self.initialState = initialState
        self.input = input
        self.optionValues = optionValues
        self.preferredSize = preferredSize
        self.scriptCode = scriptCode
        self.isAsync = isAsync
    }
}

public struct CanvasDispatchRequest: Sendable {
    public var event: CanvasEvent
    public var state: CanvasSessionState

    public init(event: CanvasEvent, state: CanvasSessionState) {
        self.event = event
        self.state = state
    }
}

public struct CanvasMountResult: Sendable {
    public var state: CanvasSessionState
    public var tree: CanvasComponent
    public var preferredSize: CanvasSize?

    public init(state: CanvasSessionState, tree: CanvasComponent, preferredSize: CanvasSize? = nil) {
        self.state = state
        self.tree = tree
        self.preferredSize = preferredSize
    }
}

public struct CanvasDispatchResult: Sendable {
    public var state: CanvasSessionState
    public var tree: CanvasComponent
    public var effects: [CanvasEffect]
    public var status: StatusFeedback?

    public init(state: CanvasSessionState, tree: CanvasComponent, effects: [CanvasEffect] = [], status: StatusFeedback? = nil) {
        self.state = state
        self.tree = tree
        self.effects = effects
        self.status = status
    }
}

public protocol CanvasScripting: Sendable {
    func mount(_ request: CanvasMountRequest) async throws -> CanvasMountResult
    func dispatch(_ request: CanvasDispatchRequest) async throws -> CanvasDispatchResult
}
