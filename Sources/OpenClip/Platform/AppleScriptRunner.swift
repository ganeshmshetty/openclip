// AppleScriptRunner.swift
// OpenClip
//
// In-process NSAppleScript blocks its thread and cannot be timed out, so scripts run as killable
// `osascript` subprocesses via ShellProcessRunner. See docs/runtimes/applescript.md.
import Foundation
import Core

/// Stateless facade over `osascript`; `@unchecked Sendable` because per-run state is local.
public final class AppleScriptRunner: @unchecked Sendable {
    public static let shared = AppleScriptRunner()

    private init() {}

    /// Returns trimmed stdout. Throws on non-zero exit or watchdog timeout; nil timeout disables the watchdog.
    public func run(_ source: String, timeout: TimeInterval? = nil) async throws -> String {
        let invocation = ShellProcessRunner.Invocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-e", source],
            environment: [:],
            timeout: timeout
        )
        let output = try await ShellProcessRunner.run(invocation)
        return output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
