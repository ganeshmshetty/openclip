// AIActionsSection.swift
// OpenClip
//
// The AI prompt library as a `Section` of the AI page: the reorderable list, each row a way into
// that prompt's page. This used to be a sub-tab of a 440x480 popover, and editing a preset opened
// a `.sheet` from inside that popover — three layers, to change two text fields.

import SwiftUI

/// Row frames of the AI preset list, keyed by preset id, in the list's coordinate space.
private struct PresetRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Drop handling for the AI preset list. A `DropDelegate` (rather than `dropDestination`) because
/// only this API reports the drag position *continuously*, which is what the insertion bar needs
/// to follow the cursor between rows.
private struct PresetListDropDelegate: DropDelegate {
    let isDraggingActive: () -> Bool
    let gapForLocation: (CGPoint) -> Int
    let onGapChanged: (Int?) -> Void
    let onDrop: (Int) -> Bool

    func dropEntered(info: DropInfo) {
        guard isDraggingActive() else { return }
        onGapChanged(gapForLocation(info.location))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isDraggingActive() else { return nil }
        onGapChanged(gapForLocation(info.location))
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        onGapChanged(nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard isDraggingActive() else { return false }
        return onDrop(gapForLocation(info.location))
    }
}

@MainActor
public struct AIActionsSection: View {
    @ObservedObject private var aiManager = AIServiceManager.shared
    @ObservedObject private var router = SettingsRouter.shared

    /// Frames of the preset rows in the list's own coordinate space, used to turn a drag position
    /// into the gap it would drop into (same rule AppKit's insertion bar follows).
    @State private var presetRowFrames: [String: CGRect] = [:]
    /// The gap a drag is currently over: 0 = above the first row, `count` = below the last.
    @State private var insertionGap: Int? = nil
    /// The preset being dragged, captured at drag start so the drop is resolved synchronously.
    @State private var draggingPresetID: String? = nil

    public init() {}

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(aiManager.presets) { preset in
                    row(preset)

                    if preset.id != aiManager.presets.last?.id {
                        Divider()
                    }
                }
            }
            .coordinateSpace(name: Self.presetListSpace)
            .onPreferenceChange(PresetRowFramePreferenceKey.self) { frames in
                MainActor.assumeIsolated { presetRowFrames = frames }
            }
            .overlay(alignment: .topLeading) { insertionBar }
            .onDrop(of: [.text], delegate: PresetListDropDelegate(
                isDraggingActive: { draggingPresetID != nil },
                gapForLocation: { location in gap(at: location) },
                onGapChanged: { gap in insertionGap = gap },
                onDrop: { gap in
                    defer {
                        insertionGap = nil
                        draggingPresetID = nil
                    }
                    guard let draggedID = draggingPresetID else { return false }
                    aiManager.movePreset(id: draggedID, toGap: gap)
                    return true
                }
            ))

            SettingsDisclosureRow {
                router.push(.aiNewPreset)
            } content: {
                Label("Add Custom AI Action", systemImage: "plus.circle")
                    .foregroundStyle(Color.accentColor)
            }
        } header: {
            HStack {
                Text("AI Actions")
                Spacer()
                Button("Reset Defaults") {
                    aiManager.resetPresetsToDefault()
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        } footer: {
            Text("These appear inside the AI Tools group in the popup bar. Drag to reorder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(!aiManager.isAIEnabled)
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(_ preset: AIActionPreset) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { preset.isEnabled },
                set: { newValue in
                    var updated = preset
                    updated.isEnabled = newValue
                    aiManager.updatePreset(updated)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel(String(localized: "Enable \(preset.title)"))

            // The rest of the row drills into the prompt: the row is the control, the way a
            // System Settings list row is.
            Button {
                router.push(.aiPreset(id: preset.id))
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.title)
                            .font(.system(size: 13, weight: .medium))
                        Text(preset.prompt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit Action Prompt")
        }
        .padding(.vertical, 6)
        // The row is also the drag handle — no grip glyph, matching the Actions outline.
        .background(rowFrameReader(for: preset.id))
        .onDrag {
            draggingPresetID = preset.id
            return NSItemProvider(object: preset.id as NSString)
        } preview: {
            Text(preset.title)
                .font(.system(size: 12, weight: .medium))
                .padding(6)
        }
    }

    // MARK: - Preset Reordering

    private static let presetListSpace = "aiPresetList"

    /// Reports a row's frame in the list's coordinate space (drawn as a clear background, so it
    /// never affects layout).
    private func rowFrameReader(for id: String) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: PresetRowFramePreferenceKey.self,
                value: [id: geo.frame(in: .named(Self.presetListSpace))]
            )
        }
    }

    /// The gap a drag at `location` would drop into, resolved against the current row frames.
    private func gap(at location: CGPoint) -> Int {
        Self.insertionGap(atY: location.y, rowFrames: orderedRowFrames)
    }

    /// Row frames in list order (a row that has not reported its frame yet is skipped).
    private var orderedRowFrames: [CGRect] {
        aiManager.presets.compactMap { presetRowFrames[$0.id] }
    }

    /// Pure gap rule (unit-tested): every row whose midpoint the drag has passed counts, so 0 is
    /// above the first row and `rowFrames.count` is below the last — the same rule AppKit's
    /// insertion bar follows in the Actions outline.
    public static func insertionGap(atY y: CGFloat, rowFrames: [CGRect]) -> Int {
        rowFrames.filter { y > $0.midY }.count
    }

    /// The blue insertion bar, drawn in the gap rather than on a row.
    @ViewBuilder
    private var insertionBar: some View {
        if let insertionGap, let y = Self.insertionY(forGap: insertionGap, rowFrames: orderedRowFrames) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
                .frame(maxWidth: .infinity)
                .offset(y: y - 1)
                .allowsHitTesting(false)
        }
    }

    /// Y position of a gap (unit-tested): the top edge of the row it precedes, or the bottom edge
    /// of the last row for the trailing gap. Nil when there are no rows to sit between.
    public static func insertionY(forGap gap: Int, rowFrames: [CGRect]) -> CGFloat? {
        guard let first = rowFrames.first, let last = rowFrames.last else { return nil }
        if gap <= 0 { return first.minY }
        if gap >= rowFrames.count { return last.maxY }
        return rowFrames[gap].minY
    }
}
