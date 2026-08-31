// SettingKey+MenuBar.swift
// OpenClip
//
// Defines the AppKit presentation preference for the menu bar status item.
import Core

extension SettingKey where Value == Bool {
    static var showMenuBarIcon: SettingKey<Bool> {
        SettingKey<Bool>("showMenuBarIcon", defaultValue: true)
    }
}
