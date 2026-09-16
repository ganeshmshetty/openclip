// AppleIntelligenceAvailability.swift
// OpenClip
//
// Reports whether Apple Intelligence's on-device model can serve a request on this Mac and turns
// each cause of unavailability into copy the user can act on. Keeping this in one place means the
// Preferences status row and the provider's runtime errors never disagree about *why* the feature
// is off.
import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AppleIntelligenceAvailability {
    /// Every distinct reason the on-device model can be unusable. The OS floor is folded in here
    /// so callers never have to think about `#available` themselves.
    enum Status: Equatable {
        case available
        case unsupportedOS
        case deviceNotEligible
        case notEnabled
        case modelNotReady
        case unknown

        var isAvailable: Bool { self == .available }
    }

    static var current: Status {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .deviceNotEligible
                case .appleIntelligenceNotEnabled:
                    return .notEnabled
                case .modelNotReady:
                    return .modelNotReady
                @unknown default:
                    return .unknown
                }
            @unknown default:
                return .unknown
            }
        }
        #endif
        return .unsupportedOS
    }

    static var isAvailable: Bool { current.isAvailable }

    /// Short label for the Preferences status row.
    static func statusLabel(for status: Status) -> String {
        switch status {
        case .available:
            return String(localized: "Available")
        case .unsupportedOS:
            return String(localized: "Requires macOS 26 or later")
        case .deviceNotEligible:
            return String(localized: "Not supported on this Mac")
        case .notEnabled:
            return String(localized: "Turn on in System Settings")
        case .modelNotReady:
            return String(localized: "Model still downloading")
        case .unknown:
            return String(localized: "Unavailable")
        }
    }

    /// Actionable sentence used as the provider's runtime error. Points at the specific fix — the
    /// System Settings toggle, a retry, or switching provider — rather than a generic failure.
    static func unavailableExplanation(for status: Status) -> String {
        switch status {
        case .available:
            return String(localized: "Apple Intelligence is available.")
        case .unsupportedOS:
            return String(localized: "Apple Intelligence requires macOS 26.0+ with supported Apple Silicon hardware. Configure another provider in Preferences → AI.")
        case .deviceNotEligible:
            return String(localized: "This Mac doesn't support Apple Intelligence. Configure another provider in Preferences → AI.")
        case .notEnabled:
            return String(localized: "Turn on Apple Intelligence in System Settings → Apple Intelligence & Siri, or configure another provider in Preferences → AI.")
        case .modelNotReady:
            return String(localized: "Apple Intelligence models are still downloading. Try again shortly, or configure another provider in Preferences → AI.")
        case .unknown:
            return String(localized: "Apple Intelligence is unavailable right now. Configure another provider in Preferences → AI.")
        }
    }

    static var unavailableExplanation: String {
        unavailableExplanation(for: current)
    }
}
