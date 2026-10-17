// SettingsRowLabel.swift
// OpenClip
//
// The shared row and card shapes used by preferences panes:
// - SettingsCard: an outside section heading with an inset rounded card container.
// - SettingsRow: a row with a rounded-square icon tile (colored fill + white glyph), title,
//   optional subtitle, trailing control or chevron, and inset hairline dividers.
// - SettingsToggleRow: a switch row with the same tile and title layout.
// - SettingsDivider: an inset hairline divider.

import SwiftUI

/// Section card with its heading outside a rounded, lightly filled container.
struct SettingsCard<Content: View>: View {
    var title: LocalizedStringKey?
    var infoTooltip: String?
    @ViewBuilder let content: () -> Content

    init(
        _ title: LocalizedStringKey? = nil,
        infoTooltip: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.infoTooltip = infoTooltip
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SettingsDesignTokens.sectionHeaderColor)
                    if let infoTooltip {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondary.opacity(0.7))
                            .help(infoTooltip)
                    }
                }
                .padding(.horizontal, 4)
            }

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: SettingsDesignTokens.sectionCardRadius, style: .continuous)
                    .fill(SettingsDesignTokens.sectionCardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsDesignTokens.sectionCardRadius, style: .continuous)
                    .strokeBorder(SettingsDesignTokens.sectionCardBorder, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: SettingsDesignTokens.sectionCardRadius, style: .continuous))
        }
    }
}

/// Inset hairline divider between rows inside a section card.
struct SettingsDivider: View {
    var insetLeading: CGFloat = SettingsDesignTokens.dividerInsetLeading

    var body: some View {
        Rectangle()
            .fill(SettingsDesignTokens.rowDivider)
            .frame(height: 0.5)
            .padding(.leading, insetLeading)
    }
}

