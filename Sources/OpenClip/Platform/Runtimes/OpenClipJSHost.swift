// OpenClipJSHost.swift
// OpenClip
//
// Dedicated, testable JavaScriptCore bridge for JS extensions (plan §8, Phase 6). Exposes the full
// read-only `openclip.*` author surface (input/matchedText/captures/app, read-only options, and the
// effect API) and resolves collected effects into a RAW runtime ActionResult via a deterministic
// resolution order — no declarative after/stayVisible translation here (that is
// ActionResultAdapter.apply, applied by the runtime's perform). JS exceptions surface as
// `.showStatus(.error, message)` rather than throwing; Swift-level setup failures may throw.
//
// Execution model: every run executes inside a `Task.detached` on a background thread — never the
// MainActor. JavaScriptCore contexts are not thread-safe, so ALL JavaScript VM access is confined to
// the single thread that created the context (the detached task's thread). The URLSession→JS
// hand-off hops back onto that thread's CFRunLoop via CFRunLoopPerformBlock + CFRunLoopWakeUp, so
// the promise settlement always runs on the JS thread. Async extensions (manifest `"async": true`)
// get a `fetch(url, options)` polyfill bridged to URLSession (GET/POST with JSON bodies; responses
// expose `{ status, ok, text(), json() }`) and a promise bridge: the wrapped entry point attaches
// `.then`/catch handlers that settle a PromiseState, and the host pumps the thread's runloop until
// the promise settles. A watchdog (TimeoutFlag pattern from ShellProcessRunner) invalidates the
// context and throws after `Constants.scriptTimeout`. Synchronous extensions keep the exact legacy
// wrapped-script shape and immediate-result behavior.
import Foundation
import JavaScriptCore
import Core

/// Stateless facade over a URLSession that executes one JS run per call. `@unchecked Sendable`
/// because it only holds `let session` (URLSession) — all mutable evaluation state lives in locals
/// passed down to `execute`, and JS VM access is confined to the detached task's thread.
public final class OpenClipJSHost: @unchecked Sendable {
    public struct Request: Sendable {
        public var actionID: String
        public var scriptCode: String
        public var context: ActionContext
        public var options: [ExtensionOption]
        public var optionStore: any ActionOptionReading
        public var rules: ExtensionActionRules
        /// When true the host awaits the action's promise (and enables the fetch polyfill). When
        /// false, legacy synchronous evaluation is used.
        public var isAsync: Bool
        /// Watchdog budget. Defaults to `Constants.scriptTimeout` when nil (test override).
        public var timeout: TimeInterval?

        public init(
            actionID: String,
            scriptCode: String,
            context: ActionContext,
            options: [ExtensionOption],
            optionStore: any ActionOptionReading,
            rules: ExtensionActionRules,
            isAsync: Bool = false,
            timeout: TimeInterval? = nil
        ) {
            self.actionID = actionID
            self.scriptCode = scriptCode
            self.context = context
            self.options = options
            self.optionStore = optionStore
            self.rules = rules
            self.isAsync = isAsync
            self.timeout = timeout
        }
    }

    public struct Collected: Sendable {
        public var openURL: URL?
        public var paste: String?
        public var copy: String?
        public var cut: String?
        public var content: CanvasComponent?
        public var isContentRejected: Bool
        public var status: StatusFeedback?
        public var configuration: ConfigurationRequest?
        public var keyPress: KeyPressSpec?
        public var shortcutName: String?
        public var keepVisible: Bool
        public var notification: (title: String, body: String)?
        public var shareService: (identifier: String, text: String)?
        public var returnValue: String?

        public init() {
            self.isContentRejected = false
            self.keepVisible = false
        }
    }

    /// One side-effecting JS call, kept in call order for `.sequence` resolution.
    enum Effect: Sendable {
        case paste(String)
        case copy(String)
        case cut(String)
        case openURL(URL)
        case keyPress(KeyPressSpec)
        case runShortcut(name: String, input: String?)
        case notify(title: String, body: String)
        case shareService(identifier: String, text: String)
    }

    /// Result of one JS evaluation: collected effects, any JS exception, and the value resolved from
    /// an awaited promise (async mode). Sendable because it crosses the detached-task boundary.
    private struct EvaluationResult: Sendable {
        let collected: Collected
        let effects: [Effect]
        let exceptionMessage: String?
        let asyncReturnValue: String?
    }

