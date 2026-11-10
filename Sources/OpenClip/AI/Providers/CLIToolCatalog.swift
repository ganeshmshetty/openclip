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
    /// Nothing to report. Custom Command stays quiet until the field has text.
    case unspecified

    public var title: String {
        switch self {
        case .notInstalled: return String(localized: "Not installed")
        case .signInNeeded: return String(localized: "Sign in needed")
        case .ready: return String(localized: "Ready")
        case .unspecified: return ""
        }
    }
}

public struct CLIReadiness: Sendable, Equatable {
    public var state: CLIReadinessState
    public var version: String?
    public var hint: String
    public var fixCommand: String?

    public var title: String { state.title }

    var showsStatus: Bool { state != .unspecified }

    var setupActionTitle: String? {
        guard let fixCommand, !fixCommand.isEmpty else { return nil }
        switch state {
        case .notInstalled: return String(localized: "Install")
        case .signInNeeded: return String(localized: "Sign In")
        case .ready, .unspecified: return nil
        }
    }

    var menuSuffix: String? {
        guard state == .notInstalled, let fixCommand, !fixCommand.isEmpty else { return nil }
        return state.title
    }

    static func notInstalled(command: String) -> CLIReadiness {
        CLIReadiness(state: .notInstalled, version: nil, hint: command, fixCommand: command.isEmpty ? nil : command)
    }

    static func signInNeeded(command: String) -> CLIReadiness {
        CLIReadiness(state: .signInNeeded, version: nil, hint: command, fixCommand: command.isEmpty ? nil : command)
    }

    static func ready(version: String?) -> CLIReadiness {
        CLIReadiness(state: .ready, version: version, hint: "", fixCommand: nil)
    }

