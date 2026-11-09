// CLIToolCatalog.swift
// OpenClip
//
// One entry per CLI preset: binary names, argument template, version probe,
// auth probe, and model discovery. Adding a CLI means adding one entry.

import Foundation

/// How a preset is launched. `subprocess` is the only kind; a new case is the slot for another launch style.
enum CLIRunnerKind: Sendable, Equatable {
    case subprocess
}

public enum CLIReadinessState: String, Sendable, Equatable {
    case notInstalled
    case signInNeeded
    case ready

    public var title: String {
        switch self {
        case .notInstalled: return String(localized: "Not installed")
        case .signInNeeded: return String(localized: "Sign in needed")
        case .ready: return String(localized: "Ready")
        }
    }
}

public struct CLIReadiness: Sendable, Equatable {
    public var state: CLIReadinessState
    public var version: String?
    public var hint: String
    public var fixCommand: String?

    public var title: String { state.title }

    static func notInstalled(command: String) -> CLIReadiness {
        CLIReadiness(state: .notInstalled, version: nil, hint: command, fixCommand: command.isEmpty ? nil : command)
    }

    static func signInNeeded(command: String) -> CLIReadiness {
        CLIReadiness(state: .signInNeeded, version: nil, hint: command, fixCommand: command.isEmpty ? nil : command)
    }

    static func ready(version: String?) -> CLIReadiness {
        CLIReadiness(state: .ready, version: version, hint: "", fixCommand: nil)
    }
}

enum CLIArgToken: Sendable, Equatable {
    case literal(String)
    case systemPrompt
    /// System prompt, a blank line, then the user text, as one argument.
    case joinedPrompt
    case thinkingArguments
    /// Emits `flag` and the model only when a model override is set.
    case modelIfSet(String)
}

enum CLIStdinSource: Sendable, Equatable {
    case none
    case userText
}

enum CLIOutputKind: Sendable, Equatable {
    case plainText
    case codexJSONL
}

struct CLIInvocationTemplate: Sendable, Equatable {
    var tokens: [CLIArgToken]
    var stdin: CLIStdinSource
    var output: CLIOutputKind
    var environment: [String: String]
}

enum CLIAuthCheck: Sendable, Equatable {
    case command(binary: String?, arguments: [String], rule: CLIAuthRule)
    case environmentNonEmpty([String])
    case keychainService(String)
    case homeRelativeFile(String)
    indirect case any([CLIAuthCheck])
}

enum CLIAuthRule: Sendable, Equatable {
    /// `"key": true` in the command's JSON output.
    case jsonBool(String)
    /// Exit 0, output contains `marker`, and does not contain `negated`.
    case phrase(marker: String, negated: String)
    case exitZero
}

enum CLIModelCheck: Sendable, Equatable {
    case none
    case command(arguments: [String], parse: CLIModelListFormat)
    /// The model pinned in `~/.codex/config.toml`, when one is set.
    case codexConfig
}

enum CLIModelListFormat: Sendable, Equatable {
    /// `id - display name` lines from `agent models`.
    case idDashName
    /// JSON array of objects with a string `modelId` from `gemini models -o json`.
    case jsonModelID
}

struct CLITool: Sendable, Equatable, Identifiable {
    var preset: CLIPreset
    var id: CLIPreset { preset }
    var displayName: String
    var binaries: [String]
    var versionArguments: [String]
    var installCommand: String
    var signInCommand: String
    var authHelp: String
    var runner: CLIRunnerKind
    var auth: CLIAuthCheck
    var models: CLIModelCheck
    var documentedAliases: [String]
    var thinkingArguments: [String]
    var invocation: CLIInvocationTemplate

    static func tool(for preset: CLIPreset) -> CLITool? {
        catalog.first { $0.preset == preset }
    }

