// JevDecisionProvider.swift
// OpenClip
//
// Cloud BYOK provider for TypeSafe System One (`POST …/systemone`).
import Foundation
import Core

@MainActor
public final class JevDecisionProvider: DecisionProvider {
    public let type: DecisionProviderType = .jev
    public var apiKey: String
    public var baseURL: String
    public var session: URLSession

    public init(apiKey: String, baseURL: String = "https://api.typesafe.ai/v1", session: URLSession = .shared) {
        self.apiKey = apiKey
        self.baseURL = AIRequestSupport.normalizedBaseURL(baseURL, fallback: "https://api.typesafe.ai/v1")
        self.session = session
    }

    public func availability() async -> DecisionProviderAvailability {
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .unavailable(reason: String(localized: "Jev API key not configured."))
        }
        return .available
    }

    public func decide(_ request: DecisionRequest) async throws -> DecisionResponse {
        let status = await availability()
        guard status.isAvailable else {
            if case .unavailable(let reason) = status { throw DecisionError.providerUnavailable(reason) }
            throw DecisionError.providerUnavailable(String(localized: "Jev unavailable."))
        }
        guard !request.state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecisionError.emptyInput
        }
        guard let url = URL(string: "\(baseURL)/systemone") else {
            throw DecisionError.invalidURL("\(baseURL)/systemone")
        }
        var urlRequest = URLRequest(url: url, timeoutInterval: AIRequestSupport.timeoutInterval)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try DecisionQuestionPacker.encodeRequest(request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw DecisionError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIRequestSupport.httpErrorMessage(status: http.statusCode, data: data).asDecisionError
        }
        return try DecisionResponseParser.parse(data)
    }
}

private extension AIError {
    var asDecisionError: DecisionError {
        switch self {
        case .httpStatus(let code, let body): return .httpStatus(code, body)
        case .missingAPIKey: return .missingAPIKey
        case .invalidURL(let u): return .invalidURL(u)
        case .invalidResponse: return .invalidResponse
        case .cancelled: return .cancelled
        case .emptyInput: return .emptyInput
        case .providerUnavailable(let m): return .providerUnavailable(m)
        default: return .invalidResponse
        }
    }
}