    /// URLSession used by the fetch polyfill. Injected for tests (URLProtocol mocks); the shared
    /// session by default.
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func run(_ request: Request) async throws -> ActionResult {
        let session = self.session

        // Synchronous evaluations (and the top-level synchronous parsing/execution phase of async
        // scripts) cannot be interrupted once started (JSVirtualMachine.invalidate is gone in modern
        // SDKs), so a CPU-bound sync script permanently parks a cooperative-pool thread. Cap in-flight
        // sync evaluations and refuse new ones at the cap, logging at .error.
        let gate = OpenClipJSHost.syncEvaluationGate
        guard gate.tryEnter() else {
            Log.js.error("Refusing JS evaluation for action \(request.actionID, privacy: .public): \(gate.inFlightCount) in-flight sync evaluations at cap")
            throw NSError(
                domain: Constants.actionErrorDomain,
                code: Int(Constants.actionErrorCode) + 2,
                userInfo: [NSLocalizedDescriptionKey: "Too many in-flight script evaluations; another script may be stuck."]
            )
        }

        // Note: reference static members via the explicit type name, not `Self` — `Self.X` inside a
        // Task.detached closure triggers a Swift 6 region-based-isolation checker bug ("pattern that
        // the region-based isolation checker does not understand how to check").
        return try await Task.detached {
            defer { gate.leave() }
            return try OpenClipJSHost.execute(request, session: session)
        }.value
    }

    // MARK: - JS evaluation

    /// Runs the whole evaluation on the calling thread (the detached task's thread). Kept as a thin
    /// nonisolated function so the @Sendable detached closure stays a single call.
    private static func execute(_ request: Request, session: URLSession) throws -> ActionResult {
        let evaluation = try evaluate(request, session: session)
        return makeActionResult(evaluation, request: request)
    }

