// JavaScriptCanvasEngine.swift
// OpenClip
//
// In-process JavaScriptCore canvas engine implementing `CanvasScripting` (spec §5.2).
// Session VM lazily initialized; fresh JSContext created per evaluation (mount/dispatch) in that VM.
// Synchronous evaluation is bounded across the app via `OpenClipJSHost.syncEvaluationGate`.
// Watchdog timeout flag checks deadline between steps. Note: JavaScriptCore does not support
// synchronous script cancellation; a tight loop (e.g. while(true)) will block until thread exits.

import Foundation
import JavaScriptCore
import Core

public enum CanvasJSRuntimeError: Error, Sendable, Equatable {
    case scriptException(String)
    case asyncNotSupported
    case missingUISymbol
}

public final class JavaScriptCanvasEngine: CanvasScripting, @unchecked Sendable {
    private let lock = NSLock()
    private var _scriptCode: String = ""
    private var _timeoutOverride: TimeInterval?

    // Session cache across dispatches
    private var _sessionState: CanvasSessionState
    private var _sessionInput: String
    private var _sessionCaptures: [String]
    private var _sessionApp: AppIdentity?
    private var _sessionOptionValues: [String: JSONValue]
    private var _isAsync: Bool

    public let virtualMachine: JSVirtualMachine = JSVirtualMachine()

    public let session: URLSession

    public init(timeout: TimeInterval? = nil, session: URLSession = .shared) {
        self.session = session
        self._sessionState = CanvasSessionState()
        self._sessionInput = ""
        self._sessionCaptures = []
        self._sessionApp = nil
        self._sessionOptionValues = [:]
        self._isAsync = false
        self._timeoutOverride = timeout
    }

    private func updateMountState(scriptCode: String, input: String, captures: [String], sourceApp: AppIdentity?, optionValues: [String: JSONValue], isAsync: Bool, state: CanvasSessionState) {
        lock.withLock {
            _scriptCode = scriptCode
            _sessionInput = input
            _sessionCaptures = captures
            _sessionApp = sourceApp
            _sessionOptionValues = optionValues
            _isAsync = isAsync
            _sessionState = state
        }
    }

    private func getDispatchInputs() -> (scriptCode: String, input: String, captures: [String], sourceApp: AppIdentity?, optionValues: [String: JSONValue]) {
        lock.withLock {
            (_scriptCode, _sessionInput, _sessionCaptures, _sessionApp, _sessionOptionValues)
        }
    }

    private func getIsAsync() -> Bool {
        lock.withLock {
            _isAsync
        }
    }

    private func updateDispatchState(_ state: CanvasSessionState) {
        lock.withLock {
            _sessionState = state
        }
    }

    public func mount(_ request: CanvasMountRequest) async throws -> CanvasMountResult {
        let gate = OpenClipJSHost.syncEvaluationGate
        guard gate.tryEnter() else {
            Log.js.error("Refusing canvas mount: sync evaluation gate at cap")
            throw NSError(
                domain: Constants.actionErrorDomain,
                code: Int(Constants.actionErrorCode) + 2,
                userInfo: [NSLocalizedDescriptionKey: "Too many in-flight script evaluations; another script may be stuck."]
            )
        }
        defer { gate.leave() }

        let timeoutSeconds = self.lock.withLock { self._timeoutOverride } ?? Constants.scriptTimeout
        let vm = self.virtualMachine

        return try await Task.detached {
            try JavaScriptCanvasEngine.executeMount(
                request: request,
                virtualMachine: vm,
                timeoutSeconds: timeoutSeconds,
                engine: self
            )
        }.value
    }

    public func dispatch(_ request: CanvasDispatchRequest) async throws -> CanvasDispatchResult {
        let gate = OpenClipJSHost.syncEvaluationGate
        guard gate.tryEnter() else {
            Log.js.error("Refusing canvas dispatch: sync evaluation gate at cap")
            throw NSError(
                domain: Constants.actionErrorDomain,
                code: Int(Constants.actionErrorCode) + 2,
                userInfo: [NSLocalizedDescriptionKey: "Too many in-flight script evaluations; another script may be stuck."]
            )
        }
        defer { gate.leave() }

        let timeoutSeconds = self.lock.withLock { self._timeoutOverride } ?? Constants.scriptTimeout
        let vm = self.virtualMachine

        return try await Task.detached {
            try JavaScriptCanvasEngine.executeDispatch(
                request: request,
                virtualMachine: vm,
                timeoutSeconds: timeoutSeconds,
                engine: self
            )
        }.value
    }

