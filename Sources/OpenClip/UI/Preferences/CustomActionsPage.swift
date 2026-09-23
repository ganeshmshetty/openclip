// CustomActionsPage.swift
// OpenClip
//
// The user's own actions — Open URL, Text Snippet, Shell Script, JavaScript — as one sidebar page:
// a hero header, AI-assisted action creation, and quick-start cards for manual action creation.
// Follows macOS Settings UI liquid glass and grouped Form conventions.

import SwiftUI
import Core

@MainActor
struct CustomActionsPage: View {
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>

    @ObservedObject private var router = SettingsRouter.shared

    @State private var hoveredKind: String? = nil

    init(
        disabledActionIDs: Binding<Set<String>> = .constant([]),
        disabledPackages: Binding<Set<String>> = .constant([])
    ) {
        _disabledActionIDs = disabledActionIDs
        _disabledPackages = disabledPackages
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    let size: CGFloat = 42
                    let radius = SettingsDesignTokens.iconTileRadius(for: size)
                    let squircle = RoundedRectangle(cornerRadius: radius, style: .continuous)

                    ZStack {
                        squircle
                            .fill(SettingsTint.neutral)
                            .shadow(color: Color.black.opacity(0.12), radius: 2, y: 1)

                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: size, height: size)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "Custom Actions"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(SettingsDesignTokens.primaryText)
                            .lineLimit(1)

                        Text(String(localized: "Create your own quick actions using URL templates, snippet placeholders, or shell scripts."))
                            .font(.system(size: 12))
                            .foregroundStyle(SettingsDesignTokens.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)
                }
                .padding(.vertical, 4)
            }

            Section {
                AICustomActionBuilderCard()
            } header: {
                Text(String(localized: "Create with AI"))
            }

            Section {
                quickCreateRow(
                    kind: "url",
                    title: "Open URL",
                    subtitle: "Search the web or open query URLs with selected text",
                    systemImage: "safari.fill"
                )

                quickCreateRow(
                    kind: "snippet",
                    title: "Text Snippet",
                    subtitle: "Expand reusable text templates with dynamic placeholders",
                    systemImage: "text.quote"
                )

                quickCreateRow(
                    kind: "shell",
                    title: "Shell Script",
                    subtitle: "Automate tasks by running custom bash or zsh scripts",
                    systemImage: "terminal.fill"
                )

                quickCreateRow(
                    kind: "javascript",
                    title: "JavaScript",
                    subtitle: "Transform text or call web APIs using JavaScriptCore",
                    systemImage: "curlybraces"
                )
            } header: {
                Text(String(localized: "Create New Action"))
            } footer: {
                Text(String(localized: "Custom actions appear in your popup bar and search palette. Assign global hotkeys or search aliases to trigger them anytime."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }

    private func quickCreateRow(
        kind: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        systemImage: String
    ) -> some View {
        Button {
            router.push(.newCustomAction(kind: kind))
        } label: {
            HStack(spacing: 12) {
                let tint = SettingsDesignTokens.iconTileColor(forSystemImage: systemImage)
                SettingsIconTile(systemImage: systemImage, tint: tint, size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SettingsDesignTokens.primaryText)

                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsDesignTokens.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text(String(localized: "Create"))
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(SettingsDesignTokens.primaryText)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .settingsGlassCapsule()
                .contentShape(Capsule())
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            hoveredKind = isHovered ? kind : nil
        }
    }
}