    static let catalog: [CLITool] = [
        CLITool(
            preset: .claude,
            displayName: "Claude Code (claude)",
            binaries: ["claude"],
            versionArguments: ["--version"],
            installCommand: "npm install -g @anthropic-ai/claude-code",
            signInCommand: "claude auth login",
            authHelp: "Run “claude auth login” in Terminal to sign in with your Claude subscription.",
            runner: .subprocess,
            auth: .command(binary: nil, arguments: ["auth", "status"], rule: .jsonBool("loggedIn")),
            models: .none,
            // `--help` documents these aliases (`fable`, `opus`, `sonnet`).
            documentedAliases: ["fable", "opus", "sonnet"],
            thinkingArguments: [],
            invocation: CLIInvocationTemplate(
                tokens: [
                    .literal("-p"),
                    .literal("--tools"),
                    .literal(""),
                    .literal("--no-session-persistence"),
                    .literal("--system-prompt"),
                    .systemPrompt,
                    .modelIfSet("--model")
                ],
                stdin: .userText,
                output: .plainText,
                environment: ["MAX_THINKING_TOKENS": "0"]
            )
        ),
        CLITool(
            preset: .codex,
            displayName: "Codex CLI (codex)",
            binaries: ["codex"],
            versionArguments: ["--version"],
            installCommand: "brew install codex",
            signInCommand: "codex login",
            authHelp: "Run “codex login” in Terminal to sign in with your ChatGPT subscription.",
            runner: .subprocess,
            auth: .command(binary: nil, arguments: ["login", "status"], rule: .phrase(marker: "logged in", negated: "not logged in")),
            models: .codexConfig,
            documentedAliases: [],
            thinkingArguments: ["-c", "model_reasoning_effort=none"],
            invocation: CLIInvocationTemplate(
                tokens: [
                    .literal("exec"),
                    .thinkingArguments,
                    .systemPrompt,
                    .literal("--skip-git-repo-check"),
                    .literal("--ephemeral"),
                    .literal("--sandbox"),
                    .literal("read-only"),
                    .literal("--json"),
                    .modelIfSet("-m")
                ],
                stdin: .userText,
                output: .codexJSONL,
                environment: [:]
            )
        ),
        CLITool(
            preset: .copilot,
            displayName: "GitHub Copilot (copilot)",
            binaries: ["copilot"],
            versionArguments: ["--version"],
            installCommand: "brew install copilot-cli",
            signInCommand: "copilot login",
            authHelp: "Run “copilot login” in Terminal. A GitHub CLI login is also accepted.",
            runner: .subprocess,
            // `copilot login` stores its own credential. The CLI also accepts COPILOT_GITHUB_TOKEN / GH_TOKEN / GITHUB_TOKEN and a `gh` login.
            auth: .any([
                .environmentNonEmpty(["COPILOT_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN"]),
                .keychainService("copilot-cli"),
                .command(binary: "gh", arguments: ["auth", "status"], rule: .exitZero)
            ]),
            models: .none,
            // `--help` example: `copilot --model gpt-5.4`.
            documentedAliases: ["gpt-5.4"],
            thinkingArguments: [],
            invocation: CLIInvocationTemplate(
                tokens: [
                    .literal("-p"),
                    .joinedPrompt,
                    .literal("-s"),
                    // Non-interactive mode requires permission to run tools; an empty tool list leaves it nothing to run.
                    .literal("--allow-all-tools"),
                    .literal("--no-ask-user"),
                    .literal("--available-tools"),
                    .literal(""),
                    .literal("--no-custom-instructions"),
                    .modelIfSet("--model")
                ],
                stdin: .none,
                output: .plainText,
                environment: [:]
            )
        ),
        CLITool(
            preset: .gemini,
            displayName: "Gemini CLI (gemini)",
            binaries: ["gemini"],
            versionArguments: ["--version"],
            installCommand: "brew install gemini-cli",
            signInCommand: "gemini",
            authHelp: "Run “gemini” and choose Sign in with Google, or set GEMINI_API_KEY.",
            runner: .subprocess,
            auth: .any([
                .environmentNonEmpty(["GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_GENAI_USE_VERTEXAI"]),
                .keychainService("gemini-cli-oauth"),
                .homeRelativeFile(".gemini/oauth_creds.json")
            ]),
            models: .command(arguments: ["models", "-o", "json"], parse: .jsonModelID),
            // Documented aliases from the CLI reference. `auto` is Gemini's own default, distinct from OpenClip's Default.
            documentedAliases: ["auto", "pro", "flash", "flash-lite"],
            thinkingArguments: [],
            invocation: CLIInvocationTemplate(
                tokens: [
                    .literal("-p"),
                    .joinedPrompt,
                    // Skips the folder-trust prompt, which would hang a non-interactive run.
                    .literal("--skip-trust"),
                    .literal("--output-format"),
                    .literal("text"),
                    .modelIfSet("--model")
                ],
                stdin: .none,
                output: .plainText,
                environment: [:]
            )
        ),
        CLITool(
            preset: .cursor,
            displayName: "Cursor Agent (agent)",
            binaries: ["cursor-agent", "agent"],
            versionArguments: ["--version"],
            installCommand: "curl https://cursor.com/install -fsS | bash",
            signInCommand: "agent login",
            authHelp: "Run “agent login” in Terminal to sign in to Cursor. The cursor-agent binary is the same CLI.",
            runner: .subprocess,
            auth: .command(binary: nil, arguments: ["status", "--format", "json"], rule: .jsonBool("isAuthenticated")),
            models: .command(arguments: ["models"], parse: .idDashName),
            documentedAliases: [],
            thinkingArguments: [],
            invocation: CLIInvocationTemplate(
                tokens: [
                    .literal("-p"),
                    .literal("--mode"),
                    .literal("ask"),
                    .literal("--output-format"),
                    .literal("text"),
                    // Ask mode is read-only. Trust skips the workspace prompt that would hang a non-interactive run.
                    .literal("--trust"),
                    .joinedPrompt,
                    .modelIfSet("--model")
                ],
                stdin: .none,
                output: .plainText,
                environment: [:]
            )
        )
    ]
}

