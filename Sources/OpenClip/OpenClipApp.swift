// OpenClipApp.swift
// OpenClip
//
// Defines the SwiftUI App entrypoint and main application scene graph for OpenClip.
import SwiftUI
import AppKit

/// The main entry point for the OpenClip application.
@main
struct OpenClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings{} is kept here so SwiftUI's Cmd+, handling and SettingsLink work
        // correctly. The Dock icon is suppressed by calling
        // NSApp.setActivationPolicy(.accessory) in AppDelegate.applicationDidFinishLaunching,
        // which is the Apple-documented approach for agent apps that need a settings window.
        // hiddenTitleBar is the SwiftUI spelling of fullSizeContentView plus a
        // transparent title bar, which is what lets the sidebar run full height with
        // the traffic lights sitting on it (see StatusBarController.showPreferences,
        // which configures the same thing on the window it opens).
        Settings {
            PreferencesView()
        }
        .windowStyle(.hiddenTitleBar)
    }
}
