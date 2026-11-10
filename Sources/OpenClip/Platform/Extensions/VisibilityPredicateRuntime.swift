// VisibilityPredicateRuntime.swift
// OpenClip
//
// Host-side JavaScript visibility predicate runtime. Reuses the package-confined CommonJS loader,
// keeps a persistent environment per predicate file, and never exposes the action bridge.
import Foundation
import JavaScriptCore
import Core

public final class VisibilityPredicateRuntime: VisibilityPredicateEvaluating, @unchecked Sendable {
    public static let shared = VisibilityPredicateRuntime()

    private struct CacheKey: Hashable {
        let fileURL: URL
        let fileHash: String
    }

    private final class Environment {
        let context: JSContext
        let function: JSValue
        let freeze: JSValue
        let packageRoot: URL

        init(context: JSContext, function: JSValue, freeze: JSValue, packageRoot: URL) {
            self.context = context
            self.function = function
            self.freeze = freeze
            self.packageRoot = packageRoot
        }
    }

    @MainActor private var environments: [CacheKey: Environment] = [:]

    private init() {}

    @MainActor
    public func invalidate() {
        environments.removeAll()
    }

    /// Evaluates the predicate associated with the request. Returns nil when the predicate could
    /// not be loaded or run; callers treat nil as fail-open.
    @MainActor
    public func evaluate(_ request: VisibilityPredicateRequest) -> Bool? {
        let predicatePath = request.predicatePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileURL = request.packageRoot
            .appendingPathComponent(predicatePath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard Constants.isPathSafe(destinationURL: fileURL, baseDirectory: request.packageRoot),
              let fileHash = ExtensionPackageHashResolver.fileHash(fileURL) else {
            Log.extensions.error("Visibility predicate unreadable for \(request.actionID, privacy: .public)")
            return nil
        }

        let key = CacheKey(fileURL: fileURL, fileHash: fileHash)
        let environment: Environment
        if let cached = environments[key] {
            environment = cached
        } else {
            guard let built = buildEnvironment(request: request, predicatePath: predicatePath, fileURL: fileURL) else { return nil }
            environments[key] = built
            environment = built
        }

        return call(environment: environment, request: request)
    }

    @MainActor
    private func buildEnvironment(request: VisibilityPredicateRequest, predicatePath: String, fileURL: URL) -> Environment? {
        let specifier = predicatePath.hasPrefix("./")
            ? predicatePath
            : "./\(predicatePath)"
        let resolved: ResolvedModule
        do {
            resolved = try OpenClipModuleLoader.load(
                specifier: specifier,
                requiringDirectory: request.packageRoot,
                packageRoot: request.packageRoot
            )
        } catch let error as ModuleResolutionError {
            Log.extensions.error("Visibility predicate \(request.actionID, privacy: .public) rejected: \(error.message)")
            return nil
        } catch {
            Log.extensions.error("Visibility predicate \(request.actionID, privacy: .public) rejected: \(error.localizedDescription)")
            return nil
        }

        guard let context = JSContext() else {
            Log.extensions.error("Visibility predicate \(request.actionID, privacy: .public): could not create JavaScript context")
            return nil
        }

        let packageRoot = request.packageRoot
        let resolver: @convention(block) (String, String) -> [String: Any] = { directory, specifier in
            do {
                let module = try OpenClipModuleLoader.load(
                    specifier: specifier,
                    requiringDirectory: URL(fileURLWithPath: directory, isDirectory: true),
                    packageRoot: packageRoot
                )
                return ["ok": true, "path": module.url.path, "dir": module.directoryURL.path, "source": module.source]
            } catch let error as ModuleResolutionError {
                return ["ok": false, "message": error.message]
            } catch {
                return ["ok": false, "message": error.localizedDescription]
            }
        }
        context.setObject(resolver, forKeyedSubscript: "__openclipResolveModule" as NSString)

        let prelude = OpenClipCommonJS.prelude(
            entryDirectory: resolved.directoryURL.path,
            resolverExpression: "__openclipResolveModule",
            deleteResolverGlobal: true
        )

        let timeoutFlag = TimeoutFlag()
        let limit = JSExecutionTimeLimit(context: context, timeout: 0.05, timeoutFlag: timeoutFlag)
        _ = context.evaluateScript(prelude)
        guard context.exception == nil,
              let wrapper = context.evaluateScript("""
              (function(require, module, exports, __dirname, source) {
                  (new Function('require', 'module', 'exports', '__dirname', source))(require, module, exports, __dirname);
                  return (typeof module.exports === 'function') ? module.exports : null;
              })
              """),
              let requireValue = context.objectForKeyedSubscript("require"),
              let moduleValue = context.objectForKeyedSubscript("module"),
              let exportsValue = context.objectForKeyedSubscript("exports"),
              let dirnameValue = context.objectForKeyedSubscript("__dirname"),
              let sourceValue = JSValue(object: resolved.source, in: context) else {
            limit.clear()
            context.exception = nil
            Log.extensions.error("Visibility predicate \(request.actionID, privacy: .public) could not initialize CommonJS")
            return nil
        }
        let exported = wrapper.call(withArguments: [requireValue, moduleValue, exportsValue, dirnameValue, sourceValue])
        limit.clear()
        if timeoutFlag.isTimedOut {
            context.exception = nil
            Log.extensions.error("Visibility predicate \(request.actionID, privacy: .public) environment timed out")
            return nil
        }
        guard let exported,
              !exported.isNull,
              !exported.isUndefined else {
            if context.exception != nil {
                Log.extensions.error("Visibility predicate \(request.actionID, privacy: .public) evaluation failed with a JavaScript exception")
            } else {
                Log.extensions.error("Visibility predicate \(request.actionID, privacy: .public) must export a function")
            }
            context.exception = nil
            return nil
        }

        guard let freeze = context.evaluateScript("""
        (function(value) {
            function freezeInner(current) {
                if (current && typeof current === 'object') {
                    Object.keys(current).forEach(function(key) { freezeInner(current[key]); });
                    Object.freeze(current);
                }
            }
            freezeInner(value);
            return value;
        })
        """) else {
            Log.extensions.error("Visibility predicate \(request.actionID, privacy: .public) could not install input freeze")
            return nil
        }

        return Environment(context: context, function: exported, freeze: freeze, packageRoot: packageRoot)
    }

    @MainActor
    private func call(environment: Environment, request: VisibilityPredicateRequest) -> Bool? {
        let context = environment.context
        context.exception = nil

        let timeoutFlag = TimeoutFlag()
        let limit = JSExecutionTimeLimit(context: context, timeout: 0.005, timeoutFlag: timeoutFlag)
        defer { limit.clear() }

        guard let input = inputValue(for: request, in: context) else {
            Log.extensions.error("Visibility predicate input could not be created for \(request.actionID, privacy: .public)")
            return nil
        }
        let frozenInput = environment.freeze.call(withArguments: [input]) ?? input

        let result = environment.function.call(withArguments: [frozenInput])
        if timeoutFlag.isTimedOut {
            context.exception = nil
            Log.extensions.error("Visibility predicate \(request.actionID, privacy: .public) timed out")
            return nil
        }
        if context.exception != nil {
            context.exception = nil
            Log.extensions.error("Visibility predicate \(request.actionID, privacy: .public) threw a JavaScript exception")
            return nil
        }
        return result?.toBool() ?? false
    }

    @MainActor
    private func inputValue(for request: VisibilityPredicateRequest, in context: JSContext) -> JSValue? {
        let selection = request.context.selection
        let detected = selection.detectedContent(for: request.requirements?.content ?? [])
        let iso8601 = ISO8601DateFormatter()
        let dates: [[String: Any]] = detected.dates.map { item in
            var value: [String: Any] = [
                "text": item.text,
                "date": iso8601.string(from: item.date),
                "duration": item.duration
            ]
            if let timeZone = item.timeZone { value["timeZone"] = timeZone }
            return value
        }
        let addresses: [[String: Any]] = detected.addresses.map { item in
            ["text": item.text, "components": item.components]
        }
        let source: String
        switch selection.source {
        case .selection: source = "selection"
        case .clipboard: source = "clipboard"
        case .ocr: source = "ocr"
        }
        let hasRegex = request.requirements?.regex?.isEmpty == false
            || request.legacyRegex?.isEmpty == false
        let matchedText = hasRegex
            ? (request.context.match?.matchedText ?? selection.text)
            : selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        var input: [String: Any] = [
            "text": selection.text,
            "app": selection.sourceApp.bundleIdentifier ?? NSNull(),
            "source": source,
            "editable": selection.isEditable.map { $0 as Any } ?? NSNull(),
            "pasteTarget": request.context.pasteTargetAvailable.map { $0 as Any } ?? NSNull(),
            "matchedText": matchedText,
            "captures": request.context.match?.captures ?? [],
            "detected": [
                "urls": detected.urls,
                "emails": detected.emails,
                "paths": detected.paths,
                "dates": dates,
                "phones": detected.phones,
                "addresses": addresses
            ]
        ]
        return JSValue(object: input, in: context)
    }
}
