// JSNativeFetch.swift
// OpenClip
//
// Shared URLSession-backed fetch bridge for the JavaScript runtime. Installs
// `openclip.__nativeFetch` (a URLSession dataTask) and the `openclip.fetch`
// polyfill into any JSContext that already exposes a global `openclip` object.
// OpenClipJSHost (async JS actions) calls installNativeFetch after installing its
// own bridge; tests route through an injected URLSession with MockURLProtocol.
import Foundation
import JavaScriptCore
import Darwin
import Core

enum JSNativeFetch {
    /// Installs `openclip.__nativeFetch` + the `openclip.fetch` polyfill. The
    /// context must already have a global `openclip` object (both hosts set it
    /// before calling). All JS VM access stays on the thread that created the
    /// context: the URLSession completion only schedules work back onto that
    /// thread's CFRunLoop; the host's pump loop drains it.
    @discardableResult
    static func installNativeFetch(in context: JSContext, session: URLSession, fetchTasks: FetchTaskBox) -> FetchResolvers? {
        guard let openclip = context.objectForKeyedSubscript("openclip" as NSString),
              !openclip.isUndefined, !openclip.isNull, openclip.isObject else { return nil }

        // Weak, so the block stored on `openclip` — and therefore on the context itself — does not
        // retain the context (issue #47). Synchronous calls use JSContext.current() instead.
        let weakContextBox = WeakJSContextBox(context)
        // resolve/reject live here, owned by this JS thread, instead of being captured by the
        // off-thread URLSession completion. The completion reaches them only through a weak box.
        let resolvers = FetchResolvers()
        // runLoopBox keeps CFRunLoopGetCurrent() out of the block's @Sendable
        // capture region (region-based isolation checker).
        let runLoopBox = RunLoopBox(CFRunLoopGetCurrent())
        // Rebuild the injected session with a redirect-intercepting delegate so every hop is
        // validated before URLSession follows it, while keeping the caller's configuration
        // (notably the MockURLProtocol classes used in tests).
        let policySession = PolicySession(from: session)
        // URLSession retains its delegate until explicit invalidation. Tie the session to the
        // evaluation so it is torn down — releasing the session, its delegate, worker threads, and
        // Mach ports — when the run ends instead of leaking one per async action (issue #46).
        fetchTasks.setCloseHandler { policySession.session.invalidateAndCancel() }

        let nativeFetchBlock: @convention(block) (String, JSValue, JSValue, JSValue) -> Void = { urlString, options, resolve, reject in
            guard let url = URL(string: urlString) else {
                guard let currentContext = JSContext.current(),
                      let err = JSNativeFetch.jsError("Invalid URL: \(urlString)", in: currentContext) else { return }
                reject.call(withArguments: [err])
                return
            }
            // Enforce the destination policy on the initial URL: http/https only, and never a
            // loopback with an unallowed/privileged port, or an RFC1918 / link-local / Unix-local host.
            // Redirects are validated by JSNativeFetchRedirectDelegate before they are followed.
            guard JSNativeFetch.isDestinationAllowed(url) else {
                guard let currentContext = JSContext.current(),
                      let err = JSNativeFetch.jsError("Destination not allowed: \(urlString)", in: currentContext) else { return }
                reject.call(withArguments: [err])
                return
            }
            let request = JSNativeFetch.makeURLRequest(url: url, options: options)
            let taskID = TaskIdentifierBox()
            // The completion runs on a URLSession worker thread, so it holds only Sendable scalars
            // and weak boxes — never a strong JSValue/JSContext (issue #47). The JS references are
            // looked up on the JS thread inside the runloop block.
            let weakResolvers = WeakRef(resolvers)
            let task = policySession.session.dataTask(with: request) { data, response, error in
                // Remove by the task's stable identifier (captured via the box) rather than reading a
                // mutable `task` reference across threads.
                fetchTasks.remove(taskID.value)
                // The evaluation is complete. Do not do work for it.
                // A cancelled task also calls this handler, with an error.
                guard !fetchTasks.isEnded else { return }
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let errorMessage = error.map { "Fetch failed: \($0.localizedDescription)" }
                CFRunLoopPerformBlock(runLoopBox.runLoop, CFRunLoopMode.defaultMode.rawValue) {
                    // The evaluation can end after the block goes into the queue.
                    // A later evaluation on this thread can run the block. Do not call the JavaScript VM.
                    guard !fetchTasks.isEnded,
                          let currentContext = weakContextBox.context,
                          let pending = weakResolvers.value?.take(taskID.value) else { return }
                    if let errorMessage {
                        if let err = JSNativeFetch.jsError(errorMessage, in: currentContext) {
                            pending.reject.call(withArguments: [err])
                        }
                    } else if let resp = JSNativeFetch.fetchResponse(status: status, body: body, context: currentContext) {
                        pending.resolve.call(withArguments: [resp])
                    }
                }
                CFRunLoopWakeUp(runLoopBox.runLoop)
            }
            // Track the task (and its identifier) before resuming, so even an immediately-failing
            // task is registered for watchdog cancellation. Register the resolver first so an
            // immediate completion can still find it.
            taskID.set(task.taskIdentifier)
            fetchTasks.add(task)
            resolvers.register(task.taskIdentifier, resolve: resolve, reject: reject)
            task.resume()
        }
        openclip.setObject(nativeFetchBlock, forKeyedSubscript: "__nativeFetch" as NSString)
        context.evaluateScript(fetchPolyfillScript)
        // Handed back so the host can drop any still-pending resolve/reject pair at the end of the
        // run, on the JS thread.
        return resolvers
    }

