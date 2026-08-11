// JSNativeFetch.swift
// OpenClip
//
// Shared URLSession-backed fetch bridge for both JavaScript runtimes. Installs
// `openclip.__nativeFetch` (a URLSession dataTask) and the `openclip.fetch`
// polyfill into any JSContext that already exposes a global `openclip` object.
// OpenClipJSHost (async JS actions) and JavaScriptCanvasEngine (async canvas
// dispatches) both call installNativeFetch after installing their own bridge;
// tests route through an injected URLSession with MockURLProtocol.
import Foundation
import JavaScriptCore
import Core

enum JSNativeFetch {
    /// Installs `openclip.__nativeFetch` + the `openclip.fetch` polyfill. The
    /// context must already have a global `openclip` object (both hosts set it
    /// before calling). All JS VM access stays on the thread that created the
    /// context: the URLSession completion only schedules work back onto that
    /// thread's CFRunLoop; the host's pump loop drains it.
    static func installNativeFetch(in context: JSContext, session: URLSession, fetchTasks: FetchTaskBox) {
        guard let openclip = context.objectForKeyedSubscript("openclip" as NSString),
              !openclip.isUndefined, !openclip.isNull, openclip.isObject else { return }

        let contextBox = JSContextBox(context)
        // runLoopBox keeps CFRunLoopGetCurrent() out of the block's @Sendable
        // capture region (region-based isolation checker).
        let runLoopBox = RunLoopBox(CFRunLoopGetCurrent())

        let nativeFetchBlock: @convention(block) (String, JSValue, JSValue, JSValue) -> Void = { urlString, options, resolve, reject in
            guard let url = URL(string: urlString) else {
                guard let err = JSNativeFetch.jsError("Invalid URL: \(urlString)", in: context) else { return }
                reject.call(withArguments: [err])
                return
            }
            let request = JSNativeFetch.makeURLRequest(url: url, options: options)
            let resolveBox = JSValueBox(resolve)
            let rejectBox = JSValueBox(reject)
            var task: URLSessionDataTask?
            task = session.dataTask(with: request) { data, response, error in
                if let task {
                    fetchTasks.remove(task)
                }
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let errorMessage = error.map { "Fetch failed: \($0.localizedDescription)" }
                CFRunLoopPerformBlock(runLoopBox.runLoop, CFRunLoopMode.defaultMode.rawValue) {
                    if let errorMessage {
                        if let err = JSNativeFetch.jsError(errorMessage, in: contextBox.context) {
                            rejectBox.value.call(withArguments: [err])
                        }
                    } else if let resp = JSNativeFetch.fetchResponse(status: status, body: body, context: contextBox.context) {
                        resolveBox.value.call(withArguments: [resp])
                    }
                }
                CFRunLoopWakeUp(runLoopBox.runLoop)
            }
            if let task {
                fetchTasks.add(task)
                task.resume()
            }
        }
        openclip.setObject(nativeFetchBlock, forKeyedSubscript: "__nativeFetch" as NSString)
        context.evaluateScript(fetchPolyfillScript)
    }

    /// Builds a URLRequest from `fetch(url, options)`: method (default GET),
    /// optional headers object, and an optional string body.
    static func makeURLRequest(url: URL, options: JSValue) -> URLRequest {
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
    static func fetchResponse(status: Int, body: String, context: JSContext) -> JSValue? {
        guard let response = JSValue(newObjectIn: context) else { return nil }
        response.setObject(status, forKeyedSubscript: "status")
        response.setObject(status >= 200 && status < 300, forKeyedSubscript: "ok")

        let textBlock: @convention(block) () -> String = { body }
        response.setObject(textBlock, forKeyedSubscript: "text")

        // The json block escapes into JS, so it captures the context through a
        // Sendable box rather than the raw non-Sendable JSContext.
        let contextBox = JSContextBox(context)
        let jsonBlock: @convention(block) () -> Any = {
            if let data = body.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) {
                return object
            }
            Log.js.debug("response.json() received non-JSON body")
            if let err = JSNativeFetch.jsError("Invalid JSON response", in: contextBox.context) {
                contextBox.context.exception = err
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

    static let fetchPolyfillScript = """
    openclip.fetch = function(url, options) {
        return new Promise(function(resolve, reject) {
            openclip.__nativeFetch(String(url), options || {}, resolve, reject);
        });
    };
    """
}