/// The label portion of a row: an icon tile (or a plain neutral glyph), title, optional subtitle.
struct SettingsRowLabel: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var subtitleText: Text?
    var systemImage: String?
    var iconTileTint: Color?
    /// Plain secondary-colored glyph instead of a colored tile, for control rows where a tile is decoration.
    var plainIcon: Bool
    var descriptionOnHover: Bool
    @State private var isHovered = false
    @State private var isDescriptionPresented = false

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        systemImage: String? = nil,
        iconTileTint: Color? = nil,
        plainIcon: Bool = false,
        descriptionOnHover: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.subtitleText = nil
        self.systemImage = systemImage
        self.iconTileTint = iconTileTint
        self.plainIcon = plainIcon
        self.descriptionOnHover = descriptionOnHover
    }

    init(
        title: LocalizedStringKey,
        subtitleText: Text?,
        systemImage: String? = nil,
        iconTileTint: Color? = nil,
        plainIcon: Bool = false,
        descriptionOnHover: Bool = false
    ) {
        self.title = title
        self.subtitle = nil
        self.subtitleText = subtitleText
        self.systemImage = systemImage
        self.iconTileTint = iconTileTint
        self.plainIcon = plainIcon
        self.descriptionOnHover = descriptionOnHover
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let systemImage {
                if plainIcon {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(iconTileTint ?? SettingsDesignTokens.secondaryText)
                        .frame(width: 20, alignment: .center)
                } else {
                    let tint = iconTileTint ?? SettingsDesignTokens.iconTileColor(forSystemImage: systemImage)
                    SettingsIconTile(systemImage: systemImage, tint: tint, size: 20)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(SettingsDesignTokens.rowTitleColor)

                    if descriptionOnHover && (subtitle != nil || subtitleText != nil) {
                        Button {
                            isDescriptionPresented = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(SettingsDesignTokens.secondaryText)
                                .frame(width: 16, height: 16)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .opacity(isHovered || isDescriptionPresented ? 1 : 0)
                        .help(String(localized: "Show setting description"))
                        .accessibilityLabel(String(localized: "Show setting description"))
                        .popover(isPresented: $isDescriptionPresented, arrowEdge: .leading) {
                            Group {
                                if let subtitleText {
                                    subtitleText
                                } else if let subtitle {
                                    Text(subtitle)
                                }
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(SettingsDesignTokens.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 280, alignment: .leading)
                            .padding(12)
                        }
                    }
                }

                if !descriptionOnHover {
                    if let subtitleText {
                        subtitleText
                            .font(.caption)
                            .foregroundStyle(SettingsDesignTokens.rowSubtitleColor)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(SettingsDesignTokens.rowSubtitleColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered || isDescriptionPresented)
    }
}

/// A full settings row: icon tile + label on the left, control on the right, both centred.
struct SettingsRow<Trailing: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    /// Explanation shown in the (i) popover next to the title instead of a line under it.
    var info: LocalizedStringKey?
    var subtitleText: Text?
    var systemImage: String?
    var iconTileTint: Color?
    var plainIcon: Bool
    var descriptionOnHover: Bool
    var showChevron: Bool
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        info: LocalizedStringKey? = nil,
        systemImage: String? = nil,
        iconTileTint: Color? = nil,
        plainIcon: Bool = false,
        descriptionOnHover: Bool = false,
        showChevron: Bool = false,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.info = info
        self.subtitleText = nil
        self.systemImage = systemImage
        self.iconTileTint = iconTileTint
        self.plainIcon = plainIcon
        self.descriptionOnHover = descriptionOnHover
        self.showChevron = showChevron
        self.trailing = trailing
    }

    init(
        title: LocalizedStringKey,
        subtitleText: Text?,
        systemImage: String? = nil,
        iconTileTint: Color? = nil,
        plainIcon: Bool = false,
        descriptionOnHover: Bool = false,
        showChevron: Bool = false,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = nil
        self.subtitleText = subtitleText
        self.systemImage = systemImage
        self.iconTileTint = iconTileTint
        self.plainIcon = plainIcon
        self.descriptionOnHover = descriptionOnHover
        self.showChevron = showChevron
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                if let subtitleText {
                    SettingsRowLabel(
                        title: title,
                        subtitleText: subtitleText,
                        systemImage: systemImage,
                        iconTileTint: iconTileTint,
                        plainIcon: plainIcon,
                        descriptionOnHover: descriptionOnHover
                    )
                } else {
                    SettingsRowLabel(
                        title: title,
                        subtitle: subtitle,
                        systemImage: systemImage,
                        iconTileTint: iconTileTint,
                        plainIcon: plainIcon,
                        descriptionOnHover: descriptionOnHover
                    )
                }
                if let info {
                    SettingsInfoButton(title: title, info: info)
                }
            }
            Spacer(minLength: 12)
            trailing()
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SettingsDesignTokens.tertiaryText)
            }
        }
        .padding(.horizontal, SettingsDesignTokens.sectionCardPaddingH)
        .padding(.vertical, SettingsDesignTokens.sectionCardPaddingV)
        .frame(minHeight: 34)
    }
}

/// A row whose whole label describes one switch.
struct SettingsToggleRow: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var info: LocalizedStringKey?
    var systemImage: String?
    var iconTileTint: Color?
    var plainIcon: Bool
    @Binding var isOn: Bool

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        info: LocalizedStringKey? = nil,
        systemImage: String? = nil,
        iconTileTint: Color? = nil,
        plainIcon: Bool = false,
        isOn: Binding<Bool>
    ) {
        self.title = title
        self.subtitle = subtitle
        self.info = info
        self.systemImage = systemImage
        self.iconTileTint = iconTileTint
        self.plainIcon = plainIcon
        self._isOn = isOn
    }

    var body: some View {
        SettingsRow(
            title: title,
            subtitle: subtitle,
            info: info,
            systemImage: systemImage,
            iconTileTint: iconTileTint,
            plainIcon: plainIcon
        ) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(title)
        }
    }
}
