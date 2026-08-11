// ActionsTabView.swift
// OpenClip
//
// The Actions preferences tab: the reorderable action list with per-action toggles,
// package headers for multi-action extension packages, and the add/install controls.
// Split out of PreferencesView.swift.
import SwiftUI
import Core

@MainActor
struct ActionsTab: View {
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>
    /// Called by the AI Tools row's gear to open the AI tab. Wired in PreferencesView to switch
    /// `selectedTab` to `.ai` (and land on the Configure sub-tab where `isAIEnabled` lives).
    let onOpenAI: () -> Void
    @State private var showingAddActionSheet = false
    @ObservedObject private var coordinator = ActionCoordinator.shared
    /// Single observation site for action presentation (title/icon) customizations. Rows no longer
    /// subscribe to `ActionCustomizationManager.shared` directly — they receive resolved values.
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    
    /// Row model for the grouped actions list: multi-action extension packages get a package
    /// header row (with a whole-package toggle) before their actions; single-action packages and
    /// builtins stay flat.
    private enum ListRow: Identifiable {
        case packageHeader(packageID: String, title: String)
        case action(any Action)
        
        var id: String {
            switch self {
            case .packageHeader(let packageID, _): return "pkg.\(packageID)"
            case .action(let action): return action.id
            }
        }
    }
    
