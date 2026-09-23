import XCTest
@testable import Core
@testable import OpenClip

final class JavaScriptCustomActionTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
    }

    @MainActor
    func testJavaScriptCustomActionCodableRoundTrip() throws {
        let action = CustomAction(
            id: "custom.js1",
            title: "Uppercase JS",
            iconName: "curlybraces",
            type: .javaScript(
                script: "function action(text) { return text.toUpperCase(); }",
                isAsync: false,
                replaceSelection: true
            )
        )

        let encoded = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(CustomAction.self, from: encoded)

        XCTAssertEqual(decoded.id, action.id)
        XCTAssertEqual(decoded.title, action.title)
        XCTAssertEqual(decoded.iconName, action.iconName)
        XCTAssertEqual(decoded.type, action.type)
        XCTAssertEqual(decoded.chrome.source, .custom)
        XCTAssertEqual(decoded.chrome.outputKind, .text)
        XCTAssertEqual(decoded.chrome.recommendedResult, .pasteOrCopy)
    }

    @MainActor
    func testJavaScriptCustomActionSyncExecution() async throws {
        let action = CustomAction(
            id: "custom.js_sync",
            title: "Trim JS",
            iconName: "curlybraces",
            type: .javaScript(
                script: "function action(t) { return t.trim() + '!!!'; }",
                isAsync: false,
                replaceSelection: true
            )
        )

        let context = ActionContext(
            selection: SelectionContext(text: "  hello world  "),
            match: nil
        )

        let result = try await action.perform(context)
        guard case .text(let text) = result else {
            XCTFail("Expected .text result, got \(result)")
            return
        }
        XCTAssertEqual(text, "hello world!!!")
    }

    @MainActor
    func testJavaScriptCustomActionExplicitOpenClipEffects() async throws {
        let action = CustomAction(
            id: "custom.js_effect",
            title: "Toast JS",
            iconName: "curlybraces",
            type: .javaScript(
                script: "openclip.toast('Executed custom JS', 'success');",
                isAsync: false,
                replaceSelection: false
            )
        )

        let context = ActionContext(
            selection: SelectionContext(text: "some input"),
            match: nil
        )

        let result = try await action.perform(context)
        guard case .toast(let feedback) = result else {
            XCTFail("Expected .toast result, got \(result)")
            return
        }
        XCTAssertEqual(feedback.message, "Executed custom JS")
        XCTAssertEqual(feedback.style, .success)
    }

    @MainActor
    func testJavaScriptCustomActionAsyncPromiseExecution() async throws {
        let action = CustomAction(
            id: "custom.js_async",
            title: "Async JS",
            iconName: "curlybraces",
            type: .javaScript(
                script: "function action(text) { return Promise.resolve('async: ' + text); }",
                isAsync: true,
                replaceSelection: true
            )
        )

        let context = ActionContext(
            selection: SelectionContext(text: "test data"),
            match: nil
        )

        let result = try await action.perform(context)
        guard case .text(let text) = result else {
            XCTFail("Expected .text result, got \(result)")
            return
        }
        XCTAssertEqual(text, "async: test data")
    }

    @MainActor
    func testJavaScriptCustomActionWhenRunnerUnavailable() async throws {
        let savedRunner = CustomActionJSRunnerRegistry.runner
        CustomActionJSRunnerRegistry.runner = nil
        defer { CustomActionJSRunnerRegistry.runner = savedRunner }

        let action = CustomAction(
            id: "custom.js_no_runner",
            title: "No Runner",
            iconName: "curlybraces",
            type: .javaScript(
                script: "return 'fail';",
                isAsync: false,
                replaceSelection: true
            )
        )

        let context = ActionContext(
            selection: SelectionContext(text: "test"),
            match: nil
        )

        let result = try await action.perform(context)
        guard case .toast(let feedback) = result else {
            XCTFail("Expected .toast result, got \(result)")
            return
        }
        XCTAssertEqual(feedback.message, String(localized: "JavaScript runner unavailable"))
        XCTAssertEqual(feedback.style, .error)
    }
}
