// LocalLLMProvider.swift
// OpenClip
//
// Universal AI text processing for locally hosted LLM runners (LM Studio, Ollama, Jan, llama.cpp, LocalAI).
// Uses the standard OpenAI-compatible /v1/chat/completions SSE format with automatic fallback to Ollama's native /api/generate.
import Foundation
import Core

public enum LocalLLMPreset: String, CaseIterable, Identifiable, Sendable {
    case lmstudio = "lmstudio"
    case ollama = "ollama"
    case jan = "jan"
    case llamacpp = "llamacpp"
    case custom = "custom"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .lmstudio: return "LM Studio"
        case .ollama: return "Ollama"
        case .jan: return "Jan"
        case .llamacpp: return "llama.cpp / LocalAI"
        case .custom: return "Custom Local Server"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .lmstudio: return "http://localhost:1234/v1"
        case .ollama: return "http://localhost:11434/v1"
        case .jan: return "http://localhost:1337/v1"
        case .llamacpp: return "http://localhost:8080/v1"
        case .custom: return "http://localhost:1234/v1"
        }
    }

    public var defaultModels: [String] {
        switch self {
        case .lmstudio: return ["default"]
        case .ollama: return ["llama3.2", "llama3.1", "qwen2.5", "mistral", "deepseek-r1"]
        case .jan: return ["default"]
        case .llamacpp: return ["default"]
        case .custom: return ["default"]
        }
    }

    public var primaryModel: String {
        switch self {
        case .lmstudio: return "qwen2.5-coder-7b-instruct"
        case .ollama: return "llama3.2"
        case .jan: return "mistral"
        case .llamacpp: return "default"
        case .custom: return "default"
        }
    }
}

@MainActor
public final class LocalLLMProvider: AIProvider {
    public var type: AIProviderType { .local }

    public let baseURL: String
    public let model: String

    public init(baseURL: String, model: String) {
        self.baseURL = AIRequestSupport.normalizedBaseURL(baseURL, fallback: "http://localhost:1234/v1")
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = trimmedModel.isEmpty ? "default" : trimmedModel
    }

    public func processStream(prompt: String, text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let validated = try AIRequestSupport.validateInput(prompt: prompt, text: text)
                    let hasInputText = !validated.text.isEmpty
                    let systemInstruction = AIRequestSupport.systemPrompt(for: validated.prompt, hasInputText: hasInputText)
                    let userContent = AIRequestSupport.userContent(for: validated.text, fallbackPrompt: validated.prompt)

                    // 1. Try standard OpenAI-compatible /chat/completions endpoint
                    let chatURL = Self.resolveChatCompletionsURL(baseURL: baseURL)
                    if let chatURL {
                        do {
                            var request = URLRequest(url: chatURL, timeoutInterval: AIRequestSupport.timeoutInterval)
                            request.httpMethod = "POST"
                            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                            let body = OpenAIChatRequest(
                                model: model,
                                messages: [
                                    .init(role: "system", content: systemInstruction),
                                    .init(role: "user", content: userContent)
                                ],
                                stream: true
                            )
                            request.httpBody = try JSONEncoder().encode(body)

                            let (bytes, response) = try await URLSession.shared.bytes(for: request)
                            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                                struct StreamChunk: Decodable {
                                    struct Choice: Decodable {
                                        struct Delta: Decodable {
                                            let content: String?
                                        }
                                        let delta: Delta?
                                    }
                                    let choices: [Choice]?
                                }

                                for try await line in bytes.lines {
                                    guard !Task.isCancelled else { break }
                                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard trimmed.hasPrefix("data:") else { continue }
                                    let dataStr = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                                    if dataStr == "[DONE]" { break }
                                    guard let chunkData = dataStr.data(using: .utf8) else { continue }
                                    if let decoded = try? JSONDecoder().decode(StreamChunk.self, from: chunkData),
                                       let content = decoded.choices?.first?.delta?.content, !content.isEmpty {
                                        continuation.yield(content)
                                    }
                                }
                                continuation.finish()
                                return
                            }
                        } catch {
                            // If cancellation, rethrow
                            if Task.isCancelled { throw error }
                            Log.ai.debug("OpenAI-compatible chat completion failed on \(chatURL.absoluteString); trying Ollama native fallback: \(error.localizedDescription)")
                        }
                    }

