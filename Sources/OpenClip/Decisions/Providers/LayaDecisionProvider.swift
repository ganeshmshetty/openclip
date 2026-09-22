// LayaDecisionProvider.swift
// OpenClip
//
// Local Laya Decision provider. Laya has no CLI, so decisions go through `LayaRuntime`: the Python
// environment OpenClip downloads into ~/.openclip/laya and the bundled bridge it keeps resident.
// Preferred for Live assist because nothing leaves the Mac.
import Foundation
import Core

@MainActor
public final class LayaDecisionProvider: DecisionProvider {
    public let type: DecisionProviderType = .laya
    /// Checkpoint to run: see `LayaRuntime.models`.
    public var model: String
    /// Injected runner for tests, called with (model, request payload); replaces the runtime.
    public var runner: (@Sendable (String, Data) async throws -> Data)?
    private let runtime: LayaRuntime

    public init(model: String = LayaRuntime.defaultModel, runtime: LayaRuntime = .shared) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = trimmed.isEmpty ? LayaRuntime.defaultModel : trimmed
        self.runtime = runtime
    }

    public func availability() async -> DecisionProviderAvailability {
        if runner != nil { return .available }
        switch runtime.status {
        case .notDownloaded:
            return .unavailable(reason: LayaRuntime.notDownloadedMessage)
        case .downloading(let step):
            return .unavailable(reason: String(localized: "Laya is downloading: \(step)"))
        case .failed(let message):
            return .unavailable(reason: message)
        case .downloaded, .starting, .running:
            return runtime.isDownloaded ? .available : .unavailable(reason: LayaRuntime.notDownloadedMessage)
        }
    }

    public func decide(_ request: DecisionRequest) async throws -> DecisionResponse {
        let status = await availability()
        guard status.isAvailable else {
            if case .unavailable(let reason) = status { throw DecisionError.providerUnavailable(reason) }
            throw DecisionError.providerUnavailable(String(localized: "Laya unavailable."))
        }
        guard !request.state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecisionError.emptyInput
        }
        let payload = try DecisionQuestionPacker.encodeRequest(request)
        let data: Data
        if let runner {
            data = try await runner(model, payload)
        } else {
            data = try await runtime.decide(payload, model: model)
        }
        return try DecisionResponseParser.parse(data)
    }
}
