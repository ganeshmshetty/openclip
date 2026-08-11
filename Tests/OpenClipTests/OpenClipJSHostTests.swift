import XCTest
@testable import Core
@testable import OpenClip

/// In-memory option store for host tests; never touches UserDefaults. All access happens on the
/// MainActor in these tests, so the plain dictionary is safe.
fileprivate final class MemoryOptionStore: ActionOptionReading, ActionOptionWriting, @unchecked Sendable {
    private var values: [String: String] = [:]

    func stringValue(actionID: String, option: ExtensionOption) -> String {
        values[SettingKey.actionOption(actionID: actionID, optionID: option.identifier).name]
            ?? (option.defaultValue ?? "")
    }

    func setStringValue(_ value: String, actionID: String, option: ExtensionOption) {
        values[SettingKey.actionOption(actionID: actionID, optionID: option.identifier).name] = value
    }

    func clearValue(actionID: String, option: ExtensionOption) {
        values[SettingKey.actionOption(actionID: actionID, optionID: option.identifier).name] = ""
    }
}

/// URLProtocol that serves canned responses, letting fetch tests run without real networking.
final class MockURLProtocol: URLProtocol {
    /// Nonisolated global mutable state — `nonisolated(unsafe)` because it's only touched from the
    /// MainActor between tests (set + defer-nil around each request).
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    static let capturedRequests = LockedArray<URLRequest>()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        MockURLProtocol.capturedRequests.append(request)
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// Thread-safe capture box for requests seen by MockURLProtocol.
final class LockedArray<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [T] = []
    func append(_ value: T) {
        lock.lock(); defer { lock.unlock() }
        storage.append(value)
    }
    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll()
    }
    var values: [T] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}

@MainActor
final class OpenClipJSHostTests: XCTestCase {
    private var host: OpenClipJSHost!
    private var optionStore: MemoryOptionStore!

    override func setUp() async throws {
        try await super.setUp()
        host = OpenClipJSHost()
        optionStore = MemoryOptionStore()
        MockURLProtocol.requestHandler = nil
        MockURLProtocol.capturedRequests.removeAll()
    }

    private func makeContext(selectedText: String = "hello", match: ActionMatchInfo? = nil) -> ActionContext {
        let selection = SelectionContext(
            text: selectedText,
            sourceApp: AppIdentity(bundleIdentifier: "com.host.test", localizedName: "HostTestApp"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        return ActionContext(selection: selection, match: match)
    }

    private func makeRequest(
        script: String,
        options: [ExtensionOption] = [],
        rules: ExtensionActionRules = ExtensionActionRules(),
        isAsync: Bool = false,
        timeout: TimeInterval? = nil
    ) -> OpenClipJSHost.Request {
        OpenClipJSHost.Request(
            actionID: "test.action",
            scriptCode: script,
            context: makeContext(),
            options: options,
            optionStore: optionStore,
            rules: rules,
            isAsync: isAsync,
            timeout: timeout
        )
    }

    /// A host whose fetch polyfill resolves through MockURLProtocol instead of the network.
    private func makeMockedHost() -> OpenClipJSHost {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return OpenClipJSHost(session: URLSession(configuration: config))
    }

    func testPasteEffectReturnsPaste() async throws {
        let result = try await host.run(makeRequest(script: "openclip.paste('Hello World');"))
        guard case .paste(let text) = result else {
            return XCTFail("Expected .paste, got \(result)")
        }
        XCTAssertEqual(text, "Hello World")
    }

    func testCopyEffectReturnsCopy() async throws {
        let result = try await host.run(makeRequest(script: "openclip.copy('Copied');"))
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "Copied")
    }

    // MARK: - Console shim

    /// `console.log` must not throw a ReferenceError that breaks the action; it routes to Log.js
    /// and the script still completes normally. Covers variadic args + object formatting.
    func testConsoleLogShimDoesNotThrowAndActionSucceeds() async throws {
        let result = try await host.run(makeRequest(script: """
            console.log('hello', 42, { a: 1 });
            function action() { return 'ok'; }
            """))
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "ok")
    }

