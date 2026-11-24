// MenuItemImageVisibility.swift
// OpenClip
//
// Opts AppKit menu items back into showing their image on macOS 27, where AppKit hides images for apps linked against the 27 SDK.
import AppKit

extension NSMenuItem {
    func preferVisibleImage() {
        guard image != nil else { return }
        if #available(macOS 27.0, *) {
            preferredImageVisibility = .visible
        }
    }
}
