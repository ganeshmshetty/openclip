// BrandColor.swift
// OpenClip
//
// OpenClip's own blue, taken from the marketing site rather than the app icon: getopenclip.app
// uses `#0071e3` and the icon uses `#0084FF`, close but not the same, and the site is what the
// rest of the brand follows (see `docs/dmg.md`).

import SwiftUI

public extension Color {
    /// The brand blue. In the settings sidebar it is reserved for rows OpenClip ships, so a
    /// third-party extension's generated tint can never claim it — see `SettingsTint`.
    static let openClipBrand = Color(red: 0x00 / 255, green: 0x71 / 255, blue: 0xe3 / 255)
}
