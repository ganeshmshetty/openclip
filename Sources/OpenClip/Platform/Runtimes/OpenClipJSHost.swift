// OpenClipJSHost.swift
// OpenClip
//
// Testable JavaScriptCore bridge for JS extensions: runs one script per call and resolves its
// effects into a raw ActionResult. JS exceptions become `.toast(.error)`.
// Threading: each run is a Task.detached on a background thread. JSContext is not thread-safe, so
// all VM access stays on that thread; URLSession callbacks hop back onto its CFRunLoop so promise
// settlement runs there too. Async extensions pump that runloop until their promise settles.
import Foundation
import JavaScriptCore
import Core
import AppKit

/// Stateless facade over a URLSession, one JS run per call. `@unchecked Sendable`: only `let session`
/// is shared; evaluation state lives in locals.
public final class OpenClipJSHost: @unchecked Sendable {
    public struct PasteboardContent: Sendable {
        public let text: String
        public let html: String
        public let rtf: String
        public let hasContent: Bool
        public let hasHtml: Bool
        public let hasRtf: Bool
        public let types: [String]

        public init(
            text: String = "",
            html: String = "",
            rtf: String = "",
            hasContent: Bool = false,
            hasHtml: Bool = false,
            hasRtf: Bool = false,
            types: [String] = []
        ) {
            self.text = text
            self.html = html
            self.rtf = rtf
            self.hasContent = hasContent
            self.hasHtml = hasHtml
            self.hasRtf = hasRtf
            self.types = types
        }

        public static func read(from pasteboard: NSPasteboard = .general) -> PasteboardContent {
            guard let items = pasteboard.pasteboardItems, let firstItem = items.first else {
                return PasteboardContent()
            }

            let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
            let onePasswordType = NSPasteboard.PasteboardType("com.agilebits.onepassword")
            let isConcealed = firstItem.types.contains(concealedType) || firstItem.types.contains(onePasswordType)

            if isConcealed {
                return PasteboardContent(types: firstItem.types.map(\.rawValue))
            }

            let text = pasteboard.string(forType: .string) ?? ""
            let html = pasteboard.string(forType: .html) ?? ""
            let rtf = pasteboard.string(forType: .rtf) ?? ""
            let types = firstItem.types.map(\.rawValue)

            let hasContent = !text.isEmpty || !html.isEmpty || !rtf.isEmpty
            return PasteboardContent(
                text: text,
                html: html,
                rtf: rtf,
                hasContent: hasContent,
                hasHtml: !html.isEmpty,
                hasRtf: !rtf.isEmpty,
                types: types
            )
        }
    }

    public struct Request: Sendable {
        public var actionID: String
        public var scriptCode: String
        public var context: ActionContext
        public var options: [ExtensionOption]
        public var optionStore: any ActionOptionReading
        public var rules: ExtensionActionRules
        /// Awaits the action's promise and enables fetch. False uses legacy synchronous evaluation.
        public var isAsync: Bool
        /// Watchdog budget; nil runs with no timer.
        public var timeout: TimeInterval?
        /// Enables module mode (`require`). Nil keeps the single-file behavior.
        public var packageDirectory: URL?
        /// Defaults to packageDirectory when nil.
        public var entryDirectory: URL?
        /// Pre-captured pasteboard content; injectable for tests.
        public var pasteboardContent: PasteboardContent?

        public init(
            actionID: String,
            scriptCode: String,
            context: ActionContext,
            options: [ExtensionOption],
            optionStore: any ActionOptionReading,
            rules: ExtensionActionRules,
            isAsync: Bool = false,
            timeout: TimeInterval? = nil,
            packageDirectory: URL? = nil,
            entryDirectory: URL? = nil,
            pasteboardContent: PasteboardContent? = nil
        ) {
            self.actionID = actionID
            self.scriptCode = scriptCode
            self.context = context
            self.options = options
            self.optionStore = optionStore
            self.rules = rules
            self.isAsync = isAsync
            self.timeout = timeout
            self.packageDirectory = packageDirectory
            self.entryDirectory = entryDirectory
            self.pasteboardContent = pasteboardContent
        }
    }

    public struct Collected: Sendable {
        public var openURL: URL?
        public var paste: String?
        public var copy: String?
        public var pasteContent: RichPasteboardPayload?
        public var copyContent: RichPasteboardPayload?
        public var cut: String?
        public var toast: StatusFeedback?
        public var configuration: ConfigurationRequest?
        public var keyPress: KeyPressSpec?
        public var shortcutName: String?
        public var notification: (title: String, body: String)?
        public var shareService: (identifier: String, text: String)?
        public var file: FileOutputPayload?
        public var copyFile: URL?
        public var saveFile: URL?
        public var returnValue: String?

        public init() {}
    }

