// SettingKey+ResultCard.swift
// OpenClip
//
// The remembered size of the native result card. A presentation-only preference, so it lives in
// the App target next to the other popup chrome keys rather than in Core.
import Core

extension SettingKey where Value == Double {
    /// Width (pt) the user last resized the result card to. `0` (the default) means "never
    /// resized", so the card sizes itself from its content. Written together with
    /// `resultCardHeight` when a resize gesture ends; read once on every entry into content mode.
    static var resultCardWidth: SettingKey<Double> {
        SettingKey<Double>("resultCard.width", defaultValue: 0)
    }

    /// Height (pt) the user last resized the result card to; `0` means "never resized".
    static var resultCardHeight: SettingKey<Double> {
        SettingKey<Double>("resultCard.height", defaultValue: 0)
    }
}
