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

    @MainActor
    public func evaluate(_ request: VisibilityPredicateRequest) -> Bool? {
        let fileURL = request.packageRoot
            .appendingPathComponent(request.predicatePath)
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
            guard let built = buildEnvironment(request: request, fileURL: fileURL) else { return nil }
            environments[key] = built
            environment = built
        }

        return call(environment: environment, request: request)
    }

    @MainActor
    private func buildEnvironment(request: VisibilityPredicateRequest, fileURL: URL) -> Environment? {
        let specifier = request.predicatePath.hasPrefix("./")
            ? request.predicatePath
            : "./\(request.predicatePath)"
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

        let script = OpenClipCommonJS.prelude(
            entryDirectory: resolved.directoryURL.path,
            resolverExpression: "__openclipResolveModule",
            deleteResolverGlobal: true
        ) + "\n" + resolved.source + "\n;(typeof module.exports === 'function' ? module.exports : null);"

        let timeoutFlag = TimeoutFlag()
        let limit = JSExecutionTimeLimit(context: context, timeout: 0.05, timeoutFlag: timeoutFlag)
        let exported = context.evaluateScript(script)
        limit.clear()
        if timeoutFlag.isTimedOut {
            context.exception = nil
            Log.extensions.error("Visibility predicate \(request.actionID, privacy: .public) environment timed out")
            return nil
        }
        guard let exported,
              !exported.isNull,
              !exported.isUndefined else {
            if let exception = context.exception {
                Log.extensions.error("Visibility predicate \(request.actionID, privacy: .public) evaluation failed: \(exception.toString() ?? "unknown error")")
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
        if let exception = context.exception {
            context.exception = nil
            Log.extensions.error("Visibility predicate \(request.actionID, privacy: .public) threw: \(exception.toString() ?? "unknown error")")
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
