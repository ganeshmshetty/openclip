// ActionAppearanceFields.swift
// OpenClip
//
// Provides reusable SwiftUI form controls for customizing action titles, icon symbols, and display modes.
// The name field and icon picker share one row so the icon control stays compact. The preview mirrors what
// the popup bar will render: in Show-Text mode it shows the effective display text; otherwise it renders
// the action's real icon (package file, remote image, or text glyph) until the user picks a replacement.
import SwiftUI
import Core

/// Reusable appearance configuration form fields for Action Name + Icon (one row) and Display Mode (Icon vs Text).
struct ActionAppearanceFields: View {
    @Binding var title: String
    /// Native action title used when the name field is empty in Show-Text mode (matches what
    /// saving persists as the display text).
    let displayTextFallback: String
    @Binding var iconSymbol: String
    /// Symbol the field was seeded with ("" when the action's real icon is not symbol-representable);
    /// used to tell a user-picked symbol apart from the untouched baseline.
    let initialIconSymbol: String
    /// The action's effective current icon (.local/.url/.text/.symbol) shown until the user picks a
    /// replacement; nil when the baseline is already fully described by `iconSymbol`.
    let baseIcon: ActionIcon?
    @Binding var displayMode: Int // 0 = Show Icon, 1 = Show Text

    @State private var showingIconPicker = false

    /// What the icon preview should render right now (same resolution the popup bar applies).
    private var previewIcon: ActionIcon {
        Self.resolvedPreviewIcon(
            displayMode: displayMode,
            title: title,
            displayTextFallback: displayTextFallback,
            iconSymbol: iconSymbol,
            initialIconSymbol: initialIconSymbol,
            baseIcon: baseIcon
        )
    }

    /// Preview resolution, mirroring `ActionCustomizationManager.popupIcon`: Show-Text mode swaps the
    /// icon slot for the effective display text (custom title, else the native one); Show-Icon mode
    /// keeps the real icon until a genuinely user-picked replacement symbol exists.
    static func resolvedPreviewIcon(
        displayMode: Int,
        title: String,
        displayTextFallback: String,
        iconSymbol: String,
        initialIconSymbol: String,
        baseIcon: ActionIcon?
    ) -> ActionIcon {
        if displayMode == 1 {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return .text(trimmed.isEmpty ? displayTextFallback : trimmed)
        }
        if iconSymbol.isEmpty {
            return baseIcon ?? .symbol(Constants.defaultIconSymbol)
        }
        if iconSymbol == initialIconSymbol, let base = baseIcon {
            return base
        }
        return .symbol(iconSymbol)
    }

    /// Long display texts would stretch the compact picker button, so they render as a capped label;
    /// everything else goes through ActionIconView like the popup does.
    @ViewBuilder
    private var previewContent: some View {
        if case .text(let text) = previewIcon, text.count > 2 {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 2)
                .frame(maxWidth: 84)
                .frame(height: 20)
        } else {
            ActionIconView(icon: previewIcon, size: 20)
                .frame(width: 20, height: 20)
        }
    }

    private var iconButtonHelp: String {
        switch previewIcon {
        case .symbol(let name):
            return name.isEmpty ? "Choose icon" : name
        case .text(let text):
            if displayMode == 1 {
                return "Popup bar shows “\(text)” — click to choose the icon for icon mode"
            }
            return "Text glyph “\(text)” — click to replace with an icon"
        case .url:
            return "Remote image — click to replace with an icon"
        case .local(let url):
            return "Package image “\(url.lastPathComponent)” — click to replace with an icon"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Name + Icon on one axis so the icon control hugs its content instead of stretching full width
            VStack(alignment: .leading, spacing: 6) {
                Text("Action Name & Icon")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    TextField("Action Name", text: $title)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        showingIconPicker.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            previewContent
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
                    .fixedSize()
                    .help(iconButtonHelp)
                    .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                        IconPickerPopover(selectedIcon: $iconSymbol)
                    }
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