    /// Effectively disables URLRequest's 60 s default: a fetch has no app-imposed deadline and is
    /// left to finish, bounded only by clicking the loading toast (which cancels in-flight tasks).
    private static let fetchTimeout: TimeInterval = 60 * 60 * 24 * 365

    /// Builds a URLRequest from `fetch(url, options)`: method (default GET),
    /// optional headers object, and an optional string body.
    static func makeURLRequest(url: URL, options: JSValue) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = fetchTimeout

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
    static func fetchResponse(status: Int, body: String, context: JSContext) -> JSValue? {
        guard let response = JSValue(newObjectIn: context) else { return nil }
        response.setObject(status, forKeyedSubscript: "status")
        response.setObject(status >= 200 && status < 300, forKeyedSubscript: "ok")

        let textBlock: @convention(block) () -> String = { body }
        response.setObject(textBlock, forKeyedSubscript: "text")

        // `json()` is called synchronously from JS and the block lives on the response JSValue, so
        // it must not capture its context: a block that does forms a retain cycle
        // (context -> JSValue -> block -> context) that keeps the whole JSVirtualMachine alive
        // (issue #47). JSContext.current() is the context that invoked the block.
        let jsonBlock: @convention(block) () -> Any = {
            guard let currentContext = JSContext.current() else { return NSNull() }
            if let data = body.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) {
                return object
            }
            Log.js.debug("response.json() received non-JSON body")
            if let err = JSNativeFetch.jsError("Invalid JSON response", in: currentContext) {
                currentContext.exception = err
            }
            return NSNull()
        }
        response.setObject(jsonBlock, forKeyedSubscript: "json")
        return response
    }

    /// Creates a JS `Error` value (falls back to a plain object if the Error
    /// constructor is gone).
    static func jsError(_ message: String, in context: JSContext) -> JSValue? {
        if let errorConstructor = context.objectForKeyedSubscript("Error"),
           !errorConstructor.isUndefined, !errorConstructor.isNull {
            return errorConstructor.call(withArguments: [message])
        }
        return JSValue(object: ["message": message], in: context)
    }

    /// Destination policy for the fetch bridge. Only http/https are allowed, and the host must not
    /// be an RFC1918/private, link-local, or Unix-local target (SSRF guard). Loopback is allowed
    /// on unprivileged ports (>= 1024), excluding sensitive database and daemon ports.
    /// Applied to the initial URL and, via `JSNativeFetchRedirectDelegate`, to every redirect hop
    /// before it is followed.
    static func isDestinationAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        guard let host = url.host, !host.isEmpty else { return false }

        if isLoopbackHost(host) {
            let port = url.port ?? (scheme == "https" ? 443 : 80)
            return isAllowedLocalPort(port)
        }

        return !isLocalOrPrivateHost(host)
    }

    /// Classifies a host string as loopback (localhost, 127.0.0.0/8, ::1).
    static func isLoopbackHost(_ host: String) -> Bool {
        let bare = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let bareNoZone = String(bare.split(separator: "%").first ?? Substring(bare))
        if bareNoZone == "localhost" || bareNoZone == "local" || bareNoZone == "ip6-localhost" || bareNoZone.hasSuffix(".localhost") {
            return true
        }

        var ipv4 = in_addr()
        if inet_pton(AF_INET, bareNoZone, &ipv4) == 1 {
            let value = UInt32(bigEndian: ipv4.s_addr)
            let a = UInt8((value >> 24) & 0xFF)
            return a == 127
        }

        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, bareNoZone, &ipv6) == 1 {
            let bytes = withUnsafeBytes(of: &ipv6) { Array($0) }
            if bytes.prefix(15).allSatisfy({ $0 == 0 }) && bytes[15] == 1 { return true }
            if bytes.prefix(10).allSatisfy({ $0 == 0 }) && bytes[10] == 0xFF && bytes[11] == 0xFF {
                return bytes[12] == 127
            }
        }

        return false
    }

    /// Validates whether a destination port on loopback is safe:
    /// - Must be an unprivileged high port (>= 1024)
    /// - Must not be a sensitive daemon / database port
    static func isAllowedLocalPort(_ port: Int) -> Bool {
        guard port >= 1024 && port <= 65535 else { return false }
        let blockedPorts: Set<Int> = [
            2375, 2376, // Docker daemon
            3306,       // MySQL
            5432,       // PostgreSQL
            6379,       // Redis
            11211,      // Memcached
            27017,      // MongoDB
            9200        // Elasticsearch
        ]
        return !blockedPorts.contains(port)
    }

    /// Classifies a host string as loopback / RFC1918 / link-local / Unix-local. Handles `localhost`
    /// hostnames and IPv4/IPv6 literals (including IPv4-mapped IPv6 and ULA). Non-literal hostnames
    /// that resolve to such addresses are not resolved here (that requires DNS); the guard covers
    /// direct literal/localhost targets.
    static func isLocalOrPrivateHost(_ host: String) -> Bool {
        let bare = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let bareNoZone = String(bare.split(separator: "%").first ?? Substring(bare))
        if bareNoZone == "localhost" || bareNoZone == "local" || bareNoZone == "ip6-localhost" || bareNoZone.hasSuffix(".localhost") {
            return true
        }

        var ipv4 = in_addr()
        if inet_pton(AF_INET, bareNoZone, &ipv4) == 1 {
            let value = UInt32(bigEndian: ipv4.s_addr)
            let a = UInt8((value >> 24) & 0xFF)
            let b = UInt8((value >> 16) & 0xFF)
            return isPrivateIPv4(a: a, b: b)
        }

        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, bareNoZone, &ipv6) == 1 {
            let bytes = withUnsafeBytes(of: &ipv6) { Array($0) }
            if bytes.allSatisfy({ $0 == 0 }) { return true }                       // ::
            if bytes.prefix(15).allSatisfy({ $0 == 0 }) && bytes[15] == 1 { return true } // ::1
            if bytes[0] == 0xfe && (bytes[1] & 0xC0) == 0x80 { return true }       // fe80::/10 link-local
            if bytes[0] == 0xfc || bytes[0] == 0xfd { return true }                // fc00::/7 ULA
            if bytes.prefix(10).allSatisfy({ $0 == 0 }) && bytes[10] == 0xFF && bytes[11] == 0xFF {
                return isPrivateIPv4(a: bytes[12], b: bytes[13]) // ::ffff:a.b.c.d
            }
            return false
        }
        return false
    }

    private static func isPrivateIPv4(a: UInt8, b: UInt8) -> Bool {
        if a == 127 { return true }                                  // 127/8 loopback
        if a == 10 { return true }                                   // 10/8
        if a == 172 && b >= 16 && b <= 31 { return true }            // 172.16/12
        if a == 192 && b == 168 { return true }                      // 192.168/16
        if a == 169 && b == 254 { return true }                      // 169.254/16 link-local
        if a == 0 { return true }                                    // 0.0.0.0/8 unspecified
        return false
    }

    /// Holds a URLSession rebuilt from the injected session's configuration plus a
    /// redirect-validating delegate. Captured by the fetch block for the run's lifetime; the box's
    /// close handler invalidates it when the evaluation ends, releasing the session, delegate,
    /// worker threads, and Mach ports (issue #46).
    private final class PolicySession: @unchecked Sendable {
        let session: URLSession
        let delegate: JSNativeFetchRedirectDelegate
        init(from base: URLSession) {
            let delegate = JSNativeFetchRedirectDelegate()
            self.delegate = delegate
            self.session = URLSession(configuration: base.configuration, delegate: delegate, delegateQueue: nil)
        }
    }

    /// URLSession task delegate that rejects any redirect whose destination fails the fetch
    /// destination policy. Returning `nil` from `willPerformHTTPRedirection` aborts the redirect,
    /// so the task surfaces the original 3xx response instead of following the hop.
    private final class JSNativeFetchRedirectDelegate: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            if let url = request.url, JSNativeFetch.isDestinationAllowed(url) {
                completionHandler(request)
            } else {
                completionHandler(nil)
            }
        }
    }

    static let fetchPolyfillScript = """
    openclip.fetch = function(url, options) {
        return new Promise(function(resolve, reject) {
            openclip.__nativeFetch(String(url), options || {}, resolve, reject);
        });
    };
    """
}
