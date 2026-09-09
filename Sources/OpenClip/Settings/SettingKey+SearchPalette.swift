// SettingKey+SearchPalette.swift
// OpenClip
//
// The remembered size of the action-search palette. A presentation-only preference, so it lives
// in the App target next to the result card's keys rather than in Core.
import Core

extension SettingKey where Value == Double {
    /// Width (pt) the user last resized the search palette to. `0` (the default) means "never
    /// resized", so the palette keeps its default column width. Written together with
    /// `searchPaletteHeight` when a resize gesture ends; read once on every entry into search mode.
    static var searchPaletteWidth: SettingKey<Double> {
        SettingKey<Double>("searchPalette.width", defaultValue: 0)
    }

    /// Height (pt) the user last resized the search palette to; `0` means "never resized".
    static var searchPaletteHeight: SettingKey<Double> {
        SettingKey<Double>("searchPalette.height", defaultValue: 0)
    }
}
