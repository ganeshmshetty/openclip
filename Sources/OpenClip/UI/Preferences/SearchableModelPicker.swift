// SearchableModelPicker.swift
// OpenClip
//
// A model pop-up whose dropdown contains its own search field. The list can be long enough that
// typing in a menu is faster than scanning it, but a separate filter above the picker duplicated
// the control and hid the result the user was choosing.
import SwiftUI

struct SearchableModelPicker: View {
    let title: LocalizedStringKey
    @Binding var selection: String
    let models: [String]
    let customTag: String
    var customTitle: LocalizedStringKey = "Custom…"
    var defaultTag: String? = nil
    var defaultTitle: LocalizedStringKey = "Default"
    var displayName: (String) -> String = { $0 }
    var isEnabled: Bool = true

    @State private var isPresented = false
    @State private var query = ""

    private var filteredModels: [String] {
        let keep: String? = {
            guard !selection.isEmpty, selection != customTag, selection != defaultTag else { return nil }
            return selection
        }()
        return CloudModelCatalog.matching(models, query: query, keeping: keep, label: displayName)
    }

    private var selectedLabel: Text {
        if selection == customTag { return Text(customTitle) }
        if let defaultTag, selection == defaultTag { return Text(defaultTitle) }
        if selection.isEmpty { return Text("Select a model") }
        return Text(verbatim: displayName(selection))
    }

    private var showsNoMatch: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && filteredModels.isEmpty
    }

    private var listHeight: CGFloat {
        let rows = filteredModels.count + 1 + (defaultTag == nil ? 0 : 1) + (showsNoMatch ? 1 : 0)
        return min(CGFloat(rows) * 28 + 16, 320)
    }

    var body: some View {
        Button {
            query = ""
            isPresented = true
        } label: {
            HStack(spacing: 8) {
                selectedLabel
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 240, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(!isEnabled)
        .accessibilityLabel(Text(title))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                NativeSearchField(
                    text: $query,
                    placeholder: String(localized: "Search models"),
                    controlSize: .small,
                    autoFocus: true
                )
                .padding(8)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if let defaultTag {
                            SearchableModelPickerRow(
                                label: Text(defaultTitle),
                                isSelected: selection == defaultTag
                            ) {
                                choose(defaultTag)
                            }
                        }
                        ForEach(filteredModels, id: \.self) { model in
                            SearchableModelPickerRow(
                                label: Text(verbatim: displayName(model)),
                                isSelected: selection == model
                            ) {
                                choose(model)
                            }
                        }
                        if showsNoMatch {
                            Text("No matching models")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                        }
                        Divider()
                        SearchableModelPickerRow(
                            label: Text(customTitle),
                            isSelected: selection == customTag
                        ) {
                            choose(customTag)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: listHeight)
            }
            .frame(width: 280)
        }
    }

    private func choose(_ value: String) {
        selection = value
        isPresented = false
    }
}

private struct SearchableModelPickerRow: View {
    let label: Text
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                label
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
                .padding(.horizontal, 4)
        )
        .onHover { isHovered = $0 }
    }
}