    // MARK: - Mount

    private static func executeMount(
        request: CanvasMountRequest,
        virtualMachine: JSVirtualMachine,
        timeoutSeconds: TimeInterval,
        engine: JavaScriptCanvasEngine
    ) throws -> CanvasMountResult {
        let timeoutFlag = TimeoutFlag()
        let watchdog = Task.detached {
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            timeoutFlag.markTimedOut()
        }
        defer { watchdog.cancel() }

        guard let jsContext = JSContext(virtualMachine: virtualMachine) else {
            throw CanvasJSRuntimeError.scriptException("Could not create JavaScript context")
        }

        CanvasScriptBox.installH(in: jsContext)
        let collector = CanvasBridgeCollector()
        CanvasScriptBox.installCanvasBridge(
            in: jsContext,
            input: request.input,
            captures: request.captures,
            sourceApp: request.sourceApp,
            optionValues: request.optionValues,
            collector: collector
        )

        let scriptCode = request.scriptCode
        jsContext.evaluateScript(scriptCode)

        if timeoutFlag.isTimedOut {
            throw CanvasJSRuntimeError.scriptException("Script timed out after \(Int(timeoutSeconds)) seconds")
        }
        if let exception = jsContext.exception {
            throw CanvasJSRuntimeError.scriptException(exception.toString() ?? "JavaScript exception")
        }

        if !collector.effects.isEmpty {
            throw CanvasJSRuntimeError.scriptException("Effects are not allowed at mount time")
        }

        let setupSnippet = """
        var __canvas_ui = typeof ui !== 'undefined' ? ui : (typeof render !== 'undefined' ? render : null);
        var __canvas_handlers = typeof handlers !== 'undefined' ? handlers : {};
        var __canvas_initialState = typeof initialState !== 'undefined' ? initialState : {};
        """
        jsContext.evaluateScript(setupSnippet)

        guard let uiValue = jsContext.objectForKeyedSubscript("__canvas_ui"),
              !uiValue.isUndefined, !uiValue.isNull, uiValue.isObject else {
            throw CanvasJSRuntimeError.missingUISymbol
        }

        var stateDict: [String: Any] = [:]
        if !request.initialState.values.isEmpty {
            stateDict = request.initialState.values.mapValues(CanvasScriptBox.jsonValueToRawObject)
        } else if let initVal = jsContext.objectForKeyedSubscript("__canvas_initialState"),
                  initVal.isObject, let dict = initVal.toDictionary() as? [String: Any] {
            stateDict = dict
        }
        let effectiveState = CanvasSessionState(stateDict.compactMapValues(CanvasScriptBox.jsonValue(from:)))

        guard let stateJS = JSValue(object: stateDict, in: jsContext),
              let inputJS = JSValue(object: request.input, in: jsContext) else {
            throw CanvasJSRuntimeError.scriptException("Could not bridge state into JavaScript context")
        }

        let uiResult = uiValue.call(withArguments: [stateJS, inputJS])

        if timeoutFlag.isTimedOut {
            throw CanvasJSRuntimeError.scriptException("Script timed out after \(Int(timeoutSeconds)) seconds")
        }
        if let exception = jsContext.exception {
            throw CanvasJSRuntimeError.scriptException(exception.toString() ?? "JavaScript exception")
        }

        guard let uiResult else {
            throw CanvasJSRuntimeError.scriptException("UI function returned null or undefined")
        }

        if isPromiseLike(uiResult) {
            throw CanvasJSRuntimeError.asyncNotSupported
        }

        guard uiResult.isObject, let elementDict = uiResult.toObject() as? [String: Any] else {
            throw CanvasJSRuntimeError.scriptException("UI function must return an element object")
        }

        guard let spec = CanvasScriptBox.elementSpec(from: elementDict) else {
            throw CanvasJSRuntimeError.scriptException("Failed to parse element spec")
        }

        if let parseError = collector.parseError {
            throw CanvasJSRuntimeError.scriptException(parseError.localizedDescription)
        }

        let tree: CanvasComponent
        if let mountedTree = collector.mountedTree {
            tree = mountedTree
        } else {
            do {
                tree = try CanvasElementParser.parseTree(spec)
            } catch {
                throw CanvasJSRuntimeError.scriptException(error.localizedDescription)
            }
        }

        engine.updateMountState(
            scriptCode: scriptCode,
            input: request.input,
            captures: request.captures,
            sourceApp: request.sourceApp,
            optionValues: request.optionValues,
            isAsync: request.isAsync,
            state: effectiveState
        )

        if !collector.effects.isEmpty {
            throw CanvasJSRuntimeError.scriptException("Effects are not allowed at mount time")
        }

        return CanvasMountResult(state: effectiveState, tree: tree, preferredSize: collector.preferredSize)
    }

