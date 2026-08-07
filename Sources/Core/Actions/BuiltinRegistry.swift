// BuiltinRegistry.swift
// OpenClip
//
// Constructs and provides the catalog of core AppKit-free builtin actions available in OpenClip.
// Instantiates default actions including text search, definitions, date calculations, and clipboard operations.
import Foundation

/// Core (AppKit-free) builtin actions. AppDelegate appends platform-specific ones.
public enum BuiltinRegistry {
    @MainActor
    public static func makeCoreBuiltins(settingsStore: any SettingsStore = DefaultSettingsStore.shared) -> [any Action] {
        let actions: [any Action] = [
            SearchAction(settingsStore: settingsStore),
            DefineAction(),
            CalendarAction(settingsStore: settingsStore),
            CopyAction(),
            CutAction(),
            PasteAction(),
            CalculateAction(settingsStore: settingsStore)
        ]
        return actions
    }
}
