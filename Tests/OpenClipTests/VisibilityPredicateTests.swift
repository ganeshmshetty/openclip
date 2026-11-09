import XCTest
@testable import Core
@testable import OpenClip

private final class MemoryOptionStore: ActionOptionReading, @unchecked Sendable {
    private var values: [String: String] = [:]

    func stringValue(actionID: String, option: ExtensionOption) -> String {
        values["\(actionID).\(option.identifier)"] ?? (option.defaultValue ?? "")
    }
}

private extension ActionContext {
    init(predicateText: String, bundleID: String = "com.test.app", source: SelectionSource = .selection) {
        let selection = SelectionContext(
            text: predicateText,
            sourceApp: AppIdentity(bundleIdentifier: bundleID, localizedName: "TestApp"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default,
            source: source
        )
        self.init(selection: selection)
    }
}

@MainActor
final class VisibilityPredicateTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        TestIsolation.reset()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        VisibilityPredicateRuntime.shared.invalidate()
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        TestIsolation.reset()
        try await super.tearDown()
    }

    private func makeAction(
        files: [String: String] = [:],
        actionJSON: String = #"{"id":"run","title":"Run","type":"javascript","scriptCode":"return text;"}"#,
        manifestExtras: String = ""
    ) async throws -> any Action {
        let dir = tempDir.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manifest = """
        {"identifier":"com.test.predicate","name":"Predicate","minOpenClipVersion":"1.10.0",\(manifestExtras) "actions":[\(actionJSON)]}
        """
        try manifest.write(to: dir.appendingPathComponent("openclip.json"), atomically: true, encoding: .utf8)
        for (name, contents) in files {
            let url = dir.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        let data = try Data(contentsOf: dir.appendingPathComponent("openclip.json"))
        let decoded = try ExtensionManifestStore.decodeManifest(from: data)
        let factory = DefaultActionFactory(optionStore: MemoryOptionStore())
        let action = await factory.createAction(metadata: decoded.actions[0], manifest: decoded, directoryURL: dir, index: 0)
        return try XCTUnwrap(action)
    }

    func testPredicateTrueAndFalse() async throws {
        let action = try await makeAction(
            files: ["visible.js": "module.exports = function(input) { return input.text === 'yes'; };"],
            actionJSON: #"{"id":"run","title":"Run","type":"javascript","scriptCode":"return text;","requirements":{"predicate":"visible.js"}}"#
        )
        XCTAssertTrue(action.isEnabled(for: ActionContext(predicateText: "yes")))
        XCTAssertFalse(action.isEnabled(for: ActionContext(predicateText: "no")))
    }

    func testPredicateIsANDedWithExistingGates() async throws {
        let action = try await makeAction(
            files: ["visible.js": "module.exports = function(input) { return input.text.length > 2; };"],
            actionJSON: #"{"id":"run","title":"Run","type":"javascript","scriptCode":"return text;","requirements":{"apps":["com.test.app"],"predicate":"visible.js"}}"#
        )
        XCTAssertTrue(action.isEnabled(for: ActionContext(predicateText: "abc", bundleID: "com.test.app")))
        XCTAssertFalse(action.isEnabled(for: ActionContext(predicateText: "abc", bundleID: "com.other.app")))
        XCTAssertFalse(action.isEnabled(for: ActionContext(predicateText: "a", bundleID: "com.test.app")))
    }

    func testPredicateReceivesDetectedContentAndMatchInfo() async throws {
        let js = """
        module.exports = function(input) {
          return input.detected.urls.length === 1
            && input.matchedText === 'https://example.com'
            && input.source === 'selection'
            && input.app === 'com.test.app';
        };
        """
        let action = try await makeAction(
            files: ["visible.js": js],
            actionJSON: #"{"id":"run","title":"Run","type":"javascript","scriptCode":"return text;","requirements":{"regex":"https?://\\S+","content":["url"],"predicate":"visible.js"}}"#
        )
        XCTAssertTrue(action.isEnabled(for: ActionContext(predicateText: "prefix https://example.com suffix")))
        XCTAssertFalse(action.isEnabled(for: ActionContext(predicateText: "prefix plain text suffix")))
    }

    func testPredicateInputIsReadOnly() async throws {
        let action = try await makeAction(
            files: ["visible.js": "module.exports = function(input) { input.text = 'changed'; return input.text === 'original'; };"],
            actionJSON: #"{"id":"run","title":"Run","type":"javascript","scriptCode":"return text;","requirements":{"predicate":"visible.js"}}"#
        )
        XCTAssertTrue(action.isEnabled(for: ActionContext(predicateText: "original")))
    }

    func testPredicateCanRequirePackageLocalHelper() async throws {
        let action = try await makeAction(
            files: [
                "visible.js": "var rules = require('./lib/rules.js'); module.exports = function(input) { return rules.allow(input.text); };",
                "lib/rules.js": "module.exports = { allow: function(text) { return text.length >= 4; } };"
            ],
            actionJSON: #"{"id":"run","title":"Run","type":"javascript","scriptCode":"return text;","requirements":{"predicate":"visible.js"}}"#
        )
        XCTAssertTrue(action.isEnabled(for: ActionContext(predicateText: "four")))
        XCTAssertFalse(action.isEnabled(for: ActionContext(predicateText: "no")))
    }

    func testPredicateErrorsFailOpen() async throws {
        let action = try await makeAction(
            files: ["visible.js": "module.exports = function() { throw new Error('boom'); };"],
            actionJSON: #"{"id":"run","title":"Run","type":"javascript","scriptCode":"return text;","requirements":{"predicate":"visible.js"}}"#
        )
        XCTAssertTrue(action.isEnabled(for: ActionContext(predicateText: "anything")))
    }

    func testPredicateTimeoutFailsOpen() async throws {
        let action = try await makeAction(
            files: ["visible.js": "module.exports = function() { while (true) {} };"],
            actionJSON: #"{"id":"run","title":"Run","type":"javascript","scriptCode":"return text;","requirements":{"predicate":"visible.js"}}"#
        )
        XCTAssertTrue(action.isEnabled(for: ActionContext(predicateText: "anything")))
    }

    func testPredicateTopLevelTimeoutFailsOpen() async throws {
        let action = try await makeAction(
            files: ["visible.js": "while (true) {}"],
            actionJSON: #"{"id":"run","title":"Run","type":"javascript","scriptCode":"return text;","requirements":{"predicate":"visible.js"}}"#
        )
        XCTAssertTrue(action.isEnabled(for: ActionContext(predicateText: "anything")))
    }

    func testNonFunctionPredicateFailsOpen() async throws {
        let action = try await makeAction(
            files: ["visible.js": "module.exports = true;"],
            actionJSON: #"{"id":"run","title":"Run","type":"javascript","scriptCode":"return text;","requirements":{"predicate":"visible.js"}}"#
        )
        XCTAssertTrue(action.isEnabled(for: ActionContext(predicateText: "anything")))
    }

    func testPredicateResultIsMemoizedForThePresentationContext() async throws {
        let action = try await makeAction(
            files: ["visible.js": "module.exports = function() { globalThis.n = (globalThis.n || 0) + 1; return globalThis.n === 1; };"],
            actionJSON: #"{"id":"run","title":"Run","type":"javascript","scriptCode":"return text;","requirements":{"predicate":"visible.js"}}"#
        )
        let context = ActionContext(predicateText: "anything")
        XCTAssertTrue(action.isEnabled(for: context))
        XCTAssertTrue(action.isEnabled(for: context))
        XCTAssertFalse(action.isEnabled(for: ActionContext(predicateText: "fresh")))
    }

    func testPredicateMakesActionContextualByDefault() async throws {
        let action = try await makeAction(
            files: ["visible.js": "module.exports = function() { return true; };"],
            actionJSON: #"{"id":"run","title":"Run","type":"javascript","scriptCode":"return text;","requirements":{"predicate":"visible.js"}}"#
        )
        XCTAssertTrue(action.isContextual)
    }

    func testExplicitContextualFalseWinsOverNarrowingRequirement() async throws {
        let action = try await makeAction(
            files: ["visible.js": "module.exports = function() { return true; };"],
            actionJSON: #"{"id":"run","title":"Run","type":"javascript","scriptCode":"return text;","contextual":false,"requirements":{"apps":["com.test.app"],"predicate":"visible.js"}}"#
        )
        XCTAssertFalse(action.isContextual)
    }

    func testExplicitContextualTrueWorksWithoutRequirements() async throws {
        let action = try await makeAction(
            actionJSON: #"{"id":"run","title":"Run","type":"javascript","scriptCode":"return text;","contextual":true}"#
        )
        XCTAssertTrue(action.isContextual)
    }

    func testRequiredOptionsAloneDoesNotMakeActionContextual() async throws {
        let action = try await makeAction(
            actionJSON: #"{"id":"run","title":"Run","type":"javascript","scriptCode":"return text;","requirements":{"requiredOptions":["mode"]}}"#
        )
        XCTAssertFalse(action.isContextual)
    }

    func testAppsRequirementMakesActionContextual() async throws {
        let action = try await makeAction(
            actionJSON: #"{"id":"run","title":"Run","type":"javascript","scriptCode":"return text;","requirements":{"apps":["com.test.app"]}}"#
        )
        XCTAssertTrue(action.isContextual)
    }

    func testPredicateOnGroupRowKeepsSubActionsResolvable() async throws {
        let dir = tempDir.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manifestJSON = """
        {"identifier":"com.test.group","name":"Group","minOpenClipVersion":"1.10.0","actions":[
          {"id":"group","title":"Group","type":"group","requirements":{"predicate":"visible.js"},"subActions":[
            {"id":"sub","title":"Sub","type":"javascript","scriptCode":"return text;"}
          ]}
        ]}
        """
        try manifestJSON.write(to: dir.appendingPathComponent("openclip.json"), atomically: true, encoding: .utf8)
        try "module.exports = function() { return true; };"
            .write(to: dir.appendingPathComponent("visible.js"), atomically: true, encoding: .utf8)

        let data = try Data(contentsOf: dir.appendingPathComponent("openclip.json"))
        let manifest = try ExtensionManifestStore.decodeManifest(from: data)
        let factory = DefaultActionFactory(optionStore: MemoryOptionStore())
        let actions = await factory.createActions(metadata: manifest.actions[0], manifest: manifest, directoryURL: dir, index: 0)
        let group = try XCTUnwrap(actions.first { $0.id == "com.test.group.group" })
        let subs = SubActionResolver().subActions(of: group, in: actions)
        XCTAssertEqual(subs.map(\.id), ["com.test.group.group.sub"])
        XCTAssertTrue(group.isEnabled(for: ActionContext(predicateText: "anything")))
    }
}
