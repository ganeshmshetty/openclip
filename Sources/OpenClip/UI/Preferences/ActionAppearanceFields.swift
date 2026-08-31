// ActionAppearanceFields.swift
// OpenClip
//
// Provides reusable SwiftUI form controls for customizing action titles, icon symbols, and display modes.
// Follows Approach 2 (Hero Header / Shortcuts style): prominent 48x48 hero icon button on the left,
// action name TextField and [Show Icon | Show Text] segmented control on the right.
import SwiftUI
import Core

/// Reusable appearance configuration form fields: Hero Icon on the left, Title + Display Mode on the right.
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
    @State private var isIconHovered = false

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

    /// Hero icon content sized appropriately for the 48x48 hero button.
    @ViewBuilder
    private var heroIconView: some View {
        if case .text(let text) = previewIcon, text.count > 2 {
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .padding(.horizontal, 4)
        } else {
            ActionIconView(icon: previewIcon, size: 22)
        }
    }

    private var iconButtonHelp: String {
        switch previewIcon {
        case .symbol(let name):
            return name.isEmpty ? String(localized: "Choose icon") : String(localized: "Icon: \(name) — click to change")
        case .text(let text):
            if displayMode == 1 {
                return String(localized: "Popup bar shows “\(text)” — click to choose the icon for icon mode")
            }
            return String(localized: "Text glyph “\(text)” — click to replace with an icon")
        case .url:
            return String(localized: "Remote image — click to replace with an icon")
        case .local(let url):
            return String(localized: "Package image “\(url.lastPathComponent)” — click to replace with an icon")
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Hero Icon Button
            Button {
                showingIconPicker.toggle()
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(isIconHovered ? 0.09 : 0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(isIconHovered ? 0.22 : 0.10), lineWidth: 1)
                        )
                        .frame(width: 48, height: 48)

                    heroIconView
                        .frame(width: 48, height: 48)

                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .background(Circle().fill(Color(nsColor: .windowBackgroundColor)).padding(1))
                        .offset(x: 2, y: 2)
                        .opacity(isIconHovered ? 1.0 : 0.6)
                }
            }
            .buttonStyle(.plain)
            .help(iconButtonHelp)
            .onHover { isIconHovered = $0 }
            .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                IconPickerPopover(selectedIcon: $iconSymbol)
            }

            // Title & Display Mode Controls
            VStack(alignment: .leading, spacing: 8) {
                TextField("Action Name", text: $title)
                    .font(.system(size: 13, weight: .medium))
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    Text("Popup Bar:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("", selection: $displayMode) {
                        Text("Show Icon").tag(0)
                        Text("Show Text").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
                }
            }
        }
        .padding(14)
    }
}
