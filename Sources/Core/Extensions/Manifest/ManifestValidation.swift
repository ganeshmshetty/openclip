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
        /// An action's option identifier is defined more than once.
        case duplicateOptionIdentifier(String)
        /// A `javascript` action declares `secondary`, which is reserved for non-scripting kinds;
        /// JS authors branch on `openclip.input.isSecondaryClick` instead.
        case secondaryOnJavaScriptAction
        /// An action declares a script path that escapes the package directory or uses an absolute path.
        case unsafeScriptPath(String)
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
        case .duplicateOptionIdentifier(let identifier):
            return "\(path): duplicate option identifier \"\(identifier)\""
        case .secondaryOnJavaScriptAction:
            return "\(path): `secondary` is not supported on javascript actions; branch on `openclip.input.isSecondaryClick` in the script instead"
        case .unsafeScriptPath(let script):
            return "\(path): script path escapes extension directory \"\(script)\""
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
        if let options = manifest.options {
            issues.append(contentsOf: validateOptions(options, path: "options"))
        }
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
            fingerprint: data.map(ContentFingerprint.sha256Hex) ?? "",
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
        case .shortcut:
            if isBlank(action.shortcutName) {
                issues.append(ManifestValidationIssue(kind: .missingRequiredField("shortcutName"), path: path))
            }
        case .service:
            // `serviceName` is optional; it identifies a sharing service (or service-menu name) to
            // invoke. Nothing is required.
            break
        default:
            // Every other runnable kind needs at least one executable payload. Without any, the
            // factory deterministically drops the action — a schema error, so reject the manifest.
            if !hasExecutablePayload([action.url, action.script, action.scriptCode]) {
                issues.append(ManifestValidationIssue(kind: .missingRequiredField("url/script/scriptCode"), path: path))
            }
        }
        if action.kind == .js && action.secondary != nil {
            issues.append(ManifestValidationIssue(kind: .secondaryOnJavaScriptAction, path: path))
        }
        if let options = action.options {
            issues.append(contentsOf: validateOptions(options, path: path))
        }
        if let script = action.script, !isSafeScriptPath(script) {
            issues.append(ManifestValidationIssue(kind: .unsafeScriptPath(script), path: path))
        }
        return issues
    }

    private func isSafeScriptPath(_ script: String) -> Bool {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~"), !trimmed.contains(":") else {
            return false
        }
        let dummyBase = URL(fileURLWithPath: "/extension_root")
        let destination = dummyBase.appendingPathComponent(trimmed)
        guard Constants.isPathSafe(destinationURL: destination, baseDirectory: dummyBase) else {
            return false
        }
        return destination.standardized.path != dummyBase.standardized.path
    }

    private func validateOptions(_ options: [ExtensionOptionMetadata], path: String) -> [ManifestValidationIssue] {
        var issues: [ManifestValidationIssue] = []
        var seenIdentifiers = Set<String>()
        for option in options {
            let id = option.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            if seenIdentifiers.contains(id) {
                issues.append(ManifestValidationIssue(kind: .duplicateOptionIdentifier(id), path: path))
            } else {
                seenIdentifiers.insert(id)
            }
        }
        return issues
    }

    private func isBlank(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }

    /// Whether at least one candidate payload field carries non-blank content. Kinds that run from
    /// a payload (inline `scriptCode`, `script` file, `url`) reject a manifest only when *all* of
    /// their candidate fields are blank.
    private func hasExecutablePayload(_ fields: [String?]) -> Bool {
        !fields.allSatisfy(isBlank)
    }
}