enum CLIArgumentPlan {
    static func arguments(
        template: CLIInvocationTemplate,
        thinkingArguments: [String],
        systemPrompt: String,
        userContent: String,
        model: String
    ) -> [String] {
        var args: [String] = []
        for token in template.tokens {
            switch token {
            case .literal(let value):
                args.append(value)
            case .systemPrompt:
                args.append(systemPrompt)
            case .joinedPrompt:
                args.append(systemPrompt + "\n\n" + userContent)
            case .thinkingArguments:
                args.append(contentsOf: thinkingArguments)
            case .modelIfSet(let flag):
                if !model.isEmpty {
                    args.append(flag)
                    args.append(model)
                }
            }
        }
        return args
    }
}

enum CLIModelListParser {
    static func parse(_ output: String, format: CLIModelListFormat) -> [String] {
        switch format {
        case .idDashName:
            var ids: [String] = []
            for line in output.split(whereSeparator: \.isNewline) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard let separator = trimmed.range(of: " - ") else { continue }
                let id = String(trimmed[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
                guard !id.isEmpty, !ids.contains(id) else { continue }
                ids.append(id)
            }
            return ids
        case .jsonModelID:
            guard let data = output.data(using: .utf8),
                  let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return []
            }
            var ids: [String] = []
            for row in rows {
                guard let id = row["modelId"] as? String else { continue }
                let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !ids.contains(trimmed) else { continue }
                ids.append(trimmed)
            }
            return ids
        }
    }
}

enum CLIAuthOutput {
    static func passes(rule: CLIAuthRule, exitCode: Int32, output: String) -> Bool {
        switch rule {
        case .exitZero:
            return exitCode == 0
        case .jsonBool(let key):
            return output.contains("\"\(key)\": true") || output.contains("\"\(key)\":true")
        case .phrase(let marker, let negated):
            guard exitCode == 0 else { return false }
            let folded = output.lowercased()
            return folded.contains(marker.lowercased()) && !folded.contains(negated.lowercased())
        }
    }
}

enum CLIReadinessPlan {
    static func builtin(binaryFound: Bool, version: String?, authenticated: Bool, tool: CLITool) -> CLIReadiness {
        guard binaryFound else { return .notInstalled(command: tool.installCommand) }
        guard authenticated else { return .signInNeeded(command: tool.signInCommand) }
        return .ready(version: version)
    }
}

public enum CLIPreset: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case copilot
    case gemini
    case cursor
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        if let tool = CLITool.tool(for: self) { return tool.displayName }
        return "Custom Command"
    }

    public var binaryName: String {
        CLITool.tool(for: self)?.binaries.first ?? ""
    }

    /// "Default" plus documented aliases. Live model lists replace this when the CLI can print one.
    public var defaultModels: [String] {
        guard let tool = CLITool.tool(for: self) else { return ["default"] }
        var aliases = tool.documentedAliases
        if case .codexConfig = tool.models,
           let configured = CLIProvider.inspectConfiguredModel(for: self),
           !aliases.contains(configured) {
            aliases.insert(configured, at: 0)
        }
        return ["default"] + aliases
    }

    public var primaryModel: String { "default" }

    public var loginCommand: String {
        CLITool.tool(for: self)?.signInCommand ?? ""
    }

    public var authHelpText: String {
        if let tool = CLITool.tool(for: self) { return tool.authHelp }
        return "Custom CLI tools can authenticate via shell environment variables (e.g. API keys in ~/.zshrc), session credentials, or local execution without credentials."
    }

    public var installationHint: String {
        guard let tool = CLITool.tool(for: self) else {
            return "Specify any CLI command that accepts stdin or prompt arguments"
        }
        return "Install: \(tool.installCommand)"
    }

    public var thinkingDisabledEnvironment: [String: String] {
        CLITool.tool(for: self)?.invocation.environment ?? [:]
    }

    public var thinkingDisabledArguments: [String] {
        CLITool.tool(for: self)?.thinkingArguments ?? []
    }
}
