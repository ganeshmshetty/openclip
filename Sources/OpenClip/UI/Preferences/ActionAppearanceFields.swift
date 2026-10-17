// ActionAppearanceFields.swift
// OpenClip
//
// Provides reusable SwiftUI form controls for customizing action titles, icon symbols, and display modes.
// Follows Approach 2 (Hero Header / Shortcuts style): prominent 48x48 hero icon button on the left,
// action name TextField and [Show Icon | Show Text] segmented control on the right. The hero button
// asks the router for the icon chooser page (see `IconPickerPage`) instead of floating a popover.
import SwiftUI
import Core

/// Reusable appearance configuration form fields: Hero Icon on the left, Title + Display Mode on the right.
struct ActionAppearanceFields: View {
    @Binding var title: String
    /// Native title shown in Show-Text mode when the name field is empty.
    let displayTextFallback: String
    @Binding var iconSymbol: String
    /// Seed symbol ("" when not symbol-representable); tells a user-picked symbol from the baseline.
    let initialIconSymbol: String
    /// Effective current icon until the user picks a replacement; nil when `iconSymbol` fully describes it.
    let baseIcon: ActionIcon?
    @Binding var displayMode: Int // 0 = Show Icon, 1 = Show Text
    /// Show-Icon fallback for text-glyph builtins (Copy/Cut/Paste) until a replacement is picked.
    var textGlyphFallbackSymbol: String? = nil
    var onPickIcon: (() -> Void)? = nil

    @State private var isIconPickerPresented = false
    @State private var isIconHovered = false

    private var previewIcon: ActionIcon {
        Self.resolvedPreviewIcon(
            displayMode: 0,
            title: title,
            displayTextFallback: displayTextFallback,
            iconSymbol: iconSymbol,
            initialIconSymbol: initialIconSymbol,
            baseIcon: baseIcon,
            textGlyphFallbackSymbol: textGlyphFallbackSymbol
        )
    }

    /// Mirrors `ActionCustomizationManager.popupIcon`; keep the two in sync.
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

    @ViewBuilder
    private var heroIconView: some View {
        if case .text(let text) = previewIcon, !text.isEmpty, !ActionTextIconStyle.isCompactGlyph(text) {
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
            Button {
                isIconPickerPresented = true
                onPickIcon?()
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
            .accessibilityLabel(String(localized: "Choose icon"))
            .popover(isPresented: $isIconPickerPresented, arrowEdge: .bottom) {
                IconPickerPopover(selectedSymbol: $iconSymbol) {
                    isIconPickerPresented = false
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("Action Name", text: $title)
                    .font(.system(size: 13, weight: .medium))
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    Text("Show as:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("", selection: $displayMode) {
                        Text("Icon").tag(0)
                        Text("Text").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 140)
                }
            }
        }
        .padding(14)
    }
}

// MARK: - Inset Group Card Container

struct InsetGroupCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    private var cardFill: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.065)
        } else {
            return Color.primary.opacity(0.04)
        }
    }

    private var cardStroke: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.12)
        } else {
            return Color.primary.opacity(0.06)
        }
    }
}

// MARK: - Icon Picker Page

/// Icon chooser page. Writes to the binding the router was handed; picking an icon leaves the page.
@MainActor
struct IconPickerPage: View {
    @ObservedObject private var router = SettingsRouter.shared

    var body: some View {
        if let target = router.iconTarget {
            IconPickerView(selectedSymbol: target, fillsAvailableHeight: true) {
                router.pop()
            }
            .padding(20)
            .settingsPaneWidth()
        } else {
            // Nothing to write to: the chooser was reached without an editor underneath it.
            Color.clear.onAppear { router.pop() }
        }
    }
}
