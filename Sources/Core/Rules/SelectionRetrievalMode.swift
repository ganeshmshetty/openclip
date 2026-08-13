// SelectionRetrievalMode.swift
// OpenClip
//
// Describes which mechanism should be used to read the current selection from a target
// application. Kebab-case raw values match the JSON emitted/consumed by the browser-script
// bridge and runtime config. Pure Core — no AppKit.
import Foundation

public enum SelectionRetrievalMode: String, Codable, Sendable, CaseIterable {
    case axTextControl = "ax-text-control"
    case axWebArea = "ax-web-area"
    case browserScript = "browser-script"
    case menuCopy = "menu-copy"
    case keyboardCopy = "keyboard-copy"
}