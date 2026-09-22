// DecisionProvider.swift
// OpenClip
//
// Protocol and errors for Decision backends (Jev / Laya).
import Foundation
import Core

public enum DecisionProviderType: String, CaseIterable, Identifiable, Sendable {
    case jev = "jev"
    case laya = "laya"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .jev: return String(localized: "Jev (TypeSafe System One)")
        case .laya: return String(localized: "Laya (local CLI)")
        }
    }
}

public enum DecisionProviderAvailability: Sendable, Equatable {
    case available
    case unavailable(reason: String)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

public enum DecisionError: Error, LocalizedError, Sendable, Equatable {
    case emptyInput
    case missingAPIKey
    case invalidURL(String)
    case invalidResponse
    case httpStatus(Int, String?)
    case providerUnavailable(String)
    case cancelled
    case lowConfidence
    case bulkBudgetExceeded

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return String(localized: "No text selected to judge.")
        case .missingAPIKey:
            return String(localized: "API key required. Configure it in Preferences → Decisions.")
        case .invalidURL(let value):
            return String(localized: "Invalid URL: \(value)")
        case .invalidResponse:
            return String(localized: "The decision provider returned an empty or unreadable response.")
        case .httpStatus(let code, let body):
            if let body, !body.isEmpty {
                return String(localized: "Decision request failed (HTTP \(code)): \(body)")
            }
            return String(localized: "Decision request failed (HTTP \(code)).")
        case .providerUnavailable(let message):
            return message
        case .cancelled:
            return String(localized: "Decision request was cancelled.")
        case .lowConfidence:
            return String(localized: "Confidence too low — fail closed.")
        case .bulkBudgetExceeded:
            return String(localized: "Bulk decision budget exceeded.")
        }
    }
}

@MainActor
public protocol DecisionProvider: AnyObject {
    var type: DecisionProviderType { get }
    func availability() async -> DecisionProviderAvailability
    func decide(_ request: DecisionRequest) async throws -> DecisionResponse
}
