import XCTest
@testable import Core
@testable import OpenClip

/// Exercises the composite `KeychainActionOptionStore` against the real macOS Keychain: secrets go
/// to Keychain and never to UserDefaults; non-secrets round-trip through SettingsStore. Every
/// account written is deleted in tearDown, and each run uses a unique actionID prefix so accounts
/// never collide across runs.
final class KeychainActionOptionStoreTests: XCTestCase {
    private var store: KeychainActionOptionStore!
    private let actionIDPrefix = "com.test.keychain.\(UUID().uuidString)"

    private var writtenAccounts: [String] = []
    private var writtenDefaultsKeys: [String] = []

    private func actionID(_ suffix: String) -> String { "\(actionIDPrefix).\(suffix)" }

    private func secretOption(_ id: String, defaultValue: String? = nil) -> ExtensionOption {
        ExtensionOption(identifier: id, label: id, type: .secret, defaultValue: defaultValue)
    }

    private func stringOption(_ id: String, defaultValue: String? = nil) -> ExtensionOption {
        ExtensionOption(identifier: id, label: id, type: .string, defaultValue: defaultValue)
    }

    private func account(for actionID: String, option: ExtensionOption) -> String {
        ActionOptionKey.keychainAccount(actionID: actionID, optionID: option.identifier)
    }

    override func setUp() {
        super.setUp()
        store = KeychainActionOptionStore()
        writtenAccounts = []
        writtenDefaultsKeys = []
    }

    override func tearDown() {
        for account in writtenAccounts {
            _ = KeychainStore.delete(account: account)
        }
        for key in writtenDefaultsKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        writtenAccounts = []
        writtenDefaultsKeys = []
        super.tearDown()
    }

    func testSecretWritesToKeychainAndNeverUserDefaults() {
        let option = secretOption("apiKey")
        let aid = actionID("writeSecret")
        let account = account(for: aid, option: option)
        writtenAccounts.append(account)

        store.setStringValue("supersecret", actionID: aid, option: option)

        XCTAssertEqual(KeychainStore.get(account: account), "supersecret")
        XCTAssertNil(
            UserDefaults.standard.string(forKey: ActionOptionKey.defaultsKey(actionID: aid, optionID: option.identifier)),
            "Secret option values must never be stored in UserDefaults"
        )
    }

    func testUnsetSecretReadsDefaultValue() {
        let withDefault = secretOption("withDefault", defaultValue: "fallback")
        XCTAssertEqual(store.stringValue(actionID: actionID("unset1"), option: withDefault), "fallback")

        let withoutDefault = secretOption("withoutDefault")
        XCTAssertEqual(store.stringValue(actionID: actionID("unset2"), option: withoutDefault), "")
    }

    func testEmptySetAndClearDeleteKeychainEntry() {
        let option = secretOption("apiKey")
        let aid = actionID("clearSecret")
        let account = account(for: aid, option: option)
        writtenAccounts.append(account)

        store.setStringValue("v", actionID: aid, option: option)
        XCTAssertEqual(KeychainStore.get(account: account), "v")

        store.setStringValue("", actionID: aid, option: option)
        XCTAssertNil(KeychainStore.get(account: account), "Empty secret value should delete the Keychain entry")

        store.setStringValue("v2", actionID: aid, option: option)
        XCTAssertEqual(KeychainStore.get(account: account), "v2")

        store.clearValue(actionID: aid, option: option)
        XCTAssertNil(KeychainStore.get(account: account), "clearValue should delete the Keychain entry")
    }

    func testNonSecretRoundTripsThroughSettingsStore() {
        let option = stringOption("prefix", defaultValue: "DEFAULT")
        let aid = actionID("nonSecret")
        let defaultsKey = ActionOptionKey.defaultsKey(actionID: aid, optionID: option.identifier)
        writtenDefaultsKeys.append(defaultsKey)

        XCTAssertEqual(store.stringValue(actionID: aid, option: option), "DEFAULT")
        store.setStringValue("SET", actionID: aid, option: option)
        XCTAssertEqual(store.stringValue(actionID: aid, option: option), "SET")
        store.clearValue(actionID: aid, option: option)
        XCTAssertEqual(store.stringValue(actionID: aid, option: option), "DEFAULT")
    }

    /// Exit criterion: no legacy UserDefaults→Keychain migration/scrub path. Even a stale UserDefaults
    /// value under the secret's defaults key must NOT be read, migrated, or scrubbed into the Keychain.
    func testSecretHasNoUserDefaultsReadOrMigrationFallback() {
        let option = secretOption("apiKey", defaultValue: "DEFAULT")
        let aid = actionID("noFallback")
        let defaultsKey = ActionOptionKey.defaultsKey(actionID: aid, optionID: option.identifier)
        UserDefaults.standard.set("stale-legacy-secret", forKey: defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

        XCTAssertEqual(
            store.stringValue(actionID: aid, option: option), "DEFAULT",
            "Secret reads must not fall back to UserDefaults"
        )
        XCTAssertNil(
            KeychainStore.get(account: account(for: aid, option: option)),
            "No legacy UserDefaults secret should be migrated into the Keychain"
        )
    }
}
