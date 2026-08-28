// AppLaunchClassifierTests.swift
// OpenClipTests
//
// Tests for AppLaunchClassifier ensuring accurate classification of first install,
// app update, reinstall/permission recovery, and normal launch flows.
import XCTest
import Core

final class AppLaunchClassifierTests: XCTestCase {

    func testFirstInstallWhenOnboardingNotCompleted() {
        let scenario = AppLaunchClassifier.classify(
            lastRunVersion: "",
            currentVersion: "1.1.0",
            hasCompletedOnboarding: false,
            isAccessibilityGranted: false
        )
        XCTAssertEqual(scenario, .firstInstall)
    }

    func testFirstInstallWhenLastRunVersionEmpty() {
        let scenario = AppLaunchClassifier.classify(
            lastRunVersion: "   ",
            currentVersion: "1.1.0",
            hasCompletedOnboarding: true,
            isAccessibilityGranted: true
        )
        XCTAssertEqual(scenario, .firstInstall)
    }

    func testAppUpdateWhenVersionChanges() {
        let scenario = AppLaunchClassifier.classify(
            lastRunVersion: "1.0.0",
            currentVersion: "1.1.0",
            lastRunBuild: "1",
            currentBuild: "2",
            hasCompletedOnboarding: true,
            isAccessibilityGranted: false
        )
        XCTAssertEqual(scenario, .appUpdate(
            previousVersion: "1.0.0",
            currentVersion: "1.1.0",
            previousBuild: "1",
            currentBuild: "2"
        ))
    }

    func testAppUpdateWhenOnlyBuildNumberChanges() {
        // Marketing version unchanged (1.1.0 == 1.1.0), but build number bumped from 3 to 4.
        let scenario = AppLaunchClassifier.classify(
            lastRunVersion: "1.1.0",
            currentVersion: "1.1.0",
            lastRunBuild: "3",
            currentBuild: "4",
            hasCompletedOnboarding: true,
            isAccessibilityGranted: false
        )
        XCTAssertEqual(scenario, .appUpdate(
            previousVersion: "1.1.0",
            currentVersion: "1.1.0",
            previousBuild: "3",
            currentBuild: "4"
        ))
    }

    func testPermissionRecoveryWhenSameVersionAndPermissionMissing() {
        // Simulates reinstalling the same version or user revoking AX in System Settings
        let scenario = AppLaunchClassifier.classify(
            lastRunVersion: "1.1.0",
            currentVersion: "1.1.0",
            lastRunBuild: "3",
            currentBuild: "3",
            hasCompletedOnboarding: true,
            isAccessibilityGranted: false
        )
        XCTAssertEqual(scenario, .permissionRecovery)
    }

    func testNormalLaunchWhenSameVersionAndPermissionGranted() {
        let scenario = AppLaunchClassifier.classify(
            lastRunVersion: "1.1.0",
            currentVersion: "1.1.0",
            lastRunBuild: "3",
            currentBuild: "3",
            hasCompletedOnboarding: true,
            isAccessibilityGranted: true
        )
        XCTAssertEqual(scenario, .normalLaunch)
    }
}
