// SettingsNavigationStack.swift
// OpenClip
//
// Hosts the router's path in the detail column: the sidebar's page at the bottom, every page
// drilled into from it on top, the topmost one visible.
//
// Every level stays mounted (offset out of view and faded) rather than being torn down, so a
// page's in-progress edits survive drilling into the icon chooser and coming back. Only the top
// level takes clicks or is exposed to accessibility.

import SwiftUI

@MainActor
struct SettingsNavigationStack<Content: View>: View {
    let path: [SettingsPage]
    @ViewBuilder let content: (SettingsPage) -> Content

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(Array(path.enumerated()), id: \.element.id) { index, page in
                let isTop = index == path.count - 1
                content(page)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(x: isTop ? 0 : -40)
                    .opacity(isTop ? 1 : 0)
                    .allowsHitTesting(isTop)
                    .accessibilityHidden(!isTop)
                    .zIndex(Double(index))
                    .transition(
                        index == 0
                            ? .opacity
                            : .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            )
                    )
            }
        }
        .clipped()
    }
}

// MARK: - Page layout

/// A page that edits something and ends with buttons: scrolling content above, a pinned footer
/// below. The footer is where Cancel / Save live, so it never scrolls out of reach.
@MainActor
struct SettingsEditorPage<Content: View, Footer: View>: View {
    /// Widest the content grows; matches the grouped `Form` panes' card width at the window's
    /// default size so pages line up when you move between them.
    var contentMaxWidth: CGFloat = 640
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .frame(maxWidth: contentMaxWidth)
                    .frame(maxWidth: .infinity)
            }

            Divider()

            footer()
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
        }
    }
}

/// One line of red text with a warning glyph, for a save that could not go through. Replaces the
/// alerts the editors used to run modal over the window.
struct SettingsInlineError: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// The small uppercase caption that titles a card, matching a grouped `Form`'s section header.
struct SettingsCardTitle: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }
}

/// A list row that drills into another page: content on the left, a chevron on the right, the
/// whole row the hit target the way a System Settings row is.
struct SettingsDisclosureRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                content()
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
