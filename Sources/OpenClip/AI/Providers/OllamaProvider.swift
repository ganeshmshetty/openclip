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

    public func processStream(prompt: String, text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let input = try AIRequestSupport.requireNonEmptyText(text)
                    let systemInstruction = AIRequestSupport.systemPrompt(for: prompt)
                    let userContent = AIRequestSupport.userContent(for: input)
                    let fullPrompt = "\(systemInstruction)\n\n\(userContent)"

                    guard let url = URL(string: "\(baseURL)/api/generate") else {
                        continuation.finish(throwing: AIError.invalidURL("\(baseURL)/api/generate"))
                        return
                    }

                    var request = URLRequest(url: url, timeoutInterval: AIRequestSupport.timeoutInterval)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let body = OllamaGenerateRequest(model: model, prompt: fullPrompt, stream: true)
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: AIError.invalidResponse)
                        return
                    }
                    guard http.statusCode == 200 else {
                        var errorBytes = Data()
                        for try await byte in bytes {
                            errorBytes.append(byte)
                            if errorBytes.count > 1024 { break }
                        }
                        continuation.finish(throwing: AIRequestSupport.httpErrorMessage(status: http.statusCode, data: errorBytes))
                        return
                    }

                    for try await line in bytes.lines {
                        guard !Task.isCancelled else { break }
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, let lineData = trimmed.data(using: .utf8) else { continue }
                        if let decoded = try? JSONDecoder().decode(OllamaGenerateResponse.self, from: lineData) {
                            if let chunk = decoded.response, !chunk.isEmpty {
                                continuation.yield(chunk)
                            }
                            if decoded.done == true {
                                break
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public static func fetchAvailableModels(baseURL: String) async throws -> [String] {
        let normalized = AIRequestSupport.normalizedBaseURL(baseURL, fallback: "http://localhost:11434")
        guard let url = URL(string: "\(normalized)/api/tags") else {
            throw AIError.invalidURL("\(normalized)/api/tags")
        }
        var request = URLRequest(url: url, timeoutInterval: 5)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIError.invalidResponse
        }
        struct OllamaTagsResponse: Decodable {
            struct ModelTag: Decodable {
                let name: String
            }
            let models: [ModelTag]?
        }
        let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return (decoded.models ?? []).map { $0.name }.sorted()
    }
}

private struct OllamaGenerateRequest: Encodable, Sendable {
    let model: String
    let prompt: String
    let stream: Bool
}

private struct OllamaGenerateResponse: Decodable, Sendable {
    let response: String?
    let done: Bool?
}
