// CloudAPIProvider.swift
// OpenClip
//
// Implements AI processing by querying cloud-based LLM API endpoints (such as OpenAI or Anthropic).
import Foundation

@MainActor
public final class CloudAPIProvider: AIProvider {
    public var type: AIProviderType { .cloud }

    public let apiKey: String
    public let model: String
    public let serviceProvider: CloudServiceProvider
    public let customBaseURL: String

    public init(apiKey: String, model: String, serviceProvider: CloudServiceProvider = .openai, customBaseURL: String = "") {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = trimmedModel.isEmpty ? (serviceProvider.defaultModels.first ?? "gpt-4o-mini") : trimmedModel
        self.serviceProvider = serviceProvider
        self.customBaseURL = customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func process(prompt: String, text: String) async throws -> String {
        let input = try AIRequestSupport.requireNonEmptyText(text)
        guard !apiKey.isEmpty else {
            throw AIError.missingAPIKey
        }

        let instruction = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let userContent = instruction.isEmpty ? input : "\(instruction): \(input)"

        switch serviceProvider {
        case .anthropic:
            return try await processAnthropic(userContent: userContent)
        case .google:
            return try await processGemini(userContent: userContent)
        case .openai, .deepseek, .groq, .openrouter, .custom:
            let baseURL = effectiveBaseURL
            return try await processOpenAICompatible(userContent: userContent, baseURL: baseURL)
        }
    }

    public var effectiveBaseURL: String {
        if serviceProvider == .custom {
            return customBaseURL.isEmpty ? "https://api.openai.com/v1" : customBaseURL
        }
        return serviceProvider.defaultBaseURL
    }

    // MARK: - OpenAI-compatible chat completions

    private func processOpenAICompatible(userContent: String, baseURL: String) async throws -> String {
        let endpoint = baseURL.hasSuffix("/") ? "\(baseURL)chat/completions" : "\(baseURL)/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw AIError.invalidURL(endpoint)
        }

        var request = URLRequest(url: url, timeoutInterval: AIRequestSupport.timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = OpenAIChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: "You are an inline text editing tool. Perform the requested task on the user's text and wrap your final result inside <result>...</result> tags."),
                .init(role: "user", content: userContent)
            ]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw AIRequestSupport.httpErrorMessage(status: http.statusCode, data: data)
        }

        let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        let rawContent = decoded.choices?.first?.message?.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let content = AIRequestSupport.sanitizeResponseText(rawContent)
        guard !content.isEmpty else {
            throw AIError.invalidResponse
        }
        return content
    }

    // MARK: - Anthropic Messages API

    private func processAnthropic(userContent: String) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw AIError.invalidURL("https://api.anthropic.com/v1/messages")
        }

        var request = URLRequest(url: url, timeoutInterval: AIRequestSupport.timeoutInterval)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = AnthropicMessagesRequest(
            model: model,
            maxTokens: 1024,
            system: "You are an inline text editing tool. Perform the requested task on the user's text and wrap your final result inside <result>...</result> tags.",
            messages: [.init(role: "user", content: userContent)]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw AIRequestSupport.httpErrorMessage(status: http.statusCode, data: data)
        }

        let decoded = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
        let rawContent = decoded.content?
            .compactMap { $0.text }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let content = AIRequestSupport.sanitizeResponseText(rawContent)
        guard !content.isEmpty else {
            throw AIError.invalidResponse
        }
        return content
    }

    public static func fetchAvailableModels(apiKey: String, provider: CloudServiceProvider, customBaseURL: String = "") async throws -> [String] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw AIError.missingAPIKey
        }

        switch provider {
        case .anthropic:
            return try await fetchAnthropicModels(apiKey: trimmedKey)
        case .google:
            return try await fetchGeminiModels(apiKey: trimmedKey)
        case .openai, .deepseek, .groq, .openrouter, .custom:
            let baseURL = provider == .custom ? (customBaseURL.isEmpty ? "https://api.openai.com/v1" : customBaseURL) : provider.defaultBaseURL
            return try await fetchOpenAICompatibleModels(apiKey: trimmedKey, baseURL: baseURL)
        }
    }

    private static func fetchOpenAICompatibleModels(apiKey: String, baseURL: String) async throws -> [String] {
        let endpoint = baseURL.hasSuffix("/") ? "\(baseURL)models" : "\(baseURL)/models"
        guard let url = URL(string: endpoint) else {
            throw AIError.invalidURL(endpoint)
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIError.invalidResponse
        }

        struct ModelListResponse: Decodable {
            struct ModelItem: Decodable {
                let id: String
            }
            let data: [ModelItem]?
        }

        let decoded = try JSONDecoder().decode(ModelListResponse.self, from: data)
        let modelIds = (decoded.data ?? []).map { $0.id }
        let filtered = modelIds.filter { id in
            let l = id.lowercased()
            return l.contains("gpt") || l.contains("o1") || l.contains("o3") || l.contains("chat")
        }.sorted()

        return filtered.isEmpty ? modelIds.sorted() : filtered
    }

    private static func fetchAnthropicModels(apiKey: String) async throws -> [String] {
        guard let url = URL(string: "https://api.anthropic.com/v1/models") else {
            throw AIError.invalidURL("https://api.anthropic.com/v1/models")
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIError.invalidResponse
        }

        struct AnthropicModelListResponse: Decodable {
            struct ModelItem: Decodable {
                let id: String
            }
            let data: [ModelItem]?
        }

        let decoded = try JSONDecoder().decode(AnthropicModelListResponse.self, from: data)
        return (decoded.data ?? []).map { $0.id }.sorted()
    }

    private static func fetchGeminiModels(apiKey: String) async throws -> [String] {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)") else {
            throw AIError.invalidURL("https://generativelanguage.googleapis.com/v1beta/models")
        }

        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIError.invalidResponse
        }

        struct GeminiModelListResponse: Decodable {
            struct ModelItem: Decodable {
                let name: String
            }
            let models: [ModelItem]?
        }

        let decoded = try JSONDecoder().decode(GeminiModelListResponse.self, from: data)
        let ids = (decoded.models ?? []).map { item in
            item.name.replacingOccurrences(of: "models/", with: "")
        }.filter { $0.contains("gemini") }.sorted()

        return ids.isEmpty ? ["gemini-2.0-flash", "gemini-1.5-flash", "gemini-1.5-pro"] : ids
    }

    // MARK: - Google Gemini API

    private func processGemini(userContent: String) async throws -> String {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else {
            throw AIError.invalidURL("https://generativelanguage.googleapis.com/v1beta/models/\(model)")
        }

        var request = URLRequest(url: url, timeoutInterval: AIRequestSupport.timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = GeminiChatRequest(
            systemInstruction: .init(parts: [.init(text: "You are an inline text editing tool. Perform the requested task on the user's text and wrap your final result inside <result>...</result> tags.")]),
            contents: [.init(parts: [.init(text: userContent)])]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw AIRequestSupport.httpErrorMessage(status: http.statusCode, data: data)
        }

        let decoded = try JSONDecoder().decode(GeminiChatResponse.self, from: data)
        let rawContent = decoded.candidates?.first?.content?.parts?.first?.text?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let content = AIRequestSupport.sanitizeResponseText(rawContent)
        guard !content.isEmpty else {
            throw AIError.invalidResponse
        }
        return content
    }
}