    /// One side-effecting JS call, kept in call order for `.sequence` resolution.
    enum Effect: Sendable {
        case paste(String)
        case copy(String)
        case pasteContent(RichPasteboardPayload)
        case copyContent(RichPasteboardPayload)
        case cut(String)
        case openURL(URL)
        case file(FileOutputPayload)
        case copyFile(URL)
        case saveFile(URL)
        case keyPress(KeyPressSpec)
        case runShortcut(name: String, input: String?)
        case notify(title: String, body: String)
        case shareService(identifier: String, text: String)
        case toast(StatusFeedback)
    }

    /// One JS evaluation's effects, exception and awaited value; crosses the detached-task boundary.
    private struct EvaluationResult: Sendable {
        let collected: Collected
        let effects: [Effect]
        let exceptionMessage: String?
        let asyncReturnValue: String?
    }

    /// Fetch polyfill session; injected for URLProtocol mocks in tests.
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func run(_ request: Request) async throws -> ActionResult {
        let session = self.session

        // Every run enters the gate, since async scripts also run synchronously first.
        let gate = OpenClipJSHost.syncEvaluationGate
        guard gate.tryEnter() else {
            Log.js.error("Refusing JS evaluation for action \(request.actionID, privacy: .public): \(gate.inFlightCount) in-flight sync evaluations at cap")
            throw NSError(
                domain: Constants.actionErrorDomain,
                code: Int(Constants.actionErrorCode) + 2,
                userInfo: [NSLocalizedDescriptionKey: "Too many in-flight script evaluations; another script may be stuck."]
            )
        }

        let cancellationFlag = CancellationFlag()
        let fetchTasks = FetchTaskBox()

        // Use the explicit type name, not `Self`: `Self.X` in a Task.detached closure trips a Swift 6 isolation checker bug.
        return try await withTaskCancellationHandler {
            try await Task.detached {
                defer { gate.leave() }
                // End the evaluation on this thread before the thread returns to the pool.
                defer { fetchTasks.finish() }
                return try OpenClipJSHost.execute(
                    request,
                    session: session,
                    cancellationFlag: cancellationFlag,
                    fetchTasks: fetchTasks
                )
            }.value
        } onCancel: {
            cancellationFlag.markCancelled()
            fetchTasks.cancelAll()
        }
    }

    // MARK: - JS evaluation

    /// Runs on the detached task's thread.
    private static func execute(
        _ request: Request,
        session: URLSession,
        cancellationFlag: CancellationFlag,
        fetchTasks: FetchTaskBox
    ) throws -> ActionResult {
        let evaluation = try evaluate(
            request,
            session: session,
            cancellationFlag: cancellationFlag,
            fetchTasks: fetchTasks
        )
        return makeActionResult(evaluation, request: request)
    }

