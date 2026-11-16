// EditabilityProbe.swift
// OpenClip
//
// App-side seam over OpenSelection's focused-element editability read. Palette and clipboard
// sessions start without a selected text range, so they cannot reuse a selection read to learn
// whether a pasted result would land.
import Core
import OpenSelection

public struct EditabilityProbe: Sendable {
    private let inner: OpenSelection.EditabilityProbe

    public init() {
        self.inner = OpenSelection.EditabilityProbe()
    }

    public func probe() async -> Bool? {
        await inner.probe()
    }
}
