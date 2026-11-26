// SettingKey+ClipBasket.swift
// OpenClip
//
// App-target presentation settings for the Clip Basket. Screen placement is a UI concern, so it
// lives here rather than in Core.
import Core

extension SettingKey where Value == String {
    /// Last parked panel position, normalized to the screen's visible frame as "x,y" (0...1).
    static var clipBasketPanelOrigin: SettingKey<String> {
        SettingKey<String>("clipBasket.panelOrigin", defaultValue: "")
    }
}
