// SettingsHeroHeader.swift
// OpenClip
//
// The identity block at the top of a page that is *about something* — an installed extension, AI
// Tools, the user's custom actions. A large icon, the name, one line about what it is, centred,
// on the window's background rather than in a card.
//
// It is the same shape the app's own About page uses for OpenClip, and the same shape Raycast and
// Setapp use for an extension: the page says what it belongs to before it says anything else, so
// the switch and the ellipsis menu in the toolbar have an obvious subject.

import SwiftUI
import Core

@MainActor
struct SettingsHeroHeader: View {
    /// The tile at the top: a system symbol for OpenClip's own pages, an action icon for an
    /// extension (its manifest icon, which may be a template SVG, a favicon or a text glyph).
    enum Glyph {
        case symbol(String, tint: Color)
        case icon(ActionIcon, tint: Color)
    }

    let glyph: Glyph
    let title: String
    var subtitle: String?
    /// The quiet third line: "Version 1.0.0 · OpenClip Team".
    var footnote: String?
    var tileSize: CGFloat = 64

    var body: some View {
        VStack(spacing: 12) {
            tile

            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let footnote, !footnote.isEmpty {
                    Text(footnote)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 1)
                }
            }
            .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 22)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var tile: some View {
        switch glyph {
        case .symbol(let name, let tint):
            SettingsIconTile(systemImage: name, tint: tint, size: tileSize)
                .shadow(color: tint.opacity(0.28), radius: 8, y: 3)
        case .icon(let icon, let tint):
            ExtensionIconTile(icon: icon, tint: tint, size: tileSize)
                .shadow(color: tint.opacity(0.28), radius: 8, y: 3)
        }
    }
}

extension SettingsHeroHeader {
    /// The tile glyph for an action.
    ///
    /// Copy, Cut and Paste draw as *text* in the popup bar — that is their icon — and a tile can
    /// only show a glyph, so those fall back to the symbol they carry for exactly this purpose.
    @MainActor
    static func glyph(for action: any Action, presented: ActionPresentationModel) -> ActionIcon {
        if case .text = presented.icon,
           let symbol = (action as? any ConfigurableAction)?.preferenceIconName,
           !symbol.isEmpty {
            return .symbol(symbol)
        }
        return presented.icon
    }
}
