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
        public var content: PopupContent?
        public var status: StatusFeedback?
        public var configuration: ConfigurationRequest?
        public var keyPress: KeyPressSpec?
        public var shortcutName: String?
        public var keepVisible: Bool
        public var notification: (title: String, body: String)?
        public var returnValue: String?

        public init() {
            self.keepVisible = false
        }
    }

    /// One side-effecting JS call, kept in call order for `.sequence` resolution.
    fileprivate enum Effect: Sendable {
        case paste(String)
        case copy(String)
        case cut(String)
        case openURL(URL)
        case keyPress(KeyPressSpec)
        case runShortcut(name: String)
        case notify(title: String, body: String)
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
        // Note: reference static members via the explicit type name, not `Self` — `Self.X` inside a
        // Task.detached closure triggers a Swift 6 region-based-isolation checker bug ("pattern that
        // the region-based isolation checker does not understand how to check").
        return try await Task.detached {
            try OpenClipJSHost.execute(request, session: session)
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

        // Read-only input context. Options are injected as a plain dictionary (values resolved via
        // the option store); `option(id)` is a functional form over the same dictionary.
        let optionsDict = optionValues(for: request)
        let openclip = makeOpenClipObject(
            in: jsContext,
            text: text,
            matchedText: matchedText,
            captures: captures,
            sourceApp: request.context.selection.sourceApp,
            options: optionsDict
        )

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
        let keyPressBlock: @convention(block) (String, NSArray) -> Void = { key, modifiers in
            let spec = KeyPressSpec(key: key, modifiers: Self.mapModifiers(modifiers))
            collected.value.keyPress = spec
            effects.value.append(.keyPress(spec))
        }
        let runShortcutBlock: @convention(block) (String) -> Void = { name in
            collected.value.shortcutName = name
            effects.value.append(.runShortcut(name: name))
        }
        let notifyBlock: @convention(block) (String, String) -> Void = { title, message in
            collected.value.notification = (title: title, body: message)
            effects.value.append(.notify(title: title, body: message))
        }
        let showStatusBlock: @convention(block) (String, String) -> Void = { message, style in
            collected.value.status = StatusFeedback(message: message, style: Self.mapStatusStyle(style))
        }
        let showContentBlock: @convention(block) (JSValue) -> Void = { value in
            collected.value.content = Self.parseContent(value)
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
        openclip.setObject(showStatusBlock, forKeyedSubscript: "showStatus" as NSString)
        openclip.setObject(showContentBlock, forKeyedSubscript: "showContent" as NSString)
        openclip.setObject(keepVisibleBlock, forKeyedSubscript: "keepVisible" as NSString)
        openclip.setObject(requireConfigurationBlock, forKeyedSubscript: "requireConfiguration" as NSString)

        if request.isAsync, let promiseState {
            registerAsyncBridge(openclip: openclip, context: jsContext, promiseState: promiseState, session: session)
        }

        jsContext.setObject(openclip, forKeyedSubscript: "openclip" as NSString)
        jsContext.evaluateScript("openclip.option = function(id) { return openclip.options[id]; }")
        if request.isAsync {
            jsContext.evaluateScript(fetchPolyfillScript)
        }

        let wrappedScript = request.isAsync ? asyncWrappedScript(request.scriptCode) : syncWrappedScript(request.scriptCode)
        let jsResult = jsContext.evaluateScript(wrappedScript)

        if timeoutFlag.isTimedOut {
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

    /// Registers `openclip.__resolve` / `openclip.__reject` (promise settlement) and
    /// `openclip.__nativeFetch` (the URLSession-backed fetch). The `openclip.fetch` polyfill is
    /// evaluated separately, after the global `openclip` object is installed.
    private static func registerAsyncBridge(
        openclip: JSValue,
        context: JSContext,
        promiseState: PromiseState,
        session: URLSession
    ) {
        let resolveBlock: @convention(block) (JSValue) -> Void = { value in
            promiseState.resolve(value)
        }
        let rejectBlock: @convention(block) (JSValue) -> Void = { error in
            promiseState.reject(error)
        }
        openclip.setObject(resolveBlock, forKeyedSubscript: "__resolve" as NSString)
        openclip.setObject(rejectBlock, forKeyedSubscript: "__reject" as NSString)

        // All JS VM access must stay on the thread that created the context. The URLSession
        // completion handler therefore only schedules work back onto that thread's CFRunLoop; the
        // host's pump loop (CFRunLoopRunInMode) executes it on the JS thread.
        let contextBox = JSContextBox(context)
        // currentRunLoopBox keeps the CFRunLoopGetCurrent() call out of the detached task's
        // @Sendable region (the region-based isolation checker rejects the raw CF type there).
        let runLoopBox = currentRunLoopBox()

        let nativeFetchBlock: @convention(block) (String, JSValue, JSValue, JSValue) -> Void = { urlString, options, resolve, reject in
            guard let url = URL(string: urlString) else {
                reject.call(withArguments: [Self.jsError("Invalid URL: \(urlString)", in: context)])
                return
            }
            let request = Self.makeURLRequest(url: url, options: options)
            let resolveBox = JSValueBox(resolve)
            let rejectBox = JSValueBox(reject)
            session.dataTask(with: request) { data, response, error in
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let errorMessage = error.map { "Fetch failed: \($0.localizedDescription)" }
                CFRunLoopPerformBlock(runLoopBox.runLoop, CFRunLoopMode.defaultMode.rawValue) {
                    if let errorMessage {
                        rejectBox.value.call(withArguments: [Self.jsError(errorMessage, in: contextBox.context)])
                    } else {
                        resolveBox.value.call(withArguments: [Self.fetchResponse(status: status, body: body, context: contextBox.context)])
                    }
                }
                CFRunLoopWakeUp(runLoopBox.runLoop)
            }.resume()
        }
        openclip.setObject(nativeFetchBlock, forKeyedSubscript: "__nativeFetch" as NSString)
    }

    /// Builds a URLRequest from `fetch(url, options)`: method (default GET), optional headers
    /// object, and an optional string body (JSON bodies via `JSON.stringify`).
    private static func makeURLRequest(url: URL, options: JSValue) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = Constants.scriptTimeout

        let methodValue = options.objectForKeyedSubscript("method")
        if let methodValue, !methodValue.isUndefined, !methodValue.isNull {
            if let method = methodValue.toString(), !method.isEmpty {
                request.httpMethod = method.uppercased()
            }
        } else {
            request.httpMethod = "GET"
        }

        if let headersValue = options.objectForKeyedSubscript("headers"),
           headersValue.isObject,
           let headers = headersValue.toDictionary() {
            for (key, value) in headers {
                if let name = key as? String, let headerValue = value as? String {
                    request.setValue(headerValue, forHTTPHeaderField: name)
                }
            }
        }

        if let bodyValue = options.objectForKeyedSubscript("body"),
           !bodyValue.isUndefined, !bodyValue.isNull,
           let body = bodyValue.toString(), !body.isEmpty {
            request.httpBody = body.data(using: .utf8)
        }
        return request
    }

    /// Builds the JS response object: `{ status, ok, text(), json() }`.
    private static func fetchResponse(status: Int, body: String, context: JSContext) -> JSValue {
        let response = JSValue(newObjectIn: context)!
        response.setObject(status, forKeyedSubscript: "status")
        response.setObject(status >= 200 && status < 300, forKeyedSubscript: "ok")

        let textBlock: @convention(block) () -> String = { body }
        response.setObject(textBlock, forKeyedSubscript: "text")

        // The json block escapes into JS, so it captures the context through a Sendable box rather
        // than the raw non-Sendable JSContext (the region-based isolation checker rejects the direct
        // capture inside a Task.detached region).
        let contextBox = JSContextBox(context)
        let jsonBlock: @convention(block) () -> Any = {
            if let data = body.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) {
                return object
            }
            contextBox.context.exception = jsError("Invalid JSON response", in: contextBox.context)
            return NSNull()
        }
        response.setObject(jsonBlock, forKeyedSubscript: "json")
        return response
    }

    /// Creates a JS `Error` value (falls back to a plain object if the Error constructor is gone).
    private static func jsError(_ message: String, in context: JSContext) -> JSValue {
        if let errorConstructor = context.objectForKeyedSubscript("Error"),
           !errorConstructor.isUndefined, !errorConstructor.isNull {
            return errorConstructor.call(withArguments: [message])
        }
        return JSValue(object: ["message": message], in: context)!
    }

    /// True when a JS result is a promise-like (has a `then` function) that cannot be awaited in
    /// legacy synchronous mode.
    private static func isPromiseLike(_ value: JSValue) -> Bool {
        guard value.isObject, let then = value.objectForKeyedSubscript("then") else { return false }
        return !then.isUndefined && !then.isNull && then.isObject
    }

    private static let fetchPolyfillScript = """
    openclip.fetch = function(url, options) {
        return new Promise(function(resolve, reject) {
            openclip.__nativeFetch(String(url), options || {}, resolve, reject);
        });
    };
    """

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
            raw = .showContent(content)
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
        case .runShortcut(let name): return .runShortcut(name: name, input: input)
        case .notify(let title, let body): return .notify(title: title, body: body)
        }
    }

    private static func optionValues(for request: Request) -> [String: String] {
        var values: [String: String] = [:]
        for option in request.options {
            values[option.identifier] = request.optionStore.stringValue(actionID: request.actionID, option: option)
        }
        return values
    }

    private static func makeOpenClipObject(
        in jsContext: JSContext,
        text: String,
        matchedText: String,
        captures: [String],
        sourceApp: AppIdentity,
        options: [String: String]
    ) -> JSValue {
        let openclip = JSValue(newObjectIn: jsContext)!

        let input = JSValue(newObjectIn: jsContext)!
        input.setObject(text, forKeyedSubscript: "text")
        input.setObject(matchedText, forKeyedSubscript: "matchedText")
        input.setObject(captures, forKeyedSubscript: "captures")

        let app = JSValue(newObjectIn: jsContext)!
        app.setObject(sourceApp.bundleIdentifier ?? "", forKeyedSubscript: "bundleID")
        app.setObject(sourceApp.localizedName ?? "", forKeyedSubscript: "name")
        input.setObject(app, forKeyedSubscript: "app")

        openclip.setObject(input, forKeyedSubscript: "input")
        openclip.setObject(options, forKeyedSubscript: "options")
        return openclip
    }

    // MARK: - JS value parsing

    private static func mapModifiers(_ modifiers: NSArray) -> [KeyPressSpec.KeyModifier] {
        modifiers.compactMap { element in
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

    private static func mapStatusStyle(_ raw: String) -> StatusFeedback.Style {
        switch raw.lowercased() {
        case "success": return .success
        case "error": return .error
        case "info": return .info
        default: return .info
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

    private static func parseContent(_ value: JSValue) -> PopupContent {
        guard value.isObject else { return PopupContent() }
        let title = stringValue(value.objectForKeyedSubscript("title"))
        let icon = stringValue(value.objectForKeyedSubscript("icon"))
        let subtitle = stringValue(value.objectForKeyedSubscript("subtitle"))
        let body = stringValue(value.objectForKeyedSubscript("body"))

        var emphasis: ContentEmphasis = .result
        if let raw = stringValue(value.objectForKeyedSubscript("emphasis")) {
            switch raw.lowercased() {
            case "info": emphasis = .info
            case "menu": emphasis = .menu
            default: emphasis = .result
            }
        }

        var rows: [ContentRow] = []
        if let rowsValue = value.objectForKeyedSubscript("rows"), rowsValue.isArray {
            let array = rowsValue.toArray() ?? []
            for element in array {
                guard let row = element as? [String: Any],
                      let type = row["type"] as? String, type == "text",
                      let text = row["value"] as? String else { continue }
                rows.append(.text(text))
            }
        }
        if rows.isEmpty, let body, !body.isEmpty {
            rows = [.text(body)]
        }

        var footer: [ContentOption] = []
        if let footerValue = value.objectForKeyedSubscript("footer"), footerValue.isArray {
            for element in footerValue.toArray() ?? [] {
                if let preset = element as? String {
                    switch preset.lowercased() {
                    case "paste":
                        footer.append(ContentOption(title: "Paste", icon: "arrow.triangle.2.circlepath", outcome: .perform(.paste(body ?? ""))))
                    case "copy":
                        footer.append(ContentOption(title: "Copy", icon: "doc.on.doc", outcome: .perform(.copy(body ?? ""))))
                    default:
                        break
                    }
                } else if let object = element as? [String: Any] {
                    let optionTitle = object["title"] as? String ?? ""
                    let optionIcon = object["icon"] as? String
                    let action = (object["action"] as? String)?.lowercased()
                    let optionValue = object["value"] as? String ?? body ?? ""
                    switch action {
                    case "paste":
                        footer.append(ContentOption(title: optionTitle, icon: optionIcon, outcome: .perform(.paste(optionValue))))
                    case "copy":
                        footer.append(ContentOption(title: optionTitle, icon: optionIcon, outcome: .perform(.copy(optionValue))))
                    default:
                        break
                    }
                }
            }
        }

        return PopupContent(title: title, icon: icon, subtitle: subtitle, rows: rows, footer: footer, emphasis: emphasis)
    }

    /// Captures the calling thread's CFRunLoop in a Sendable box. Kept as a helper so the raw CF
    /// value never appears inside a @Sendable closure body.
    private static func currentRunLoopBox() -> RunLoopBox {
        RunLoopBox(CFRunLoopGetCurrent())
    }

    // MARK: - Watchdog + threading helpers

    private static func timeoutError(_ seconds: TimeInterval) -> NSError {
        NSError(domain: Constants.actionErrorDomain,
                code: Int(Constants.actionErrorCode) + 1,
                userInfo: [NSLocalizedDescriptionKey: "Script timed out after \(Int(seconds)) seconds"])
    }
}

/// Thread-safe flag set by the watchdog when the execution budget is exceeded (mirrors the
/// TimeoutFlag pattern in ShellProcessRunner).
private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var timedOut = false

    func markTimedOut() {
        lock.lock()
        defer { lock.unlock() }
        timedOut = true
    }

    var isTimedOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return timedOut
    }
}

/// Boxes the JS context so the fetch completion handler can hand it back to the JS thread's
/// runloop. The context is only ever *used* on the JS thread.
private final class JSContextBox: @unchecked Sendable {
    let context: JSContext
    init(_ context: JSContext) { self.context = context }
}

/// Boxes a JSValue so a `@Sendable` URLSession completion can hand it back to the JS thread's
/// runloop without the compiler rejecting a non-Sendable capture. The value is only ever *used* on
/// the JS thread (inside the CFRunLoopPerformBlock).
private final class JSValueBox: @unchecked Sendable {
    let value: JSValue
    init(_ value: JSValue) { self.value = value }
}

private final class RunLoopBox: @unchecked Sendable {
    let runLoop: CFRunLoop
    init(_ runLoop: CFRunLoop) { self.runLoop = runLoop }
}

/// Mutable evaluation state written by the JS effect blocks and read back on the host thread. Boxed
/// so the `@convention(block)` closures capture a Sendable reference instead of a non-Sendable local
/// `var` — the region-based isolation checker rejects the direct capture inside a `Task.detached`
/// region.
private final class CollectedBox: @unchecked Sendable {
    var value: OpenClipJSHost.Collected
    init() { self.value = OpenClipJSHost.Collected() }
}

/// Call-ordered side effects collected from the JS effect blocks (mirrors CollectedBox rationale).
private final class EffectsBox: @unchecked Sendable {
    var value: [OpenClipJSHost.Effect]
    init() { self.value = [] }
}

/// Settled by the promise bridge on the JS thread (via `openclip.__resolve`/`__reject`) and read by
/// the host's pump loop on that same thread.
private final class PromiseState: @unchecked Sendable {
    private(set) var isSettled = false
    private(set) var resolvedValue: JSValue?
    private(set) var rejectedValue: JSValue?

    func resolve(_ value: JSValue) {
        resolvedValue = value
        isSettled = true
    }

    func reject(_ error: JSValue) {
        rejectedValue = error
        isSettled = true
    }
}
