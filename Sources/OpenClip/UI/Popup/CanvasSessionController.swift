// CanvasSessionController.swift
// OpenClip
//
// The owner of the single active content-canvas session (spec §5.1/§5.2). It serializes every
// mount/dispatch through one MainActor task chain, writes the engine result back into the session
// (`apply`), routes collected leaf effects to `onEffects` (never dismiss — in-session dismissal is
// suppressed), routes script-surfaced `showStatus` feedback to `onStatus` (the popup queues it for
// the bar banner while the canvas is open), and restores focus after submit/toggle/fallback rules
// (§4.2). The engine-declared `preferredSize` from `showContent` wins over the request value. A
// `generation` guard discards the late result of a replaced/cleared session, and `mount` waits on
// the previous chain so a rapid re-mount always wins over the earlier one. Focus lives in
// CanvasSession.focusedComponentID so the renderer can re-apply it on the next run loop; the panel
// is key in content mode (enterKeyMode) exactly like search. Mount success reports the armed
// session via `onSessionArmed` so the presenter can enter content mode and key the panel — the
// `.showCanvas` mount path's only transition into content mode.
import Foundation
import Core

@MainActor
public final class CanvasSessionController {
    public private(set) var session: CanvasSession?
    /// Collected leaf effects (never dismiss).
    public var onEffects: (@MainActor ([CanvasEffect]) -> Void)?
    /// Mount/dispatch failure → presenter collapses.
    public var onSessionError: (@MainActor (Error) -> Void)?
    /// Script-surfaced status feedback (openclip.showStatus) → presenter shows/queues it.
    public var onStatus: (@MainActor (StatusFeedback) -> Void)?
    /// Mount success → presenter enters content mode and keys the panel (the `.showCanvas` path).
    public var onSessionArmed: (@MainActor (CanvasSession) -> Void)?
    private var dispatchChain: Task<Void, Never>?
    private var generation = 0

    public init() {}

    /// Discards the old session and any in-flight dispatch.
    public func replace(with session: CanvasSession) {
        generation += 1
        dispatchChain?.cancel()
        dispatchChain = nil
        self.session = session
    }

    /// hide()/collapse: cancel in-flight, drop session.
    public func clear() {
        generation += 1
        dispatchChain?.cancel()
        dispatchChain = nil
        session = nil
    }

    public func mount(_ request: CanvasMountRequest, scripting: any CanvasScripting, header: CanvasHeader) {
        generation += 1
        let myGeneration = generation
        let previous = dispatchChain
        dispatchChain = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, self.generation == myGeneration else { return }
            do {
                let result = try await scripting.mount(request)
                guard self.generation == myGeneration else { return }
                let session = CanvasSession(header: header, input: request.input,
                                            preferredSize: result.preferredSize ?? request.preferredSize,
                                            scripting: scripting,
                                            isAsync: request.isAsync, tree: result.tree, state: result.state)
                self.session = session
                // No onEffects at mount: CanvasMountResult carries state+tree only (spec §5.2).
                self.onSessionArmed?(session)
                let firstInteractive = session.tree.firstInteractiveID()
                Task { @MainActor in await Task.yield(); session.requestFocus(firstInteractive) }
            } catch {
                guard self.generation == myGeneration else { return }
                self.session = nil
                self.onSessionError?(error)
            }
        }
    }

    public func dispatch(_ event: CanvasEvent) {
        guard let session, let scripting = session.scripting else { return } // native v1: no named handlers
        let myGeneration = generation
        let previous = dispatchChain
        dispatchChain = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, self.generation == myGeneration, let session = self.session else { return }
            // Pre-flip write + request snapshot happen INSIDE the serialized chain — never at
            // enqueue time. A `.change` commits the new value into session state BEFORE the request
            // is built so the receiving handler reads post-flip state (a toggle flip toggles the
            // stored value; a textField blur-change commits the draft string the view is carrying).
            // Building the request here also means a second rapid tap reads the state left by the
            // first dispatch: an enqueue-time snapshot would carry stale pre-dispatch state and lose
            // updates (a counter tapped twice must reach count 2, not 1).
            if event.kind == .change, let id = event.targetID {
                if session.tree.isToggleNodeID(id) {
                    if let val = event.value, let b = Bool(val) {
                        session.state.values[id] = .bool(b)
                    } else {
                        let flipped = !(session.state.bool(id) ?? false)
                        session.state.values[id] = .bool(flipped)
                    }
                } else if session.tree.isTextFieldNodeID(id) {
                    session.state.values[id] = .string(event.value ?? "")
                }
            }
            let request = CanvasDispatchRequest(event: event, state: session.state)
            do {
                let result = try await scripting.dispatch(request)
                guard self.generation == myGeneration, self.session?.id == session.id else { return }
                session.apply(state: result.state, tree: result.tree)
                self.onEffects?(result.effects)
                if let status = result.status {
                    self.onStatus?(status)
                }
                self.restoreFocus(after: event, in: session)
            } catch {
                guard self.generation == myGeneration else { return }
                self.session = nil
                self.onSessionError?(error)
            }
        }
    }

    /// Forwards a focus request to the session (renderer-driven focus, e.g. a click).
    public func requestFocus(_ id: String?) {
        session?.requestFocus(id)
    }

    /// Focus restore (§4.2): submit → re-focus targetID; change from a textField (blur) → skip;
    /// change from a toggle → keep focus on the toggle; missing target → firstInteractiveID.
    private func restoreFocus(after event: CanvasEvent, in session: CanvasSession) {
        switch event.kind {
        case .submit:
            let target = event.targetID.flatMap { session.tree.containsNodeID($0) ? $0 : nil }
                ?? session.tree.firstInteractiveID()
            session.requestFocus(target)
        case .change:
            guard let target = event.targetID, session.tree.containsNodeID(target) else {
                session.requestFocus(session.tree.firstInteractiveID())
                return
            }
            if !session.tree.isTextFieldNodeID(target) { session.requestFocus(target) } // toggle keeps focus
        case .tap:
            break
        }
    }
}

// MARK: - Tree helpers (App-side)

/// Small depth-first walkers over the component tree. `containsNodeID(_:)`/`isTextFieldNodeID(_:)`/
/// `isToggleNodeID(_:)` resolve whether a target id exists and what kind of node it names — used by
/// the pre-flip commit and the focus-restore rules. (Could live in Core if a second consumer shows up.)
fileprivate extension CanvasComponent {
    private var ownID: String? {
        switch self {
        case .stack(let props, _): return props.id
        case .divider(let props): return props.id
        case .spacer(let props): return props.id
        case .text(let props): return props.id
        case .icon(let props): return props.id
        case .image(let props): return props.id
        case .button(let props): return props.id
        case .list(let props, _): return props.id
        case .textField(let props): return props.id
        case .toggle(let props): return props.id
        case .link(let props): return props.id
        }
    }

    private var children: [CanvasComponent] {
        if case .stack(_, let children) = self { return children }
        return []
    }

    func containsNodeID(_ id: String) -> Bool {
        if ownID == id { return true }
        for child in children where child.containsNodeID(id) { return true }
        return false
    }

    func isTextFieldNodeID(_ id: String) -> Bool {
        if case .textField(let props) = self { return props.id == id }
        for child in children where child.isTextFieldNodeID(id) { return true }
        return false
    }

    func isToggleNodeID(_ id: String) -> Bool {
        if case .toggle(let props) = self { return props.id == id }
        for child in children where child.isToggleNodeID(id) { return true }
        return false
    }
}
