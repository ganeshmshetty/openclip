import XCTest
import Combine
@testable import OpenClip
@testable import Core

@MainActor
final class AppUpdateManagerTests: XCTestCase {
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        TestIsolation.reset()
        cancellables.removeAll()
        AppUpdateManager.shared.setAvailableUpdateVersionForTesting(nil)
    }

    override func tearDown() {
        AppUpdateManager.shared.setAvailableUpdateVersionForTesting(nil)
        cancellables.removeAll()
        super.tearDown()
    }

    func testAvailableUpdateVersionPublishing() {
        let manager = AppUpdateManager.shared
        XCTAssertNil(manager.availableUpdateVersion)

        var publishedValues: [String?] = []
        let exp = expectation(description: "Publishes 1.2.0 update version")

        let sub = manager.$availableUpdateVersion
            .dropFirst() // Drop the initial nil
            .sink { val in
                publishedValues.append(val)
                if val == "1.2.0" {
                    exp.fulfill()
                }
            }

        manager.setAvailableUpdateVersionForTesting("1.2.0")
        waitForExpectations(timeout: 1.0)
        sub.cancel()

        XCTAssertEqual(publishedValues, ["1.2.0"])
        XCTAssertEqual(manager.availableUpdateVersion, "1.2.0")
    }

    func testClearAvailableUpdateVersion() {
        let manager = AppUpdateManager.shared
        manager.setAvailableUpdateVersionForTesting("2.0.0")
        XCTAssertEqual(manager.availableUpdateVersion, "2.0.0")

        manager.setAvailableUpdateVersionForTesting(nil)
        XCTAssertNil(manager.availableUpdateVersion)
    }

    func testStatusBarControllerUpdatesMenuItemWhenUpdateAvailable() async {
        let store = MemorySettingsStore()
        store.set(.showMenuBarIcon, value: true)
        let controller = StatusBarController(settingsStore: store)
        XCTAssertEqual(controller.updateMenuItemTitle, "Check for Updates…")

        AppUpdateManager.shared.setAvailableUpdateVersionForTesting("1.5.0")
        for _ in 0..<20 {
            if controller.updateMenuItemTitle == "Update Available (v1.5.0)…" { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(controller.updateMenuItemTitle, "Update Available (v1.5.0)…")

        AppUpdateManager.shared.setAvailableUpdateVersionForTesting(nil)
        for _ in 0..<20 {
            if controller.updateMenuItemTitle == "Check for Updates…" { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(controller.updateMenuItemTitle, "Check for Updates…")
    }

    func testAvailableUpdateWithReleaseNotesAndStagedForQuit() {
        let manager = AppUpdateManager.shared
        manager.setAvailableUpdateVersionForTesting("1.6.0", releaseNotes: "### Features\n- Great feature", isStagedForQuit: true)

        XCTAssertEqual(manager.availableUpdateVersion, "1.6.0")
        XCTAssertEqual(manager.availableUpdateReleaseNotes, "### Features\n- Great feature")
        XCTAssertTrue(manager.isUpdateStagedForQuitInstall)

        manager.setAvailableUpdateVersionForTesting(nil)
        XCTAssertNil(manager.availableUpdateVersion)
        XCTAssertNil(manager.availableUpdateReleaseNotes)
        XCTAssertFalse(manager.isUpdateStagedForQuitInstall)
    }

    func testStatusBarControllerUpdatesMenuItemWhenUpdateStagedForQuit() async {
        let store = MemorySettingsStore()
        store.set(.showMenuBarIcon, value: true)
        let controller = StatusBarController(settingsStore: store)

        AppUpdateManager.shared.setAvailableUpdateVersionForTesting("1.7.0", isStagedForQuit: true)
        for _ in 0..<20 {
            if controller.updateMenuItemTitle == "Update Ready on Quit (v1.7.0)…" { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(controller.updateMenuItemTitle, "Update Ready on Quit (v1.7.0)…")

        AppUpdateManager.shared.setAvailableUpdateVersionForTesting(nil)
    }

    func testUpdateSettingKeysPersistence() {
        let manager = AppUpdateManager.shared
        let originalCheck = manager.automaticallyChecksForUpdates
        let originalDownload = manager.automaticallyDownloadsUpdates
        let originalNotify = manager.notifyOnUpdate

        manager.automaticallyChecksForUpdates = false
        XCTAssertFalse(DefaultSettingsStore.shared.get(.automaticallyChecksForUpdates))
        XCTAssertFalse(DefaultSettingsStore.shared.get(.automaticallyDownloadsUpdates))

        manager.automaticallyDownloadsUpdates = true
        XCTAssertTrue(DefaultSettingsStore.shared.get(.automaticallyDownloadsUpdates))
        XCTAssertTrue(manager.automaticallyChecksForUpdates)
        XCTAssertTrue(DefaultSettingsStore.shared.get(.automaticallyChecksForUpdates))

        manager.automaticallyDownloadsUpdates = false
        XCTAssertFalse(DefaultSettingsStore.shared.get(.automaticallyDownloadsUpdates))
        XCTAssertTrue(manager.automaticallyChecksForUpdates)

        manager.notifyOnUpdate = false
        XCTAssertFalse(DefaultSettingsStore.shared.get(.notifyOnUpdate))

        // Restore
        manager.automaticallyChecksForUpdates = originalCheck
        manager.automaticallyDownloadsUpdates = originalDownload
        manager.notifyOnUpdate = originalNotify
    }
}
