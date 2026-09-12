// AIPages.swift
// OpenClip
//
// AI settings as pages of the Actions pane's navigation stack, replacing the 440x480 popover that
// carried the whole AI surface — engine choice, endpoints, API keys, CLI auth, model lists and the
// prompt library — behind a segmented control, with a modal sheet on top of it for editing a
// prompt.
//
// AI Tools ▸ AI Actions ▸ a prompt is a hierarchy, so it is navigated as one.

import SwiftUI

// MARK: - AI Tools

/// Engine + provider settings, with a row that drills into the AI action library.
@MainActor
struct AIConfigurePage: View {
    @ObservedObject private var navigator = SettingsNavigator.shared
    @ObservedObject private var aiManager = AIServiceManager.shared

    var body: some View {
        Form {
            AIConfigureForm(embedded: true)

            Section {
                SettingsDisclosureRow(
                    title: String(localized: "AI Actions"),
                    subtitle: String(localized: "\(aiManager.presets.count) prompts in the AI Tools group")
                ) {
                    navigator.push(.aiActions)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - AI Actions

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
public struct AIActionsPage: View {
    @ObservedObject private var navigator = SettingsNavigator.shared
    @ObservedObject private var aiManager = AIServiceManager.shared

    /// Frames of the preset rows in the list's own coordinate space, used to turn a drag position
    /// into the gap it would drop into (same rule AppKit's insertion bar follows).
    @State private var presetRowFrames: [String: CGRect] = [:]
    /// The gap a drag is currently over: 0 = above the first row, `count` = below the last.
    @State private var insertionGap: Int? = nil
    /// The preset being dragged, captured at drag start so the drop is resolved synchronously.
    @State private var draggingPresetID: String? = nil

    public init() {}

    public var body: some View {
        Form {
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
            } header: {
                HStack {
                    Text("Configured AI Actions")
                    Spacer()
                    Button("Reset Defaults") {
                        aiManager.resetPresetsToDefault()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            } footer: {
                Text("Drag to reorder.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Button {
                    navigator.push(.aiNewPreset)
                } label: {
                    Label("Add Custom AI Action", systemImage: "plus.circle")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

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
            .accessibilityLabel(String(localized: "Enable \(preset.title)"))

            VStack(alignment: .leading, spacing: 2) {
                Text(preset.title)
                    .font(.system(size: 13, weight: .medium))
                Text(preset.prompt)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        // Clicking the row drills into the prompt: the whole row is the control, the way a
        // System Settings list row is.
        .onTapGesture { navigator.push(.aiPreset(id: preset.id)) }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(String(localized: "Edit Action Prompt"))
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

// MARK: - A single prompt

/// Editing one AI prompt. This was a `.sheet` opened from inside the AI popover, so it dimmed the
/// popover, whatever else was still floating, and the window. As a page it is just the next level.
@MainActor
struct AIPresetPage: View {
    let presetID: String

    @ObservedObject private var navigator = SettingsNavigator.shared
    @ObservedObject private var aiManager = AIServiceManager.shared

    @State private var title: String = ""
    @State private var prompt: String = ""
    @State private var loaded = false

    private var preset: AIActionPreset? {
        aiManager.presets.first(where: { $0.id == presetID })
    }

    private var isCustom: Bool {
        !AIServiceManager.defaultPresets.contains(where: { $0.id == presetID })
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Action Title")) {
                    TextField("Title", text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Prompt Instruction")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Prompt instruction...", text: $prompt, axis: .vertical)
                        .lineLimit(4...10)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section {
                HStack {
                    if isCustom {
                        Button("Delete Action", role: .destructive) {
                            deletePreset()
                            navigator.pop()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                    }

                    Spacer()

                    Button("Cancel") { navigator.pop() }

                    Button("Save") {
                        guard var updated = preset else { return }
                        updated.title = title.trimmingCharacters(in: .whitespaces)
                        updated.prompt = prompt.trimmingCharacters(in: .whitespaces)
                        aiManager.updatePreset(updated)
                        navigator.pop()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty
                              || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            guard !loaded, let preset else { return }
            title = preset.title
            prompt = preset.prompt
            loaded = true
        }
    }

    private func deletePreset() {
        var list = aiManager.presets
        list.removeAll(where: { $0.id == presetID })
        aiManager.presets = list
    }
}

/// Adding a prompt, as the next page rather than a sheet over everything.
@MainActor
struct AINewPresetPage: View {
    @ObservedObject private var navigator = SettingsNavigator.shared
    @ObservedObject private var aiManager = AIServiceManager.shared

    @State private var title: String = ""
    @State private var prompt: String = ""

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Action Title")) {
                    TextField("e.g. Simplify", text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Prompt Instruction")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("e.g. Rewrite text using simple 5th-grade vocabulary", text: $prompt, axis: .vertical)
                        .lineLimit(4...10)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section {
                HStack {
                    Spacer()

                    Button("Cancel") { navigator.pop() }

                    Button("Add Action") {
                        aiManager.addCustomPreset(title: title, prompt: prompt)
                        navigator.pop()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty
                              || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Shared row

/// A list row that drills into another page: title, optional subtitle, trailing chevron. The whole
/// row is the hit target, the way System Settings rows are.
struct SettingsDisclosureRow: View {
    let title: String
    var subtitle: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}
