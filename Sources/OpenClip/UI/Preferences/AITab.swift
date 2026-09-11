// AITab.swift
// OpenClip
//
// Renders the AI preferences view with top-bar sub-tab switching between AI Engine Configuration and AI Actions Management.
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

public enum AISubTab: String, CaseIterable, Identifiable, Sendable {
    case configure = "Configure"
    case actions = "Actions"
    public var id: String { rawValue }
}

@MainActor
public struct AITab: View {
    @Binding var selectedSubTab: AISubTab
    @ObservedObject private var aiManager = AIServiceManager.shared

    @State private var editingPreset: AIActionPreset? = nil
    @State private var showingAddPresetSheet = false
    /// Frames of the preset rows in the list's own coordinate space, used to turn a drag position
    /// into the gap it would drop into (same rule AppKit's insertion bar follows).
    @State private var presetRowFrames: [String: CGRect] = [:]
    /// The gap a drag is currently over: 0 = above the first row, `count` = below the last.
    @State private var insertionGap: Int? = nil
    /// The preset being dragged, captured at drag start so the drop is resolved synchronously.
    @State private var draggingPresetID: String? = nil
    @State private var newTitle: String = ""
    @State private var newPrompt: String = ""
    
    public init(selectedSubTab: Binding<AISubTab> = .constant(.configure)) {
        self._selectedSubTab = selectedSubTab
    }
    
    public var body: some View {
        Group {
            switch selectedSubTab {
            case .configure:
                AIConfigureForm()
            case .actions:
                actionsView
            }
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
    static func insertionGap(atY y: CGFloat, rowFrames: [CGRect]) -> Int {
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
    static func insertionY(forGap gap: Int, rowFrames: [CGRect]) -> CGFloat? {
        guard let first = rowFrames.first, let last = rowFrames.last else { return nil }
        if gap <= 0 { return first.minY }
        if gap >= rowFrames.count { return last.maxY }
        return rowFrames[gap].minY
    }

    // MARK: - Actions View
    private var actionsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                Section(header: HStack {
                    Text("Configured AI Actions")
                    Spacer()
                    Button("Reset Defaults") {
                        aiManager.resetPresetsToDefault()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(aiManager.presets) { preset in
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

                                Button(action: {
                                    editingPreset = preset
                                }) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Edit Action Prompt")
                                .accessibilityLabel("Edit Action Prompt")

                                if isCustomPreset(preset) {
                                    Button(action: {
                                        deletePreset(preset)
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 13))
                                            .foregroundColor(.red.opacity(0.8))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Delete Custom Action")
                                    .accessibilityLabel("Delete Custom Action")
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            // The row itself is the drag handle — no grip glyph, matching the
                            // Actions outline. The drop is resolved by the whole list below, which
                            // draws the insertion bar in the gap the drag is over.
                            .background(rowFrameReader(for: preset.id))
                            .onDrag {
                                draggingPresetID = preset.id
                                return NSItemProvider(object: preset.id as NSString)
                            } preview: {
                                Text(preset.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .padding(6)
                            }

                            if preset.id != aiManager.presets.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.vertical, 4)
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
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                Button(action: {
                    showingAddPresetSheet = true
                }) {
                    Label("Add Custom AI Action", systemImage: "plus.circle")
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
        }
        .padding(12)
        .sheet(item: $editingPreset) { preset in
            EditAIPresetSheet(
                preset: preset,
                isCustom: isCustomPreset(preset),
                onSave: { updated in
                    aiManager.updatePreset(updated)
                },
                onDelete: {
                    deletePreset(preset)
                }
            )
        }
        .sheet(isPresented: $showingAddPresetSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add Custom AI Action")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Action Title")
                        .font(.caption)
                        .fontWeight(.medium)
                    TextField("e.g. Simplify", text: $newTitle)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Prompt Instruction")
                        .font(.caption)
                        .fontWeight(.medium)
                    TextField("e.g. Rewrite text using simple 5th-grade vocabulary", text: $newPrompt)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Spacer()
                    Button("Cancel") {
                        showingAddPresetSheet = false
                        newTitle = ""
                        newPrompt = ""
                    }
                    Button("Add Action") {
                        aiManager.addCustomPreset(title: newTitle, prompt: newPrompt)
                        showingAddPresetSheet = false
                        newTitle = ""
                        newPrompt = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty || newPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 420)
        }
    }

    private func isCustomPreset(_ preset: AIActionPreset) -> Bool {
        !AIServiceManager.defaultPresets.contains(where: { $0.id == preset.id })
    }

    private func deletePreset(_ preset: AIActionPreset) {
        var list = aiManager.presets
        list.removeAll(where: { $0.id == preset.id })
        aiManager.presets = list
    }
}

struct EditAIPresetSheet: View {
    @Environment(\.dismiss) private var dismiss
    let preset: AIActionPreset
    let isCustom: Bool
    let onSave: (AIActionPreset) -> Void
    let onDelete: () -> Void

    @State private var title: String
    @State private var prompt: String

    init(preset: AIActionPreset, isCustom: Bool, onSave: @escaping (AIActionPreset) -> Void, onDelete: @escaping () -> Void) {
        self.preset = preset
        self.isCustom = isCustom
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: preset.title)
        _prompt = State(initialValue: preset.prompt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit AI Action")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Action Title")
                    .font(.caption)
                    .fontWeight(.medium)
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Prompt Instruction")
                    .font(.caption)
                    .fontWeight(.medium)
                TextField("Prompt instruction...", text: $prompt, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                if isCustom {
                    Button("Delete Action", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                    .foregroundColor(.red)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    var updated = preset
                    updated.title = title.trimmingCharacters(in: .whitespaces)
                    updated.prompt = prompt.trimmingCharacters(in: .whitespaces)
                    onSave(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

/// Modal configuration sheet for AI Tools, opened from the gear icon in the Actions tab.
@MainActor
public struct ConfigureAISheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Set when the editor is shown in the Actions tab's settings popover, which closes itself
    /// only on request; `nil` when it is presented as a sheet.
    @Environment(\.popoverDismiss) private var popoverDismiss
    @State private var selectedSubTab: AISubTab

    public init(initialSubTab: AISubTab = .configure) {
        _selectedSubTab = State(initialValue: initialSubTab)
    }

    private func close() {
        if let popoverDismiss {
            popoverDismiss()
        } else {
            dismiss()
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center) {
                Text(String(localized: "AI Tools"))
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Picker("", selection: $selectedSubTab) {
                    Text(String(localized: "Configure")).tag(AISubTab.configure)
                    Text(String(localized: "Actions")).tag(AISubTab.actions)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)

                Spacer()

                Button(action: { close() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Close"))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            AITab(selectedSubTab: $selectedSubTab)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
        }
        .frame(width: 440, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