    private var packageActionCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for action in coordinator.actions {
            if let packageID = ActionIdentity.extensionPackageID(of: action) {
                counts[packageID, default: 0] += 1
            }
        }
        return counts
    }
    
    private var listRows: [ListRow] {
        var seenPackages: Set<String> = []
        var rows: [ListRow] = []
        for action in coordinator.actions {
            // AI presets never appear here — they're managed in the AI tab (and the palette).
            // The reorderable "AI Tools" launcher action (chrome.launchesAI) renders as a normal row.
            if ActionIdentity.isAIPreset(action) {
                continue
            }
            if let packageID = ActionIdentity.extensionPackageID(of: action) {
                if !seenPackages.contains(packageID) {
                    seenPackages.insert(packageID)
                    if packageActionCounts[packageID] ?? 0 >= 2 {
                        let title: String
                        if case .extensionPkg(let name) = action.chrome.badge {
                            title = name
                        } else {
                            title = packageID
                        }
                        rows.append(.packageHeader(packageID: packageID, title: title))
                    }
                }
                rows.append(.action(action))
            } else {
                rows.append(.action(action))
            }
        }
        return rows
    }
    
    /// Translates indices in the grouped row list (which contains inert package headers) back to
    /// `coordinator.actions` indices so reordering stays correct despite the inserted headers.
    private func moveRows(source: IndexSet, destination: Int) {
        let actionIndices: [(rowIndex: Int, actionIndex: Int)] = listRows.enumerated().compactMap { rowIndex, row in
            guard case .action(let action) = row else { return nil }
            guard let actionIndex = coordinator.actions.firstIndex(where: { $0.id == action.id }) else { return nil }
            return (rowIndex, actionIndex)
        }
        let actionIndexByRow = Dictionary(uniqueKeysWithValues: actionIndices.map { ($0.rowIndex, $0.actionIndex) })
        let actionSource = IndexSet(source.compactMap { actionIndexByRow[$0] })
        let actionDestination = actionIndices.prefix { $0.rowIndex < destination }.count
        coordinator.moveActions(from: actionSource, to: actionDestination)
    }

    @State private var selectedRowID: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List(selection: $selectedRowID) {
                Section {
                    ForEach(listRows) { row in
                        switch row {
                        case .packageHeader(let packageID, let title):
                            PackageHeaderRowView(packageID: packageID, title: title, disabledPackages: $disabledPackages)
                                .tag(row.id)
                        case .action(let action):
                            ActionRowView(
                                action: action,
                                presentationModel: presentationModel(for: action),
                                isEnabled: enabledBinding(for: action),
                                onOpenAI: onOpenAI
                            )
                            .tag(row.id)
                        }
                    }
                    .onMove(perform: moveRows)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            HStack(spacing: 12) {
                Button(action: {
                    showingAddActionSheet = true
                }, label: {
                    Label("Add Custom Action", systemImage: "plus.circle")
                })
                
                Button(action: {
                    openInstallExtensionPanel()
                }, label: {
                    Label("Install Extension…", systemImage: "square.and.arrow.down")
                })
                
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
        }
        .padding(12)
        .sheet(isPresented: $showingAddActionSheet) {
            AddCustomActionSheet()
        }
    }
    
    /// Resolves a row's title/icon from `ActionCustomizationManager` — the single observation site
    /// for customizations. Passed to rows as a value so they never subscribe to the shared manager.
    private func presentationModel(for action: any Action) -> ActionPresentationModel {
        customizationManager.presented(action, surface: .table)
    }

    /// Scoped enabled binding for a row, built from the row's single source of truth:
    /// - AI Tools launcher → `AIServiceManager.isAIEnabled` (shared with the AI tab toggle)
    /// - AI preset rows → the preset's `isEnabled`
    /// - everything else → `disabledActionIDs`
    /// Reading the singletons inside the binding — rather than via `@ObservedObject` on every row —
    /// keeps rows off the shared observation fan-out: a `Toggle` reflects its own live value without
    /// re-rendering every row when an unrelated setting changes.
    private func enabledBinding(for action: any Action) -> Binding<Bool> {
        if action.chrome.launchesAI {
            return Binding(
                get: { AIServiceManager.shared.isAIEnabled },
                set: { AIServiceManager.shared.isAIEnabled = $0 }
            )
        }
        if ActionIdentity.isAIPreset(action) {
            return Binding(
                get: { AIServiceManager.shared.preset(forActionID: action.id)?.isEnabled ?? false },
                set: { enabled in
                    guard var preset = AIServiceManager.shared.preset(forActionID: action.id) else { return }
                    preset.isEnabled = enabled
                    AIServiceManager.shared.updatePreset(preset)
                }
            )
        }
        return Binding(
            get: { !disabledActionIDs.contains(action.id) },
            set: { enabled in
                if enabled {
                    disabledActionIDs.remove(action.id)
                } else {
                    disabledActionIDs.insert(action.id)
                }
            }
        )
    }

    private func openInstallExtensionPanel() {
        let panel = NSOpenPanel()
        panel.title = "Select Extension to Install"
        panel.message = "Choose a .openclipext folder, .zip archive, or script file"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        // Treat .openclipext packages as directories so they can be read
        panel.treatsFilePackagesAsDirectories = true
        panel.allowedContentTypes = []

        panel.begin { response in
            guard response == .OK, let selectedURL = panel.url else { return }
            Task {
                do {
                    _ = try await ExtensionManager.shared.installExtension(from: selectedURL)
                    await MainActor.run {
                        // Post notification so any listening view refreshes its action list
                        NotificationCenter.default.post(name: .init("OpenClipExtensionsDidChange"), object: nil)
                    }
                } catch {
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = "Extension Install Failed"
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            }
        }
    }
}

@MainActor
struct ActionRowView: View {
    let action: any Action
    /// Resolved title/icon for this row, computed once by `ActionsTab` from
    /// `ActionCustomizationManager` and passed down as a value — this row never subscribes to the
    /// shared manager, so it only re-renders when its own presentation actually changes.
    let presentationModel: ActionPresentationModel
    /// Scoped, live binding from the parent (`ActionsTab`): AI manager for AI rows,
    /// `disabledActionIDs` otherwise. No per-row `@ObservedObject` on shared singletons.
    let isEnabled: Binding<Bool>
    /// Opens the AI tab (AI Tools launcher rows); nil for rows without a nav gear.
    let onOpenAI: (() -> Void)?

    init(action: any Action, presentationModel: ActionPresentationModel, isEnabled: Binding<Bool>, onOpenAI: (() -> Void)? = nil) {
        self.action = action
        self.presentationModel = presentationModel
        self.isEnabled = isEnabled
        self.onOpenAI = onOpenAI
    }

    /// AI preset rows share their toggle with the AI tab: enabling/disabling here (or there)
    /// writes the preset's `isEnabled`, the single source of truth. Never touches
    /// `disabledActionIDs`, which drives the bar via ActionRegistry.availableActions.
    private var isAI: Bool {
        ActionIdentity.isAIPreset(action)
    }

    /// The "AI Tools" bar launcher also shares its toggle with the AI tab — but with
    /// `isAIEnabled`, the single source of truth for the whole AI feature. Never touches
    /// `disabledActionIDs`.
    private var isAITools: Bool {
        action.chrome.launchesAI
    }

    @State private var showingConfigSheet = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Icon Column
            ZStack {
                ActionIconView(icon: presentationModel.icon, size: 12)
            }
            .frame(width: 22, height: 22)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(5)
            
            // Title Column
            Text(presentationModel.title)
                .font(.system(size: 12, weight: .medium))

            Spacer()
            
            // Right-aligned controls (Remove | Toggle | Gear)
            HStack(alignment: .center, spacing: 8) {
                // Delete / Uninstall Button (if applicable)
                switch action.chrome.source {
                case .custom, .extensionPkg:
                    Button(action: {
                        Task {
                            do {
                                try await ExtensionManager.shared.uninstallExtension(actionID: action.id)
                            } catch {
                                Log.extensions.error("Failed to uninstall extension '\(action.id, privacy: .public)': \(error.localizedDescription)")
                                let failure = NSAlert()
                                failure.messageText = "Uninstall Failed"
                                failure.informativeText = "OpenClip could not uninstall extension: \(error.localizedDescription)"
                                failure.alertStyle = .warning
                                failure.runModal()
                            }
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 20, height: 20)
                    .help("Uninstall Extension")
                    .accessibilityLabel("Uninstall Extension")
                case .builtin, .ai:
                    EmptyView()
                }

                // Enable/Disable Switch
                Toggle("", isOn: isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .accessibilityLabel("Enable \(presentationModel.title)")
                
                // Edit / Configure Button
                if isAITools {
                    if let onOpenAI {
                        Button(action: onOpenAI) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 20, height: 20)
                        .help("Open AI settings")
                        .accessibilityLabel("Open AI settings")
                    }
                } else if !isAI {
                    Button(action: {
                        showingConfigSheet = true
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 20, height: 20)
                    .help("Configure Action")
                    .accessibilityLabel("Configure Action")
                    .sheet(isPresented: $showingConfigSheet) {
                        EditActionSheet(action: action)
                    }
                }
            }
        }
        .padding(.vertical, 1)
    }
}


@MainActor
struct PackageHeaderRowView: View {
    let packageID: String
    let title: String
    @Binding var disabledPackages: Set<String>
    
    var isEnabled: Binding<Bool> {
        Binding<Bool>(
            get: { !disabledPackages.contains(packageID) },
            set: { enabled in
                if enabled {
                    disabledPackages.remove(packageID)
                } else {
                    disabledPackages.insert(packageID)
                }
            }
        )
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 22, height: 22)
            
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Toggle("", isOn: isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel("Enable \(title)")
        }
        .padding(.vertical, 1)
    }
}
