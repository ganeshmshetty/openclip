// ActionAppearanceFields.swift
// OpenClip
//
// Provides reusable SwiftUI form controls for customizing action titles, icon symbols, and display modes.
import SwiftUI

/// Reusable appearance configuration form fields for Action Name, Icon Symbol, and Display Mode (Icon vs Text).
struct ActionAppearanceFields: View {
    @Binding var title: String
    @Binding var iconSymbol: String
    @Binding var displayMode: Int // 0 = Show Icon, 1 = Show Text

    @State private var showingIconPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Action Name
            VStack(alignment: .leading, spacing: 6) {
                Text("Action Name")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextField("Action Name", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            // Icon Selection
            VStack(alignment: .leading, spacing: 6) {
                Text("Icon Symbol")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Button {
                    showingIconPicker.toggle()
                } label: {
                    HStack(spacing: 6) {
                        AnyIconView(iconId: iconSymbol.isEmpty ? "star" : iconSymbol)
                            .frame(width: 22, height: 22)
                        Text(iconSymbol.isEmpty ? "Select Icon" : iconSymbol)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help("Choose icon")
                .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                    IconPickerPopover(selectedIcon: $iconSymbol)
                }
            }
            
            Divider()
            
            // Display Preference Picker (Show Icon vs Show Text in Popup Bar)
            VStack(alignment: .leading, spacing: 6) {
                Text("Display Mode in Popup Bar")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Picker("", selection: $displayMode) {
                    Text("Show Icon").tag(0)
                    Text("Show Text").tag(1)
                }
                .pickerStyle(.segmented)
            }
        }
    }
}
