// SettingsRowLabel.swift
// OpenClip
//
// The shared row shapes used by every preferences pane: a symbol, a title, an
// optional line of secondary text, and a trailing control that stays centred
// against the whole label rather than riding the first line of it.
//
// The rows sit inside a grouped `Form`, which still owns the card, the
// dividers and the row insets — only the label/control split is taken over
// here, because `LabeledContent` aligns a control to the label's first
// baseline and leaves it high on any row that carries a description.
import SwiftUI

struct SettingsRowLabel: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var systemImage: String?

    init(title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, systemImage: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .center)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A full settings row: label on the left, control on the right, both centred
/// on the row's height.
struct SettingsRow<Trailing: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var systemImage: String?
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        systemImage: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsRowLabel(title: title, subtitle: subtitle, systemImage: systemImage)
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.vertical, 2)
    }
}

/// A row whose whole label describes one switch.
struct SettingsToggleRow: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var systemImage: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle, systemImage: systemImage) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(title)
        }
    }
}
