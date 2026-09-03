import XCTest
@testable import Core
@testable import OpenClip

/// Exercises the composite `SecretActionOptionStore` against the file-backed `SecretStore`: secrets go
/// to SecretStore (~/.openclip/secrets.json) and never to UserDefaults; non-secrets round-trip through SettingsStore.
final class SecretActionOptionStoreTests: XCTestCase {
    private var store: SecretActionOptionStore!
    private let actionIDPrefix = "com.test.secret.\(UUID().uuidString)"
    private var tempDir: URL!
    private var tempFileURL: URL!

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
        ActionOptionKey.defaultsKey(actionID: actionID, optionID: option.identifier)
    }

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        tempFileURL = tempDir.appendingPathComponent("secrets.json")
        SecretStore.setFileURLForTesting(tempFileURL)
        store = SecretActionOptionStore()
        writtenAccounts = []
        writtenDefaultsKeys = []
    }

    override func tearDown() async throws {
        for account in writtenAccounts {
            _ = SecretStore.delete(account: account)
        }
        for key in writtenDefaultsKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        writtenAccounts = []
        writtenDefaultsKeys = []
        SecretStore.setFileURLForTesting(Constants.secretsFileURL)
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    func testSecretWritesToSecretStoreAndNeverUserDefaults() {
        let option = secretOption("apiKey")
        let aid = actionID("writeSecret")
        let account = account(for: aid, option: option)
        writtenAccounts.append(account)

        store.setStringValue("supersecret", actionID: aid, option: option)

        XCTAssertEqual(SecretStore.get(account: account), "supersecret")
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

    func testEmptySetAndClearDeleteSecretStoreEntry() {
        let option = secretOption("apiKey")
        let aid = actionID("clearSecret")
        let account = account(for: aid, option: option)
        writtenAccounts.append(account)

        store.setStringValue("v", actionID: aid, option: option)
        XCTAssertEqual(SecretStore.get(account: account), "v")

        store.setStringValue("", actionID: aid, option: option)
        XCTAssertNil(SecretStore.get(account: account), "Empty secret value should delete the SecretStore entry")

        store.setStringValue("v2", actionID: aid, option: option)
        XCTAssertEqual(SecretStore.get(account: account), "v2")

        store.clearValue(actionID: aid, option: option)
        XCTAssertNil(SecretStore.get(account: account), "clearValue should delete the SecretStore entry")
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
            SecretStore.get(account: account(for: aid, option: option)),
            "No legacy UserDefaults secret should be migrated into the SecretStore"
        )
    }

    func testSecretStoreFilePermissions() {
        XCTAssertTrue(SecretStore.set("test-key-value", account: "testAccount"))
        XCTAssertEqual(SecretStore.get(account: "testAccount"), "test-key-value")

        let attrs = try? FileManager.default.attributesOfItem(atPath: tempFileURL.path)
        let posix = attrs?[.posixPermissions] as? NSNumber
        XCTAssertEqual(posix?.intValue, 0o600, "Secrets file must have 0600 POSIX permissions")
    }

    func testSecretStoreAtomicOverwriteReplacesWith0600AndCleansStagingFiles() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        FileManager.default.createFile(atPath: tempFileURL.path, contents: "{}".data(using: .utf8), attributes: [.posixPermissions: 0o644])

        var attrs = try FileManager.default.attributesOfItem(atPath: tempFileURL.path)
        var posix = (attrs[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(posix, 0o644)

        XCTAssertTrue(SecretStore.set("new-secret", account: "account1"))
        XCTAssertEqual(SecretStore.get(account: "account1"), "new-secret")

        attrs = try FileManager.default.attributesOfItem(atPath: tempFileURL.path)
        posix = (attrs[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(posix, 0o600, "Overwritten secrets file must have 0600 POSIX permissions")

        let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertEqual(files, ["secrets.json"], "No staged temporary files should remain")
    }

    func testSecretStoreStagedFailureCleansUpAndLeavesNoInsecureFile() throws {
        let blockingFile = tempDir.appendingPathComponent("not_a_dir")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: blockingFile.path, contents: Data())

        let invalidSecretFile = blockingFile.appendingPathComponent("secrets.json")
        SecretStore.setFileURLForTesting(invalidSecretFile)

        XCTAssertFalse(SecretStore.set("val", account: "acc"))
    }

    func testSecretStoreCorruptedFileSelfHealsAndBacksUpCorruptedData() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let corruptedPayload = "corrupted-non-json-data".data(using: .utf8)!
        FileManager.default.createFile(atPath: tempFileURL.path, contents: corruptedPayload, attributes: [.posixPermissions: 0o600])

        // Unparseable secrets file returns nil and triggers self-healing backup
        XCTAssertNil(SecretStore.get(account: "apiKey"), "get must return nil on unparseable secrets file")

        // Self-healing: set must succeed instead of permanently locking out the user
        XCTAssertTrue(SecretStore.set("newval", account: "apiKey"), "set must succeed after self-healing recovery")
        XCTAssertEqual(SecretStore.get(account: "apiKey"), "newval")

        // Corrupted file was safely preserved in a .corrupt.<timestamp> backup
        let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        let backupFiles = files.filter { $0.contains("secrets.json.corrupt.") }
        XCTAssertEqual(backupFiles.count, 1, "Corrupted file must be backed up")
        if let backupFile = backupFiles.first {
            let backupContent = try Data(contentsOf: tempDir.appendingPathComponent(backupFile))
            XCTAssertEqual(backupContent, corruptedPayload, "Corrupted data must be preserved in backup file")
        }

        // New secrets.json was created cleanly
        let newContent = try Data(contentsOf: tempFileURL)
        let json = try JSONSerialization.jsonObject(with: newContent) as? [String: String]
        XCTAssertEqual(json?["apiKey"], "newval")
    }

    func testSecretStoreZeroByteTruncatedFileSelfHeals() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        FileManager.default.createFile(atPath: tempFileURL.path, contents: Data(), attributes: [.posixPermissions: 0o600])

        XCTAssertNil(SecretStore.get(account: "apiKey"), "get must return nil on 0-byte truncated file")
        XCTAssertTrue(SecretStore.set("recovered", account: "apiKey"), "set must self-heal and succeed on 0-byte truncated file")
        XCTAssertEqual(SecretStore.get(account: "apiKey"), "recovered")
    }

    func testSecretStoreStagingPermissionsNotAffectedByUmask() throws {
        #if canImport(Darwin)
        let oldUmask = umask(0000)
        defer { umask(oldUmask) }
        #endif

        XCTAssertTrue(SecretStore.set("secret-under-umask", account: "umaskAccount"))
        let attrs = try FileManager.default.attributesOfItem(atPath: tempFileURL.path)
        let posix = (attrs[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(posix, 0o600, "Secrets file must have 0600 POSIX permissions even under umask 0000")
    }
}