    private static func evaluate(_ request: Request, session: URLSession) throws -> EvaluationResult {
        let text = request.context.selection.text
        let matchedText = request.context.match?.matchedText ?? text
        let captures = request.context.match?.captures ?? []

        guard let jsContext = JSContext() else {
            throw NSError(domain: Constants.actionErrorDomain,
                          code: Constants.actionErrorCode,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create JavaScript context"])
        }

        let timeoutSeconds = request.timeout ?? Constants.scriptTimeout
        let timeoutFlag = TimeoutFlag()
        // Watchdog: marks the timeout flag after the execution budget (matching ShellProcessRunner).
        // The async pump loop below observes the flag and throws, interrupting a never-settling
        // promise. (JSVirtualMachine.invalidate() — the old way to abort runaway scripts — was
        // removed from modern SDKs, so the flag + pump-loop check is the interruption mechanism.)
        let watchdog = Task.detached {
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            timeoutFlag.markTimedOut()
        }
        defer { watchdog.cancel() }

        let collected = CollectedBox()
        let effects = EffectsBox()
        let promiseState = request.isAsync ? PromiseState() : nil
        let fetchTasks = FetchTaskBox()

        // Give scripts a global `console.log` before anything runs, so it routes to Log.js instead
        // of throwing a ReferenceError that breaks the action.
        installConsoleShim(in: jsContext, actionID: request.actionID)

        // Read-only input context. Options are injected as a plain dictionary (values resolved via
        // the option store); `option(id)` is a functional form over the same dictionary.
        let optionsDict = optionValues(for: request)
        guard let openclip = makeOpenClipObject(
            in: jsContext,
            text: text,
            matchedText: matchedText,
            captures: captures,
            sourceApp: request.context.selection.sourceApp,
            options: optionsDict
        ) else {
            throw NSError(domain: Constants.actionErrorDomain,
                          code: Constants.actionErrorCode,
                          userInfo: [NSLocalizedDescriptionKey: "Could not build openclip bridge object"])
        }

        let pasteBlock: @convention(block) (String) -> Void = { value in
            collected.value.paste = value
            effects.value.append(.paste(value))
        }
        let copyBlock: @convention(block) (String) -> Void = { value in
            collected.value.copy = value
            effects.value.append(.copy(value))
        }
        let cutBlock: @convention(block) (String) -> Void = { value in
            collected.value.cut = value
            effects.value.append(.cut(value))
        }
        let openURLBlock: @convention(block) (String) -> Void = { value in
            guard let url = URL(string: value) else { return } // ignore invalid URLs
            collected.value.openURL = url
            effects.value.append(.openURL(url))
        }
        let keyPressBlock: @convention(block) (String, NSArray?) -> Void = { key, modifiers in
            let spec = KeyPressSpec(key: key, modifiers: Self.mapModifiers(modifiers))
            collected.value.keyPress = spec
            effects.value.append(.keyPress(spec))
        }
        let runShortcutBlock: @convention(block) (String, String?) -> Void = { name, inputOverride in
            let cleanedInput: String?
            if let inputOverride, inputOverride != "undefined", inputOverride != "null" {
                cleanedInput = inputOverride
            } else {
                cleanedInput = nil
            }
            collected.value.shortcutName = name
            effects.value.append(.runShortcut(name: name, input: cleanedInput))
        }
        let notifyBlock: @convention(block) (String, String) -> Void = { title, message in
            collected.value.notification = (title: title, body: message)
            effects.value.append(.notify(title: title, body: message))
        }
        let shareServiceBlock: @convention(block) (String, String?) -> Void = { identifier, textOverride in
            let cleanedInput: String
            if let textOverride, textOverride != "undefined", textOverride != "null" {
                cleanedInput = textOverride
            } else {
                cleanedInput = request.context.selection.text
            }
            collected.value.shareService = (identifier: identifier, text: cleanedInput)
            effects.value.append(.shareService(identifier: identifier, text: cleanedInput))
        }
        let showStatusBlock: @convention(block) (String, String?) -> Void = { message, style in
            collected.value.status = StatusFeedback(message: message, style: CanvasScriptBox.mapStatusStyle(style ?? "info"))
        }
        let showContentBlock: @convention(block) (JSValue) -> Void = { value in
            if let parsed = Self.parseElementTree(value) {
                collected.value.content = parsed
            } else {
                collected.value.isContentRejected = true
            }
        }
        let keepVisibleBlock: @convention(block) () -> Void = {
            collected.value.keepVisible = true
        }
        let requireConfigurationBlock: @convention(block) (JSValue) -> Void = { value in
            collected.value.configuration = Self.parseConfiguration(value, actionID: request.actionID)
        }

        openclip.setObject(pasteBlock, forKeyedSubscript: "paste" as NSString)
        openclip.setObject(copyBlock, forKeyedSubscript: "copy" as NSString)
        openclip.setObject(cutBlock, forKeyedSubscript: "cut" as NSString)
        openclip.setObject(openURLBlock, forKeyedSubscript: "openURL" as NSString)
        openclip.setObject(keyPressBlock, forKeyedSubscript: "keyPress" as NSString)
        openclip.setObject(runShortcutBlock, forKeyedSubscript: "runShortcut" as NSString)
        openclip.setObject(notifyBlock, forKeyedSubscript: "notify" as NSString)
        openclip.setObject(shareServiceBlock, forKeyedSubscript: "shareService" as NSString)
        openclip.setObject(showStatusBlock, forKeyedSubscript: "showStatus" as NSString)
        openclip.setObject(showContentBlock, forKeyedSubscript: "showContent" as NSString)
        openclip.setObject(keepVisibleBlock, forKeyedSubscript: "keepVisible" as NSString)
        openclip.setObject(requireConfigurationBlock, forKeyedSubscript: "requireConfiguration" as NSString)

        jsContext.setObject(openclip, forKeyedSubscript: "openclip" as NSString)
        jsContext.evaluateScript("openclip.option = function(id) { return openclip.options[id]; }")
        if request.isAsync, let promiseState {
            registerAsyncBridge(
                openclip: openclip,
                context: jsContext,
                promiseState: promiseState,
                session: session,
                fetchTasks: fetchTasks
            )
        }

        let wrappedScript = request.isAsync ? asyncWrappedScript(request.scriptCode) : syncWrappedScript(request.scriptCode)
        let jsResult = jsContext.evaluateScript(wrappedScript)

        if timeoutFlag.isTimedOut {
            fetchTasks.cancelAll()
            throw timeoutError(timeoutSeconds)
        }

        if let exception = jsContext.exception {
            return EvaluationResult(collected: collected.value, effects: effects.value, exceptionMessage: exception.toString() ?? "JavaScript exception", asyncReturnValue: nil)
        }

        // Async path: pump the JS thread's runloop until the promise settles (fetch completions and
        // promise microtasks land here via CFRunLoopPerformBlock) or the watchdog fires.
        if request.isAsync, let promiseState {
            while !promiseState.isSettled {
                if timeoutFlag.isTimedOut {
                    fetchTasks.cancelAll()
                    throw timeoutError(timeoutSeconds)
                }
                CFRunLoopRunInMode(.defaultMode, 0.05, true)
            }
            if let rejected = promiseState.rejectedValue {
                let message = rejected.toString() ?? "JavaScript promise rejected"
                return EvaluationResult(collected: collected.value, effects: effects.value, exceptionMessage: message, asyncReturnValue: nil)
            }
            let resolved = promiseState.resolvedValue.flatMap { value in
                let string = value.toString() ?? ""
                return (string.isEmpty || string == "undefined" || string == "null") ? nil : string
            }
            return EvaluationResult(collected: collected.value, effects: effects.value, exceptionMessage: nil, asyncReturnValue: resolved)
        }

        // Sync path: a promise-like return cannot be awaited in legacy mode, so it is ignored
        // rather than pasted as "[object Promise]".
        if let result = jsResult, !isPromiseLike(result) {
            if let resultString = result.toString(), resultString != "undefined", resultString != "null" {
                collected.value.returnValue = resultString
            }
        }
        return EvaluationResult(collected: collected.value, effects: effects.value, exceptionMessage: nil, asyncReturnValue: nil)
    }

    // MARK: - Async bridge (fetch polyfill + promise settling)

    /// Registers `openclip.__resolve` / `openclip.__reject` (promise settlement) and installs the
    /// shared URLSession-backed fetch bridge (`openclip.__nativeFetch` + the `openclip.fetch`
    /// polyfill) via `JSNativeFetch.installNativeFetch`. The global `openclip` object must already
    /// be installed in the context before this runs.
    private static func registerAsyncBridge(
        openclip: JSValue,
        context: JSContext,
        promiseState: PromiseState,
        session: URLSession,
        fetchTasks: FetchTaskBox
    ) {
        let resolveBlock: @convention(block) (JSValue) -> Void = { value in
            promiseState.resolve(value)
        }
        let rejectBlock: @convention(block) (JSValue) -> Void = { error in
            promiseState.reject(error)
        }
        openclip.setObject(resolveBlock, forKeyedSubscript: "__resolve" as NSString)
        openclip.setObject(rejectBlock, forKeyedSubscript: "__reject" as NSString)

        JSNativeFetch.installNativeFetch(in: context, session: session, fetchTasks: fetchTasks)
    }

    /// True when a JS result is a promise-like (has a `then` function) that cannot be awaited in
    /// legacy synchronous mode.
    private static func isPromiseLike(_ value: JSValue) -> Bool {
        guard value.isObject, let then = value.objectForKeyedSubscript("then") else { return false }
        return !then.isUndefined && !then.isNull && then.isObject
    }

    // MARK: - Console shim

    /// Installs a global `console` object with a `log` method that routes to `Log.js`. Without this,
    /// `console.log(...)` throws a `ReferenceError` that the JSContext surfaces as
    /// `.showStatus(.error)` and breaks the action. To prevent leaking sensitive text, clipboard, or
    /// extension data, arguments are redacted into non-sensitive metadata (type, length, object keys)
    /// before forwarding to `Log.js`.
    private static func installConsoleShim(in context: JSContext, actionID: String) {
        guard let console = JSValue(newObjectIn: context) else { return }
        let logBlock: @convention(block) (String) -> Void = { message in
            Log.js.info("[console.log] action=\(actionID, privacy: .public) \(message)")
        }
        console.setObject(logBlock, forKeyedSubscript: "__log" as NSString)
        context.setObject(console, forKeyedSubscript: "console" as NSString)
        context.evaluateScript("""
        (function() {
            var __consoleLog = console.__log;
            delete console.__log;
            console.log = function() {
                function formatArg(v) {
                    if (v === null) return 'null';
                    if (v === undefined) return 'undefined';
                    var t = typeof v;
                    if (t === 'string') return '<string len=' + v.length + '>';
                    if (t === 'number') return '<number>';
                    if (t === 'boolean') return '<boolean>';
                    if (t === 'function') return '<function>';
                    if (Array.isArray(v)) return '<Array len=' + v.length + '>';
                    if (t === 'object') {
                        try {
                            var keys = Object.keys(v);
                            return '<Object keys=[' + keys.join(', ') + ']>';
                        } catch (e) {
                            return '<Object>';
                        }
                    }
                    return '<' + t + '>';
                }
                var parts = [];
                for (var i = 0; i < arguments.length; i++) {
                    parts.push(formatArg(arguments[i]));
                }
                __consoleLog(parts.join(' '));
            };
        })();
        """)
    }

    /// Legacy synchronous wrapper — preserved shape: define action/main inside an IIFE and dispatch
    /// to whichever entry point the author provided (golden + option-store tests depend on this).
    private static func syncWrappedScript(_ scriptCode: String) -> String {
        """
        (function() {
            var selection = openclip.input.text;
            var options = openclip.options;
            \(scriptCode)
            if (typeof action === 'function') {
                return action(selection, options);
            }
            if (typeof main === 'function') {
                return main(selection, options);
            }
            return null;
        })();
        """
    }

    /// Async wrapper: dispatches the entry point through `__openclip_dispatch`, which settles the
    /// bridge promise — immediately for synchronous returns, via `.then`/catch for promise returns.
    /// A script with no entry point (top-level side effects only) still settles so it never hangs.
    private static func asyncWrappedScript(_ scriptCode: String) -> String {
        """
        var __openclip_dispatch = function(fn, selection, options) {
            var result;
            try {
                result = fn(selection, options);
            } catch (e) {
                openclip.__reject(e);
                return null;
            }
            if (result !== null && result !== undefined && typeof result.then === 'function') {
                result.then(
                    function(value) { openclip.__resolve(value); },
                    function(error) { openclip.__reject(error); }
                );
                return null;
            }
            openclip.__resolve(result);
            return null;
        };
        (function() {
            var selection = openclip.input.text;
            var options = openclip.options;
            \(scriptCode)
            var __entry;
            if (typeof action === 'function') {
                __entry = action;
            } else if (typeof main === 'function') {
                __entry = main;
            }
            if (__entry) {
                return __openclip_dispatch(__entry, selection, options);
            }
            openclip.__resolve(null);
            return null;
        })();
        """
    }

    // MARK: - Effect → ActionResult

    private static func makeActionResult(_ evaluation: EvaluationResult, request: Request) -> ActionResult {
        let collected = evaluation.collected

        // JS exceptions win over any partially-collected effects (do NOT throw for JS exceptions).
        if let exceptionMessage = evaluation.exceptionMessage {
            let raw: ActionResult = .showStatus(StatusFeedback(message: exceptionMessage, style: .error))
            return collected.keepVisible ? .keepVisible(raw) : raw
        }

        // Deterministic resolution order (plan §8): configuration > content > status-only > effects
        // (in call order, sequence when >1) > function string return > success.
        let effects = evaluation.effects
        let raw: ActionResult
        if let configuration = collected.configuration {
            raw = .openConfiguration(configuration)
        } else if let content = collected.content {
            raw = .showContent(content, nil)
        } else if collected.isContentRejected {
            raw = .showStatus(StatusFeedback(message: "Canvas payload rejected.", style: .error))
        } else if let status = collected.status, effects.isEmpty {
            raw = .showStatus(status)
        } else if !effects.isEmpty {
            let input = request.context.match?.matchedText ?? request.context.selection.text
            let mapped = effects.map { effectResult($0, input: input) }
            raw = mapped.count == 1 ? mapped[0] : .sequence(mapped)
        } else if let returnValue = evaluation.asyncReturnValue ?? collected.returnValue {
            raw = .copy(returnValue)
        } else {
            raw = .success
        }

        // The runtime keepVisible flag wraps the resolved result UNCONDITIONALLY (resolution 3);
        // the declarative stayVisible wrap is narrower and lives in ActionResultAdapter.
        if collected.keepVisible {
            return .keepVisible(raw)
        }
        return raw
    }

    private static func effectResult(_ effect: Effect, input: String) -> ActionResult {
        switch effect {
        case .paste(let text): return .paste(text)
        case .copy(let text): return .copy(text)
        case .cut(let text): return .cut(text)
        case .openURL(let url): return .openURL(url)
        case .keyPress(let spec): return .keyPress(spec)
        case .runShortcut(let name, let inputOverride): return .runShortcut(name: name, input: inputOverride ?? input)
        case .notify(let title, let body): return .notify(title: title, body: body)
        case .shareService(let identifier, let text): return .shareService(identifier: identifier, text: text)
        }
    }

    private static func optionValues(for request: Request) -> [String: Any] {
        var values: [String: Any] = [:]
        for option in request.options {
            let strVal = request.optionStore.stringValue(actionID: request.actionID, option: option)
            if option.type == .boolean {
                let lower = strVal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                values[option.identifier] = (lower == "true" || lower == "1")
            } else {
                values[option.identifier] = strVal
            }
        }
        return values
    }

    private static func makeOpenClipObject(
        in jsContext: JSContext,
        text: String,
        matchedText: String,
        captures: [String],
        sourceApp: AppIdentity,
        options: [String: Any]
    ) -> JSValue? {
        guard let openclip = JSValue(newObjectIn: jsContext),
              let input = JSValue(newObjectIn: jsContext),
              let app = JSValue(newObjectIn: jsContext) else {
            return nil
        }

        input.setObject(text, forKeyedSubscript: "text")
        input.setObject(matchedText, forKeyedSubscript: "matchedText")
        input.setObject(captures, forKeyedSubscript: "captures")

        app.setObject(sourceApp.bundleIdentifier ?? "", forKeyedSubscript: "bundleID")
        app.setObject(sourceApp.localizedName ?? "", forKeyedSubscript: "name")
        input.setObject(app, forKeyedSubscript: "app")

        CanvasScriptBox.installH(in: jsContext)

        openclip.setObject(input, forKeyedSubscript: "input")
        openclip.setObject(options, forKeyedSubscript: "options")
        return openclip
    }

    // MARK: - JS value parsing

    private static func mapModifiers(_ modifiers: NSArray?) -> [KeyPressSpec.KeyModifier] {
        guard let modifiers else { return [] }
        return modifiers.compactMap { element in
            guard let raw = element as? String else { return nil }
            switch raw.lowercased() {
            case "command": return .command
            case "shift": return .shift
            case "option": return .option
            case "control": return .control
            default: return nil
            }
        }
    }

    /// nil for missing/"undefined"/"null" JS string values.
    private static func stringValue(_ value: JSValue?) -> String? {
        guard let value else { return nil }
        let string = value.toString() ?? ""
        if string.isEmpty || string == "undefined" || string == "null" { return nil }
        return string
    }

    private static func parseConfiguration(_ value: JSValue, actionID: String) -> ConfigurationRequest {
        var reason: String?
        var missing: [String] = []
        if value.isObject {
            reason = stringValue(value.objectForKeyedSubscript("reason"))
            if let missingValue = value.objectForKeyedSubscript("missing"), missingValue.isArray {
                missing = missingValue.toArray()?.compactMap { $0 as? String } ?? []
            }
        }
        return ConfigurationRequest(actionID: actionID, reason: reason, missingOptionIDs: missing)
    }

    /// Parses an h() element object (`{type, props, children}`) into a CanvasComponent tree.
    private static func parseElementTree(_ value: JSValue) -> CanvasComponent? {
        guard value.isObject,
              let object = value.toObject() as? [String: Any],
              let spec = CanvasScriptBox.elementSpec(from: object),
              let root = try? CanvasElementParser.parseTree(spec) else { return nil }
        return root
    }

    // MARK: - Watchdog + threading helpers

    private static func timeoutError(_ seconds: TimeInterval) -> NSError {
        NSError(domain: Constants.actionErrorDomain,
                code: Int(Constants.actionErrorCode) + 1,
                userInfo: [NSLocalizedDescriptionKey: "Script timed out after \(Int(seconds)) seconds"])
    }

    /// Bounds in-flight synchronous evaluations across the whole host (all instances).
    static let syncEvaluationGate = SyncEvaluationGate(capacity: Constants.maxConcurrentSyncScriptEvaluations)

    /// Declared slot count for synchronous script evaluation gating.
    public static var syncEvaluationSlotCount: Int {
        syncEvaluationGate.capacity
    }
}

