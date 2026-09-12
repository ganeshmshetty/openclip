// AIActionsSection.swift
// OpenClip
//
// The AI action library as a `Section` of the AI preferences pane: the reorderable preset list,
// with editing and adding done *in place* in the row.
//
// This used to be a sub-tab of a 440x480 popover, and editing a preset opened a `.sheet` from
// inside that popover — a modal that dimmed the popover, the second popover that was often still
// open behind it, and the Preferences window, three layers at once, to change two text fields.
// Expanding the row costs one layer and keeps the list the edit belongs to on screen.

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

    /// Frames of the preset rows in the list's own coordinate space, used to turn a drag position
    /// into the gap it would drop into (same rule AppKit's insertion bar follows).
    @State private var presetRowFrames: [String: CGRect] = [:]
    /// The gap a drag is currently over: 0 = above the first row, `count` = below the last.
    @State private var insertionGap: Int? = nil
    /// The preset being dragged, captured at drag start so the drop is resolved synchronously.
    @State private var draggingPresetID: String? = nil

    /// The row currently expanded into its editor, and the draft it is editing. Only one row edits
    /// at a time, so the drafts are plain state rather than a per-row dictionary.
    @State private var editingPresetID: String? = nil
    @State private var draftTitle: String = ""
    @State private var draftPrompt: String = ""

    @State private var isAdding = false
    @State private var newTitle: String = ""
    @State private var newPrompt: String = ""

    public init() {}

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(aiManager.presets) { preset in
                    presetRow(preset)

                    if preset.id != aiManager.presets.last?.id {
                        Divider()
                    }
                }

                if isAdding {
                    Divider()
                    addRow
                } else {
                    Divider()
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            editingPresetID = nil
                            isAdding = true
                        }
                    } label: {
                        Label("Add Custom AI Action", systemImage: "plus.circle")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .padding(.vertical, 8)
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
        } header: {
            HStack {
                Text("AI Actions")
                Spacer()
                Button("Reset Defaults") {
                    aiManager.resetPresetsToDefault()
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
        } footer: {
            Text("These appear inside the AI Tools group in the popup bar. Drag to reorder.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func presetRow(_ preset: AIActionPreset) -> some View {
        let isEditing = editingPresetID == preset.id

        VStack(alignment: .leading, spacing: 0) {
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
                .accessibilityLabel(String(localized: "Enable \(preset.title)"))

                Text(preset.title)
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                // A disclosure chevron rather than a pencil: the editor opens *here*, and the
                // control says so.
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if isEditing {
                            editingPresetID = nil
                        } else {
                            isAdding = false
                            draftTitle = preset.title
                            draftPrompt = preset.prompt
                            editingPresetID = preset.id
                        }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isEditing ? 90 : 0))
                }
                .buttonStyle(.plain)
                .help("Edit Action Prompt")
                .accessibilityLabel("Edit Action Prompt")
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            // The row itself is the drag handle — no grip glyph, matching the Actions outline.
            .background(rowFrameReader(for: preset.id))
            .onDrag {
                draggingPresetID = preset.id
                return NSItemProvider(object: preset.id as NSString)
            } preview: {
                Text(preset.title)
                    .font(.system(size: 12, weight: .medium))
                    .padding(6)
            }

            if isEditing {
                presetEditor(preset)
            }
        }
    }

    /// The in-place editor for a preset. Same two fields the modal sheet had, in the row.
    @ViewBuilder
    private func presetEditor(_ preset: AIActionPreset) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledField(title: String(localized: "Action Title")) {
                TextField("Title", text: $draftTitle)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            }

            LabeledField(title: String(localized: "Prompt Instruction")) {
                TextField("Prompt instruction...", text: $draftPrompt, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            }

            HStack {
                if isCustomPreset(preset) {
                    Button("Delete Action", role: .destructive) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            editingPresetID = nil
                            deletePreset(preset)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.red)
                }

                Spacer()

                Button("Cancel") {
                    withAnimation(.easeInOut(duration: 0.18)) { editingPresetID = nil }
                }
                .controlSize(.small)

                Button("Save") {
                    var updated = preset
                    updated.title = draftTitle.trimmingCharacters(in: .whitespaces)
                    updated.prompt = draftPrompt.trimmingCharacters(in: .whitespaces)
                    aiManager.updatePreset(updated)
                    withAnimation(.easeInOut(duration: 0.18)) { editingPresetID = nil }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(draftTitle.trimmingCharacters(in: .whitespaces).isEmpty
                          || draftPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.leading, 34)
        .padding(.bottom, 10)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var addRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledField(title: String(localized: "Action Title")) {
                TextField("e.g. Simplify", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            }

            LabeledField(title: String(localized: "Prompt Instruction")) {
                TextField("e.g. Rewrite text using simple 5th-grade vocabulary", text: $newPrompt, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    withAnimation(.easeInOut(duration: 0.18)) { isAdding = false }
                    newTitle = ""
                    newPrompt = ""
                }
                .controlSize(.small)

                Button("Add Action") {
                    aiManager.addCustomPreset(title: newTitle, prompt: newPrompt)
                    withAnimation(.easeInOut(duration: 0.18)) { isAdding = false }
                    newTitle = ""
                    newPrompt = ""
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty
                          || newPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.vertical, 10)
        .transition(.opacity.combined(with: .move(edge: .top)))
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

    // MARK: - Presets

    private func isCustomPreset(_ preset: AIActionPreset) -> Bool {
        !AIServiceManager.defaultPresets.contains(where: { $0.id == preset.id })
    }

    private func deletePreset(_ preset: AIActionPreset) {
        var list = aiManager.presets
        list.removeAll(where: { $0.id == preset.id })
        aiManager.presets = list
    }
}

/// Caption-above-control pairing used by the in-place editors.
struct LabeledField<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            content()
        }
    }
}
