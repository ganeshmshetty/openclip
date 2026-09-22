// OpenRouterDecisionProvider.swift
// OpenClip
//
// OpenAI-compatible structured-decision adapter via OpenRouter (or any compatible base URL).
import Foundation
import Core

@MainActor
public final class OpenRouterDecisionProvider: DecisionProvider {
    public let type: DecisionProviderType = .openRouter
    public var apiKey: String
    public var baseURL: String
    public var model: String
    public var session: URLSession

    public init(
        apiKey: String,
        baseURL: String = "https://openrouter.ai/api/v1",
        model: String = "openai/gpt-4o-mini",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = AIRequestSupport.normalizedBaseURL(baseURL, fallback: "https://openrouter.ai/api/v1")
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "openai/gpt-4o-mini" : model
        self.session = session
    }

    public func availability() async -> DecisionProviderAvailability {
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .unavailable(reason: String(localized: "OpenRouter API key not configured."))
        }
        return .available
    }

    public func decide(_ request: DecisionRequest) async throws -> DecisionResponse {
        let status = await availability()
        guard status.isAvailable else {
            if case .unavailable(let reason) = status { throw DecisionError.providerUnavailable(reason) }
            throw DecisionError.providerUnavailable(String(localized: "OpenRouter unavailable."))
        }
        guard !request.state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecisionError.emptyInput
        }
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw DecisionError.invalidURL("\(baseURL)/chat/completions")
        }

        let schemaHint = """
        You are a Decision tool. Judge the user's selection; never rewrite it.
        Reply with ONLY JSON matching:
        {"answers":[{"id":"<question id>","value":<bool|string|string[]|number>,"confidence":0-1,"probabilities":{}}],"confidence":0-1}
        Questions:
        """
        struct QHint: Encodable {
            var id: String
            var type: String
            var prompt: String
            var options: String
        }
        let questionsJSON = String(data: try JSONEncoder().encode(request.questions.map {
            QHint(id: $0.id, type: $0.kind.rawValue, prompt: $0.prompt, options: $0.options.joined(separator: "|"))
        }), encoding: .utf8) ?? "[]"

        let body: [String: Any] = [
            "model": model,
            "temperature": 0,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": schemaHint + questionsJSON],
                ["role": "user", "content": request.state]
            ]
        ]

        var urlRequest = URLRequest(url: url, timeoutInterval: AIRequestSupport.timeoutInterval)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw DecisionError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8).map { String($0.prefix(200)) }
            throw DecisionError.httpStatus(http.statusCode, snippet)
        }

        // Extract message content then parse as DecisionResponse.
        if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = obj["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return try DecisionResponseParser.parse(jsonString: content)
        }
        // Some gateways return the decision JSON at the top level.
        return try DecisionResponseParser.parse(data)
    }
}
