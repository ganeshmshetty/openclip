// CloudAPIProvider.swift
// OpenClip
//
// Implements AI processing by querying cloud-based LLM API endpoints (such as OpenAI or Anthropic).
import Foundation
import Core

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

    public func processStream(prompt: String, text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let input: String
            do {
                input = try AIRequestSupport.requireNonEmptyText(text)
            } catch {
                continuation.finish(throwing: error)
                return
            }

            guard !apiKey.isEmpty else {
                continuation.finish(throwing: AIError.missingAPIKey)
                return
            }

            let systemInstruction = AIRequestSupport.systemPrompt(for: prompt)
            let userContent = AIRequestSupport.userContent(for: input)

            let streamTask: Task<Void, Never>
            switch serviceProvider {
            case .anthropic:
                streamTask = Task {
                    do {
                        for try await chunk in self.streamAnthropic(systemPrompt: systemInstruction, userContent: userContent) {
                            continuation.yield(chunk)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            case .google:
                streamTask = Task {
                    do {
                        for try await chunk in self.streamGemini(systemPrompt: systemInstruction, userContent: userContent) {
                            continuation.yield(chunk)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            case .openai, .deepseek, .groq, .openrouter, .custom:
                let baseURL = effectiveBaseURL
                streamTask = Task {
                    do {
                        for try await chunk in self.streamOpenAICompatible(systemPrompt: systemInstruction, userContent: userContent, baseURL: baseURL) {
                            continuation.yield(chunk)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }

            continuation.onTermination = { _ in
                streamTask.cancel()
            }
        }
    }

    public static func resolveBaseURL(provider: CloudServiceProvider, customBaseURL: String = "") -> String {
        let trimmed = customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return provider.defaultBaseURL
    }

    public var effectiveBaseURL: String {
        Self.resolveBaseURL(provider: serviceProvider, customBaseURL: customBaseURL)
    }

    private func isOpenAIReasoningModel(_ model: String) -> Bool {
        guard serviceProvider == .openai else { return false }
        let lastComponent = model.split(separator: "/").last.map(String.init) ?? model
        let lower = lastComponent.lowercased()
        return lower.hasPrefix("o1") || lower.hasPrefix("o3")
    }

    // MARK: - OpenAI-compatible chat completions

    private func streamOpenAICompatible(systemPrompt: String, userContent: String, baseURL: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
                    let endpoint = "\(base)/chat/completions"
                    guard let url = URL(string: endpoint) else {
                        continuation.finish(throwing: AIError.invalidURL(endpoint))
                        return
                    }

                    var request = URLRequest(url: url, timeoutInterval: AIRequestSupport.timeoutInterval)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let systemRole = isOpenAIReasoningModel(model) ? "developer" : "system"
                    let body = OpenAIChatRequest(
                        model: model,
                        messages: [
                            .init(role: systemRole, content: systemPrompt),
                            .init(role: "user", content: userContent)
                        ],
                        stream: true
                    )
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
                        Log.ai.error("OpenAI-compatible request failed: \(httpError.localizedDescription)")
                        continuation.finish(throwing: httpError)
                        return
                    }

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
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Anthropic Messages API

    private func streamAnthropic(systemPrompt: String, userContent: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let base = effectiveBaseURL.hasSuffix("/") ? String(effectiveBaseURL.dropLast()) : effectiveBaseURL
                    let endpoint = "\(base)/messages"
                    guard let url = URL(string: endpoint) else {
                        continuation.finish(throwing: AIError.invalidURL(endpoint))
                        return
                    }

                    var request = URLRequest(url: url, timeoutInterval: AIRequestSupport.timeoutInterval)
                    request.httpMethod = "POST"
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let body = AnthropicMessagesRequest(
                        model: model,
                        maxTokens: 4096,
                        system: systemPrompt,
                        messages: [.init(role: "user", content: userContent)],
                        stream: true
                    )
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
                        Log.ai.error("Anthropic request failed: \(httpError.localizedDescription)")
                        continuation.finish(throwing: httpError)
                        return
                    }

                    struct AnthropicDeltaEvent: Decodable {
                        struct Delta: Decodable {
                            let type: String?
                            let text: String?
                        }
                        let type: String?
                        let delta: Delta?
                    }

                    for try await line in bytes.lines {
                        guard !Task.isCancelled else { break }
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.hasPrefix("data:") else { continue }
                        let dataStr = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                        if dataStr == "[DONE]" { break }
                        guard let chunkData = dataStr.data(using: .utf8) else { continue }
                        if let decoded = try? JSONDecoder().decode(AnthropicDeltaEvent.self, from: chunkData),
                           let text = decoded.delta?.text, !text.isEmpty {
                            continuation.yield(text)
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

    // MARK: - Google Gemini API

    private func streamGemini(systemPrompt: String, userContent: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let base = effectiveBaseURL.hasSuffix("/") ? String(effectiveBaseURL.dropLast()) : effectiveBaseURL
                    let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
                    let endpoint = "\(base)/models/\(encodedModel):streamGenerateContent?alt=sse"
                    guard let url = URL(string: endpoint) else {
                        continuation.finish(throwing: AIError.invalidURL(endpoint))
                        return
                    }

                    var request = URLRequest(url: url, timeoutInterval: AIRequestSupport.timeoutInterval)
                    request.httpMethod = "POST"
                    request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let body = GeminiChatRequest(
                        systemInstruction: .init(parts: [.init(text: systemPrompt)]),
                        contents: [.init(parts: [.init(text: userContent)])]
                    )
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
                        Log.ai.error("Gemini request failed: \(httpError.localizedDescription)")
                        continuation.finish(throwing: httpError)
                        return
                    }

                    for try await line in bytes.lines {
                        guard !Task.isCancelled else { break }
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.hasPrefix("data:") else { continue }
                        let dataStr = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                        guard let chunkData = dataStr.data(using: .utf8) else { continue }
                        if let decoded = try? JSONDecoder().decode(GeminiChatResponse.self, from: chunkData),
                           let text = decoded.candidates?.first?.content?.parts?.first?.text, !text.isEmpty {
                            continuation.yield(text)
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

    public static func fetchAvailableModels(apiKey: String, provider: CloudServiceProvider, customBaseURL: String = "") async throws -> [String] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw AIError.missingAPIKey
        }

        let baseURL = resolveBaseURL(provider: provider, customBaseURL: customBaseURL)
        switch provider {
        case .anthropic:
            return try await fetchAnthropicModels(apiKey: trimmedKey, baseURL: baseURL)
        case .google:
            return try await fetchGeminiModels(apiKey: trimmedKey, baseURL: baseURL)
        case .openai, .deepseek, .groq, .openrouter, .custom:
            return try await fetchOpenAICompatibleModels(apiKey: trimmedKey, baseURL: baseURL, provider: provider)
        }
    }

    private static func fetchOpenAICompatibleModels(apiKey: String, baseURL: String, provider: CloudServiceProvider) async throws -> [String] {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let endpoint = "\(base)/models"
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
        
        if provider == .openai {
            let filtered = modelIds.filter { id in
                let l = id.lowercased()
                return l.contains("gpt") || l.contains("o1") || l.contains("o3") || l.contains("chat")
            }.sorted()
            return filtered.isEmpty ? modelIds.sorted() : filtered
        } else {
            return modelIds.sorted()
        }
    }

    private static func fetchAnthropicModels(apiKey: String, baseURL: String) async throws -> [String] {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let endpoint = "\(base)/models"
        guard let url = URL(string: endpoint) else {
            throw AIError.invalidURL(endpoint)
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

    private static func fetchGeminiModels(apiKey: String, baseURL: String) async throws -> [String] {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let endpoint = "\(base)/models"
        guard let url = URL(string: endpoint) else {
            throw AIError.invalidURL(endpoint)
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let (data, response) = try await URLSession.shared.data(for: request)
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
}
