// ManifestValidation.swift
// OpenClip
//
// Validation pass for extension manifests. The loader (`ExtensionManager`) runs this before any
// action is created: unknown/unsupported action kinds are rejected instead of silently routing
// elsewhere, required fields are checked, and the schema/api version and a fingerprint of the
// manifest are recorded for observability. The capability gate is generic with an intentionally
// **empty** known set on day one, so any declared capability rejects the manifest.
//
// Pure Core — no AppKit/SwiftUI.
import Foundation
import CryptoKit

/// A single reason a manifest fails validation, with an index path into the manifest
/// (e.g. `"actions[0]"` or `"actions[0].subActions[2]"`) for grouping into a readable log line.
public struct ManifestValidationIssue: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// The action's `type` string is not a recognized action kind.
        case unknownActionKind(String)
        /// The action is missing a field its kind requires.
        case missingRequiredField(String)
        /// The manifest declares a capability outside the host's known set.
        case unknownCapability(String)
    }

    public let kind: Kind
    public let path: String

    public init(kind: Kind, path: String) {
        self.kind = kind
        self.path = path
    }
}

extension ManifestValidationIssue: CustomStringConvertible {
    public var description: String {
        switch kind {
        case .unknownActionKind(let rawType):
            return "\(path): unknown action kind \"\(rawType)\""
        case .missingRequiredField(let field):
            return "\(path): missing required field \"\(field)\""
        case .unknownCapability(let name):
            return "\(path): unknown capability \"\(name)\""
        }
    }
}

/// The outcome of validating one manifest: the host's supported schema version, the manifest's
/// declared version when present, a content fingerprint of the manifest data, and any issues.
public struct ManifestValidationRecord: Sendable, Equatable {
    /// The manifest schema/api version this host supports.
    public let schemaVersion: String
    /// The manifest's own `version` field when present.
    public let declaredVersion: String?
    /// SHA-256 (hex) of the raw manifest data — a stable content fingerprint for the exact bytes
    /// that were loaded.
    public let fingerprint: String
    public let issues: [ManifestValidationIssue]

    public var isValid: Bool { issues.isEmpty }

    public init(schemaVersion: String, declaredVersion: String?, fingerprint: String, issues: [ManifestValidationIssue]) {
        self.schemaVersion = schemaVersion
        self.declaredVersion = declaredVersion
        self.fingerprint = fingerprint
        self.issues = issues
    }
}

/// Validates a manifest's declared capabilities against the host's known set. The known set is
/// intentionally **empty** on day one: any declared capability is unknown and rejects the manifest.
/// The mechanism is generic — add a capability by seeding `knownCapabilities` — without reserving
/// any not-yet-real slots.
public struct ManifestCapabilityGate: Sendable {
    public let knownCapabilities: Set<String>

    public init(knownCapabilities: Set<String> = []) {
        self.knownCapabilities = knownCapabilities
    }

    public func validate(_ manifest: ExtensionMetadata) -> [ManifestValidationIssue] {
        guard let declared = manifest.capabilities, !declared.isEmpty else { return [] }
        let normalized = Set(declared.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        return normalized
            .subtracting(knownCapabilities)
            .sorted()
            .map { ManifestValidationIssue(kind: .unknownCapability($0), path: "manifest") }
    }
}

/// Pure, side-effect-free validation of an `ExtensionMetadata` manifest. Used by the loader before
/// any action is materialized.
public struct ManifestValidator: Sendable {
    public static let shared = ManifestValidator()

    /// The manifest schema/api version this host supports (see `docs/developer-guide/AGENTS.md`).
    public let schemaVersion: String
    public let capabilityGate: ManifestCapabilityGate

    public init(schemaVersion: String = "2", capabilityGate: ManifestCapabilityGate = ManifestCapabilityGate()) {
        self.schemaVersion = schemaVersion
        self.capabilityGate = capabilityGate
    }

    /// Validates `manifest`, returning every issue found (empty when it passes).
    public func validate(_ manifest: ExtensionMetadata) -> [ManifestValidationIssue] {
        var issues = capabilityGate.validate(manifest)
        for (index, action) in manifest.actions.enumerated() {
            issues.append(contentsOf: validateAction(action, path: "actions[\(index)]"))
        }
        return issues
    }

    /// Validates `manifest` against the manifest data, producing a record with the schema version,
    /// declared version, content fingerprint, and issues.
    public func validate(_ manifest: ExtensionMetadata, data: Data?) -> ManifestValidationRecord {
        ManifestValidationRecord(
            schemaVersion: schemaVersion,
            declaredVersion: manifest.version,
            fingerprint: data.map(Self.sha256Hex) ?? "",
            issues: validate(manifest)
        )
    }

    private func validateAction(_ action: ExtensionActionMetadata, path: String) -> [ManifestValidationIssue] {
        guard ExtensionActionKind.isRecognized(rawType: action.type) else {
            return [ManifestValidationIssue(kind: .unknownActionKind(action.type ?? ""), path: path)]
        }

        var issues: [ManifestValidationIssue] = []
        switch action.kind {
        case .group:
            if action.subActions?.isEmpty != false {
                issues.append(ManifestValidationIssue(kind: .missingRequiredField("subActions"), path: path))
            }
            for (index, sub) in (action.subActions ?? []).enumerated() {
                issues.append(contentsOf: validateAction(sub, path: "\(path).subActions[\(index)]"))
            }
        case .keyPress:
            if isBlank(action.keyPress) {
                issues.append(ManifestValidationIssue(kind: .missingRequiredField("keyPress"), path: path))
            }
        case .canvas:
            if isBlank(action.scriptCode) {
                issues.append(ManifestValidationIssue(kind: .missingRequiredField("scriptCode"), path: path))
            }
        case .shortcut:
            if isBlank(action.shortcutName) {
                issues.append(ManifestValidationIssue(kind: .missingRequiredField("shortcutName"), path: path))
            }
        case .service:
            // `serviceName` is accepted but currently unused; nothing is required.
            break
        default:
            // Every other runnable kind needs at least one executable payload. Without any, the
            // factory deterministically drops the action — a schema error, so reject the manifest.
            if [action.url, action.script, action.scriptCode].allSatisfy(isBlank) {
                issues.append(ManifestValidationIssue(kind: .missingRequiredField("url/script/scriptCode"), path: path))
            }
        }
        return issues
    }

    private func isBlank(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }

    private static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
