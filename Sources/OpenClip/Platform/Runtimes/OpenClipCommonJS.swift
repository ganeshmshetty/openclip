// OpenClipCommonJS.swift
// OpenClip
//
// Shared JS-side CommonJS environment for action scripts and visibility predicates. The Swift
// filesystem rules stay in OpenClipModuleLoader; this type only owns the JS bindings and cache.
import Foundation

public enum OpenClipCommonJS {
    /// The per-run module cache and Node-style per-directory `require`.
    /// `resolverExpression` is a JS expression returning `{ ok, path, dir, source }` or `{ ok: false, message }`.
    public static func prelude(
        entryDirectory: String,
        resolverExpression: String,
        deleteResolverGlobal: Bool = false
    ) -> String {
        let escaped = entryDirectory
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let cleanup = deleteResolverGlobal ? "delete globalThis.__openclipResolveModule;" : ""
        return """
        var __openclipRequireState = (function() {
            var __moduleCache = {};
            var __resolveModule = \(resolverExpression);
            \(cleanup)
            var __require = function(dir, specifier) {
                var r = __resolveModule(dir, specifier);
                if (!r.ok) throw new Error(r.message);
                if (__moduleCache[r.path] !== undefined) return __moduleCache[r.path];
                var m = { exports: {} };
                __moduleCache[r.path] = m.exports;
                (new Function('require', 'module', 'exports', '__dirname', r.source))(__require.bind(null, r.dir), m, m.exports, r.dir);
                __moduleCache[r.path] = m.exports;
                return m.exports;
            };
            var module = { exports: {} };
            return {
                require: __require.bind(null, "\(escaped)"),
                module: module,
                exports: module.exports,
                dirname: "\(escaped)"
            };
        })();
        var require = __openclipRequireState.require;
        var module = __openclipRequireState.module;
        var exports = __openclipRequireState.exports;
        var __dirname = __openclipRequireState.dirname;
        """
    }
}
