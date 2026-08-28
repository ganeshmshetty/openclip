// AppLaunchClassifier.swift
// OpenClip
//
// Pure domain classifier that categorizes an application launch into First Install,
// App Update, Permission Recovery, or Normal Launch based on persisted state and current runtime.
import Foundation

public enum AppLaunchScenario: Equatable, Sendable {
    /// Clean first install or install where onboarding has not been completed.
    case firstInstall
    /// The app binary version or build changed (e.g., 1.0.0 -> 1.1.0 or build 1 -> build 2).
    case appUpdate(previousVersion: String, currentVersion: String, previousBuild: String, currentBuild: String)
    /// Same-version reinstall or runtime permission drop where Accessibility is missing.
    case permissionRecovery
    /// Normal launch with active permissions.
    case normalLaunch
}

public struct AppLaunchClassifier: Sendable {
    /// Classifies the launch scenario based on persisted version/build, current bundle version/build,
    /// onboarding completion flag, and current accessibility authorization.
    public static func classify(
        lastRunVersion: String,
        currentVersion: String,
        lastRunBuild: String = "",
        currentBuild: String = "",
        hasCompletedOnboarding: Bool,
        isAccessibilityGranted: Bool
    ) -> AppLaunchScenario {
        let trimmedLastVersion = lastRunVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCurrentVersion = currentVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLastBuild = lastRunBuild.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCurrentBuild = currentBuild.trimmingCharacters(in: .whitespacesAndNewlines)

        // If onboarding has not been completed or no version was ever recorded, it's a first install.
        if !hasCompletedOnboarding || trimmedLastVersion.isEmpty {
            return .firstInstall
        }

        // If marketing version changed or build number changed, it's an app update.
        // Build-only bumps count even for migrated installs where lastRunBuild was never persisted (empty).
        let versionChanged = trimmedLastVersion != trimmedCurrentVersion
        let buildChanged: Bool = {
            guard !trimmedCurrentBuild.isEmpty else { return false }
            if trimmedLastBuild.isEmpty { return true }
            return trimmedLastBuild != trimmedCurrentBuild
        }()

        if versionChanged || buildChanged {
            return .appUpdate(
                previousVersion: trimmedLastVersion,
                currentVersion: trimmedCurrentVersion,
                previousBuild: trimmedLastBuild,
                currentBuild: trimmedCurrentBuild
            )
        }

        // If the same version is running but accessibility permission is missing (e.g. reinstall or revoked).
        if !isAccessibilityGranted {
            return .permissionRecovery
        }

        // Otherwise, standard operational launch.
        return .normalLaunch
    }
}
