import XCTest
@testable import Core
@testable import OpenClip

/// Regression coverage for issue #42: reverting `cloudAPIKey` after a failed `SecretStore` write
/// must not re-enter the `didSet` observer. When persisting both the new value and the reverted old
/// value fails, the naive revert ping-pongs and exhausts the stack.
@MainActor
final class AIServiceManagerPersistenceTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        SecretStore.setFileURLForTesting(tempDir.appendingPathComponent("secrets.json"))
    }

    override func tearDown() async throws {
        // Clear the in-memory singleton while the test store is still installed (whether it works or
        // not), then restore the real store location so later suites never touch the test path.
        AIServiceManager.shared.cloudAPIKey = ""
        SecretStore.setFileURLForTesting(Constants.secretsFileURL)
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    func testFailedPersistenceRevertsWithoutRecursing() throws {
        let manager = AIServiceManager.shared
        manager.cloudAPIKey = "old-key"
        XCTAssertEqual(manager.cloudAPIKey, "old-key")

        // Point the store at a path whose parent is a regular file, so every write fails at open().
        let blocker = tempDir.appendingPathComponent("blocker")
        try Data("not a directory".utf8).write(to: blocker)
        SecretStore.setFileURLForTesting(blocker.appendingPathComponent("secrets.json"))

        manager.cloudAPIKey = "new-key"

        XCTAssertEqual(manager.cloudAPIKey, "old-key", "A failed write must revert to the previous value, not recurse")
    }
}