    private static func evaluate(
        _ request: Request,
        session: URLSession,
        cancellationFlag: CancellationFlag,
        fetchTasks: FetchTaskBox
    ) throws -> EvaluationResult {
        let text = request.context.selection.text
        let matchedText = request.context.match?.matchedText ?? text
        let captures = request.context.match?.captures ?? []

        let timeoutFlag = TimeoutFlag()
        let timeoutSeconds = max(0.001, request.timeout ?? 0)

        guard let jsContext = JSContext() else {
            throw NSError(domain: Constants.actionErrorDomain,
                          code: Constants.actionErrorCode,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create JavaScript context"])
        }

        // With a budget, the VM limit goes in before any script runs so runaway sync code is
        // interrupted inside JSC, and a watchdog bounds idle async promises.
        let executionLimit: JSExecutionTimeLimit?
        let watchdog: Task<Void, Never>?
        if request.timeout != nil {
            executionLimit = JSExecutionTimeLimit(
                context: jsContext,
                timeout: timeoutSeconds,
                timeoutFlag: timeoutFlag
            )
            watchdog = Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                timeoutFlag.markTimedOut()
            }
        } else {
            executionLimit = nil
            watchdog = nil
        }
        defer {
            executionLimit?.clear()
            watchdog?.cancel()
        }

        let collected = CollectedBox()
        let effects = EffectsBox()
        let promiseState = request.isAsync ? PromiseState() : nil
        // Drop settled JSValues on the JS thread so the context can deallocate there (issue #47).
        defer { promiseState?.clear() }

        // Assign context.exception ourselves (JSContext skips it when a handler is set), and reject
        // the promise so an escaped throw ends the pump early.
        jsContext.exceptionHandler = { [promiseState] context, exception in
            guard let exception else { return }
            context?.exception = exception
            promiseState?.reject(exception)
        }
        defer { jsContext.exceptionHandler = nil }

        // Scripts need a global `console` before they run, or a ReferenceError breaks the action.
        installConsoleShim(in: jsContext, actionID: request.actionID)

        // Options are a plain dictionary; `option(id)` reads the same dictionary.
        let optionsDict = optionValues(for: request)
        let pbContent = request.pasteboardContent ?? PasteboardContent.read()
        guard let openclip = makeOpenClipObject(
            in: jsContext,
            text: text,
            html: request.context.selection.html,
            rtf: request.context.selection.rtf,
            matchedText: matchedText,
            captures: captures,
            detected: request.context.selection.detectedContent(for: request.rules.requirements?.content ?? []),
            sourceApp: request.context.selection.sourceApp,
            isSecondaryClick: request.context.isSecondaryClick,
            options: optionsDict,
            pasteboardContent: pbContent
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
        let pasteContentBlock: @convention(block) (JSValue?) -> Void = { value in
            guard let payload = Self.parseRichPayload(value) else { return }
            collected.value.pasteContent = payload
            effects.value.append(.pasteContent(payload))
        }
        let copyContentBlock: @convention(block) (JSValue?) -> Void = { value in
            guard let payload = Self.parseRichPayload(value) else { return }
            collected.value.copyContent = payload
            effects.value.append(.copyContent(payload))
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
        let toastBlock: @convention(block) (String, String?, JSValue?) -> Void = { message, style, options in
            let keepVisible: Bool
            if let options, !options.isUndefined, !options.isNull {
                keepVisible = options.objectForKeyedSubscript("keepVisible")?.toBool() ?? false
            } else {
                keepVisible = false
            }
            collected.value.toast = StatusFeedback(message: message, style: Self.mapToastStyle(style ?? "info"), keepVisible: keepVisible)
        }
        let requireConfigurationBlock: @convention(block) (JSValue) -> Void = { value in
            collected.value.configuration = Self.parseConfiguration(value, actionID: request.actionID)
        }
        let fileBlock: @convention(block) (JSValue, JSValue?) -> Void = { inputVal, optsVal in
            guard let payload = Self.parseFilePayload(inputVal, options: optsVal) else {
                effects.value.append(.toast(StatusFeedback(message: String(localized: "File not found"), style: .error)))
                return
            }
            let action = Self.parseFileAction(inputVal, options: optsVal)
            switch action {
            case "copy", "copyfile":
                collected.value.copyFile = payload.url
                effects.value.append(.copyFile(payload.url))
            case "save", "savefile":
                collected.value.saveFile = payload.url
                effects.value.append(.saveFile(payload.url))
            default:
                collected.value.file = payload
                effects.value.append(.file(payload))
            }
        }
        let copyFileBlock: @convention(block) (JSValue) -> Void = { inputVal in
            if let url = Self.parseURLFromJS(inputVal) {
                collected.value.copyFile = url
                effects.value.append(.copyFile(url))
            } else {
                effects.value.append(.toast(StatusFeedback(message: String(localized: "File not found"), style: .error)))
            }
        }
        let saveFileBlock: @convention(block) (JSValue) -> Void = { inputVal in
            if let url = Self.parseURLFromJS(inputVal) {
                collected.value.saveFile = url
                effects.value.append(.saveFile(url))
            } else {
                effects.value.append(.toast(StatusFeedback(message: String(localized: "File not found"), style: .error)))
            }
        }

        openclip.setObject(pasteBlock, forKeyedSubscript: "paste" as NSString)
        openclip.setObject(copyBlock, forKeyedSubscript: "copy" as NSString)
        openclip.setObject(pasteContentBlock, forKeyedSubscript: "pasteContent" as NSString)
        openclip.setObject(copyContentBlock, forKeyedSubscript: "copyContent" as NSString)
        openclip.setObject(cutBlock, forKeyedSubscript: "cut" as NSString)
        openclip.setObject(openURLBlock, forKeyedSubscript: "openURL" as NSString)
        openclip.setObject(fileBlock, forKeyedSubscript: "file" as NSString)
        openclip.setObject(copyFileBlock, forKeyedSubscript: "copyFile" as NSString)
        openclip.setObject(saveFileBlock, forKeyedSubscript: "saveFile" as NSString)
        openclip.setObject(keyPressBlock, forKeyedSubscript: "keyPress" as NSString)
        openclip.setObject(runShortcutBlock, forKeyedSubscript: "runShortcut" as NSString)
        openclip.setObject(notifyBlock, forKeyedSubscript: "notify" as NSString)
        openclip.setObject(shareServiceBlock, forKeyedSubscript: "shareService" as NSString)
        openclip.setObject(toastBlock, forKeyedSubscript: "toast" as NSString)
        openclip.setObject(requireConfigurationBlock, forKeyedSubscript: "requireConfiguration" as NSString)

        // Module mode: the prelude's require calls `openclip.__resolveModule`, resolved host-side by OpenClipModuleLoader.
        if let packageDirectory = request.packageDirectory {
            let resolveModuleBlock: @convention(block) (String, String) -> [String: Any] = { dirString, specifier in
                let requiringDirectory = URL(fileURLWithPath: dirString, isDirectory: true)
                do {
                    let resolved = try OpenClipModuleLoader.load(
                        specifier: specifier,
                        requiringDirectory: requiringDirectory,
                        packageRoot: packageDirectory
                    )
                    return [
                        "ok": true,
                        "path": resolved.url.path,
                        "dir": resolved.directoryURL.path,
                        "source": resolved.source
                    ]
                } catch let error as ModuleResolutionError {
                    return ["ok": false, "message": error.message]
                } catch {
                    return ["ok": false, "message": (error as NSError).localizedDescription]
                }
            }
            openclip.setObject(resolveModuleBlock, forKeyedSubscript: "__resolveModule" as NSString)
        }

        jsContext.setObject(openclip, forKeyedSubscript: "openclip" as NSString)
        // Detection is a snapshot owned by the host, including nested date/address objects.
        jsContext.evaluateScript("""
        (function() {
            function freeze(value) {
                if (value && typeof value === 'object') {
                    Object.keys(value).forEach(function(key) { freeze(value[key]); });
                    Object.freeze(value);
                }
            }
            freeze(openclip.input.detected);
            Object.defineProperty(openclip.input, 'detected', {
                value: openclip.input.detected, writable: false, configurable: false, enumerable: true
            });
        })();
        """)
        installPasteboardBridge(in: jsContext)
        jsContext.evaluateScript("openclip.option = function(id) { return openclip.options[id]; }")
        jsContext.evaluateScript("openclip.i18n = function(dict) { if (!dict) return ''; var baseLang = (openclip.language || '').split('-')[0]; return dict[openclip.language] || dict[openclip.locale] || dict[baseLang] || dict['en'] || Object.values(dict)[0] || ''; }")
        let asyncResolvers: FetchResolvers?
        if request.isAsync, let promiseState {
            asyncResolvers = registerAsyncBridge(
                openclip: openclip,
                context: jsContext,
                promiseState: promiseState,
                session: session,
                fetchTasks: fetchTasks
            )
        } else {
            asyncResolvers = nil
        }
        // Cancelled or late fetches never `take` their resolvers; drop them on the JS thread (issue #47).
        defer { asyncResolvers?.clearPending() }

        let wrappedScript: String
        if let packageDirectory = request.packageDirectory {
            let entryDir = request.entryDirectory ?? packageDirectory
            wrappedScript = request.isAsync
                ? asyncModuleWrappedScript(request.scriptCode, entryDirectory: entryDir.path)
                : syncModuleWrappedScript(request.scriptCode, entryDirectory: entryDir.path)
        } else {
            wrappedScript = request.isAsync ? asyncWrappedScript(request.scriptCode) : syncWrappedScript(request.scriptCode)
        }
        let jsResult = jsContext.evaluateScript(wrappedScript)

        if cancellationFlag.isCancelled {
            fetchTasks.cancelAll()
            throw CancellationError()
        }

        if timeoutFlag.isTimedOut {
            fetchTasks.cancelAll()
            throw timeoutError(timeoutSeconds)
        }

        if let exception = jsContext.exception {
            return EvaluationResult(collected: collected.value, effects: effects.value, exceptionMessage: exception.toString() ?? "JavaScript exception", asyncReturnValue: nil)
        }

        // Async: pump the runloop until the promise settles or the watchdog fires.
        if request.isAsync, let promiseState {
            while !promiseState.isSettled {
                if cancellationFlag.isCancelled {
                    fetchTasks.cancelAll()
                    throw CancellationError()
                }
                if timeoutFlag.isTimedOut {
                    fetchTasks.cancelAll()
                    throw timeoutError(timeoutSeconds)
                }
                CFRunLoopRunInMode(.defaultMode, 0.05, true)
            }
            if let exception = jsContext.exception {
                return EvaluationResult(collected: collected.value, effects: effects.value, exceptionMessage: exception.toString() ?? "JavaScript exception", asyncReturnValue: nil)
            }
            if let rejected = promiseState.rejectedValue {
                let message = rejected.toString() ?? "JavaScript promise rejected"
                return EvaluationResult(collected: collected.value, effects: effects.value, exceptionMessage: message, asyncReturnValue: nil)
            }
            if let resolvedVal = promiseState.resolvedValue, resolvedVal.isObject {
                if let typeVal = resolvedVal.objectForKeyedSubscript("type"), typeVal.isString {
                    let typeStr = (typeVal.toString() ?? "").lowercased()
                    if typeStr == "file" || typeStr == "copyfile" || typeStr == "savefile" {
                        if effects.value.isEmpty {
                            if let payload = parseFilePayload(resolvedVal, options: nil) {
                                let fileAction = parseFileAction(resolvedVal, options: nil)
                                if typeStr == "copyfile" || fileAction == "copy" || fileAction == "copyfile" {
                                    effects.value.append(.copyFile(payload.url))
                                } else if typeStr == "savefile" || fileAction == "save" || fileAction == "savefile" {
                                    effects.value.append(.saveFile(payload.url))
                                } else {
                                    effects.value.append(.file(payload))
                                }
                            } else {
                                effects.value.append(.toast(StatusFeedback(message: String(localized: "File not found"), style: .error)))
                            }
                        }
                    }
                }
            }
            // Plain objects stringify to "[object Object]" and are dropped.
            let resolved = promiseState.resolvedValue.flatMap { (value: JSValue) -> String? in
                let string = value.toString() ?? ""
                return (string.isEmpty || string == "undefined" || string == "null" || string == "[object Object]") ? nil : string
            }
            return EvaluationResult(collected: collected.value, effects: effects.value, exceptionMessage: nil, asyncReturnValue: resolved)
        }

        // Legacy sync mode cannot await a promise-like return, so it is ignored.
        if let result = jsResult, !isPromiseLike(result) {
            var fileType: String?
            if result.isObject, let typeVal = result.objectForKeyedSubscript("type"), typeVal.isString {
                fileType = (typeVal.toString() ?? "").lowercased()
            }
            if let typeStr = fileType, typeStr == "file" || typeStr == "copyfile" || typeStr == "savefile" {
                if effects.value.isEmpty {
                    if let payload = parseFilePayload(result, options: nil) {
                        let fileAction = parseFileAction(result, options: nil)
                        if typeStr == "copyfile" || fileAction == "copy" || fileAction == "copyfile" {
                            effects.value.append(.copyFile(payload.url))
                        } else if typeStr == "savefile" || fileAction == "save" || fileAction == "savefile" {
                            effects.value.append(.saveFile(payload.url))
                        } else {
                            effects.value.append(.file(payload))
                        }
                    } else {
                        effects.value.append(.toast(StatusFeedback(message: String(localized: "File not found"), style: .error)))
                    }
                }
            } else if let resultString = result.toString(), resultString != "undefined", resultString != "null", resultString != "[object Object]" {
                collected.value.returnValue = resultString
            }
        }
        return EvaluationResult(collected: collected.value, effects: effects.value, exceptionMessage: nil, asyncReturnValue: nil)
    }

    // MARK: - Async bridge (fetch polyfill + promise settling)

    /// Registers promise settlement hooks and the URLSession-backed fetch polyfill. `openclip` must already exist.
    @discardableResult
    private static func registerAsyncBridge(
        openclip: JSValue,
        context: JSContext,
        promiseState: PromiseState,
        session: URLSession,
        fetchTasks: FetchTaskBox
    ) -> FetchResolvers? {
        let resolveBlock: @convention(block) (JSValue) -> Void = { value in
            promiseState.resolve(value)
        }
        let rejectBlock: @convention(block) (JSValue) -> Void = { error in
            promiseState.reject(error)
        }
        openclip.setObject(resolveBlock, forKeyedSubscript: "__resolve" as NSString)
        openclip.setObject(rejectBlock, forKeyedSubscript: "__reject" as NSString)

        return JSNativeFetch.installNativeFetch(in: context, session: session, fetchTasks: fetchTasks)
    }

    /// True when a JS result has a `then` function.
    private static func isPromiseLike(_ value: JSValue) -> Bool {
        guard value.isObject, let then = value.objectForKeyedSubscript("then") else { return false }
        return !then.isUndefined && !then.isNull && then.isObject
    }

    // MARK: - Console shim

    /// Global `console.log` routed to Log.js. Arguments are redacted to type, length and keys so no clipboard or extension data is logged.
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

    /// Installs getters and setters on `openclip.pasteboard` for reactive read/write access.
    private static func installPasteboardBridge(in context: JSContext) {
        context.evaluateScript("""
        (function() {
            var _pb = openclip.pasteboard;
            if (!_pb) return;
            var _text = _pb.text;
            var _html = _pb.html;
            var _rtf = _pb.rtf;

            Object.defineProperty(openclip.pasteboard, 'text', {
                get: function() { return _text; },
                set: function(v) {
                    _text = (v === null || v === undefined) ? "" : String(v);
                    openclip.copy(_text);
                },
                configurable: true,
                enumerable: true
            });

            Object.defineProperty(openclip.pasteboard, 'html', {
                get: function() { return _html; },
                set: function(v) {
                    _html = (v === null || v === undefined) ? "" : String(v);
                    openclip.copyContent({ html: _html });
                },
                configurable: true,
                enumerable: true
            });

            Object.defineProperty(openclip.pasteboard, 'rtf', {
                get: function() { return _rtf; },
                set: function(v) {
                    _rtf = (v === null || v === undefined) ? "" : String(v);
                    openclip.copyContent({ rtf: _rtf });
                },
                configurable: true,
                enumerable: true
            });

            Object.defineProperty(openclip.pasteboard, 'content', {
                get: function() {
                    return {
                        'public.utf8-plain-text': _text,
                        'public.html': _html,
                        'public.rtf': _rtf
                    };
                },
                set: function(v) {
                    if (v && typeof v === 'object') {
                        if (v['public.utf8-plain-text'] !== undefined) _text = String(v['public.utf8-plain-text']);
                        else if (v.text !== undefined) _text = String(v.text);
                        else if (v.plainText !== undefined) _text = String(v.plainText);

                        if (v['public.html'] !== undefined) _html = String(v['public.html']);
                        else if (v.html !== undefined) _html = String(v.html);

                        if (v['public.rtf'] !== undefined) _rtf = String(v['public.rtf']);
                        else if (v.rtf !== undefined) _rtf = String(v.rtf);
                    }
                    openclip.copyContent(v);
                },
                configurable: true,
                enumerable: true
            });
        })();
        """)
    }

    /// Legacy sync wrapper. Its shape is pinned by golden and option-store tests.
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

    /// Async wrapper. Dispatch settles the bridge promise; a script with no entry point still settles.
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

    /// Module-mode sync wrapper: `module.exports` wins, with legacy `action`/`main` as fallback.
    private static func syncModuleWrappedScript(_ scriptCode: String, entryDirectory: String) -> String {
        """
        \(modulePrelude(entryDirectory: entryDirectory))
        var selection = openclip.input.text;
        var options = openclip.options;
        \(scriptCode)
        (function() {
            var __entry;
            if (typeof module.exports === 'function') {
                if (typeof action === 'function' && module.exports !== action && module.exports.name !== 'action') {
                    __entry = action;
                } else {
                    __entry = module.exports;
                }
            } else if (typeof module.exports.action === 'function') {
                __entry = module.exports.action;
            } else if (typeof module.exports.main === 'function') {
                __entry = module.exports.main;
            } else if (typeof action === 'function') {
                __entry = action;
            } else if (typeof main === 'function') {
                __entry = main;
            }
            if (__entry) return __entry(selection, options);
            return null;
        })();
        """
    }

    /// Module-mode async wrapper: same dispatch as the sync variant, settling promise returns.
    private static func asyncModuleWrappedScript(_ scriptCode: String, entryDirectory: String) -> String {
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
        \(modulePrelude(entryDirectory: entryDirectory))
        var selection = openclip.input.text;
        var options = openclip.options;
        \(scriptCode)
        (function() {
            var __entry;
            if (typeof module.exports === 'function') {
                if (typeof action === 'function' && module.exports !== action && module.exports.name !== 'action') {
                    __entry = action;
                } else {
                    __entry = module.exports;
                }
            } else if (typeof module.exports.action === 'function') {
                __entry = module.exports.action;
            } else if (typeof module.exports.main === 'function') {
                __entry = module.exports.main;
            } else if (typeof action === 'function') {
                __entry = action;
            } else if (typeof main === 'function') {
                __entry = main;
            }
            if (__entry) return __openclip_dispatch(__entry, selection, options);
            openclip.__resolve(null);
            return null;
        })();
        """
    }

    /// Per-run module cache (cache-first, so cycles see partial exports) and a Node-style per-directory `require`.
    private static func modulePrelude(entryDirectory: String) -> String {
        let escaped = entryDirectory
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        var __moduleCache = {};
        var __require = function(dir, specifier) {
            var r = openclip.__resolveModule(dir, specifier);
            if (!r.ok) throw new Error(r.message);
            if (__moduleCache[r.path] !== undefined) return __moduleCache[r.path];
            var m = { exports: {} };
            __moduleCache[r.path] = m.exports;
            (new Function('require', 'module', 'exports', '__dirname', r.source))(__require.bind(null, r.dir), m, m.exports, r.dir);
            __moduleCache[r.path] = m.exports;
            return m.exports;
        };
        var require = __require.bind(null, "\(escaped)");
        var module = { exports: {} };
        var exports = module.exports;
        var __dirname = "\(escaped)";
        """
    }

    // MARK: - Effect → ActionResult

    private static func makeActionResult(_ evaluation: EvaluationResult, request: Request) -> ActionResult {
        let collected = evaluation.collected

        // JS exceptions win over partial effects; they are never thrown.
        if let exceptionMessage = evaluation.exceptionMessage {
            return .toast(StatusFeedback(message: exceptionMessage, style: .error))
        }

        // Resolution order: configuration > toast > effects > string return > success.
        let effects = evaluation.effects
        let sourceID = request.context.selection.sourceApp.bundleIdentifier
        let browserID = BrowserDetector.isBrowser(bundleIdentifier: sourceID) ? sourceID : nil
        let raw: ActionResult
        if let configuration = collected.configuration {
            raw = .openConfiguration(configuration)
        } else if let toast = collected.toast {
            if effects.isEmpty {
                raw = .toast(toast)
            } else {
                let input = request.context.match?.matchedText ?? request.context.selection.text
                let mapped = effects.map { effectResult($0, input: input, browserBundleID: browserID) }
                raw = .sequence([.toast(toast)] + mapped)
            }
        } else if !effects.isEmpty {
            let input = request.context.match?.matchedText ?? request.context.selection.text
            let mapped = effects.map { effectResult($0, input: input, browserBundleID: browserID) }
            raw = mapped.count == 1 ? mapped[0] : .sequence(mapped)
        } else if let returnValue = evaluation.asyncReturnValue ?? collected.returnValue {
            // A string naming an existing regular file becomes a file result.
            if let fileResult = ShellResultMapper.detectFileResult(from: returnValue) {
                raw = fileResult
            } else {
                raw = .text(returnValue)
            }
        } else {
            raw = .success
        }

        return raw
    }

    private static func effectResult(_ effect: Effect, input: String, browserBundleID: String?) -> ActionResult {
        switch effect {
        case .paste(let text): return .paste(text)
        case .copy(let text): return .copy(text)
        case .pasteContent(let payload): return .pasteContent(payload)
        case .copyContent(let payload): return .copyContent(payload)
        case .cut(let text): return .cut(text)
        case .openURL(let url):
            if let browserBundleID = BrowserDetector.browserToOpen(url, sourceBundleIdentifier: browserBundleID) {
                return .openURLInApp(url: url, appBundleIdentifier: browserBundleID)
            }
            return .openURL(url)
        case .file(let payload): return .file(payload)
        case .copyFile(let url): return .copyFile(url)
        case .saveFile(let url): return .saveFile(url)
        case .keyPress(let spec): return .keyPress(spec)
        case .runShortcut(let name, let inputOverride): return .runShortcut(name: name, input: inputOverride ?? input)
        case .notify(let title, let body): return .notify(title: title, body: body)
        case .shareService(let identifier, let text): return .shareService(identifier: identifier, text: text)
        case .toast(let feedback): return .toast(feedback)
        }
    }

    private static func parseRichPayload(_ value: JSValue?) -> RichPasteboardPayload? {
        guard let value, value.isObject else { return nil }
        var plainText: String?
        var rtf: String?
        var html: String?

        let plainKeys = ["public.utf8-plain-text", "text", "plainText", "string"]
        for k in plainKeys {
            if let val = value.objectForKeyedSubscript(k), !val.isUndefined && !val.isNull {
                plainText = val.toString()
                break
            }
        }

        let rtfKeys = ["public.rtf", "rtf"]
        for k in rtfKeys {
            if let val = value.objectForKeyedSubscript(k), !val.isUndefined && !val.isNull {
                rtf = val.toString()
                break
            }
        }

        let htmlKeys = ["public.html", "html"]
        for k in htmlKeys {
            if let val = value.objectForKeyedSubscript(k), !val.isUndefined && !val.isNull {
                html = val.toString()
                break
            }
        }

        guard plainText != nil || rtf != nil || html != nil else { return nil }
        return RichPasteboardPayload(plainText: plainText, rtf: rtf, html: html)
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

    /// Builds the read-only `openclip.*` bridge object.
    ///
    /// For secondary (right-click/⇧-click) behavior, branch on `openclip.input.isSecondaryClick` and emit
    /// explicit `openclip.paste`/`copy` effects; manifest `secondary` is rejected for JavaScript.
    private static func makeOpenClipObject(
        in jsContext: JSContext,
        text: String,
        html: String?,
        rtf: String?,
        matchedText: String,
        captures: [String],
        detected: DetectedContent,
        sourceApp: AppIdentity,
        isSecondaryClick: Bool,
        options: [String: Any],
        pasteboardContent: PasteboardContent
    ) -> JSValue? {
        guard let openclip = JSValue(newObjectIn: jsContext),
              let input = JSValue(newObjectIn: jsContext),
              let app = JSValue(newObjectIn: jsContext),
              let pasteboard = JSValue(newObjectIn: jsContext) else {
            return nil
        }

        input.setObject(text, forKeyedSubscript: "text")
        input.setObject(html ?? "", forKeyedSubscript: "html")
        input.setObject(rtf ?? "", forKeyedSubscript: "rtf")
        input.setObject(matchedText, forKeyedSubscript: "matchedText")
        input.setObject(captures, forKeyedSubscript: "captures")
        input.setObject(isSecondaryClick, forKeyedSubscript: "isSecondaryClick")
        let dateFormatter = ISO8601DateFormatter()
        let detectedValues: [String: Any] = [
            "urls": detected.urls, "emails": detected.emails, "paths": detected.paths, "phones": detected.phones,
            "dates": detected.dates.map { item -> [String: Any] in
                var value: [String: Any] = ["text": item.text, "date": dateFormatter.string(from: item.date),
                                            "duration": item.duration]
                if let zone = item.timeZone { value["timeZone"] = zone }
                return value
            },
            "addresses": detected.addresses.map { ["text": $0.text, "components": $0.components] as [String: Any] }
        ]
        input.setObject(detectedValues, forKeyedSubscript: "detected")

        app.setObject(sourceApp.bundleIdentifier ?? "", forKeyedSubscript: "bundleID")
        app.setObject(sourceApp.localizedName ?? "", forKeyedSubscript: "name")
        input.setObject(app, forKeyedSubscript: "app")
        let currentLocale = Locale.current
        let activeTag = currentLocale.identifier
        let langCode = currentLocale.language.languageCode?.identifier ?? "en"
        let scriptCode = currentLocale.language.script?.identifier
        let fullLangTag: String
        if let scriptCode {
            fullLangTag = "\(langCode)-\(scriptCode)"
        } else {
            fullLangTag = langCode
        }

        pasteboard.setObject(pasteboardContent.text, forKeyedSubscript: "text")
        pasteboard.setObject(pasteboardContent.html, forKeyedSubscript: "html")
        pasteboard.setObject(pasteboardContent.rtf, forKeyedSubscript: "rtf")
        pasteboard.setObject(pasteboardContent.hasContent, forKeyedSubscript: "hasContent")
        pasteboard.setObject(pasteboardContent.hasHtml, forKeyedSubscript: "hasHtml")
        pasteboard.setObject(pasteboardContent.hasRtf, forKeyedSubscript: "hasRtf")
        pasteboard.setObject(pasteboardContent.types, forKeyedSubscript: "types")

        openclip.setObject(input, forKeyedSubscript: "input")
        openclip.setObject(options, forKeyedSubscript: "options")
        openclip.setObject(activeTag, forKeyedSubscript: "locale")
        openclip.setObject(fullLangTag, forKeyedSubscript: "language")
        openclip.setObject(pasteboard, forKeyedSubscript: "pasteboard")
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

    private static func parseURLFromJS(_ value: JSValue?) -> URL? {
        guard let value else { return nil }
        if value.isString, let str = stringValue(value) {
            return ShellResultMapper.parseExistingFileURL(from: str)
        }
        if value.isObject {
            if let pathVal = value.objectForKeyedSubscript("path"), !pathVal.isUndefined && !pathVal.isNull, let str = stringValue(pathVal) {
                return ShellResultMapper.parseExistingFileURL(from: str)
            }
            if let urlVal = value.objectForKeyedSubscript("url"), !urlVal.isUndefined && !urlVal.isNull, let str = stringValue(urlVal) {
                return ShellResultMapper.parseExistingFileURL(from: str)
            }
        }
        return nil
    }

    /// `type` is also a file-object discriminator, so only MIME-shaped values count (else "file" becomes `output-.bin`).
    private static func mimeType(from value: JSValue) -> String? {
        if let explicit = stringValue(value.objectForKeyedSubscript("mimeType")) {
            return explicit
        }
        guard let type = stringValue(value.objectForKeyedSubscript("type")), type.contains("/") else {
            return nil
        }
        return type
    }

    private static func parseFilePayload(_ value: JSValue, options: JSValue?) -> FileOutputPayload? {
        var pathStr: String?
        var dataStr: String?
        var filename: String?
        var mimeType: String?

        if value.isString {
            pathStr = stringValue(value)
        } else if value.isObject {
            pathStr = stringValue(value.objectForKeyedSubscript("path")) ?? stringValue(value.objectForKeyedSubscript("url"))
            dataStr = stringValue(value.objectForKeyedSubscript("data"))
            filename = stringValue(value.objectForKeyedSubscript("filename")) ?? stringValue(value.objectForKeyedSubscript("name"))
            mimeType = Self.mimeType(from: value)
        }

        if let options, options.isObject {
            if filename == nil {
                filename = stringValue(options.objectForKeyedSubscript("filename")) ?? stringValue(options.objectForKeyedSubscript("name"))
            }
            if mimeType == nil {
                mimeType = Self.mimeType(from: options)
            }
        }

        if let dataStr, let data = Data(base64Encoded: dataStr) {
            guard let tempURL = ShellResultMapper.writeTemporaryOutput(data: data, filename: filename, mimeType: mimeType) else {
                return nil
            }
            return FileOutputPayload(url: tempURL, filename: filename ?? tempURL.lastPathComponent, mimeType: mimeType, isTemporary: true)
        }

        if let pathStr, let url = ShellResultMapper.parseExistingFileURL(from: pathStr) {
            return FileOutputPayload(url: url, filename: filename ?? url.lastPathComponent, mimeType: mimeType, isTemporary: false)
        }

        return nil
    }

    private static func parseFileAction(_ value: JSValue, options: JSValue?) -> String? {
        if value.isObject, let act = stringValue(value.objectForKeyedSubscript("action")) {
            return act.lowercased()
        }
        if let options, options.isObject, let act = stringValue(options.objectForKeyedSubscript("action")) {
            return act.lowercased()
        }
        return nil
    }

    private static func mapToastStyle(_ raw: String) -> StatusFeedback.Style {
        switch raw.lowercased() {
        case "success": return .success
        case "error": return .error
        case "info": return .info
        default: return .info
        }
    }

    // MARK: - Watchdog + threading helpers

    private static func timeoutError(_ seconds: TimeInterval) -> NSError {
        NSError(domain: Constants.actionErrorDomain,
                code: Int(Constants.actionErrorCode) + 1,
                userInfo: [NSLocalizedDescriptionKey: "Script timed out after \(Int(seconds)) seconds"])
    }

    /// Shared across all host instances.
    static let syncEvaluationGate = SyncEvaluationGate(capacity: Constants.maxConcurrentSyncScriptEvaluations)

    public static var syncEvaluationSlotCount: Int {
        syncEvaluationGate.capacity
    }
}
