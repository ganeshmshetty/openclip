// AppleScriptRunner.swift
// OpenClip
//
// Bounded off-main strategy for AppleScript execution. In-process
// `NSAppleScript.executeAndReturnError` blocks the calling thread until the target application
// answers over Apple Events and cannot be cancelled or timed out — a hung `tell application` would
// permanently park a cooperative-pool thread (NSAppleScript is also not thread-safe across
// instances). Running each script as an `/usr/bin/osascript` subprocess through the shared
// ShellProcessRunner keeps the cooperative pool free and makes the evaluation killable: an
// explicit `timeout` arms the watchdog, and without one the subprocess runs until it exits or the
// caller cancels, so a stuck script never wedges a thread. See docs/runtimes/applescript.md.
import Foundation
import Core

/// Executes AppleScript sources as killable `osascript` subprocesses. `@unchecked Sendable` because
/// it is a stateless facade — all per-run state lives in ShellProcessRunner locals.
public final class AppleScriptRunner: @unchecked Sendable {
    public static let shared = AppleScriptRunner()

    private init() {}

    /// Runs `source` and returns its trimmed string result. Throws on non-zero exit (stderr text as
    /// the message, matching ShellProcessRunner's error policy) and on watchdog timeout. `timeout`
    /// arms the subprocess watchdog; nil runs with none.
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
