// JavaScriptCanvasEngine.swift
// OpenClip
//
// In-process JavaScriptCore canvas engine implementing `CanvasScripting` (spec §5.2).
// Session VM created once; script compiled once per session VM; fresh JSContext created per
// evaluation (mount/dispatch) in that VM. Synchronous evaluation is bounded across the app via
// `OpenClipJSHost.syncEvaluationGate`. Watchdog timeout flag bounds CPU runaway.

import Foundation
import JavaScriptCore
import Core

public enum CanvasJSRuntimeError: Error, Sendable, Equatable {
    case scriptException(String)
    case asyncNotSupported
    case missingUISymbol
}

public final class JavaScriptCanvasEngine: CanvasScripting, @unchecked Sendable {
    private let virtualMachine: JSVirtualMachine
    private var scriptCode: String = ""
    private var timeoutOverride: TimeInterval?

    // Session cache across dispatches
    private var sessionState: CanvasSessionState
    private var sessionInput: String
    private var sessionOptionValues: [String: JSONValue]
    private var isAsync: Bool

    public init(timeout: TimeInterval? = nil) {
        self.virtualMachine = JSVirtualMachine()
        self.sessionState = CanvasSessionState()
        self.sessionInput = ""
        self.sessionOptionValues = [:]
        self.isAsync = false
        self.timeoutOverride = timeout
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

        let timeoutSeconds = self.timeoutOverride ?? Constants.scriptTimeout
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

        let timeoutSeconds = self.timeoutOverride ?? Constants.scriptTimeout
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
            optionValues: request.optionValues,
            collector: collector
        )

        let scriptCode = request.scriptCode
        engine.scriptCode = scriptCode
        engine.sessionInput = request.input
        engine.sessionOptionValues = request.optionValues
        engine.isAsync = request.isAsync

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

        let stateJS = JSValue(object: stateDict, in: jsContext)!
        let inputJS = JSValue(object: request.input, in: jsContext)!

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

        engine.sessionState = effectiveState
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

        CanvasScriptBox.installH(in: jsContext)
        let collector = CanvasBridgeCollector()
        CanvasScriptBox.installCanvasBridge(
            in: jsContext,
            input: engine.sessionInput,
            optionValues: engine.sessionOptionValues,
            collector: collector
        )

        let scriptCode = engine.scriptCode
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
            let stateJS = JSValue(object: stateDict, in: jsContext)!
            let eventDict: [String: Any] = [
                "kind": request.event.kind.rawValue,
                "handler": request.event.handler,
                "value": request.event.value as Any,
                "targetID": request.event.targetID as Any
            ]
            let eventJS = JSValue(object: eventDict, in: jsContext)!
            let inputJS = JSValue(object: engine.sessionInput, in: jsContext)!

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
                    let resJS = JSValue(object: resolveBlock, in: jsContext)!
                    let rejJS = JSValue(object: rejectBlock, in: jsContext)!
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
        let newStateJS = JSValue(object: newStateDict, in: jsContext)!
        let inputJS = JSValue(object: engine.sessionInput, in: jsContext)!
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

        engine.sessionState = currentState
        return CanvasDispatchResult(state: currentState, tree: tree, effects: collector.effects, status: collector.status)
    }

    private static func isPromiseLike(_ value: JSValue) -> Bool {
        guard value.isObject, let then = value.objectForKeyedSubscript("then") else { return false }
        return !then.isUndefined && !then.isNull && then.isObject
    }
}
