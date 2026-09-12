// AIPane.swift
// OpenClip
//
// The AI preferences pane: engine, provider credentials and the AI action library, as one
// top-level sidebar pane.
//
// AI settings used to hang off the gear on the "AI Tools" row of the Actions tab, which opened a
// fixed 440x480 popover with its own segmented sub-tabs — a whole settings window's worth of
// configuration (engine choice, endpoints, API keys, CLI auth, model lists, the prompt library)
// squeezed into a transient container attached to a list row. It is not a per-action setting, so
// it is not presented like one; System Settings gives the same treatment to anything with this
// much surface area (Network, Displays, Keyboard), and Raycast lists AI alongside the other panes.

import SwiftUI

@MainActor
public struct AIPane: View {
    public init() {}

    public var body: some View {
        Form {
            AIConfigureForm(embedded: true)
            AIActionsSection()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
