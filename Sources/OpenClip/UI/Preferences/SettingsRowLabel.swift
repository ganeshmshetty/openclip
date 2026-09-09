// SettingsRowLabel.swift
// OpenClip
//
// The one shared label shape used by every preferences row: a symbol, a title,
// and an optional line of secondary text. Everything else about a row — the
// card, the dividers, the row height, the label/control split — is left to the
// system's grouped `Form`, so rows follow System Settings rather than tracking
// a private style sheet.
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
