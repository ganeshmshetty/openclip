// AppRulesTab.swift
// OpenClip
//
// Renders the Rules preferences tab: application rules and blocked websites.
import SwiftUI
import AppKit
import Core

@MainActor
public struct AppRulesTab: View {
    @ObservedObject private var ruleEngine = RuleEngine.shared
    @State private var isAddingWebsite = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                applicationsCard
                websitesCard

                Text("Application rules control triggers and paste behavior. Website rules keep the popup off on the sites you add.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $isAddingWebsite) {
            WebsiteRuleEditor { patterns in
                patterns.forEach { RuleEngine.shared.addWebsite($0) }
            }
        }
    }

    private var applicationsCard: some View {
        SettingsCard("Applications") {
            if ruleEngine.userRules.isEmpty {
                ContentUnavailableView {
                    Label("No App Rules Configured", systemImage: "shield")
                } description: {
                    Text("OpenClip works in all applications by default. Add an application to configure per-app rules or exclusions.")
                        .multilineTextAlignment(.center)
                } actions: {
                    Button("Add Application") { SettingsRouter.shared.push(.addApplication) }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ForEach(Array(ruleEngine.userRules.enumerated()), id: \.element.id) { index, rule in
                    if index > 0 {
                        SettingsDivider(insetLeading: 56)
                    }
                    AppRuleRowView(rule: rule) { updatedRule in
                        RuleEngine.shared.addOrUpdateRule(updatedRule)
                    } onDelete: {
                        RuleEngine.shared.removeRule(id: rule.id)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
                SettingsDivider(insetLeading: 56)
                addRow("Add Application", systemImage: "app.badge.checkmark") {
                    SettingsRouter.shared.push(.addApplication)
                }
            }
        }
    }

    private var websitesCard: some View {
        SettingsCard("Websites") {
            if ruleEngine.websitePatterns.isEmpty {
                ContentUnavailableView {
                    Label("No Websites Blocked", systemImage: "globe")
                } description: {
                    Text("The popup stays off on these sites. The keyboard shortcut still works.")
                        .multilineTextAlignment(.center)
                } actions: {
                    Button("Add Website") { isAddingWebsite = true }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ForEach(Array(ruleEngine.websitePatterns.enumerated()), id: \.element) { index, pattern in
                    if index > 0 {
                        SettingsDivider(insetLeading: 56)
                    }
                    WebsiteRowView(pattern: pattern) {
                        RuleEngine.shared.removeWebsite(pattern)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
                SettingsDivider(insetLeading: 56)
                addRow("Add Website", systemImage: "globe.badge.chevron.backward") {
                    isAddingWebsite = true
                }
            }
        }
    }

    private func addRow(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

@MainActor
private struct WebsiteRowView: View {
    let pattern: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28)
            Text(pattern)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove Website")
            .accessibilityLabel("Remove Website")
        }
        .padding(.vertical, 4)
    }
}

@MainActor
private struct AppRuleRowView: View {
    let rule: AppRule
    let onUpdate: (AppRule) -> Void
    let onDelete: () -> Void

    private var identifier: String {
        rule.bundleIdentifiers.first ?? String(localized: "Unknown App")
    }

    private var displayName: String {
        for prefix in [DefaultAppRules.processNamePrefix, DefaultAppRules.executablePathPrefix] where identifier.hasPrefix(prefix) {
            let rest = String(identifier.dropFirst(prefix.count))
            let name = URL(fileURLWithPath: rest).lastPathComponent
            return name.isEmpty ? rest : name
        }
        return identifier
    }

    /// The default catalog can disable an app without a user rule. The switch must show the
    /// effective policy, or a default-blocked app looks enabled while it is not.
    private var isDisabled: Bool {
        let scoped = identifier.hasPrefix(DefaultAppRules.processNamePrefix)
            || identifier.hasPrefix(DefaultAppRules.executablePathPrefix)
        guard !scoped, !identifier.contains("*") else { return rule.disabled == true }
        return RuleEngine.shared.resolvePolicies(for: identifier).disabled
    }

    private var isHotkeyOnly: Bool {
        rule.hotkeyOnly == true
    }

    private var isPasteDenied: Bool {
        rule.denyPaste == true
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // App Icon
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                    .resizable()
                    .frame(width: 28, height: 28)
                    .opacity(isDisabled ? 0.5 : 1.0)
            } else {
                Image(systemName: identifier.contains("*") ? "asterisk.circle" : "app.dashed")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
                    .opacity(isDisabled ? 0.5 : 1.0)
            }

            // App Title & Identifier
            VStack(alignment: .leading, spacing: 2) {
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
                   let bundle = Bundle(url: appURL),
                   let appName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
                    Text(appName)
                        .foregroundStyle(isDisabled ? .secondary : .primary)
                    Text(identifier)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text(displayName)
                        .foregroundStyle(isDisabled ? .secondary : .primary)
                }
            }

            Spacer()

            // Disable Toggle
            Toggle("", isOn: Binding(
                get: { !isDisabled },
                set: { isEnabled in
                    let updated = AppRule(
                        bundleIdentifiers: rule.bundleIdentifiers,
                        disabled: !isEnabled,
                        hotkeyOnly: rule.hotkeyOnly,
                        useMenuCopy: rule.useMenuCopy,
                        denyPaste: rule.denyPaste,
                        retrievalMode: rule.retrievalMode,
                        gate: rule.gate
                    )
                    onUpdate(updated)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel(isDisabled ? String(localized: "Enable in this app") : String(localized: "Disable in this app"))

            // Three-Dots (...) Actions Menu
            Menu {
                Button {
                    let updated = AppRule(
                        bundleIdentifiers: rule.bundleIdentifiers,
                        disabled: rule.disabled,
                        hotkeyOnly: isHotkeyOnly ? nil : true,
                        useMenuCopy: rule.useMenuCopy,
                        denyPaste: rule.denyPaste,
                        retrievalMode: rule.retrievalMode,
                        gate: rule.gate
                    )
                    onUpdate(updated)
                } label: {
                    if isHotkeyOnly {
                        Label("Hotkey Only", systemImage: "checkmark")
                    } else {
                        Text("Hotkey Only")
                    }
                }

                Button {
                    let updated = AppRule(
                        bundleIdentifiers: rule.bundleIdentifiers,
                        disabled: rule.disabled,
                        hotkeyOnly: rule.hotkeyOnly,
                        useMenuCopy: rule.useMenuCopy,
                        denyPaste: isPasteDenied ? nil : true,
                        retrievalMode: rule.retrievalMode,
                        gate: rule.gate
                    )
                    onUpdate(updated)
                } label: {
                    if isPasteDenied {
                        Label("Copy Result Only", systemImage: "checkmark")
                    } else {
                        Text("Copy Result Only")
                    }
                }

                Divider()

                Button(role: .destructive, action: onDelete) {
                    Label("Remove Rule", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More Actions")
            .accessibilityLabel("More Actions")
        }
        .padding(.vertical, 4)
    }
}
