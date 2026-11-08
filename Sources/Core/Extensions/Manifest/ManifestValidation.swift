// ManifestValidation.swift
// OpenClip
//
// Validation pass for extension manifests, run by the loader before any action is created.
// Unknown kinds are rejected rather than silently routed; the capability set starts empty.
//
// Pure Core — no AppKit/SwiftUI.
import Foundation

/// A reason a manifest fails validation, with an index path such as `"actions[0].subActions[2]"`.
public struct ManifestValidationIssue: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case unknownActionKind(String)
        case missingRequiredField(String)
        case unknownCapability(String)
        case duplicateOptionIdentifier(String)
        /// JS authors branch on `openclip.input.isSecondaryClick` instead.
        case secondaryOnJavaScriptAction
        case unsafeScriptPath(String)
        case invalidInlineAction
        case invalidDisplayOnlyAction
        case minimumVersionRequired(feature: String, version: String)
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
        case .invalidInlineAction:
            return "\(path): `inline: true` is only supported on synchronous javascript actions (kind \"js\"/\"javascript\" without \"async: true\", captureRtf, or captureHtml)"
        case .invalidDisplayOnlyAction:
            return "\(path): `displayOnly: true` requires `inline: true` on a synchronous javascript action"
        case .minimumVersionRequired(let feature, let version):
            return "\(path): `\(feature)` requires `minOpenClipVersion` \(version) or newer"
        }
    }
}

public struct ManifestValidationWarning: Sendable, Equatable, CustomStringConvertible {
    public enum Kind: Sendable, Equatable {
        case incompatibleOutputResult(output: ExtensionOutputKind, result: ExtensionResultDelivery)
    }

    public let kind: Kind
    public let path: String

    public init(kind: Kind, path: String) {
        self.kind = kind
        self.path = path
    }

    public var description: String {
        switch kind {
        case .incompatibleOutputResult(let output, let result):
            let fallback = ExtensionOutputContract.defaultResult(for: output)?.rawValue ?? "none"
            return "\(path): incompatible output \"\(output.rawValue)\" and result \"\(result.rawValue)\"; dropping result and defaulting to \(fallback)"
        }
    }
}

/// The outcome of validating one manifest.
public struct ManifestValidationRecord: Sendable, Equatable {
    public let schemaVersion: String
    public let declaredVersion: String?
    /// SHA-256 (hex) of the raw manifest bytes.
    public let fingerprint: String
    public let issues: [ManifestValidationIssue]
    public let warnings: [ManifestValidationWarning]

    public var isValid: Bool { issues.isEmpty }

    public init(
        schemaVersion: String,
        declaredVersion: String?,
        fingerprint: String,
        issues: [ManifestValidationIssue],
        warnings: [ManifestValidationWarning] = []
    ) {
        self.schemaVersion = schemaVersion
        self.declaredVersion = declaredVersion
        self.fingerprint = fingerprint
        self.issues = issues
        self.warnings = warnings
    }
}

/// Rejects any declared capability not in `knownCapabilities`, which starts empty.
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

/// Pure validation of an `ExtensionMetadata` manifest.
public struct ManifestValidator: Sendable {
    public static let shared = ManifestValidator()

    /// The manifest schema/api version this host supports (see `docs/developer-guide/AGENTS.md`).
    public let schemaVersion: String
    public let capabilityGate: ManifestCapabilityGate

    public init(schemaVersion: String = "2", capabilityGate: ManifestCapabilityGate = ManifestCapabilityGate()) {
        self.schemaVersion = schemaVersion
        self.capabilityGate = capabilityGate
    }

    public static func validate(_ manifest: ExtensionMetadata) -> [ManifestValidationIssue] {
        shared.validate(manifest)
    }

    public static func validateWarnings(_ manifest: ExtensionMetadata) -> [ManifestValidationWarning] {
        shared.validateWarnings(manifest)
    }

    public func validate(_ manifest: ExtensionMetadata) -> [ManifestValidationIssue] {
        var issues = capabilityGate.validate(manifest)
        if let options = manifest.options {
            issues.append(contentsOf: validateOptions(options, path: "options"))
        }
        let typedInlineVersionSatisfied = Self.satisfiesMinimumVersion(
            manifest.minOpenClipVersion,
            required: InlineResultValue.minimumOpenClipVersion
        )
        if !typedInlineVersionSatisfied, manifest.output == .color {
            issues.append(ManifestValidationIssue(
                kind: .minimumVersionRequired(feature: "output: \(manifest.output?.rawValue ?? "")", version: InlineResultValue.minimumOpenClipVersion),
                path: "manifest"
            ))
        }
        for (index, action) in manifest.actions.enumerated() {
            issues.append(contentsOf: validateAction(
                action,
                path: "actions[\(index)]",
                inheritedOutput: manifest.output,
                typedInlineVersionSatisfied: typedInlineVersionSatisfied
            ))
        }
        return issues
    }

    private static func satisfiesMinimumVersion(_ declared: String?, required: String) -> Bool {
        guard let minimum = SemanticVersion.parse(required) else { return false }
        guard let declared, let version = SemanticVersion.parse(declared) else { return false }
        return version >= minimum
    }

