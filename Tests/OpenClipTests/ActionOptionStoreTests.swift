import XCTest
@testable import Core
@testable import OpenClip

/// In-memory option store for tests; never touches UserDefaults. All calls happen on the
/// MainActor in these tests, so the plain dictionary is safe.
private final class MemoryOptionStore: ActionOptionReading, ActionOptionWriting, @unchecked Sendable {
    private var values: [String: String] = [:]

    func stringValue(actionID: String, option: ExtensionOption) -> String {
        let name = SettingKey.actionOption(actionID: actionID, optionID: option.identifier).name
        return values[name] ?? (option.defaultValue ?? "")
    }

    func setStringValue(_ value: String, actionID: String, option: ExtensionOption) {
        values[SettingKey.actionOption(actionID: actionID, optionID: option.identifier).name] = value
    }

    func clearValue(actionID: String, option: ExtensionOption) {
        values[SettingKey.actionOption(actionID: actionID, optionID: option.identifier).name] = ""
    }
}

private extension ActionContext {
    init(selectedText: String) {
        let policy = AppPolicyContext(
            denyFormatting: false,
            denyProbe: false,
            denyPreprobe: false,
            assumePaste: false
        )
        let selection = SelectionContext(
            text: selectedText,
            sourceApp: AppIdentity(bundleIdentifier: "com.openclip.tests", localizedName: "OpenClipTests"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: policy
        )
        self.init(selection: selection)
    }
}

@MainActor
final class ActionOptionStoreTests: XCTestCase {
    private let jsScript = "function action(text, options) { return (options.prefix || '') + text.toUpperCase(); }"

    func testJavaScriptActionUsesInjectedOptionStoreValue() async throws {
        let option = ExtensionOption(identifier: "prefix", label: "Prefix", type: .string, defaultValue: "DEFAULT: ")
        let store = MemoryOptionStore()
        let action = JavaScriptAction(
            id: "com.test.prefix",
            title: "Prefix",
            iconSymbol: "textformat",
            scriptCode: jsScript,
            options: [option],
            optionStore: store
        )
        store.setStringValue("CUSTOM: ", actionID: action.id, option: option)

        let result = try await action.perform(ActionContext(selectedText: "hello"))
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy result, got \(result)")
        }
        XCTAssertEqual(text, "CUSTOM: HELLO")
    }

    func testJavaScriptActionFallsBackToOptionDefaultWhenUnset() async throws {
        let option = ExtensionOption(identifier: "prefix", label: "Prefix", type: .string, defaultValue: "DEFAULT: ")
        let action = JavaScriptAction(
            id: "com.test.prefix",
            title: "Prefix",
            iconSymbol: "textformat",
            scriptCode: jsScript,
            options: [option],
            optionStore: MemoryOptionStore()
        )

        let result = try await action.perform(ActionContext(selectedText: "hello"))
        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy result, got \(result)")
        }
        XCTAssertEqual(text, "DEFAULT: HELLO")
    }

    func testSettingsActionOptionStoreRoundTripsThroughDefaultSettingsStore() {
        let suiteName = "ActionOptionStoreTests"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create suite UserDefaults")
        }
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsActionOptionStore(store: DefaultSettingsStore(userDefaults: userDefaults))
        let option = ExtensionOption(identifier: "prefix", label: "Prefix", type: .string, defaultValue: "DEFAULT: ")

        XCTAssertEqual(store.stringValue(actionID: "com.test.action", option: option), "DEFAULT: ")

        store.setStringValue("SET: ", actionID: "com.test.action", option: option)
        XCTAssertEqual(store.stringValue(actionID: "com.test.action", option: option), "SET: ")

        store.clearValue(actionID: "com.test.action", option: option)
        XCTAssertEqual(store.stringValue(actionID: "com.test.action", option: option), "DEFAULT: ")
    }
}
