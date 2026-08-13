// PasteRequiringAction.swift
// OpenClip
//
// Marks actions that can only perform when the frontmost target app supports Paste (its Edit ▸
// Paste menu item is enabled): the built-in Paste and Cut actions. The popup hides these actions
// from the bar and search palette while the paste-availability probe confirms the target cannot
// paste. Core is pure — the protocol carries no behavior; the platform probe lives in the App
// target and the gating is a presentation-layer filter.
import Foundation

/// An action that requires the target app to support Paste. Popup-level gating hides it when the
/// paste-availability probe reports `false`.
public protocol PasteRequiringAction {}