                    // 2. Fallback to native Ollama /api/generate endpoint if chat completions unavailable
                    let ollamaURL = Self.resolveOllamaGenerateURL(baseURL: baseURL)
                    guard let ollamaURL else {
                        continuation.finish(throwing: AIError.invalidURL(baseURL))
                        return
                    }

                    let fullPrompt = "\(systemInstruction)\n\n\(userContent)"
                    var request = URLRequest(url: ollamaURL, timeoutInterval: AIRequestSupport.timeoutInterval)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    struct OllamaGenerateRequest: Encodable {
                        let model: String
                        let prompt: String
                        let stream: Bool
                    }
                    struct OllamaGenerateResponse: Decodable {
                        let response: String?
                        let done: Bool?
                    }

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
                        let httpError = AIRequestSupport.httpErrorMessage(status: http.statusCode, data: errorBytes)
                        Log.ai.error("Local LLM request failed: \(httpError.localizedDescription)")
                        continuation.finish(throwing: httpError)
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
        let normalized = AIRequestSupport.normalizedBaseURL(baseURL, fallback: "http://localhost:1234/v1")

        // 1. Try standard OpenAI /v1/models (LM Studio, Jan, Ollama v1, llama.cpp)
        if let modelsURL = resolveModelsURL(baseURL: normalized) {
            var request = URLRequest(url: modelsURL, timeoutInterval: 5)
            request.httpMethod = "GET"
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse, http.statusCode == 200 {
                struct ModelListResponse: Decodable {
                    struct ModelItem: Decodable {
                        let id: String
                    }
                    let data: [ModelItem]?
                }
                if let decoded = try? JSONDecoder().decode(ModelListResponse.self, from: data),
                   let items = decoded.data, !items.isEmpty {
                    return items.map(\.id).sorted()
                }
            }
        }

        // 2. Try Ollama /api/tags
        if let tagsURL = resolveOllamaTagsURL(baseURL: normalized) {
            let request = URLRequest(url: tagsURL, timeoutInterval: 5)
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse, http.statusCode == 200 {
                struct OllamaTagsResponse: Decodable {
                    struct ModelTag: Decodable {
                        let name: String
                    }
                    let models: [ModelTag]?
                }
                if let decoded = try? JSONDecoder().decode(OllamaTagsResponse.self, from: data),
                   let items = decoded.models, !items.isEmpty {
                    return items.map(\.name).sorted()
                }
            }
        }

        throw AIError.invalidResponse
    }

    private static func resolveChatCompletionsURL(baseURL: String) -> URL? {
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        if trimmed.hasSuffix("/v1") {
            return URL(string: "\(trimmed)/chat/completions")
        }
        return URL(string: "\(trimmed)/v1/chat/completions") ?? URL(string: "\(trimmed)/chat/completions")
    }

    private static func resolveModelsURL(baseURL: String) -> URL? {
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        if trimmed.hasSuffix("/v1") {
            return URL(string: "\(trimmed)/models")
        }
        return URL(string: "\(trimmed)/v1/models") ?? URL(string: "\(trimmed)/models")
    }

    private static func resolveOllamaGenerateURL(baseURL: String) -> URL? {
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let root = trimmed.replacingOccurrences(of: "/v1", with: "")
        return URL(string: "\(root)/api/generate")
    }

    private static func resolveOllamaTagsURL(baseURL: String) -> URL? {
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let root = trimmed.replacingOccurrences(of: "/v1", with: "")
        return URL(string: "\(root)/api/tags")
    }
}

/// Backwards-compatibility typealias so any external reference to OllamaProvider continues to compile.
public typealias OllamaProvider = LocalLLMProvider
