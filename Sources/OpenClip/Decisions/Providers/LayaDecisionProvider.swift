// LayaDecisionProvider.swift
// OpenClip
//
// Local Laya CLI / sidecar Decision provider. Prefers on-device judgment for Live assist.
import Foundation
import Core

@MainActor
public final class LayaDecisionProvider: DecisionProvider {
    public let type: DecisionProviderType = .laya
    public var command: String
    /// Injected runner for tests; defaults to a real Process launch.
    public var runner: (@Sendable (String, Data) async throws -> Data)?

    public init(command: String = "laya") {
        self.command = command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "laya" : command
    }

    public func availability() async -> DecisionProviderAvailability {
        if runner != nil { return .available }
        // Check PATH for the binary without executing a decision.
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = [command]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = Pipe()
        do {
            try which.run()
            which.waitUntilExit()
            if which.terminationStatus == 0 {
                return .available
            }
        } catch {
            // fall through
        }
        return .unavailable(reason: String(localized: "Laya CLI (“\(command)”) not found on PATH. Install a local Laya build or point Preferences → Decisions at your binary."))
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
        if let runner {
            let data = try await runner(command, payload)
            return try DecisionResponseParser.parse(data)
        }
        // Real CLI: `laya decide --json` reading request JSON from stdin.
        // TODO: wire through ShellProcessRunner when Laya's CLI flag set stabilizes.
        throw DecisionError.providerUnavailable(String(localized: "Laya CLI invoke is stubbed until a stable `laya decide` interface is confirmed. Set a test runner or use Jev."))
    }
}
