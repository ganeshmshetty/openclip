// AppServices.swift
// OpenClip
//
// Serves as the UI composition root in the Wiring Door, instantiating and publishing application singletons for SwiftUI views.
import Foundation
import Combine
import Core

@MainActor
public final class AppServices: ObservableObject, Sendable {
    public static let shared = AppServices()

    public let settingsStore: SettingsStore
    public let actionRegistry: ActionRegistry
    public let actionPresentation: ActionPresentation
    public let customizationManager: ActionCustomizationManager

    public init(
        settingsStore: SettingsStore = DefaultSettingsStore.shared,
        actionRegistry: ActionRegistry = .shared,
        actionPresentation: ActionPresentation = .shared,
        customizationManager: ActionCustomizationManager = .shared
    ) {
        self.settingsStore = settingsStore
        self.actionRegistry = actionRegistry
        self.actionPresentation = actionPresentation
        self.customizationManager = customizationManager
    }
}