    static func unspecified() -> CLIReadiness {
        CLIReadiness(state: .unspecified, version: nil, hint: "", fixCommand: nil)
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
    /// A non-empty JSON array from commands such as `opencode auth list --format json`.
    case jsonNonEmptyArray
    /// Exit 0, output contains `marker`, and does not contain `negated`.
    case phrase(marker: String, negated: String)
    case exitZero
}

enum CLIModelCheck: Sendable, Equatable {
    case none
    case command(arguments: [String], parse: CLIModelListFormat)
    /// The model pinned in `~/.codex/config.toml`, when one is set.
    case codexConfig
    /// The model pinned in `~/.copilot/settings.json`, when one is set.
    case copilotConfig
}

enum CLIModelListFormat: Sendable, Equatable {
    /// `id - display name` lines from `agent models`.
    case idDashName
    /// One model id per line, as `opencode models` prints.
    case lines
    /// `id\tDisplay name` lines, as `agy models` prints.
    case tabName
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
            models: .copilotConfig,
            // `--help` uses `gpt-5.4` as its example, and `auto` lets Copilot choose.
            documentedAliases: ["auto", "gpt-5.4"],
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
            preset: .antigravity,
            displayName: "Antigravity CLI (agy)",
            binaries: ["agy"],
            versionArguments: ["--version"],
            installCommand: "curl -fsSL https://antigravity.google/cli/install.sh | bash",
            signInCommand: "agy",
            authHelp: "Run “agy” in Terminal to sign in with Google. It opens the browser when no session is saved.",
            runner: .subprocess,
            auth: .any([
                .environmentNonEmpty(["GEMINI_API_KEY", "AGY_ADC_AUTH"]),
                .homeRelativeFile(".gemini/antigravity-cli/antigravity-oauth-token")
            ]),
            models: .command(arguments: ["models"], parse: .tabName),
            documentedAliases: [],
            thinkingArguments: [],
            invocation: CLIInvocationTemplate(
                tokens: [
                    .literal("-p"),
                    .joinedPrompt,
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
        ),
        CLITool(
            preset: .opencode,
            displayName: "OpenCode (opencode)",
            binaries: ["opencode"],
            versionArguments: ["--version"],
            installCommand: "curl -fsSL https://opencode.ai/v2/install | bash",
            signInCommand: "opencode auth login",
            authHelp: "Run “opencode auth login” in Terminal, then choose OpenCode or another provider.",
            runner: .subprocess,
            auth: .command(binary: nil, arguments: ["auth", "list", "--format", "json"], rule: .jsonNonEmptyArray),
            models: .command(arguments: ["models"], parse: .lines),
            documentedAliases: [],
            thinkingArguments: [],
            invocation: CLIInvocationTemplate(
                tokens: [
                    .literal("run"),
                    .modelIfSet("--model"),
                    .literal("--auto"),
                    .joinedPrompt
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
        case .lines:
            var ids: [String] = []
            for line in output.split(whereSeparator: \.isNewline) {
                let id = line.trimmingCharacters(in: .whitespaces)
                guard !id.isEmpty, id.contains("/"), !ids.contains(id) else { continue }
                ids.append(id)
            }
            return ids
        case .tabName:
            var ids: [String] = []
            for line in output.split(whereSeparator: \.isNewline) {
                let id = line.split(separator: "\t", maxSplits: 1).first
                    .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
                guard !id.isEmpty, !ids.contains(id) else { continue }
                ids.append(id)
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
        case .jsonNonEmptyArray:
            guard exitCode == 0,
                  let data = output.data(using: .utf8),
                  let rows = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
                return false
            }
            return !rows.isEmpty
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

    /// Empty input is not a failure. A command is checked only after one is entered, and never offers an install or sign-in button.
    static func custom(command: String, binaryFound: Bool, authCommand: String, authPassed: Bool) -> CLIReadiness {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unspecified() }
        guard binaryFound else {
            let name = trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? trimmed
            let hint = String(format: String(localized: "Command “%@” not found"), name)
            return CLIReadiness(state: .notInstalled, version: nil, hint: hint, fixCommand: nil)
        }
        let auth = authCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if auth.isEmpty || authPassed {
            return .ready(version: nil)
        }
        return CLIReadiness(
            state: .signInNeeded,
            version: nil,
            hint: String(localized: "Auth check failed"),
            fixCommand: nil
        )
    }
}

public enum CLIPreset: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case copilot
    case antigravity
    case cursor
    case opencode
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
        switch tool.models {
        case .codexConfig, .copilotConfig:
            if let configured = CLIProvider.inspectConfiguredModel(for: self), !aliases.contains(configured) {
                aliases.insert(configured, at: 0)
            }
        case .none, .command:
            break
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

/// On-disk picture of nvm's alias files and installed Node versions.
struct CLINvmLayout: Sendable, Equatable {
    var aliasFiles: [String: String]
    var versionNames: [String]
}

/// Resolves a CLI the way a login shell would, then in install locations a GUI app's PATH omits.
enum CLIExecutableSearch {
    static func trimmedDirectory(_ path: String) -> String {
        var value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.count > 1 && value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    static func parsePATH(_ raw: String) -> [String] {
        raw.split(separator: ":", omittingEmptySubsequences: true)
            .map { trimmedDirectory(String($0)) }
            .filter { !$0.isEmpty }
    }

    /// Login profiles sometimes print banners. The markers keep that text out of PATH.
    static func pathFromLoginOutput(_ output: String) -> [String] {
        guard let start = output.range(of: "OPENCLIP_PATH_BEGIN\n"),
              let end = output.range(of: "\nOPENCLIP_PATH_END", range: start.upperBound..<output.endIndex) else {
            return []
        }
        let value = String(output[start.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return parsePATH(value)
    }

    /// `$SHELL -l -c` script. Fish's `$PATH` is a list, so it is joined explicitly.
    static func loginPathScript(shellPath: String) -> String {
        let name = (shellPath as NSString).lastPathComponent
        if name == "fish" {
            return "printf '%s\\n' OPENCLIP_PATH_BEGIN; string join : $PATH; printf '%s\\n' OPENCLIP_PATH_END"
        }
        return "printf 'OPENCLIP_PATH_BEGIN\\n%s\\nOPENCLIP_PATH_END\\n' \"$PATH\""
    }

    /// Directories to search after the login PATH. `~/.cargo/bin` stays so Rust installs keep resolving.
    static func supplementalDirectories(home: String, nvmBin: String?) -> [String] {
        let root = trimmedDirectory(home)
        var directories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            root + "/.local/bin",
            root + "/.opencode/bin",
            root + "/.npm-global/bin",
            root + "/.bun/bin",
            root + "/.volta/bin"
        ]
        if let nvmBin {
            let trimmed = trimmedDirectory(nvmBin)
            if !trimmed.isEmpty {
                directories.append(trimmed)
            }
        }
        directories.append(root + "/.cargo/bin")
        directories.append("/usr/bin")
        directories.append("/bin")
        return directories
    }

    /// First occurrence wins, which is the login PATH ahead of the supplemental list.
    static func searchDirectories(loginPATH: [String], supplemental: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for directory in loginPATH + supplemental {
            let normalized = trimmedDirectory(directory)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            ordered.append(normalized)
        }
        return ordered
    }

    static func resolve(name: String, home: String, directories: [String], isExecutable: (String) -> Bool) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("/") {
            return isExecutable(trimmed) ? trimmed : nil
        }
        if trimmed.hasPrefix("~/") {
            let expanded = trimmedDirectory(home) + String(trimmed.dropFirst(1))
            return isExecutable(expanded) ? expanded : nil
        }
        guard !trimmed.contains("/") else { return nil }
        for directory in directories {
            let root = trimmedDirectory(directory)
            guard !root.isEmpty else { continue }
            let candidate = root + "/" + trimmed
            if isExecutable(candidate) { return candidate }
        }
        return nil
    }

    /// A directory is executable on Unix, so a folder named like the CLI must not count.
    static func isExecutableFile(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: path)
    }

    /// `alias/default` is the version a new shell runs. It may point at another alias (`lts/*` → `lts/jod` → a version).
    /// With no default alias, the newest installed version is the only signal on disk. `system` means "not nvm".
    static func nvmBinDirectory(home: String, nvmDir: String?, layout: CLINvmLayout) -> String? {
        let fallback = trimmedDirectory(home) + "/.nvm"
        let root: String
        if let nvmDir {
            let trimmed = trimmedDirectory(nvmDir)
            root = trimmed.isEmpty ? fallback : trimmed
        } else {
            root = fallback
        }
        guard let version = activeNvmVersion(layout: layout) else { return nil }
        return root + "/versions/node/" + version + "/bin"
    }

    static func activeNvmVersion(layout: CLINvmLayout) -> String? {
        let aliases = normalizedAliases(layout.aliasFiles)
        let versions = layout.versionNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let defaultAlias = aliases["default"] {
            return followNvmAlias(defaultAlias, aliases: aliases, versions: versions, depth: 0)
        }
        return newestNvmVersion(in: versions)
    }

    private static func normalizedAliases(_ files: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in files {
            let name = key.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !text.isEmpty else { continue }
            result[name] = text
        }
        return result
    }

    private static func followNvmAlias(_ token: String, aliases: [String: String], versions: [String], depth: Int) -> String? {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token != "system", depth < 8 else { return nil }
        if let exact = exactNvmVersion(token, in: versions) { return exact }
        if let prefixed = newestNvmVersion(matching: token, in: versions) { return prefixed }
        guard let next = aliases[token], next != token else { return nil }
        return followNvmAlias(next, aliases: aliases, versions: versions, depth: depth + 1)
    }

    private static func exactNvmVersion(_ token: String, in versions: [String]) -> String? {
        if versions.contains(token) { return token }
        let prefixed = token.hasPrefix("v") ? token : "v" + token
        if versions.contains(prefixed) { return prefixed }
        return nil
    }

    private static func newestNvmVersion(matching token: String, in names: [String]) -> String? {
        var needle = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.hasPrefix("v") { needle.removeFirst() }
        guard let first = needle.first, first.isNumber else { return nil }
        let matches = names.filter { name in
            var bare = name
            if bare.hasPrefix("v") { bare.removeFirst() }
            return bare == needle || bare.hasPrefix(needle + ".")
        }
        return newestNvmVersion(in: matches)
    }

    private static func newestNvmVersion(in names: [String]) -> String? {
        names.max { compareVersionNames($0, $1) == .orderedAscending }
    }

    static func compareVersionNames(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionNumbers(lhs)
        let right = versionNumbers(rhs)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func versionNumbers(_ name: String) -> [Int] {
        var bare = name.hasPrefix("v") ? String(name.dropFirst()) : name
        if let hyphen = bare.firstIndex(of: "-") {
            bare = String(bare[..<hyphen])
        }
        return bare.split(separator: ".").compactMap { Int($0) }
    }
}
