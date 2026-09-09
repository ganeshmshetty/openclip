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
    /// Symbol Show Icon mode resolves to for text-glyph builtins (Copy/Cut/Paste) while no
    /// replacement has been picked; nil for actions whose icon is already symbol-representable.
    var textGlyphFallbackSymbol: String? = nil

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
            baseIcon: baseIcon,
            textGlyphFallbackSymbol: textGlyphFallbackSymbol
        )
    }

    /// Preview resolution, mirroring `ActionCustomizationManager.popupIcon`: Show-Text mode swaps the
    /// icon slot for the effective display text (custom title, else the native one); Show-Icon mode
    /// keeps the real icon until a genuinely user-picked replacement symbol exists, falling back to
    /// `textGlyphFallbackSymbol` for text-glyph builtins.
    static func resolvedPreviewIcon(
        displayMode: Int,
        title: String,
        displayTextFallback: String,
        iconSymbol: String,
        initialIconSymbol: String,
        baseIcon: ActionIcon?,
        textGlyphFallbackSymbol: String? = nil
    ) -> ActionIcon {
        if displayMode == 1 {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return .text(trimmed.isEmpty ? displayTextFallback : trimmed)
        }
        if iconSymbol.isEmpty {
            if case .text? = baseIcon, let fallback = textGlyphFallbackSymbol {
                return .symbol(fallback)
            }
            return baseIcon ?? .symbol(Constants.defaultIconSymbol)
        }
        if iconSymbol == initialIconSymbol, let base = baseIcon {
            return base
        }
        return ActionIcon.resolve(from: iconSymbol)
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
            if url.path.hasPrefix(Constants.customIconsDirectory.path) {
                return String(localized: "Custom icon “\(url.lastPathComponent)” — click to change")
            }
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
                        .font(.system(size: 17))
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

// MARK: - Inset Group Card Container

struct InsetGroupCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }
}

// MARK: - Icon Picker Popover

@MainActor
struct IconPickerPopover: View {
    @Binding var selectedIcon: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        IconPickerView(selectedSymbol: $selectedIcon) {
            dismiss()
        }
        .padding(12)
        .frame(width: 360, height: 320)
    }
}

