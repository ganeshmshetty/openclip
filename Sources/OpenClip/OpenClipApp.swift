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
        Settings {
            PreferencesView()
        }
    }
}
