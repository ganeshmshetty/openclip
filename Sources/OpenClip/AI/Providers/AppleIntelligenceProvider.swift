// AppleIntelligenceProvider.swift
// OpenClip
//
// Implements AI processing capabilities using local Apple Intelligence system features.
import Foundation
import AppKit
import Core

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
public final class AppleIntelligenceProvider: AIProvider {
    public var type: AIProviderType { .apple }

    public init() {}

    public func processStream(prompt: String, text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let input: String
            do {
                input = try AIRequestSupport.requireNonEmptyText(text)
            } catch {
                continuation.finish(throwing: error)
                return
            }

            // 1. FoundationModels native Apple Intelligence model session API
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                let streamTask = Task {
                    do {
                        let session = LanguageModelSession(instructions: AIRequestSupport.systemPrompt(for: prompt))
                        let userContent = AIRequestSupport.userContent(for: input)
                        let response = try await session.respond(to: userContent)
                        try Task.checkCancellation()
                        let content = AIRequestSupport.extractResultText(response.content)
                        if !content.isEmpty {
                            continuation.yield(content)
                            continuation.finish()
                        } else {
                            continuation.finish(throwing: AIError.invalidResponse)
                        }
                    } catch is CancellationError {
                        continuation.finish(throwing: CancellationError())
                    } catch let error as LanguageModelSession.GenerationError {
                        switch error {
                        case .assetsUnavailable(let context):
                            Log.ai.notice("Apple Intelligence assets unavailable: \(context.debugDescription)")
                            continuation.finish(throwing: AIError.providerUnavailable("Apple Intelligence assets unavailable: \(context.debugDescription)"))
                        case .exceededContextWindowSize:
                            continuation.finish(throwing: AIError.requestTooLarge)
                        case .decodingFailure:
                            continuation.finish(throwing: AIError.invalidResponse)
                        case .guardrailViolation, .unsupportedGuide, .unsupportedLanguageOrLocale, .rateLimited, .concurrentRequests, .refusal:
                            continuation.finish(throwing: error)
                        @unknown default:
                            continuation.finish(throwing: error)
                        }
                    } catch {
                        if Task.isCancelled {
                            continuation.finish(throwing: CancellationError())
                        } else {
                            Log.ai.notice("Apple Intelligence generation failed: \(error.localizedDescription)")
                            continuation.finish(throwing: error)
                        }
                    }
                }
                continuation.onTermination = { _ in
                    streamTask.cancel()
                }
                return
            }
            #endif

            // 2. Return clear error if on-device model is unavailable on this device/OS
            continuation.finish(throwing: AIError.providerUnavailable(String(localized: "Apple Intelligence requires macOS 26.0+ with supported Apple Silicon hardware. Configure another provider in Preferences → AI.")))
        }
    }
}
