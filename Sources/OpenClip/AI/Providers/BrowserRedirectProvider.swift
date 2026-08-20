// BrowserRedirectProvider.swift
// OpenClip
//
// Implements AI prompt handling by formatting queries and redirecting users to web-based AI interfaces.
import Foundation
import AppKit

@MainActor
public final class BrowserRedirectProvider: AIProvider {
    public var type: AIProviderType { .browser }

    public let template: String

    /// Soft upper bound for query URLs; longer values often fail in browsers.
    private static let maxURLLength = 8000

    public init(template: String) {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        self.template = trimmed.isEmpty ? "https://chatgpt.com/?q={text}" : trimmed
    }

    public func process(prompt: String, text: String) async throws -> String {
        let input = try AIRequestSupport.requireNonEmptyText(text)
        let instruction = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullQuery = instruction.isEmpty ? input : "\(instruction): \(input)"

        guard let encodedQuery = fullQuery.addingPercentEncoding(withAllowedCharacters: AIRequestSupport.queryValueAllowed) else {
            throw AIError.invalidURL(fullQuery)
        }

        let urlString: String
        if template.contains("{text}") {
            urlString = template.replacingOccurrences(of: "{text}", with: encodedQuery)
        } else {
            // Preserve usability for templates without a placeholder.
            let separator = template.contains("?") ? "&" : "?"
            urlString = "\(template)\(separator)q=\(encodedQuery)"
        }

        guard urlString.count <= Self.maxURLLength else {
            throw AIError.requestTooLarge
        }
        guard let url = URL(string: urlString) else {
            throw AIError.invalidURL(urlString)
        }

        let opened = NSWorkspace.shared.open(url)
        guard opened else {
            throw AIError.invalidURL(url.absoluteString)
        }
        return "Opened in browser"
    }

    public func processStream(prompt: String, text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let result = try await process(prompt: prompt, text: text)
                    continuation.yield(result)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
