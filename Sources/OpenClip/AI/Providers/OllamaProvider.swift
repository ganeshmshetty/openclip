// OllamaProvider.swift
// OpenClip
//
// Implements AI text processing by connecting to locally hosted Ollama API instances.
import Foundation

@MainActor
public final class OllamaProvider: AIProvider {
    public var type: AIProviderType { .ollama }

    public let baseURL: String
    public let model: String

    public init(baseURL: String, model: String) {
        self.baseURL = AIRequestSupport.normalizedBaseURL(baseURL, fallback: "http://localhost:11434")
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = trimmedModel.isEmpty ? "llama3" : trimmedModel
    }

    public func process(prompt: String, text: String) async throws -> String {
        let input = try AIRequestSupport.requireNonEmptyText(text)
        let instruction = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let systemHeader = "You are an inline text editing tool. Perform the requested task on the user's text and wrap your final result inside <result>...</result> tags."
        let fullPrompt = instruction.isEmpty ? "\(systemHeader)\n\nText: \(input)" : "\(systemHeader)\n\nTask: \(instruction)\nText: \(input)"

        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw AIError.invalidURL("\(baseURL)/api/generate")
        }

        var request = URLRequest(url: url, timeoutInterval: AIRequestSupport.timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = OllamaGenerateRequest(model: model, prompt: fullPrompt, stream: false)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw AIRequestSupport.httpErrorMessage(status: http.statusCode, data: data)
        }

        let decoded = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        let rawResponse = decoded.response?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let responseText = AIRequestSupport.extractResultText(rawResponse)
        guard !responseText.isEmpty else {
            throw AIError.invalidResponse
        }
        return responseText
    }
}

private struct OllamaGenerateRequest: Encodable, Sendable {
    let model: String
    let prompt: String
    let stream: Bool
}

private struct OllamaGenerateResponse: Decodable, Sendable {
    let response: String?
}
