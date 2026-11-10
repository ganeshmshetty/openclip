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
        let escaped = jsStringLiteral(entryDirectory)
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
                try {
                    (new Function('require', 'module', 'exports', '__dirname', r.source))(__require.bind(null, r.dir), m, m.exports, r.dir);
                } catch (error) {
                    delete __moduleCache[r.path];
                    throw error;
                }
                __moduleCache[r.path] = m.exports;
                return m.exports;
            };
            var module = { exports: {} };
            return {
                require: __require.bind(null, \(escaped)),
                module: module,
                exports: module.exports,
                dirname: \(escaped)
            };
        })();
        var require = __openclipRequireState.require;
        var module = __openclipRequireState.module;
        var exports = __openclipRequireState.exports;
        var __dirname = __openclipRequireState.dirname;
        """
    }

    /// Encodes a path as a JavaScript string literal, including control and line-separator characters.
    private static func jsStringLiteral(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22: result += "\\\""
            case 0x5C: result += "\\\\"
            case 0x0A: result += "\\n"
            case 0x0D: result += "\\r"
            case 0x09: result += "\\t"
            case 0x2028: result += "\\u2028"
            case 0x2029: result += "\\u2029"
            case 0x00...0x1F: result += String(format: "\\u%04X", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        result += "\""
        return result
    }
}