    public func validateWarnings(_ manifest: ExtensionMetadata) -> [ManifestValidationWarning] {
        var warnings: [ManifestValidationWarning] = []
        if let output = manifest.output, let result = manifest.result {
            if !ExtensionOutputContract.isCompatible(output: output, result: result) {
                warnings.append(ManifestValidationWarning(kind: .incompatibleOutputResult(output: output, result: result), path: "manifest"))
            }
        }
        for (index, action) in manifest.actions.enumerated() {
            warnings.append(contentsOf: validateActionWarnings(action, path: "actions[\(index)]", inheritedOutput: manifest.output))
        }
        return warnings
    }

    private func validateActionWarnings(_ action: ExtensionActionMetadata, path: String, inheritedOutput: ExtensionOutputKind?) -> [ManifestValidationWarning] {
        var warnings: [ManifestValidationWarning] = []
        // A package-level or group output applies to an inline leaf before the legacy text default.
        let effectiveOutput = action.output ?? inheritedOutput ?? (action.inline == true ? .text : nil)
        if let output = effectiveOutput, let result = action.result {
            if !ExtensionOutputContract.isCompatible(output: output, result: result) {
                warnings.append(ManifestValidationWarning(kind: .incompatibleOutputResult(output: output, result: result), path: path))
            }
        }
        if let subActions = action.subActions {
            for (index, sub) in subActions.enumerated() {
                warnings.append(contentsOf: validateActionWarnings(sub, path: "\(path).subActions[\(index)]", inheritedOutput: effectiveOutput))
            }
        }
        return warnings
    }

    public func validate(_ manifest: ExtensionMetadata, data: Data?) -> ManifestValidationRecord {
        let issues = validate(manifest)
        let warnings = validateWarnings(manifest)
        return ManifestValidationRecord(
            schemaVersion: schemaVersion,
            declaredVersion: manifest.version,
            fingerprint: data.map(ContentFingerprint.sha256Hex) ?? "",
            issues: issues,
            warnings: warnings
        )
    }

    private func validateAction(
        _ action: ExtensionActionMetadata,
        path: String,
        inheritedOutput: ExtensionOutputKind? = nil,
        typedInlineVersionSatisfied: Bool = true
    ) -> [ManifestValidationIssue] {
        guard ExtensionActionKind.isRecognized(rawType: action.type) else {
            return [ManifestValidationIssue(kind: .unknownActionKind(action.type ?? ""), path: path)]
        }

        var issues: [ManifestValidationIssue] = []
        // Typed inline output is a new contract; older apps must not treat it as text.
        let effectiveOutput = action.output ?? inheritedOutput ?? (action.inline == true ? .text : nil)
        if !typedInlineVersionSatisfied, effectiveOutput == .color {
            issues.append(ManifestValidationIssue(
                kind: .minimumVersionRequired(feature: "output: \(effectiveOutput?.rawValue ?? "")", version: InlineResultValue.minimumOpenClipVersion),
                path: path
            ))
        }
        switch action.kind {
        case .group:
            if action.subActions?.isEmpty != false {
                issues.append(ManifestValidationIssue(kind: .missingRequiredField("subActions"), path: path))
            }
            for (index, sub) in (action.subActions ?? []).enumerated() {
                issues.append(contentsOf: validateAction(
                    sub,
                    path: "\(path).subActions[\(index)]",
                    inheritedOutput: effectiveOutput,
                    typedInlineVersionSatisfied: typedInlineVersionSatisfied
                ))
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
            // `serviceName` is optional; nothing is required.
            break
        default:
            // Without a payload the factory drops the action, so reject the manifest here.
            if !hasExecutablePayload([action.url, action.script, action.scriptCode]) {
                issues.append(ManifestValidationIssue(kind: .missingRequiredField("url/script/scriptCode"), path: path))
            }
        }
        if action.kind == .js && action.secondary != nil {
            issues.append(ManifestValidationIssue(kind: .secondaryOnJavaScriptAction, path: path))
        }
        if action.inline == true {
            if action.kind != .js || action.isAsync == true || action.captureRtf == true || action.captureHtml == true {
                issues.append(ManifestValidationIssue(
                    kind: .invalidInlineAction,
                    path: path
                ))
            }
        }
        if action.displayOnly == true {
            if action.inline != true || action.kind != .js || action.isAsync == true || action.captureRtf == true || action.captureHtml == true {
                issues.append(ManifestValidationIssue(kind: .invalidDisplayOnlyAction, path: path))
            }
            if !typedInlineVersionSatisfied {
                issues.append(ManifestValidationIssue(
                    kind: .minimumVersionRequired(feature: "displayOnly", version: InlineResultValue.minimumOpenClipVersion),
                    path: path
                ))
            }
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

    /// Rejects only when *all* candidate payload fields are blank.
    private func hasExecutablePayload(_ fields: [String?]) -> Bool {
        !fields.allSatisfy(isBlank)
    }
}
