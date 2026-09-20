// ExtensionOutputContract.swift
// OpenClip
//
// Defines the domain contract for extension uncommitted outputs (`output`) and delivery
// recommendations (`result`).
import Foundation

/// The kind of uncommitted result an action produces.
public enum ExtensionOutputKind: String, Sendable, Codable, Equatable, CaseIterable {
    case text
    case file
    case none
    case dynamic
}

public typealias ActionOutputKind = ExtensionOutputKind

/// The recommended delivery mechanism for an action's uncommitted result.
public enum ExtensionResultDelivery: String, Sendable, Codable, Equatable, CaseIterable {
    case preview
    case paste
    case copy
    case pasteOrCopy = "paste-or-copy"
    case open
    case save
}

public typealias ActionResultDeliveryMode = ExtensionResultDelivery

public enum ExtensionOutputContract {
    /// Checks whether a given result delivery mode is compatible with the specified output kind.
    public static func isCompatible(output: ExtensionOutputKind, result: ExtensionResultDelivery) -> Bool {
        switch output {
        case .text:
            return result == .preview || result == .paste || result == .copy || result == .pasteOrCopy
        case .file:
            return result == .preview || result == .open || result == .save || result == .copy
        case .dynamic:
            return true
        case .none:
            return false
        }
    }

    /// Returns the default result delivery for a given output kind when `result` is omitted.
    public static func defaultResult(for output: ExtensionOutputKind) -> ExtensionResultDelivery? {
        switch output {
        case .text:
            return .pasteOrCopy
        case .file, .dynamic:
            return .preview
        case .none:
            return nil
        }
    }

    /// Infers the companion output kind when only `result` is declared.
    public static func inferredOutput(for result: ExtensionResultDelivery) -> ExtensionOutputKind {
        switch result {
        case .save, .open:
            return .file
        case .paste, .pasteOrCopy:
            return .text
        case .copy, .preview:
            // Text is the predominant uncommitted kind when output is omitted
            return .text
        }
    }

    /// Resolves the effective output kind and recommended result delivery, taking into account:
    /// 1. Action-level declarations
    /// 2. Manifest-level root defaults
    /// 3. Cross-derivation (output implies default result, result implies output kind)
    /// 4. Compatibility checks (dropping incompatible result with fallback)
    /// 5. Inline action flag (inline: true implies output: .text)
    public static func resolveEffective(
        declaredOutput: ExtensionOutputKind?,
        declaredResult: ExtensionResultDelivery?,
        manifestOutput: ExtensionOutputKind? = nil,
        manifestResult: ExtensionResultDelivery? = nil,
        inline: Bool? = nil
    ) -> (output: ExtensionOutputKind, result: ExtensionResultDelivery?, hadIncompatiblePair: Bool) {
        let rawOutput = declaredOutput ?? manifestOutput
        let rawResult = declaredResult ?? manifestResult

        var output: ExtensionOutputKind? = rawOutput
        var result: ExtensionResultDelivery? = rawResult
        var hadIncompatible = false

        if inline == true {
            output = .text
        }

        if output == nil, let r = result {
            output = inferredOutput(for: r)
        }

        if let o = output {
            if let r = result {
                if !isCompatible(output: o, result: r) {
                    hadIncompatible = true
                    result = defaultResult(for: o)
                }
            } else {
                result = defaultResult(for: o)
            }
        }

        let finalOutput = output ?? .none
        return (finalOutput, result, hadIncompatible)
    }

    public static func resolveEffective(
        action: ExtensionActionMetadata,
        package: ExtensionMetadata? = nil
    ) -> (output: ExtensionOutputKind, result: ExtensionResultDelivery?, hadIncompatiblePair: Bool) {
        resolveEffective(
            declaredOutput: action.output,
            declaredResult: action.result,
            manifestOutput: package?.output,
            manifestResult: package?.result,
            inline: action.inline
        )
    }
}
