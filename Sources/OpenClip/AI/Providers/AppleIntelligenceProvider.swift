// AppleIntelligenceProvider.swift
// OpenClip
//
// Implements AI processing capabilities using local Apple Intelligence system features.
import Foundation
import AppKit
import Core

#if canImport(FoundationModels)
import FoundationModels

/// Guided-generation shape for the Apple on-device model. Declaring the fields lets the framework
/// constrain the model's output to this structure, so the result no longer has to be scraped out of
/// free-form `<result>`/`<title>` tags that the model may or may not emit correctly.
@available(macOS 26.0, *)
@Generable
struct AppleIntelligenceResponse {
    @Guide(description: "The final transformed text. No XML tags, markdown fences, or commentary — just the text that will be pasted back into the document.")
    var result: String

    @Guide(description: "A concise 2-4 word name for the task or reusable tool, or empty when a name was not requested. No XML tags.")
    var title: String?
}
#endif

@MainActor
public final class AppleIntelligenceProvider: AIProvider {
    public var type: AIProviderType { .apple }

    public init() {}

    /// Selections shorter than this skip token counting: the extra round-trip is only worth paying
    /// when the input could plausibly overflow the on-device context window.
    private static let tokenBudgetCheckThreshold = 2_000

    public func processStream(prompt: String, text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let validated: (prompt: String, text: String)
            do {
                validated = try AIRequestSupport.validateInput(prompt: prompt, text: text)
            } catch {
                continuation.finish(throwing: error)
                return
            }

            // 1. FoundationModels native Apple Intelligence model session API
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                // Refuse early with the specific cause (wrong Mac / feature off / model still
                // downloading) instead of failing mid-generation with a generic error.
                guard AppleIntelligenceAvailability.isAvailable else {
                    continuation.finish(throwing: AIError.providerUnavailable(AppleIntelligenceAvailability.unavailableExplanation))
                    return
                }

                let streamTask = Task {
                    do {
                        let hasInputText = !validated.text.isEmpty
                        let instructions = AIRequestSupport.systemPrompt(for: validated.prompt, hasInputText: hasInputText, structuredResult: true)
                        let userContent = AIRequestSupport.userContent(for: validated.text, fallbackPrompt: validated.prompt)

                        try await Self.ensureWithinContext(instructions: instructions, userContent: userContent)

                        let session = LanguageModelSession(instructions: instructions)
                        let response = try await session.respond(to: userContent, generating: AppleIntelligenceResponse.self)
                        try Task.checkCancellation()

                        // An empty guided result means the model produced no usable text. `extractResultText`
                        // falls back to returning the raw `<result></result>` wrapper, so it cannot detect
                        // this — check the typed field directly before re-emitting tags.
                        guard !response.content.result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            continuation.finish(throwing: AIError.invalidResponse)
                            return
                        }

                        // Re-emit the typed fields as the tag contract the rest of the AI pipeline
                        // (palette, result card, save-as-tool) already parses.
                        let tagged = AIRequestSupport.taggedResponse(
                            result: response.content.result,
                            title: response.content.title
                        )
                        continuation.yield(tagged)
                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish(throwing: CancellationError())
                    } catch let error as LanguageModelSession.GenerationError {
                        switch error {
                        case .assetsUnavailable(let context):
                            Log.ai.notice("Apple Intelligence assets unavailable: \(context.debugDescription)")
                            let status = AppleIntelligenceAvailability.current
                            let message = status.isAvailable
                                ? String(localized: "Apple Intelligence models are still preparing. Try again shortly.")
                                : AppleIntelligenceAvailability.unavailableExplanation(for: status)
                            continuation.finish(throwing: AIError.providerUnavailable(message))
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
            continuation.finish(throwing: AIError.providerUnavailable(AppleIntelligenceAvailability.unavailableExplanation))
        }
    }

    #if canImport(FoundationModels)
    /// Fails fast with `requestTooLarge` when instructions plus input exceed the on-device model's
    /// context window, rather than paying for a generation round-trip that returns the same error.
    /// Skipped on macOS 26.0–26.3, which has `contextSize` but not `tokenCount`.
    @available(macOS 26.0, *)
    private static func ensureWithinContext(instructions: String, userContent: String) async throws {
        guard #available(macOS 26.4, *) else { return }
        guard userContent.count > tokenBudgetCheckThreshold else { return }
        let model = SystemLanguageModel.default
        guard let tokens = try? await model.tokenCount(for: instructions + "\n\n" + userContent) else {
            return
        }
        if tokens >= model.contextSize {
            throw AIError.requestTooLarge
        }
    }
    #endif
}