// MARK: - Codable payloads

private struct OpenAIChatRequest: Encodable, Sendable {
    struct Message: Encodable, Sendable {
        let role: String
        let content: String
    }
    let model: String
    let messages: [Message]
}

private struct OpenAIChatResponse: Decodable, Sendable {
    struct Choice: Decodable, Sendable {
        struct Message: Decodable, Sendable {
            let content: String?
        }
        let message: Message?
    }
    let choices: [Choice]?
}

private struct AnthropicMessagesRequest: Encodable, Sendable {
    struct Message: Encodable, Sendable {
        let role: String
        let content: String
    }

    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
    }
}

private struct AnthropicMessagesResponse: Decodable, Sendable {
    struct ContentBlock: Decodable, Sendable {
        let type: String?
        let text: String?
    }
    let content: [ContentBlock]?
}

private struct GeminiChatRequest: Encodable, Sendable {
    struct Part: Encodable, Sendable {
        let text: String
    }
    struct Content: Encodable, Sendable {
        let parts: [Part]
    }
    struct SystemInstruction: Encodable, Sendable {
        let parts: [Part]
    }

    let systemInstruction: SystemInstruction?
    let contents: [Content]

    enum CodingKeys: String, CodingKey {
        case systemInstruction = "system_instruction"
        case contents
    }
}

private struct GeminiChatResponse: Decodable, Sendable {
    struct Candidate: Decodable, Sendable {
        struct Content: Decodable, Sendable {
            struct Part: Decodable, Sendable {
                let text: String?
            }
            let parts: [Part]?
        }
        let content: Content?
    }
    let candidates: [Candidate]?
}
