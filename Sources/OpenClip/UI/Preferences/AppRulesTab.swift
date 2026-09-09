// AppRulesTab.swift
// OpenClip
//
// Renders the application rules preferences tab for managing app exclusion rules and application-specific settings.
import SwiftUI
import AppKit
import Core

@MainActor
public struct AppRulesTab: View {
    @ObservedObject private var ruleEngine = RuleEngine.shared
    @State private var showingAppPicker = false
    
    public init() {}
    
    public var body: some View {
        Form {
            Section {
                if ruleEngine.userRules.isEmpty {
                    ContentUnavailableView {
                        Label("No App Rules Configured", systemImage: "app.badge.checkmark")
                    } description: {
                        Text("OpenClip works in all applications by default. Add an application to configure per-app rules or exclusions.")
                    } actions: {
                        Button("Add Application") { showingAppPicker = true }
                    }
                    .padding(.vertical, 12)
                } else {
                    ForEach(ruleEngine.userRules) { rule in
                        AppRuleRowView(rule: rule) { updatedRule in
                            RuleEngine.shared.addOrUpdateRule(updatedRule)
                        } onDelete: {
                            RuleEngine.shared.removeRule(id: rule.id)
                        }
                    }
                }
            } header: {
                Text("Application Rules")
            } footer: {
                Text("Configure per-app trigger and paste behavior.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem {
                Button {
                    showingAppPicker = true
                } label: {
                    Label("Add Application", systemImage: "plus")
                }
                .help("Add Application")
            }
        }
        .sheet(isPresented: $showingAppPicker) {
            AppPickerSheet { bundleID in
                let newRule = AppRule(bundleIdentifiers: [bundleID])
                RuleEngine.shared.addOrUpdateRule(newRule)
            }
        }
    }
}

@MainActor
private struct AppRuleRowView: View {
    let rule: AppRule
    let onUpdate: (AppRule) -> Void
    let onDelete: () -> Void
    
    private var bundleID: String {
        rule.bundleIdentifiers.first ?? String(localized: "Unknown App")
    }
    
    private var isDisabled: Bool {
        rule.disabled == true
    }
    
    private var isHotkeyOnly: Bool {
        rule.hotkeyOnly == true
    }
    
    private var isPasteDenied: Bool {
        rule.denyPaste == true
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // App Icon
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                    .resizable()
                    .frame(width: 28, height: 28)
                    .opacity(isDisabled ? 0.5 : 1.0)
            } else {
                Image(systemName: bundleID.contains("*") ? "asterisk.circle" : "app.dashed")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
                    .opacity(isDisabled ? 0.5 : 1.0)
            }
            
            // App Title & Bundle ID
            VStack(alignment: .leading, spacing: 1) {
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
                   let bundle = Bundle(url: appURL),
                   let appName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
                    Text(appName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isDisabled ? .secondary : .primary)
                    Text(bundleID)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                } else {
                    Text(bundleID)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isDisabled ? .secondary : .primary)
                }
            }
            
            Spacer()
            
            // Disable Toggle
            Toggle("", isOn: Binding(
                get: { !isDisabled },
                set: { isEnabled in
                    let updated = AppRule(
                        bundleIdentifiers: rule.bundleIdentifiers,
                        disabled: isEnabled ? nil : true,
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
            .controlSize(.mini)
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
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More Actions")
            .accessibilityLabel("More Actions")
        }
        .padding(.vertical, 6)
    }
}
