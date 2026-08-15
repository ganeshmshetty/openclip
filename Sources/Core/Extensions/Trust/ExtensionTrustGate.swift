// ExtensionTrustGate.swift
// OpenClip
//
// The fail-closed consent gate. Groups already-scanned actions by package, resolves each
// package's trust state against the persisted trust/hash/source records, and returns the final
// action list (real actions or a single GatedExtensionAction per gated package) plus the dict
// writes and events the caller must apply. Pure Core, no side effects besides file reads.
import Foundation

public enum ExtensionGateReason: Sendable, Equatable {
    case notEnabled
    case filesChanged
    case needsNewerApp(required: String)
    case revoked
}

/// Placeholder action registered in place of a package's real actions when the package must not
/// run (not enabled / files changed / revoked / incompatible). Keeps the package discoverable in
/// the bar and Preferences; clicking it surfaces a review toast. `isEnabled` returns true so the
/// row appears — the gate, not the enable toggle, is what blocks execution.
public struct GatedExtensionAction: Action {
    public let packageID: String
    public let title: String
    public let icon: ActionIcon
    public let chrome: ActionChrome
    public let reason: ExtensionGateReason

    public init(packageID: String, title: String, icon: ActionIcon, chrome: ActionChrome, reason: ExtensionGateReason) {
        self.packageID = packageID
        self.title = title
        self.icon = icon
        self.chrome = chrome
        self.reason = reason
    }

    public var id: String { packageID }

    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool { true }

    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        .toast(StatusFeedback(message: Self.reviewMessage(for: reason), style: .info))
    }

    public static func reviewMessage(for reason: ExtensionGateReason) -> String {
        switch reason {
        case .notEnabled: return "This extension isn't enabled yet — review it in Preferences."
        case .filesChanged: return "This extension was disabled because its files changed — review it in Preferences."
        case .needsNewerApp(let required): return "This extension needs OpenClip \(required) or newer."
        case .revoked: return "This extension is disabled — enable it in Preferences."
        }
    }
}

/// The result of one gating pass: the actions to register plus the settings writes to apply.
public struct ExtensionGatePlan: Sendable {
    public let actions: [any Action]
    public let trust: [String: String]
    public let hashes: [String: String]
    public let sources: [String: String]
    public let isMigrated: Bool
    public let events: [ExtensionTrustChange]
    public let trustChanged: Bool
    public let hashesChanged: Bool
    public let sourcesChanged: Bool
    public let migratedChanged: Bool

    public init(actions: [any Action], trust: [String: String], hashes: [String: String], sources: [String: String], isMigrated: Bool, events: [ExtensionTrustChange], trustChanged: Bool, hashesChanged: Bool, sourcesChanged: Bool, migratedChanged: Bool) {
        self.actions = actions
        self.trust = trust
        self.hashes = hashes
        self.sources = sources
        self.isMigrated = isMigrated
        self.events = events
        self.trustChanged = trustChanged
        self.hashesChanged = hashesChanged
        self.sourcesChanged = sourcesChanged
        self.migratedChanged = migratedChanged
    }
}

public enum ExtensionTrustGate {
    public static func evaluate(
        actions: [any Action],
        in directory: URL,
        trust: [String: String],
        hashes: [String: String],
        sources: [String: String],
        isMigrated: Bool,
        appVersion: String
    ) -> ExtensionGatePlan {
        var trust = trust
        var hashes = hashes
        var sources = sources
        var newMigrated = isMigrated
        var migratedChanged = false
        var trustChanged = false
        var hashesChanged = false
        var sourcesChanged = false
        var events: [ExtensionTrustChange] = []
        var result: [any Action] = []

        var packages: [String: [any Action]] = [:]
        for action in actions {
            guard let packageID = ActionIdentity.extensionPackageID(of: action) else {
                result.append(action)
                continue
            }
            packages[packageID, default: []].append(action)
        }

        for (packageID, packageActions) in packages.sorted(by: { $0.key < $1.key }) {
            let representative = packageActions[0]
            let name = {
                if case .extensionPkg(let packageName) = representative.chrome.badge { return packageName }
                return packageID
            }()
            let icon = representative.icon
            let chrome = ActionChrome(
                badge: .extensionPkg(name),
                rowStyle: .standard,
                popupBehavior: .perform,
                source: .extensionPkg(packageID: packageID)
            )
            let currentHash = ExtensionPackageHashResolver.packageHash(for: representative, in: directory) ?? ""
            let record = trust[packageID]
            let source = sources[packageID] ?? "local"
            let required = ExtensionManifestStore.manifest(forPackageID: packageID, in: directory)?.openClipVersion
            let compatible = isCompatible(appVersion: appVersion, required: required)

            func gated(_ reason: ExtensionGateReason) {
                result.append(GatedExtensionAction(packageID: packageID, title: name, icon: icon, chrome: chrome, reason: reason))
            }
            func real() {
                result.append(contentsOf: packageActions)
            }
            func writeTrusted() {
                if trust[packageID] != "trusted" || hashes[packageID] != currentHash {
                    trust[packageID] = "trusted"
                    hashes[packageID] = currentHash
                    trustChanged = true
                    hashesChanged = true
                }
            }

            if source == "store" {
                if record == "revoked" {
                    gated(.revoked)
                } else {
                    // Store is the trust anchor: trust (or re-trust) with the current hash.
                    writeTrusted()
                    if source != (sources[packageID] ?? "local") {
                        sources[packageID] = "store"
                        sourcesChanged = true
                    }
                    if compatible { real() } else { gated(.needsNewerApp(required: required ?? "")) }
                }
            } else if record == "trusted", hashes[packageID] == currentHash {
                if compatible { real() } else { gated(.needsNewerApp(required: required ?? "")) }
            } else if record == "trusted" {
                trust[packageID] = "seen"
                trustChanged = true
                events.append(.tampered(packageID: packageID, name: name))
                gated(.filesChanged)
            } else if record == "revoked" {
                gated(.revoked)
            } else if record == nil {
                if !newMigrated {
                    // First launch after upgrade: auto-trust everything present.
                    writeTrusted()
                    if compatible { real() } else { gated(.needsNewerApp(required: required ?? "")) }
                } else {
                    trust[packageID] = "seen"
                    trustChanged = true
                    events.append(.newPackage(packageID: packageID, name: name))
                    gated(.notEnabled)
                }
            } else {
                // "seen"
                gated(.notEnabled)
            }
        }

        if !newMigrated {
            newMigrated = true
            migratedChanged = true
        }

        return ExtensionGatePlan(
            actions: result,
            trust: trust,
            hashes: hashes,
            sources: sources,
            isMigrated: newMigrated,
            events: events,
            trustChanged: trustChanged,
            hashesChanged: hashesChanged,
            sourcesChanged: sourcesChanged,
            migratedChanged: migratedChanged
        )
    }

    static func isCompatible(appVersion: String, required: String?) -> Bool {
        guard let required, let requirement = SemanticVersion.parse(required),
              let running = SemanticVersion.parse(appVersion) else {
            // Absent/malformed requirement or unreadable running version → treat as compatible.
            return true
        }
        return running >= requirement
    }
}