// OpenClipJSHost.swift
// OpenClip
//
// Dedicated, testable JavaScriptCore bridge for JS extensions (plan §8, Phase 6). Exposes the full
// read-only `openclip.*` author surface (input/matchedText/captures/app, read-only options, and the
// effect API) and resolves collected effects into a RAW runtime ActionResult via a deterministic
// resolution order — no declarative secondary/delivery translation here (that happens downstream
// via the action's declared `delivery`). JS exceptions surface as
// `.toast(.error, message)` rather than throwing; Swift-level setup failures may throw.
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
import AppKit

/// Stateless facade over a URLSession that executes one JS run per call. `@unchecked Sendable`
/// because it only holds `let session` (URLSession) — all mutable evaluation state lives in locals
/// passed down to `execute`, and JS VM access is confined to the detached task's thread.
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
        /// When true the host awaits the action's promise (and enables the fetch polyfill). When
        /// false, legacy synchronous evaluation is used.
        public var isAsync: Bool
        /// Watchdog budget. Defaults to `Constants.scriptTimeout` when nil (test override).
        public var timeout: TimeInterval?
        /// Extension package directory. When non-nil the host enables the module bridge and wraps
        /// the script in module scaffolding; nil preserves the legacy single-file behavior.
        public var packageDirectory: URL?
        /// The entry script's parent directory. When nil, defaults to packageDirectory.
        public var entryDirectory: URL?
        /// Optional pre-captured pasteboard content (injectable for testing).
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

        let cancellationFlag = CancellationFlag()
        let fetchTasks = FetchTaskBox()

        // Note: reference static members via the explicit type name, not `Self` — `Self.X` inside a
        // Task.detached closure triggers a Swift 6 region-based-isolation checker bug ("pattern that
        // the region-based isolation checker does not understand how to check").
        return try await withTaskCancellationHandler {
            try await Task.detached {
                defer { gate.leave() }
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

    /// Runs the whole evaluation on the calling thread (the detached task's thread). Kept as a thin
    /// nonisolated function so the @Sendable detached closure stays a single call.
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

        // Give scripts a global `console.log` before anything runs, so it routes to Log.js instead
        // of throwing a ReferenceError that breaks the action.
        installConsoleShim(in: jsContext, actionID: request.actionID)

        // Read-only input context. Options are injected as a plain dictionary (values resolved via
        // the option store); `option(id)` is a functional form over the same dictionary.
        let optionsDict = optionValues(for: request)
        let pbContent = request.pasteboardContent ?? PasteboardContent.read()
        guard let openclip = makeOpenClipObject(
            in: jsContext,
            text: text,
            html: request.context.selection.html,
            rtf: request.context.selection.rtf,
            matchedText: matchedText,
            captures: captures,
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

        openclip.setObject(pasteBlock, forKeyedSubscript: "paste" as NSString)
        openclip.setObject(copyBlock, forKeyedSubscript: "copy" as NSString)
        openclip.setObject(pasteContentBlock, forKeyedSubscript: "pasteContent" as NSString)
        openclip.setObject(copyContentBlock, forKeyedSubscript: "copyContent" as NSString)
        openclip.setObject(cutBlock, forKeyedSubscript: "cut" as NSString)
        openclip.setObject(openURLBlock, forKeyedSubscript: "openURL" as NSString)
        openclip.setObject(keyPressBlock, forKeyedSubscript: "keyPress" as NSString)
        openclip.setObject(runShortcutBlock, forKeyedSubscript: "runShortcut" as NSString)
        openclip.setObject(notifyBlock, forKeyedSubscript: "notify" as NSString)
        openclip.setObject(shareServiceBlock, forKeyedSubscript: "shareService" as NSString)
        openclip.setObject(toastBlock, forKeyedSubscript: "toast" as NSString)
        openclip.setObject(requireConfigurationBlock, forKeyedSubscript: "requireConfiguration" as NSString)

        // Module bridge: in module mode (packageDirectory != nil) the wrapper prelude calls
        // `openclip.__resolveModule(dir, specifier)` to resolve a require on the host side via
        // OpenClipModuleLoader, returning `{ ok, path, dir, source }` or `{ ok: false, message }`.
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
        installPasteboardBridge(in: jsContext)
        jsContext.evaluateScript("openclip.option = function(id) { return openclip.options[id]; }")
        jsContext.evaluateScript("openclip.i18n = function(dict) { if (!dict) return ''; var baseLang = (openclip.language || '').split('-')[0]; return dict[openclip.language] || dict[openclip.locale] || dict[baseLang] || dict['en'] || Object.values(dict)[0] || ''; }")
        if request.isAsync, let promiseState {
            registerAsyncBridge(
                openclip: openclip,
                context: jsContext,
                promiseState: promiseState,
                session: session,
                fetchTasks: fetchTasks
            )
        }

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

        // Async path: pump the JS thread's runloop until the promise settles (fetch completions and
        // promise microtasks land here via CFRunLoopPerformBlock) or the watchdog fires.
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
    /// `.toast(.error)` and breaks the action. To prevent leaking sensitive text, clipboard, or
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

    /// Module-mode sync wrapper. The prelude runs at wrapper top level so `module`/`require` are
    /// visible to the entry `scriptCode`; dispatch prefers `module.exports` (function or
    /// `.action`/`.main`) and falls back to in-scope `action`/`main` for legacy single-file scripts.
    private static func syncModuleWrappedScript(_ scriptCode: String, entryDirectory: String) -> String {
        """
        \(modulePrelude(entryDirectory: entryDirectory))
        var selection = openclip.input.text;
        var options = openclip.options;
        \(scriptCode)
        (function() {
            var __entry;
            if (typeof module.exports === 'function') __entry = module.exports;
            else if (typeof module.exports.action === 'function') __entry = module.exports.action;
            else if (typeof module.exports.main === 'function') __entry = module.exports.main;
            else if (typeof action === 'function') __entry = action;
            else if (typeof main === 'function') __entry = main;
            if (__entry) return __entry(selection, options);
            return null;
        })();
        """
    }

    /// Module-mode async wrapper: same prelude/dispatch as the sync variant, but routes the entry
    /// through `__openclip_dispatch` so promise returns settle the bridge promise.
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
            if (typeof module.exports === 'function') __entry = module.exports;
            else if (typeof module.exports.action === 'function') __entry = module.exports.action;
            else if (typeof module.exports.main === 'function') __entry = module.exports.main;
            else if (typeof action === 'function') __entry = action;
            else if (typeof main === 'function') __entry = main;
            if (__entry) return __openclip_dispatch(__entry, selection, options);
            openclip.__resolve(null);
            return null;
        })();
        """
    }

    /// Module scaffolding: per-run cache (cache-first so cycles get partial exports) and a
    /// per-directory `require` bound via `__require.bind(null, dir)` so nested requires resolve
    /// relative to the requiring file (Node semantics). `__dirname` is the entry directory.
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

        // JS exceptions win over any partially-collected effects (do NOT throw for JS exceptions).
        if let exceptionMessage = evaluation.exceptionMessage {
            return .toast(StatusFeedback(message: exceptionMessage, style: .error))
        }

        // Deterministic resolution order: configuration > toast (coexisting with effects) > effects
        // (in call order, sequence when >1) > function string return (.text) > success.
        let effects = evaluation.effects
        let raw: ActionResult
        if let configuration = collected.configuration {
            raw = .openConfiguration(configuration)
        } else if let toast = collected.toast {
            if effects.isEmpty {
                raw = .toast(toast)
            } else {
                let input = request.context.match?.matchedText ?? request.context.selection.text
                let mapped = effects.map { effectResult($0, input: input) }
                raw = .sequence([.toast(toast)] + mapped)
            }
        } else if !effects.isEmpty {
            let input = request.context.match?.matchedText ?? request.context.selection.text
            let mapped = effects.map { effectResult($0, input: input) }
            raw = mapped.count == 1 ? mapped[0] : .sequence(mapped)
        } else if let returnValue = evaluation.asyncReturnValue ?? collected.returnValue {
            // raw = .text(returnValue) — implicitly returned text, governed by the user's per-click preference
            raw = .text(returnValue)
        } else {
            raw = .success
        }

        return raw
    }

    private static func effectResult(_ effect: Effect, input: String) -> ActionResult {
        switch effect {
        case .paste(let text): return .paste(text)
        case .copy(let text): return .copy(text)
        case .pasteContent(let payload): return .pasteContent(payload)
        case .copyContent(let payload): return .copyContent(payload)
        case .cut(let text): return .cut(text)
        case .openURL(let url): return .openURL(url)
        case .keyPress(let spec): return .keyPress(spec)
        case .runShortcut(let name, let inputOverride): return .runShortcut(name: name, input: inputOverride ?? input)
        case .notify(let title, let body): return .notify(title: title, body: body)
        case .shareService(let identifier, let text): return .shareService(identifier: identifier, text: text)
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

    /// Builds the read-only `openclip.*` bridge object: `input` (text/matchedText/captures/app +
    /// isSecondaryClick), a plain `options` dictionary, and the effect API installed by the caller.
    ///
    /// JS authoring of a secondary (right-click/⇧-click) behavior: branch on
    /// `openclip.input.isSecondaryClick` and emit an explicit effect — `openclip.paste(...)` for the
    /// primary path, `openclip.copy(...)` for the secondary — rather than relying on a string-return
    /// convention or a manifest `secondary` (rejected on `javascript` by ManifestValidation).
    private static func makeOpenClipObject(
        in jsContext: JSContext,
        text: String,
        html: String?,
        rtf: String?,
        matchedText: String,
        captures: [String],
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

    /// Maps a JS `toast` style string to a `StatusFeedback.Style`.
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

    /// Bounds in-flight synchronous evaluations across the whole host (all instances).
    static let syncEvaluationGate = SyncEvaluationGate(capacity: Constants.maxConcurrentSyncScriptEvaluations)

    /// Declared slot count for synchronous script evaluation gating.
    public static var syncEvaluationSlotCount: Int {
        syncEvaluationGate.capacity
    }
}

