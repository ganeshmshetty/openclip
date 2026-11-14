import XCTest
import AppKit
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
        AppActivationPolicy.resetForTesting()
        super.tearDown()
    }

    func testInteractiveUpdateCleanupRestoresAccessoryAfterRepeatedChecks() async {
        let manager = AppUpdateManager.shared

        manager.beginInteractiveUpdatePresentation()
        manager.beginInteractiveUpdatePresentation()
        XCTAssertEqual(AppActivationPolicy.recordedPolicy, .regular)
        manager.finishInteractiveUpdatePresentation()
        manager.finishInteractiveUpdatePresentation()
        await waitForActivationPolicy(.accessory)
    }

    func testInteractiveUpdateCleanupKeepsOverlappingSettingsActive() async {
        let manager = AppUpdateManager.shared

        manager.beginInteractiveUpdatePresentation()
        AppActivationPolicy.enter() // Settings opens while the update dialog is visible.
        manager.finishInteractiveUpdatePresentation()
        try? await Task.sleep(nanoseconds: 5_000_000)
        XCTAssertEqual(AppActivationPolicy.recordedPolicy, .regular)

        AppActivationPolicy.leave() // Settings then closes.
        await waitForActivationPolicy(.accessory)
    }

    func testInteractiveUpdateCleanupPreservesExistingRegularPolicy() async {
        let manager = AppUpdateManager.shared
        AppActivationPolicy.seedPolicyForTesting(.regular)

        manager.beginInteractiveUpdatePresentation()
        manager.finishInteractiveUpdatePresentation()
        try? await Task.sleep(nanoseconds: 5_000_000)
        XCTAssertEqual(AppActivationPolicy.recordedPolicy, .regular)
    }

    /// The test host is the app itself. The lease must record the requested policy instead of
    /// applying it, or every run leaves OpenClip icons in the Dock.
    func testLeaseRecordsPolicyWithoutChangingTheRealOne() {
        let original = NSApp.activationPolicy()

        AppActivationPolicy.enter()
        XCTAssertEqual(AppActivationPolicy.recordedPolicy, .regular)
        XCTAssertEqual(NSApp.activationPolicy(), original, "a test run must never take a Dock icon")
        AppActivationPolicy.leave()
    }

    private func waitForActivationPolicy(_ expected: NSApplication.ActivationPolicy) async {
        for _ in 0..<20 {
            if AppActivationPolicy.recordedPolicy == expected { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(AppActivationPolicy.recordedPolicy, expected)
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

    func testUpdateChannelPersistsAndSelectsFeed() {
        let manager = AppUpdateManager.shared
        let original = manager.updateChannel

        manager.updateChannel = .beta
        XCTAssertEqual(DefaultSettingsStore.shared.get(.updateChannel), UpdateChannel.beta.rawValue)
        XCTAssertTrue(manager.currentFeedURL.contains("releases/latest"))
        XCTAssertTrue(manager.allowedChannelNames.isEmpty)

        manager.updateChannel = .stable
        XCTAssertEqual(DefaultSettingsStore.shared.get(.updateChannel), UpdateChannel.stable.rawValue)
        XCTAssertTrue(manager.allowedChannelNames.isEmpty)
        XCTAssertTrue(manager.currentFeedURL.contains("releases/latest"))

        manager.updateChannel = original
    }
    func testDevelopmentBuildCannotStartManualOrAutomaticUpdate() {
        let store = MemorySettingsStore()
        let manager = AppUpdateManager(settingsStore: store, bundleIdentifier: "com.openclip.OpenClip.dev")
        XCTAssertFalse(manager.updatesEnabled)
        manager.automaticallyDownloadsUpdates = true
        manager.checkForUpdates()
        manager.installUpdateNow()
        XCTAssertFalse(manager.canPresentUpdate)
        XCTAssertFalse(manager.canCheckForUpdates)
    }

    func testOnlyProductionBundleCanUpdate() {
        XCTAssertTrue(AppUpdateManager.supportsUpdates(bundleIdentifier: "com.openclip.OpenClip"))
        XCTAssertFalse(AppUpdateManager.supportsUpdates(bundleIdentifier: nil))
        XCTAssertFalse(AppUpdateManager.supportsUpdates(bundleIdentifier: "other.app"))
    }

    func testNotificationDeduplicationSurvivesManagerRecreation() {
        let store = MemorySettingsStore()
        let manager = AppUpdateManager(settingsStore: store, bundleIdentifier: "test")
        XCTAssertTrue(manager.shouldNotify(version: "2.0.0"))
        manager.recordNotificationDelivery(version: "2.0.0")
        let relaunched = AppUpdateManager(settingsStore: store, bundleIdentifier: "test")
        XCTAssertFalse(relaunched.shouldNotify(version: "2.0.0"))
        XCTAssertTrue(relaunched.shouldNotify(version: "2.1.0"))
        relaunched.notifyOnUpdate = false
        XCTAssertFalse(relaunched.shouldNotify(version: "2.1.0"))
    }

    func testScheduledReminderClearsOnSessionEnd() {
        let manager = AppUpdateManager(settingsStore: MemorySettingsStore(), bundleIdentifier: "test")
        manager.setAvailableUpdateVersionForTesting("2.0.0")
        manager.handleUpdatePresentation(showsWindow: false, userInitiated: false, version: "2.0.0")
        XCTAssertTrue(manager.hasUpdateReminder)
        manager.standardUserDriverWillFinishUpdateSession()
        XCTAssertFalse(manager.hasUpdateReminder)
        XCTAssertNil(manager.availableUpdateVersion)
    }

    func testManualPresentationDoesNotCreateReminder() {
        let manager = AppUpdateManager(settingsStore: MemorySettingsStore(), bundleIdentifier: "test")
        manager.handleUpdatePresentation(showsWindow: false, userInitiated: true, version: "2.0.0")
        XCTAssertFalse(manager.hasUpdateReminder)
    }

    func testSessionEndPreservesStagedOnQuitUpdate() {
        let manager = AppUpdateManager(settingsStore: MemorySettingsStore(), bundleIdentifier: "test")
        manager.setAvailableUpdateVersionForTesting("2.0.0", isStagedForQuit: true)
        manager.standardUserDriverWillFinishUpdateSession()
        XCTAssertFalse(manager.hasUpdateReminder)
        XCTAssertEqual(manager.availableUpdateVersion, "2.0.0")
        XCTAssertTrue(manager.isUpdateStagedForQuitInstall)
    }

    func testAttentionClearsReminderButKeepsUpdateAccessible() {
        let manager = AppUpdateManager(settingsStore: MemorySettingsStore(), bundleIdentifier: "test")
        manager.setAvailableUpdateVersionForTesting("2.0.0")
        manager.acknowledgeUpdateReminder()
        XCTAssertFalse(manager.hasUpdateReminder)
        XCTAssertEqual(manager.availableUpdateVersion, "2.0.0")
    }

    func testScheduledWindowUsesSharedActivationLease() async {
        let manager = AppUpdateManager(settingsStore: MemorySettingsStore(), bundleIdentifier: "test")
        manager.handleUpdatePresentation(showsWindow: true, userInitiated: false, version: "2.0.0")
        AppActivationPolicy.enter()
        manager.standardUserDriverWillFinishUpdateSession()
        XCTAssertEqual(AppActivationPolicy.recordedPolicy, .regular)
        AppActivationPolicy.leave()
        await waitForActivationPolicy(.accessory)
    }

    func testLateCanceledDeliveryCannotEraseNewerReminderOrHistory() async throws {
        let store = MemorySettingsStore()
        let delivery = SuspendedUpdateNotifications()
        let manager = AppUpdateManager(settingsStore: store, bundleIdentifier: "com.openclip.OpenClip",
                                       notificationClient: delivery.client)
        manager.setAvailableUpdateVersionForTesting("2.0.0")
        manager.postUpdateNotification(version: "2.0.0")
        await delivery.waitForRequests(1)
        manager.setAvailableUpdateVersionForTesting("2.1.0")
        manager.postUpdateNotification(version: "2.1.0")
        await delivery.waitForRequests(2)

        delivery.completeRequest(1)
        await Task.yield()
        delivery.completeRequest(0)
        for _ in 0..<10 { await Task.yield() }

        XCTAssertEqual(store.get(.lastAnnouncedAppUpdateVersion), "2.1.0")
        XCTAssertEqual(delivery.visibleVersions, ["2.1.0"])
        manager.acknowledgeUpdateReminder()
        XCTAssertTrue(delivery.visibleVersions.isEmpty)
    }

    func testAcknowledgementDuringDeliveryPreventsLateReminder() async {
        let store = MemorySettingsStore()
        let delivery = SuspendedUpdateNotifications()
        let manager = AppUpdateManager(settingsStore: store, bundleIdentifier: "com.openclip.OpenClip",
                                       notificationClient: delivery.client)
        manager.setAvailableUpdateVersionForTesting("2.0.0")
        manager.postUpdateNotification(version: "2.0.0")
        await delivery.waitForRequests(1)
        manager.acknowledgeUpdateReminder()
        delivery.completeRequest(0)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(delivery.visibleVersions.isEmpty)
        XCTAssertEqual(store.get(.lastAnnouncedAppUpdateVersion), "")
    }

    func testAcknowledgementAfterRelaunchRemovesPreviouslyDeliveredRequest() {
        let store = MemorySettingsStore()
        store.set(.lastAppUpdateNotificationIdentifier, value: "saved-request")
        let delivery = SuspendedUpdateNotifications()
        let manager = AppUpdateManager(settingsStore: store, bundleIdentifier: "test",
                                       notificationClient: delivery.client)
        manager.acknowledgeUpdateReminder()
        XCTAssertTrue(delivery.removedIdentifiers.contains("saved-request"))
        XCTAssertEqual(store.get(.lastAppUpdateNotificationIdentifier), "")
    }

    func testMenuAutoValidationKeepsDevelopmentUpdateCommandDisabled() throws {
        let store = MemorySettingsStore()
        store.set(.showMenuBarIcon, value: true)
        let controller = StatusBarController(settingsStore: store)
        let item = try XCTUnwrap(controller.updateMenuItem)
        item.isEnabled = true
        XCTAssertEqual(controller.validateMenuItem(item), AppUpdateManager.shared.updatesEnabled)
        controller.rootMenu?.update()
        XCTAssertEqual(item.isEnabled, AppUpdateManager.shared.updatesEnabled)
    }

}

@MainActor
private final class SuspendedUpdateNotifications {
    private struct Request {
        let identifier: String
        let version: String
        let continuation: CheckedContinuation<Void, any Error>
    }
    private var requests: [Request] = []
    private var visible: [String: String] = [:]
    private(set) var removedIdentifiers: Set<String> = []
    var visibleVersions: Set<String> { Set(visible.values) }

    var client: UpdateNotificationClient {
        UpdateNotificationClient(
            authorize: { true },
            add: { identifier, version in
                try await withCheckedThrowingContinuation { continuation in
                    self.requests.append(Request(identifier: identifier, version: version, continuation: continuation))
                }
            },
            remove: { identifiers in
                self.removedIdentifiers.formUnion(identifiers)
                for identifier in identifiers { self.visible.removeValue(forKey: identifier) }
            }
        )
    }

    func waitForRequests(_ count: Int) async {
        for _ in 0..<100 {
            if requests.count >= count { return }
            await Task.yield()
        }
        XCTFail("Notification task did not reach delivery")
    }

    func completeRequest(_ index: Int) {
        guard requests.indices.contains(index) else { return }
        let request = requests[index]
        visible[request.identifier] = request.version
        request.continuation.resume()
    }
}