    // MARK: - Dispatch

    private static func executeDispatch(
        request: CanvasDispatchRequest,
        virtualMachine: JSVirtualMachine,
        timeoutSeconds: TimeInterval,
        engine: JavaScriptCanvasEngine
    ) throws -> CanvasDispatchResult {
        let timeoutFlag = TimeoutFlag()
        let watchdog = Task.detached {
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            timeoutFlag.markTimedOut()
        }
        defer { watchdog.cancel() }

        guard let jsContext = JSContext(virtualMachine: virtualMachine) else {
            throw CanvasJSRuntimeError.scriptException("Could not create JavaScript context")
        }

        let inputs = engine.getDispatchInputs()

        CanvasScriptBox.installH(in: jsContext)
        let collector = CanvasBridgeCollector()
        CanvasScriptBox.installCanvasBridge(
            in: jsContext,
            input: inputs.input,
            captures: inputs.captures,
            sourceApp: inputs.sourceApp,
            optionValues: inputs.optionValues,
            collector: collector
        )

        let fetchTasks = FetchTaskBox()
        if engine.getIsAsync() {
            JSNativeFetch.installNativeFetch(in: jsContext, session: engine.session, fetchTasks: fetchTasks)
        }
        defer { fetchTasks.cancelAll() }

        let scriptCode = inputs.scriptCode
        jsContext.evaluateScript(scriptCode)

        if timeoutFlag.isTimedOut {
            throw CanvasJSRuntimeError.scriptException("Script timed out after \(Int(timeoutSeconds)) seconds")
        }
        if let exception = jsContext.exception {
            throw CanvasJSRuntimeError.scriptException(exception.toString() ?? "JavaScript exception")
        }

        let setupSnippet = """
        var __canvas_ui = typeof ui !== 'undefined' ? ui : (typeof render !== 'undefined' ? render : null);
        var __canvas_handlers = typeof handlers !== 'undefined' ? handlers : {};
        """
        jsContext.evaluateScript(setupSnippet)

        guard let uiValue = jsContext.objectForKeyedSubscript("__canvas_ui"),
              !uiValue.isUndefined, !uiValue.isNull, uiValue.isObject else {
            throw CanvasJSRuntimeError.missingUISymbol
        }

        var currentState = request.state
        let handlersObj = jsContext.objectForKeyedSubscript("__canvas_handlers")

        if let handlersObj, handlersObj.isObject,
           let handlerFn = handlersObj.objectForKeyedSubscript(request.event.handler),
           !handlerFn.isUndefined, !handlerFn.isNull, handlerFn.isObject {

            let stateDict = currentState.values.mapValues(CanvasScriptBox.jsonValueToRawObject)
            let eventDict: [String: Any] = [
                "kind": request.event.kind.rawValue,
                "handler": request.event.handler,
                "value": request.event.value as Any,
                "targetID": request.event.targetID as Any
            ]
            guard let stateJS = JSValue(object: stateDict, in: jsContext),
                  let eventJS = JSValue(object: eventDict, in: jsContext),
                  let inputJS = JSValue(object: inputs.input, in: jsContext) else {
                throw CanvasJSRuntimeError.scriptException("Could not bridge event data into JavaScript context")
            }

            let handlerResult = handlerFn.call(withArguments: [stateJS, eventJS, inputJS])

            if timeoutFlag.isTimedOut {
                throw CanvasJSRuntimeError.scriptException("Script timed out after \(Int(timeoutSeconds)) seconds")
            }
            if let exception = jsContext.exception {
                throw CanvasJSRuntimeError.scriptException(exception.toString() ?? "JavaScript exception")
            }

            if let handlerResult {
                if isPromiseLike(handlerResult) {
                    let promiseState = PromiseState()
                    let resolveBlock: @convention(block) (JSValue) -> Void = { val in
                        promiseState.resolve(val)
                    }
                    let rejectBlock: @convention(block) (JSValue) -> Void = { err in
                        promiseState.reject(err)
                    }
                    guard let resJS = JSValue(object: resolveBlock, in: jsContext),
                          let rejJS = JSValue(object: rejectBlock, in: jsContext) else {
                        throw CanvasJSRuntimeError.scriptException("Could not bridge promise callbacks into JavaScript context")
                    }
                    handlerResult.invokeMethod("then", withArguments: [resJS, rejJS])

                    while !promiseState.isSettled {
                        if timeoutFlag.isTimedOut {
                            throw CanvasJSRuntimeError.scriptException("Script timed out after \(Int(timeoutSeconds)) seconds")
                        }
                        CFRunLoopRunInMode(.defaultMode, 0.01, true)
                    }

                    if let rejected = promiseState.rejectedValue {
                        throw CanvasJSRuntimeError.scriptException(rejected.toString() ?? "Promise rejected")
                    }
                    if let resolved = promiseState.resolvedValue, resolved.isObject,
                       let dict = resolved.toObject() as? [String: Any] {
                        currentState = CanvasSessionState(dict.compactMapValues(CanvasScriptBox.jsonValue(from:)))
                    }
                } else if handlerResult.isObject, let dict = handlerResult.toObject() as? [String: Any] {
                    currentState = CanvasSessionState(dict.compactMapValues(CanvasScriptBox.jsonValue(from:)))
                }
            }
        }

        // Re-render UI
        let newStateDict = currentState.values.mapValues(CanvasScriptBox.jsonValueToRawObject)
        guard let newStateJS = JSValue(object: newStateDict, in: jsContext),
              let inputJS = JSValue(object: inputs.input, in: jsContext) else {
            throw CanvasJSRuntimeError.scriptException("Could not bridge updated state into JavaScript context")
        }
        let uiResult = uiValue.call(withArguments: [newStateJS, inputJS])

        if timeoutFlag.isTimedOut {
            throw CanvasJSRuntimeError.scriptException("Script timed out after \(Int(timeoutSeconds)) seconds")
        }
        if let exception = jsContext.exception {
            throw CanvasJSRuntimeError.scriptException(exception.toString() ?? "JavaScript exception")
        }

        guard let uiResult else {
            throw CanvasJSRuntimeError.scriptException("UI function returned null or undefined")
        }

        if isPromiseLike(uiResult) {
            throw CanvasJSRuntimeError.asyncNotSupported
        }

        guard uiResult.isObject, let elementDict = uiResult.toObject() as? [String: Any] else {
            throw CanvasJSRuntimeError.scriptException("UI function must return an element object")
        }

        guard let spec = CanvasScriptBox.elementSpec(from: elementDict) else {
            throw CanvasJSRuntimeError.scriptException("Failed to parse element spec")
        }

        if let parseError = collector.parseError {
            throw CanvasJSRuntimeError.scriptException(parseError.localizedDescription)
        }

        let tree: CanvasComponent
        if let mountedTree = collector.mountedTree {
            tree = mountedTree
        } else {
            do {
                tree = try CanvasElementParser.parseTree(spec)
            } catch {
                throw CanvasJSRuntimeError.scriptException(error.localizedDescription)
            }
        }

        engine.updateDispatchState(currentState)
        return CanvasDispatchResult(state: currentState, tree: tree, effects: collector.effects, status: collector.status)
    }

    private static func isPromiseLike(_ value: JSValue) -> Bool {
        guard value.isObject, let then = value.objectForKeyedSubscript("then") else { return false }
        return !then.isUndefined && !then.isNull && then.isObject
    }
}
