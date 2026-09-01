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
}
