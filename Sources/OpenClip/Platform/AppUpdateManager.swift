// AppUpdateManager.swift
// OpenClip
//
// Wraps Sparkle's SPUStandardUpdaterController in an ObservableObject manager with @Published
// properties that the status bar menu and General preferences tab can drive. Ed25519-verified updates
// are fetched from the appcast URL in Info.plist (SUFeedURL) — no Apple Developer ID or notarization required.
import Foundation
import Sparkle
import Combine
@preconcurrency import UserNotifications
import Core

@MainActor
public final class AppUpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    public static let shared = AppUpdateManager()

    public static let defaultFeedURL = "https://github.com/ganeshmshetty/openclip/releases/latest/download/appcast.xml"
    public static let updateNotificationCategory = "OPENCLIP_UPDATE_CATEGORY"

    /// Sparkle's standard controller; `startingUpdater: true` enables the background schedule
    /// configured via `SUScheduledCheckInterval` in Info.plist.
    private var controller: SPUStandardUpdaterController!

    /// Set when a newer version has been detected, nil when up to date.
    @Published public private(set) var availableUpdateVersion: String?

    /// KVO-backed published state so SwiftUI views can bind directly.
    @Published public private(set) var canCheckForUpdates = false
    @Published public var automaticallyChecksForUpdates: Bool = false {
        didSet {
            controller?.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    private var cancellables = Set<AnyCancellable>()
    private var lastNotifiedVersion: String?

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates

        // Mirror Sparkle's KVO-observable `canCheckForUpdates` into our @Published property.
        controller.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &cancellables)
    }

    // MARK: - SPUUpdaterDelegate

    public func feedURLString(for updater: SPUUpdater) -> String? {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? Self.defaultFeedURL
    }

    /// Triggers an interactive update check (shows the Sparkle UI).
    public func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Returns the date of the last successful update check, if any.
    public var lastUpdateCheckDate: Date? {
        controller.updater.lastUpdateCheckDate
    }

    public func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString ?? item.versionString
        Log.updates.info("Sparkle found valid update: v\(version, privacy: .public)")
        self.availableUpdateVersion = version
        self.postUpdateNotification(version: version)
    }

    public func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        Log.updates.info("Sparkle: no update found or up to date: \(error.localizedDescription, privacy: .private)")
        self.availableUpdateVersion = nil
    }

    public func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Log.updates.info("Sparkle: no update found or up to date")
        self.availableUpdateVersion = nil
    }

    public func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        self.availableUpdateVersion = nil
    }

    public func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) {
        self.availableUpdateVersion = nil
    }

    public func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        Log.updates.error("Sparkle update error: \(error.localizedDescription, privacy: .private)")
    }

    // MARK: - User Notifications

    private func postUpdateNotification(version: String) {
        guard lastNotifiedVersion != version else { return }
        lastNotifiedVersion = version

        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            var isAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            if settings.authorizationStatus == .notDetermined {
                do {
                    isAuthorized = try await center.requestAuthorization(options: [.alert, .sound])
                } catch {
                    Log.updates.error("Failed to request notification permission for update: \(error.localizedDescription, privacy: .private)")
                }
            }
            guard isAuthorized else { return }

            let content = UNMutableNotificationContent()
            content.title = "OpenClip Update Available"
            content.body = "Version \(version) is available. Click to install the update."
            content.sound = .default
            content.categoryIdentifier = Self.updateNotificationCategory
            content.userInfo = ["type": "app_update", "version": version]

            let request = UNNotificationRequest(
                identifier: "com.openclip.update.available.\(version)",
                content: content,
                trigger: nil
            )
            do {
                try await center.add(request)
            } catch {
                Log.updates.error("Failed to post update notification: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    // MARK: - Testing Hooks

    public func setAvailableUpdateVersionForTesting(_ version: String?) {
        self.availableUpdateVersion = version
    }
}
