// AppUpdateManager.swift
// OpenClip
//
// Wraps Sparkle's SPUStandardUpdaterController in an ObservableObject manager with @Published
// properties that the status bar menu and General preferences tab can drive. Ed25519-verified updates
// are fetched from the appcast URL in Info.plist (SUFeedURL) — no Apple Developer ID or notarization required.
import Foundation
import Sparkle
import Combine

@MainActor
public final class AppUpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    public static let shared = AppUpdateManager()

    public static let defaultFeedURL = "https://github.com/ganeshmshetty/openclip/releases/latest/download/appcast.xml"

    /// Sparkle's standard controller; `startingUpdater: true` enables the background schedule
    /// configured via `SUScheduledCheckInterval` in Info.plist.
    private var controller: SPUStandardUpdaterController!

    /// KVO-backed published state so SwiftUI views can bind directly.
    @Published public private(set) var canCheckForUpdates = false
    @Published public var automaticallyChecksForUpdates: Bool = false {
        didSet {
            controller?.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    private var cancellables = Set<AnyCancellable>()

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
}