    /// The console shim must also be installed for async scripts (fetch path).
    func testConsoleLogShimWorksInAsyncScript() async throws {
        let result = try await host.run(makeRequest(script: """
            console.log('async start');
            async function action() { return 'ok'; }
            """, isAsync: true))
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "ok")
    }

    /// The internal `__log` callback must not stay reachable from extension scripts: only the
    /// redacting `console.log` wrapper is exposed, so a script cannot log raw text directly.
    func testConsoleLogShimRemovesRawLogAccess() async throws {
        let result = try await host.run(makeRequest(script: """
            var exposed = (typeof console.__log);
            var throws = false;
            try { console.__log('raw text'); } catch (e) { throws = (e instanceof TypeError); }
            function action() { return exposed + '|' + throws; }
            """))
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "undefined|true")
    }

    func testShowContentReturnsElementTree() async throws {
        let script = "openclip.showContent(h('stack', {}, [h('text', { content: 'Hello' }), h('button', { title: 'Paste', handler: 'x' })]));"
        let result = try await host.run(makeRequest(script: script))
        guard case .showContent(let root, nil) = result else {
            return XCTFail("Expected .showContent, got \(result)")
        }
        guard case .stack(_, let children) = root else {
            return XCTFail("Expected stack root, got \(root)")
        }
        XCTAssertEqual(children.count, 2)
        guard case .text(let textProps) = children[0] else {
            return XCTFail("Expected text child")
        }
        XCTAssertEqual(textProps.content, "Hello")
        guard case .button(let buttonProps) = children[1] else {
            return XCTFail("Expected button child")
        }
        XCTAssertEqual(buttonProps.title, "Paste")
        XCTAssertEqual(buttonProps.handler, .dispatch("x"))
    }

    func testShowContentRejectsMalformedElementTree() async throws {
        let script = "openclip.showContent({ invalid: true });"
        let result = try await host.run(makeRequest(script: script))
        guard case .showStatus(let feedback) = result else {
            return XCTFail("Expected .showStatus, got \(result)")
        }
        XCTAssertEqual(feedback.style, .error)
        XCTAssertEqual(feedback.message, "Canvas payload rejected.")
    }

    func testCannedKeysNoLongerProduceContent() async throws {
        let script = "openclip.showContent({ title: 'T', body: 'B' });"
        let result = try await host.run(makeRequest(script: script))
        guard case .showStatus(let feedback) = result else {
            return XCTFail("Expected .showStatus, got \(result)")
        }
        XCTAssertEqual(feedback.style, .error)
        XCTAssertEqual(feedback.message, "Canvas payload rejected.")
    }

    func testRequireConfigurationReturnsOpenConfiguration() async throws {
        let script = "openclip.requireConfiguration({ reason: 'Add your API key', missing: ['apiKey'] });"
        let result = try await host.run(makeRequest(script: script))
        guard case .openConfiguration(let config) = result else {
            return XCTFail("Expected .openConfiguration, got \(result)")
        }
        XCTAssertEqual(config.actionID, "test.action")
        XCTAssertEqual(config.reason, "Add your API key")
        XCTAssertEqual(config.missingOptionIDs, ["apiKey"])
    }

    func testKeepVisibleWrapsCopyUnconditionally() async throws {
        let script = "openclip.keepVisible(); openclip.copy('keep');"
        let result = try await host.run(makeRequest(script: script))
        guard case .keepVisible(.copy(let text)) = result else {
            return XCTFail("Expected .keepVisible(.copy), got \(result)")
        }
        XCTAssertEqual(text, "keep")
    }

    func testInputCapturesExposed() async throws {
        let match = ActionMatchInfo(text: "a b", matchedText: "b", captures: ["c1", "c2"], sourceBundleID: nil)
        let request = OpenClipJSHost.Request(
            actionID: "test.action",
            scriptCode: "return openclip.input.captures.join(',');",
            context: makeContext(selectedText: "a b", match: match),
            options: [],
            optionStore: optionStore,
            rules: ExtensionActionRules()
        )
        let result = try await host.run(request)
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "c1,c2")
    }

    func testInputMatchedTextAndAppExposed() async throws {
        let match = ActionMatchInfo(text: "full text", matchedText: "text", captures: [], sourceBundleID: nil)
        let script = "return openclip.input.matchedText + '|' + openclip.input.app.bundleID + '|' + openclip.input.app.name;"
        let request = OpenClipJSHost.Request(
            actionID: "test.action",
            scriptCode: script,
            context: makeContext(selectedText: "full text", match: match),
            options: [],
            optionStore: optionStore,
            rules: ExtensionActionRules()
        )
        let result = try await host.run(request)
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "text|com.host.test|HostTestApp")
    }

    func testTypedBooleanOptionsDeliveredAsNativeBooleans() async throws {
        let boolOption = ExtensionOption(identifier: "debugMode", label: "Debug", type: .boolean, defaultValue: "true")
        let strOption = ExtensionOption(identifier: "prefix", label: "Prefix", type: .string, defaultValue: "http")
        let script = "return typeof openclip.options.debugMode === 'boolean' && openclip.options.debugMode === true ? 'bool-ok' : 'fail';"
        let request = makeRequest(script: script, options: [boolOption, strOption])
        let result = try await host.run(request)
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "bool-ok")
    }

    func testRunShortcutDefaultInput() async throws {
        let script = "openclip.runShortcut('MyShortcut');"
        let request = makeRequest(script: script)
        let result = try await host.run(request)
        guard case .runShortcut(let name, let input) = result else {
            return XCTFail("Expected .runShortcut, got \(result)")
        }
        XCTAssertEqual(name, "MyShortcut")
        XCTAssertEqual(input, "hello")
    }

    func testRunShortcutCustomInputOverride() async throws {
        let script = "openclip.runShortcut('MyShortcut', 'custom override text');"
        let request = makeRequest(script: script)
        let result = try await host.run(request)
        guard case .runShortcut(let name, let input) = result else {
            return XCTFail("Expected .runShortcut, got \(result)")
        }
        XCTAssertEqual(name, "MyShortcut")
        XCTAssertEqual(input, "custom override text")
    }

    func testFunctionStringReturnBecomesCopy() async throws {
        let result = try await host.run(makeRequest(script: "function action() { return 'result'; }"))
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "result")
    }

    func testAdapterAppliesAfterToFunctionStringReturn() async throws {
        let raw = try await host.run(makeRequest(script: "function action() { return 'result'; }"))
        let applied = ActionResultAdapter.apply(
            raw: raw,
            after: .pasteResult,
            stayVisible: false,
            title: "T",
            icon: nil
        )
        guard case .paste(let text) = applied else {
            return XCTFail("Expected .paste after paste-result, got \(applied)")
        }
        XCTAssertEqual(text, "result")
    }

    func testExceptionReturnsErrorStatus() async throws {
        let result = try await host.run(makeRequest(script: "throw new Error('boom');"))
        guard case .showStatus(let feedback) = result else {
            return XCTFail("Expected .showStatus, got \(result)")
        }
        XCTAssertEqual(feedback.style, .error)
        XCTAssertTrue(feedback.message.contains("boom"))
    }

    func testNotifyEffectReturnsNotify() async throws {
        let result = try await host.run(makeRequest(script: "openclip.notify('Title', 'Body');"))
        guard case .notify(let title, let body) = result else {
            return XCTFail("Expected .notify, got \(result)")
        }
        XCTAssertEqual(title, "Title")
        XCTAssertEqual(body, "Body")
    }

    func testShareServiceEffectReturnsShareService() async throws {
        let result = try await host.run(makeRequest(
            script: "openclip.shareService('com.apple.Notes.SharingExtension');"))
        guard case .shareService(let identifier, let text) = result else {
            return XCTFail("Expected .shareService, got \(result)")
        }
        XCTAssertEqual(identifier, "com.apple.Notes.SharingExtension")
        XCTAssertEqual(text, "hello") // falls back to selection text when no text given
    }

    func testShareServiceEffectWithExplicitText() async throws {
        let result = try await host.run(makeRequest(
            script: "openclip.shareService('com.apple.Notes.SharingExtension', 'custom');"))
        guard case .shareService(_, let text) = result else {
            return XCTFail("Expected .shareService, got \(result)")
        }
        XCTAssertEqual(text, "custom")
    }

    func testMultipleEffectsSequenceInCallOrder() async throws {
        let script = "openclip.copy('a'); openclip.paste('b');"
        let result = try await host.run(makeRequest(script: script))
        guard case .sequence(let items) = result else {
            return XCTFail("Expected .sequence, got \(result)")
        }
        XCTAssertEqual(items.count, 2)
        guard case .copy("a") = items[0], case .paste("b") = items[1] else {
            return XCTFail("Unexpected sequence order \(items)")
        }
    }

    func testStatusOnlySurfacesStatusButStatusWithEffectFallsThrough() async throws {
        let statusOnly = try await host.run(makeRequest(script: "openclip.showStatus('Done', 'success');"))
        guard case .showStatus(let feedback) = statusOnly else {
            return XCTFail("Expected .showStatus, got \(statusOnly)")
        }
        XCTAssertEqual(feedback.message, "Done")
        XCTAssertEqual(feedback.style, .success)

        let statusWithEffect = try await host.run(makeRequest(script: "openclip.showStatus('nope', 'error'); openclip.copy('c');"))
        guard case .copy(let text) = statusWithEffect else {
            return XCTFail("Expected effect to win over status, got \(statusWithEffect)")
        }
        XCTAssertEqual(text, "c")
    }

    /// One-argument `showStatus` (no style) must default to `.info`, matching the optional-arg
    /// contract used by the canvas bridge.
    func testShowStatusDefaultsToInfoWhenStyleOmitted() async throws {
        let result = try await host.run(makeRequest(script: "openclip.showStatus('Done');"))
        guard case .showStatus(let feedback) = result else {
            return XCTFail("Expected .showStatus, got \(result)")
        }
        XCTAssertEqual(feedback.message, "Done")
        XCTAssertEqual(feedback.style, .info)
    }

    /// One-argument `keyPress` (no modifiers) must produce a spec with empty modifiers, matching
    /// the optional-arg contract used by the canvas bridge.
    func testKeyPressDefaultsToEmptyModifiersWhenOmitted() async throws {
        let result = try await host.run(makeRequest(script: "openclip.keyPress('return');"))
        guard case .keyPress(let spec) = result else {
            return XCTFail("Expected .keyPress, got \(result)")
        }
        XCTAssertEqual(spec.key, "return")
        XCTAssertEqual(spec.modifiers, [])
    }

    func testOptionsReadOnlyViaOptionStore() async throws {
        let option = ExtensionOption(identifier: "prefix", label: "Prefix", type: .string, defaultValue: "DEFAULT: ")
        optionStore.setStringValue("SET: ", actionID: "test.action", option: option)
        let script = "return openclip.options.prefix + '|' + openclip.option('prefix');"
        let result = try await host.run(makeRequest(script: script, options: [option]))
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "SET: |SET: ")
    }

    // MARK: - Async runtime (isAsync: true)

    func testAsyncFunctionResolvesReturnValue() async throws {
        let request = makeRequest(script: "async function action(text) { return 'async:' + text; }", isAsync: true)
        let result = try await host.run(request)
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "async:hello")
    }

    func testAsyncTopLevelSideEffectsWithoutEntryPointSucceed() async throws {
        let request = makeRequest(script: "openclip.copy('side');", isAsync: true)
        let result = try await host.run(request)
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "side")
    }

    func testPromiseRejectionSurfacesErrorStatus() async throws {
        let request = makeRequest(script: "function action() { return Promise.reject(new Error('async-boom')); }", isAsync: true)
        let result = try await host.run(request)
        guard case .showStatus(let feedback) = result else {
            return XCTFail("Expected .showStatus, got \(result)")
        }
        XCTAssertEqual(feedback.style, .error)
        XCTAssertTrue(feedback.message.contains("async-boom"))
    }

    func testSyncModeIgnoresAsyncReturnValue() async throws {
        // Legacy mode can't await a promise; a promise-like return must not paste "[object Promise]".
        let result = try await host.run(makeRequest(script: "async function action() { return 'x'; }"))
        guard case .success = result else {
            return XCTFail("Expected .success, got \(result)")
        }
    }

    // MARK: - Fetch polyfill

    func testFetchGetReturnsStatusAndText() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("hello".utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        let script = """
        async function action() {
            const r = await openclip.fetch('https://example.com/ping');
            return r.status + ':' + await r.text();
        }
        """
        let result = try await makeMockedHost().run(makeRequest(script: script, isAsync: true))
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "200:hello")
    }

    func testFetchPostSendsJSONBodyAndParsesResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (response, Data("{\"ok\":true}".utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        let script = """
        async function action() {
            const r = await openclip.fetch('https://example.com/api', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ q: 'hi' })
            });
            const body = await r.json();
            return r.status + ':' + body.ok;
        }
        """
        let result = try await makeMockedHost().run(makeRequest(script: script, isAsync: true))
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "201:true")

        let requests = MockURLProtocol.capturedRequests.values
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Content-Type"), "application/json")
        // URLSession moves an httpBody onto httpBodyStream before a URLProtocol sees the request,
        // so read the body from either source.
        let bodyData = requests[0].httpBody ?? Self.readStreamBody(requests[0])
        XCTAssertEqual(bodyData.flatMap { String(data: $0, encoding: .utf8) }, "{\"q\":\"hi\"}")
    }

    private static func readStreamBody(_ request: URLRequest) -> Data? {
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    func testFetchNetworkErrorRejectsPromise() async throws {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        defer { MockURLProtocol.requestHandler = nil }

        let script = """
        async function action() {
            try {
                await openclip.fetch('https://example.com/down');
                return 'no-error';
            } catch (e) {
                return 'caught';
            }
        }
        """
        let result = try await makeMockedHost().run(makeRequest(script: script, isAsync: true))
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "caught")
    }

    /// Non-http(s) schemes (e.g. `file://`) must be rejected before any network access, surfacing
    /// through the promise rejection rather than reaching URLSession.
    func testFetchRejectsUnsupportedScheme() async throws {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.unsupportedURL)
        }
        defer { MockURLProtocol.requestHandler = nil }

        let script = """
        async function action() {
            try {
                await openclip.fetch('file:///etc/passwd');
                return 'no-error';
            } catch (e) {
                return 'rejected';
            }
        }
        """
        let result = try await makeMockedHost().run(makeRequest(script: script, isAsync: true))
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "rejected")
        XCTAssertTrue(MockURLProtocol.capturedRequests.values.isEmpty,
                      "unsupported scheme must not reach the network")
    }

    /// The scheme allowlist is case-insensitive, so uppercase `HTTPS://` still loads.
    func testFetchAcceptsCaseInsensitiveHTTPScheme() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("ok".utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        let script = """
        async function action() {
            const r = await openclip.fetch('HTTPS://example.com/up');
            return r.status + ':' + await r.text();
        }
        """
        let result = try await makeMockedHost().run(makeRequest(script: script, isAsync: true))
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "200:ok")
    }

    /// Loopback destinations must be rejected before any network access, surfacing through the
    /// promise rejection rather than reaching URLSession.
    func testFetchRejectsDirectLoopback() async throws {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.unsupportedURL)
        }
        defer { MockURLProtocol.requestHandler = nil }

        let script = """
        async function action() {
            try {
                await openclip.fetch('http://127.0.0.1/secret');
                return 'no-error';
            } catch (e) {
                return 'rejected';
            }
        }
        """
        let result = try await makeMockedHost().run(makeRequest(script: script, isAsync: true))
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "rejected")
        XCTAssertTrue(MockURLProtocol.capturedRequests.values.isEmpty,
                      "loopback destination must not reach the network")
    }

    /// A public URL that redirects to loopback must be intercepted and blocked before following, so
    /// the promise resolves with the original redirect (302) and no loopback request is made.
    func testFetchRejectsRedirectToLoopback() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 302,
                httpVersion: nil,
                headerFields: ["Location": "http://127.0.0.1/secret"]
            )!
            return (response, Data())
        }
        defer { MockURLProtocol.requestHandler = nil }

        let script = """
        async function action() {
            const r = await openclip.fetch('https://public.example.com/redirect');
            return String(r.status);
        }
        """
        let result = try await makeMockedHost().run(makeRequest(script: script, isAsync: true))
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "302", "redirect to loopback must be aborted, leaving the original 3xx response")
        XCTAssertTrue(MockURLProtocol.capturedRequests.values.allSatisfy { $0.url?.host == "public.example.com" },
                      "redirect must not be followed to a loopback host")
    }

    /// `FetchTaskBox.remove` matches by stable task identifier: removing a task by id takes it out
    /// of watchdog tracking, so a later `cancelAll` leaves it untouched while still cancelling the
    /// tracked tasks.
    func testFetchTaskBoxRemovesByIdentifier() {
        let box = FetchTaskBox()
        let session = URLSession(configuration: .ephemeral)
        func makeTask() -> URLSessionDataTask {
            session.dataTask(with: URLRequest(url: URL(string: "https://example.com/x")!))
        }
        let a = makeTask()
        let b = makeTask()
        let c = makeTask()
        box.add(a)
        box.add(b)
        box.add(c)

        box.remove(b.taskIdentifier)

        box.cancelAll()
        XCTAssertNotEqual(b.state, .canceling, "removed task must not be cancelled")
        XCTAssertEqual(a.state, .canceling)
        XCTAssertEqual(c.state, .canceling)
    }

    /// `add(_:)` racing with `cancelAll()` must never let a task escape cancellation: tasks added
    /// before cancellation are cancelled by `cancelAll()`, tasks added after cancellation started are
    /// cancelled immediately by `add(_:)`.
    func testFetchTaskBoxAddConcurrentWithCancelAllCancelsAll() {
        let box = FetchTaskBox()
        let session = URLSession(configuration: .ephemeral)
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "fetchbox.race", attributes: .concurrent)
        let addLock = NSLock()
        var added: [URLSessionDataTask] = []

        let producerCount = 8
        let perProducer = 100
        for _ in 0..<producerCount {
            queue.async(group: group) {
                for _ in 0..<perProducer {
                    let task = session.dataTask(with: URLRequest(url: URL(string: "https://example.com/x")!))
                    addLock.lock()
                    added.append(task)
                    addLock.unlock()
                    box.add(task)
                }
            }
        }
        queue.async(group: group) {
            box.cancelAll()
        }
        group.wait()

        addLock.lock()
        let all = added
        addLock.unlock()
        XCTAssertEqual(all.count, producerCount * perProducer)
        // Cancelled tasks end up in either `.canceling` or `.completed`; a task that escaped
        // cancellation would still be `.suspended` (never resumed).
        for task in all {
            XCTAssertNotEqual(task.state, .suspended, "every added task must be cancelled, got \(task.state)")
        }
    }

    // MARK: - Watchdog

    func testTimeoutThrowsForNeverSettlingPromise() async throws {
        let request = makeRequest(script: "function action() { return new Promise(function() {}); }", isAsync: true, timeout: 0.25)
        do {
            _ = try await host.run(request)
            return XCTFail("Expected timeout to throw")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, Constants.actionErrorDomain)
            XCTAssertTrue(nsError.localizedDescription.contains("timed out"))
        }
    }

    // MARK: - Manifest requiredOptions short-circuit (Phase 7)

    /// A required option with no resolved value must short-circuit to `.openConfiguration` BEFORE the
    /// JS body runs — the script would throw if executed, so only the short-circuit path can produce
    /// `.openConfiguration`.
    func testMissingRequiredOptionsShortCircuitsToOpenConfigurationBeforeJSRuns() async throws {
        let option = ExtensionOption(identifier: "apiKey", label: "API Key", type: .secret, defaultValue: nil)
        let rules = ExtensionActionRules(requirements: ActionRequirements(requiredOptions: ["apiKey"]))
        let action = JavaScriptAction(
            id: "test.required",
            title: "Required",
            iconSymbol: "terminal",
            scriptCode: "throw new Error('must not run');",
            options: [option],
            optionStore: MemoryOptionStore(),
            rules: rules
        )

        let result = try await action.perform(makeContext())
        guard case .openConfiguration(let config) = result else {
            return XCTFail("Expected .openConfiguration, got \(result)")
        }
        XCTAssertEqual(config.actionID, "test.required")
        XCTAssertEqual(config.missingOptionIDs, ["apiKey"])
        XCTAssertEqual(config.reason, "Required option not set.")
    }

    /// The same action with the required option set runs normally (`.copy`, not `.openConfiguration`).
    func testMissingRequiredOptionsRunsNormallyWhenStoreSet() async throws {
        let option = ExtensionOption(identifier: "apiKey", label: "API Key", type: .secret, defaultValue: nil)
        let store = MemoryOptionStore()
        store.setStringValue("secret", actionID: "test.required", option: option)
        let rules = ExtensionActionRules(requirements: ActionRequirements(requiredOptions: ["apiKey"]))
        let action = JavaScriptAction(
            id: "test.required",
            title: "Required",
            iconSymbol: "terminal",
            scriptCode: "function action() { return 'ran'; }",
            options: [option],
            optionStore: store,
            rules: rules
        )

        let result = try await action.perform(makeContext())
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy, got \(result)")
        }
        XCTAssertEqual(text, "ran")
    }
}
