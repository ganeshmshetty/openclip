// OpenClipModuleLoader.swift
// OpenClip
//
// Host-side CommonJS loader for OpenClip JS extension packages. Resolves `require('./x')` calls
// inside a package directory at run time: pure Swift resolution + containment + file IO (no
// JSContext involvement). The JS host owns wrapping/caching; this type owns the filesystem rules.
import Foundation
import Darwin
import Core

public enum ModuleResolutionError: Error, Equatable, Sendable {
    /// Specifier resolved outside the package (../ escape or symlink escape).
    case outsidePackage(String)
    /// `require("/…")` — absolute paths are not allowed.
    case absolutePath(String)
    /// Bare specifier (`fs`, `lodash`) — npm libraries must be bundled; Node builtins never run.
    case bareSpecifier(String)
    /// No candidate file exists; carries the tried candidate paths.
    case notFound(String, [String])

    /// Node's builtin module names — the only bare specifiers that get the explicit builtin message.
    static let nodeBuiltins: Set<String> = [
        "assert", "buffer", "child_process", "cluster", "console", "constants", "crypto",
        "dgram", "dns", "domain", "events", "fs", "http", "https", "module", "net", "os",
        "path", "perf_hooks", "process", "punycode", "querystring", "readline", "repl",
        "stream", "string_decoder", "sys", "timers", "tls", "trace_events", "tty", "url",
        "util", "v8", "vm", "worker_threads", "zlib"
    ]

    public var message: String {
        switch self {
        case .outsidePackage(let specifier):
            return "require(\"\(specifier)\") resolves outside the extension package; modules cannot read outside the package directory"
        case .absolutePath(let specifier):
            return "require(\"\(specifier)\") must be a relative path (./ or ../); absolute paths are not supported"
        case .bareSpecifier(let name):
            if Self.nodeBuiltins.contains(name) {
                return "Node builtin \"\(name)\" is not available to OpenClip extensions; it cannot run in the sandboxed runtime"
            }
            return "Bare specifier \"\(name)\" is not supported; bundle npm libraries with esbuild (see docs/developer-guide/extensions-modules.md)"
        case .notFound(let specifier, let tried):
            let candidates = tried.isEmpty ? "" : " (tried: \(tried.joined(separator: ", ")))"
            return "Cannot find module \"\(specifier)\"\(candidates)"
        }
    }
}

public struct ResolvedModule: Equatable, Sendable {
    public let url: URL
    public let source: String
    public let directoryURL: URL

    public init(url: URL, source: String, directoryURL: URL) {
        self.url = url
        self.source = source
        self.directoryURL = directoryURL
    }
}

public enum OpenClipModuleLoader {
    /// Resolves `require(specifier)` from `requiringDirectory` in `packageRoot`. Throws a
    /// `ModuleResolutionError` if resolution fails. Resolution follows Node rules: exact file, then
    /// `<candidate>.js`, then `<candidate>/index.js`. The loader checks containment on the final
    /// file after symlink resolution. The returned `url` and `directoryURL` are real paths
    /// (Node default, without `--preserve-symlinks`).
    public static func load(
        specifier: String,
        requiringDirectory: URL,
        packageRoot: URL
    ) throws -> ResolvedModule {
        guard specifier.hasPrefix("./") || specifier.hasPrefix("../") else {
            if specifier.hasPrefix("/") {
                throw ModuleResolutionError.absolutePath(specifier)
            }
            let firstComponent = specifier.split(separator: "/").first.map(String.init) ?? specifier
            throw ModuleResolutionError.bareSpecifier(firstComponent)
        }

        let candidate = requiringDirectory
            .appendingPathComponent(specifier)
            .resolvingSymlinksInPath()
            .standardizedFileURL

        let canonicalRoot = packageRoot.resolvingSymlinksInPath().standardizedFileURL
        guard Constants.isPathSafe(destinationURL: candidate, baseDirectory: canonicalRoot) else {
            throw ModuleResolutionError.outsidePackage(specifier)
        }

        func isFile(_ url: URL) -> Bool {
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
        }
        func isDir(_ url: URL) -> Bool {
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
        /// Reads `url` as the module source. Containment is verified against the real path of the
        /// opened file descriptor via `fcntl(F_GETPATH)`, binding verification directly to the open
        /// file to eliminate time-of-check to time-of-use (TOCTOU) symlink substitution races (issue #39).
        func resolved(_ url: URL, tried: [String]) throws -> ResolvedModule {
            let fd = open(url.path, O_RDONLY | O_CLOEXEC)
            guard fd >= 0 else {
                throw ModuleResolutionError.notFound(specifier, tried + [url.path])
            }
            defer { close(fd) }

            var resolvedBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            guard fcntl(fd, F_GETPATH, &resolvedBuffer) != -1 else {
                throw ModuleResolutionError.notFound(specifier, tried + [url.path])
            }
            let resolvedPath = String(cString: resolvedBuffer)
            let target = URL(fileURLWithPath: resolvedPath).standardizedFileURL

            guard Constants.isPathSafe(destinationURL: target, baseDirectory: canonicalRoot) else {
                throw ModuleResolutionError.outsidePackage(specifier)
            }

            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
            let data: Data
            do {
                data = try handle.readToEnd() ?? Data()
            } catch {
                throw ModuleResolutionError.notFound(specifier, tried + [url.path])
            }
            guard let source = String(data: data, encoding: .utf8) else {
                throw ModuleResolutionError.notFound(specifier, tried + [url.path])
            }

            return ResolvedModule(
                url: target,
                source: source,
                directoryURL: target.deletingLastPathComponent()
            )
        }

        var tried: [String] = [candidate.path]
        if isFile(candidate) {
            return try resolved(candidate, tried: tried)
        }

        let withJS = candidate.appendingPathExtension("js")
        tried.append(withJS.path)
        if isFile(withJS) {
            return try resolved(withJS, tried: tried)
        }

        if isDir(candidate) {
            let index = candidate.appendingPathComponent("index.js")
            tried.append(index.path)
            if isFile(index) {
                return try resolved(index, tried: tried)
            }
        }

        throw ModuleResolutionError.notFound(specifier, tried)
    }
}