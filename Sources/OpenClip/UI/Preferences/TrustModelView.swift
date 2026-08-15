// TrustModelView.swift
// OpenClip
//
// The single consent surface (the "trust model"): shows what a package is and what it does, and
// is the only way to Enable or Disable it. Reached from the Installed tab, the install-file
// panel, and trust-change notifications. Renders type-derived risk (cannot lie) plus the author's
// declared capabilities verbatim.
import SwiftUI
import Core

struct TrustReviewTarget: Identifiable {
    let packageID: String
    var id: String { packageID }
}

@MainActor
public final class TrustModelViewModel: ObservableObject {
    let packageID: String
    let manifest: ExtensionMetadata?
    let risk: ExtensionRiskProfile
    let source: String?
    let trustState: ExtensionTrustState?
    let reason: ExtensionGateReason?

    init(packageID: String,
         manifest: ExtensionMetadata?,
         source: String?,
         trustState: ExtensionTrustState?,
         reason: ExtensionGateReason?) {
        self.packageID = packageID
        self.manifest = manifest
        self.risk = manifest.map(ExtensionRiskProfile.init(manifest:)) ?? ExtensionRiskProfile(manifest: ExtensionMetadata(identifier: packageID, name: packageID, actions: []))
        self.source = source
        self.trustState = trustState
        self.reason = reason
    }

    static func load(packageID: String, in directory: URL = Constants.extensionsDirectory) -> TrustModelViewModel {
        let settings = DefaultSettingsStore.shared
        let manifest = ExtensionManifestStore.manifest(forPackageID: packageID, in: directory)
        let trustState = ExtensionTrustState(rawValue: settings.get(.extensionTrust)[packageID] ?? "")
        let source = settings.get(.extensionSources)[packageID]
        return TrustModelViewModel(packageID: packageID, manifest: manifest, source: source, trustState: trustState, reason: nil)
    }
}

public struct TrustModelView: View {
    @ObservedObject var model: TrustModelViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isMutating = false

    public init(model: TrustModelViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(model.manifest?.name ?? model.packageID)
                    .font(.title3.bold())
                Spacer()
                if model.source == "store" {
                    Label("Store", systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(model.packageID)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let version = model.manifest?.version {
                    Text("Version \(version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let warning = warningLine {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            riskSection
            capabilitiesSection
            actionsSection

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if isTrusted {
                    Button(role: .destructive, action: { Task { await perform(.disable) } }) {
                        Text("Disable")
                    }
                } else {
                    Button(action: { Task { await perform(.enable) } }) {
                        Text("Enable")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isMutating)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private enum Mutation { case enable, disable }

    private var isTrusted: Bool {
        model.trustState == .trusted
    }

    private var warningLine: String? {
        guard let reason = model.reason else { return nil }
        if case .filesChanged = reason {
            return "Files changed since you enabled it."
        }
        if case .needsNewerApp(let required) = reason {
            return "Needs OpenClip \(required) or newer."
        }
        return nil
    }

    private var riskSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What this extension can do")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            ForEach(riskRows, id: \.label) { row in
                Label(row.label, systemImage: row.icon)
                    .font(.system(size: 12))
                    .foregroundColor(row.severity == .high ? .red : .primary)
            }
            if riskRows.isEmpty {
                Text("Only opens URLs / pastes text.")
                    .font(.system(size: 12))
            }
        }
    }

    private var riskRows: [(label: String, icon: String, severity: RiskSeverity)] {
        var rows: [(String, String, RiskSeverity)] = []
        if model.risk.runsCode { rows.append(("Runs code (shell, AppleScript, or JavaScript)", "chevron.left.forwardslash.chevron.right", .high)) }
        if model.risk.scriptNetwork { rows.append(("Can make network requests", "globe", .high)) }
        if model.risk.appAutomation { rows.append(("Can drive other apps", "app.badge", .medium)) }
        if model.risk.keyboard { rows.append(("Can type for you", "keyboard", .medium)) }
        if model.risk.opensURLs { rows.append(("Opens URLs in your browser", "link", .medium)) }
        if model.risk.urlOnly && !model.risk.opensURLs { rows.append(("Only pastes text — no code, no network", "text.quote", .low)) }
        return rows
    }

    private enum RiskSeverity { case low, medium, high }

    private var capabilitiesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Declared capabilities")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            if let caps = model.manifest?.capabilities, !caps.isEmpty {
                Text(caps.joined(separator: ", "))
                    .font(.system(size: 12))
            } else {
                Text("None declared")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Actions")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            ForEach(Array((model.manifest?.actions ?? []).enumerated()), id: \.offset) { _, action in
                HStack {
                    Text(action.title ?? "Untitled")
                        .font(.system(size: 12))
                    Spacer()
                    Text(action.kind.rawValue)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func perform(_ mutation: Mutation) async {
        isMutating = true
        switch mutation {
        case .enable:
            await ExtensionManager.shared.enablePackage(packageID: model.packageID)
        case .disable:
            await ExtensionManager.shared.disablePackage(packageID: model.packageID)
        }
        isMutating = false
        NotificationCenter.default.post(name: .init("OpenClipExtensionsDidChange"), object: nil)
        dismiss()
    }
}