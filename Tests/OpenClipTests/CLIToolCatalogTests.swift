import XCTest
@testable import OpenClip

final class CLIToolCatalogTests: XCTestCase {

    private let staleModelIDs = [
        "claude-3-7-sonnet-latest",
        "claude-3-5-haiku-latest",
        "claude-3.5-sonnet",
        "gpt-4o",
        "gpt-4o-mini",
        "o1",
        "o3",
        "o3-mini"
    ]

    func testCatalogHasOneEntryPerBuiltinPreset() {
        let builtins = CLIPreset.allCases.filter { $0 != .custom }
        XCTAssertEqual(CLITool.catalog.map(\.preset), builtins)
        for tool in CLITool.catalog {
            XCTAssertEqual(tool.runner, .subprocess, tool.preset.rawValue)
            XCTAssertFalse(tool.binaries.isEmpty, tool.preset.rawValue)
            XCTAssertEqual(tool.versionArguments, ["--version"], tool.preset.rawValue)
        }
        XCTAssertNil(CLITool.tool(for: .custom))
    }

    func testPresetsDoNotShipStaleModelLists() {
        for tool in CLITool.catalog {
            for stale in staleModelIDs {
                XCTAssertFalse(tool.documentedAliases.contains(stale), "\(tool.preset.rawValue) \(stale)")
            }
        }
        XCTAssertEqual(CLIPreset.claude.defaultModels, ["default", "fable", "opus", "sonnet"])
        XCTAssertEqual(CLIPreset.copilot.defaultModels, ["default", "gpt-5.4"])
        XCTAssertEqual(CLITool.tool(for: .gemini)?.documentedAliases, ["auto", "pro", "flash", "flash-lite"])
        XCTAssertEqual(CLITool.tool(for: .codex)?.documentedAliases, [])
        XCTAssertEqual(CLITool.tool(for: .cursor)?.documentedAliases, [])
    }

    func testOnlyClaudeAndCodexDisableThinking() {
        XCTAssertEqual(CLIPreset.claude.thinkingDisabledEnvironment["MAX_THINKING_TOKENS"], "0")
        XCTAssertEqual(CLIPreset.codex.thinkingDisabledArguments, ["-c", "model_reasoning_effort=none"])
        for preset in [CLIPreset.copilot, .gemini, .antigravity, .cursor, .opencode, .custom] {
            XCTAssertTrue(preset.thinkingDisabledEnvironment.isEmpty, preset.rawValue)
            XCTAssertTrue(preset.thinkingDisabledArguments.isEmpty, preset.rawValue)
        }
    }

    func testCopilotInvocationIsTheStandaloneCLI() throws {
        let tool = try XCTUnwrap(CLITool.tool(for: .copilot))
        XCTAssertEqual(tool.binaries, ["copilot"])
        XCTAssertEqual(tool.installCommand, "brew install copilot-cli")
        XCTAssertEqual(tool.signInCommand, "copilot login")
        let args = arguments(tool, model: "gpt-5.4")
        XCTAssertEqual(args.first, "-p")
        XCTAssertTrue(args.contains("--allow-all-tools"))
        XCTAssertTrue(args.contains("--model"))
        XCTAssertTrue(args.contains("gpt-5.4"))
        XCTAssertFalse(args.contains("gh"))
        XCTAssertEqual(tool.invocation.stdin, .none)
    }

    func testClaudeAndCodexInvocationTemplates() throws {
        let claude = try XCTUnwrap(CLITool.tool(for: .claude))
        let claudeArgs = arguments(claude, model: "sonnet")
        XCTAssertEqual(
            claudeArgs,
            ["-p", "--tools", "", "--no-session-persistence", "--system-prompt", "SYS", "--model", "sonnet"]
        )
        XCTAssertEqual(claude.invocation.stdin, .userText)

        let codex = try XCTUnwrap(CLITool.tool(for: .codex))
        let codexArgs = arguments(codex, model: "configured")
        XCTAssertEqual(codexArgs.first, "exec")
        XCTAssertEqual(Array(codexArgs.prefix(3)), ["exec", "-c", "model_reasoning_effort=none"])
        XCTAssertTrue(codexArgs.contains("--json"))
        XCTAssertTrue(codexArgs.contains("--sandbox"))
        XCTAssertEqual(codexArgs.suffix(2), ["-m", "configured"])
        XCTAssertEqual(codex.invocation.stdin, .userText)
        XCTAssertEqual(codex.invocation.output, .codexJSONL)
    }

    func testGeminiAndCursorTemplates() throws {
        let gemini = try XCTUnwrap(CLITool.tool(for: .gemini))
        XCTAssertEqual(gemini.binaries, ["gemini"])
        XCTAssertEqual(gemini.installCommand, "npm install -g @google/gemini-cli")
        let geminiArgs = arguments(gemini, model: "")
        XCTAssertTrue(geminiArgs.contains("-p"))
        XCTAssertTrue(geminiArgs.contains("--skip-trust"))
        XCTAssertFalse(geminiArgs.contains("--model"))
        if case .command(let arguments, let parse) = gemini.models {
            XCTAssertEqual(arguments, ["models", "-o", "json"])
            XCTAssertEqual(parse, .jsonModelID)
        } else {
            XCTFail("Gemini should list models")
        }

        let cursor = try XCTUnwrap(CLITool.tool(for: .cursor))
        XCTAssertEqual(cursor.binaries, ["cursor-agent", "agent"])
        XCTAssertEqual(cursor.signInCommand, "agent login")
        let cursorArgs = arguments(cursor, model: "gpt-5.2")
        XCTAssertTrue(cursorArgs.contains("-p"))
        XCTAssertTrue(cursorArgs.contains("ask"))
        XCTAssertTrue(cursorArgs.contains("--trust"))
        XCTAssertTrue(cursorArgs.contains("--model"))
        if case .command(let arguments, let parse) = cursor.models {
            XCTAssertEqual(arguments, ["models"])
            XCTAssertEqual(parse, .idDashName)
        } else {
            XCTFail("Cursor should list models")
        }
    }

    func testAntigravityCatalogEntry() throws {
        let tool = try XCTUnwrap(CLITool.tool(for: .antigravity))
        XCTAssertEqual(tool.binaries, ["agy"])
        XCTAssertEqual(tool.installCommand, "curl -fsSL https://antigravity.google/cli/install.sh | bash")
        XCTAssertEqual(tool.signInCommand, "agy")
        let args = arguments(tool, model: "gemini-3.8-flash-high")
        XCTAssertEqual(args.first, "-p")
        XCTAssertTrue(args.contains("--output-format"))
        XCTAssertTrue(args.contains("text"))
        XCTAssertTrue(args.contains("--model"))
        XCTAssertTrue(args.contains("gemini-3.8-flash-high"))
        if case .command(let arguments, let parse) = tool.models {
            XCTAssertEqual(arguments, ["models"])
            XCTAssertEqual(parse, .tabName)
        } else {
            XCTFail("Antigravity should list models")
        }
    }

    func testOpenCodeCatalogEntry() throws {
        let tool = try XCTUnwrap(CLITool.tool(for: .opencode))
        XCTAssertEqual(tool.binaries, ["opencode"])
        XCTAssertEqual(tool.installCommand, "curl -fsSL https://opencode.ai/v2/install | bash")
        XCTAssertEqual(tool.signInCommand, "opencode auth login")
        let args = arguments(tool, model: "opencode-go/deepseek-v4.1-flash")
        XCTAssertEqual(args.first, "run")
        XCTAssertTrue(args.contains("--auto"))
        XCTAssertTrue(args.contains("--model"))
        XCTAssertTrue(args.contains("opencode-go/deepseek-v4.1-flash"))
        if case .command(let arguments, let parse) = tool.models {
            XCTAssertEqual(arguments, ["models"])
            XCTAssertEqual(parse, .lines)
        } else {
            XCTFail("OpenCode should list models")
        }
        if case .command(_, let arguments, let rule) = tool.auth {
            XCTAssertEqual(arguments, ["auth", "list", "--format", "json"])
            XCTAssertEqual(rule, .jsonNonEmptyArray)
        } else {
            XCTFail("OpenCode should check auth")
        }
    }

    func testModelListParsers() {
        let cursor = CLIModelListParser.parse(
            "Available models\n\nauto - Auto (current)\ngpt-5.2 - GPT-5.2\n\n",
            format: .idDashName
        )
        XCTAssertEqual(cursor, ["auto", "gpt-5.2"])

        let gemini = CLIModelListParser.parse(
            #"[{"modelId":"gemini-2.5-pro","name":"Pro"},{"modelId":"gemini-2.5-flash"}]"#,
            format: .jsonModelID
        )
        XCTAssertEqual(gemini, ["gemini-2.5-pro", "gemini-2.5-flash"])
        XCTAssertTrue(CLIModelListParser.parse("not json", format: .jsonModelID).isEmpty)

        let opencode = CLIModelListParser.parse(
            "opencode-go/deepseek-v4.1-flash\nopencode/gpt-6.1-sol\n\nopencode-go/deepseek-v4.1-flash\n",
            format: .lines
        )
        XCTAssertEqual(opencode, ["opencode-go/deepseek-v4.1-flash", "opencode/gpt-6.1-sol"])

        let antigravity = CLIModelListParser.parse(
            "gemini-3.8-flash-high\tGemini 3.8 Flash (High)\nclaude-sonnet-4-6\tClaude Sonnet 4.6\n",
            format: .tabName
        )
        XCTAssertEqual(antigravity, ["gemini-3.8-flash-high", "claude-sonnet-4-6"])
    }

    func testAuthOutputRules() {
        XCTAssertTrue(CLIAuthOutput.passes(rule: .jsonBool("loggedIn"), exitCode: 0, output: #"{"loggedIn": true}"#))
        XCTAssertFalse(CLIAuthOutput.passes(rule: .jsonBool("loggedIn"), exitCode: 0, output: #"{"loggedIn": false}"#))
        XCTAssertTrue(CLIAuthOutput.passes(rule: .jsonBool("isAuthenticated"), exitCode: 0, output: #"{"isAuthenticated":true}"#))
        XCTAssertTrue(CLIAuthOutput.passes(
            rule: .phrase(marker: "logged in", negated: "not logged in"),
            exitCode: 0,
            output: "Logged in using ChatGPT"
        ))
        XCTAssertFalse(CLIAuthOutput.passes(
            rule: .phrase(marker: "logged in", negated: "not logged in"),
            exitCode: 0,
            output: "Not logged in"
        ))
        XCTAssertFalse(CLIAuthOutput.passes(rule: .exitZero, exitCode: 1, output: ""))
        XCTAssertTrue(CLIAuthOutput.passes(rule: .jsonNonEmptyArray, exitCode: 0, output: #"[{"id":"opencode-go"}]"#))
        XCTAssertFalse(CLIAuthOutput.passes(rule: .jsonNonEmptyArray, exitCode: 0, output: "[]"))
        XCTAssertFalse(CLIAuthOutput.passes(rule: .jsonNonEmptyArray, exitCode: 1, output: #"[{"id":"opencode-go"}]"#))
    }

    func testReadinessPlan() throws {
        let gemini = try XCTUnwrap(CLITool.tool(for: .gemini))
        let missing = CLIReadinessPlan.builtin(binaryFound: false, version: nil, authenticated: false, tool: gemini)
        XCTAssertEqual(missing.state, .notInstalled)
        XCTAssertEqual(missing.fixCommand, "npm install -g @google/gemini-cli")

        let signedOut = CLIReadinessPlan.builtin(binaryFound: true, version: "1.0", authenticated: false, tool: gemini)
        XCTAssertEqual(signedOut.state, .signInNeeded)
        XCTAssertEqual(signedOut.fixCommand, "gemini")

        let ready = CLIReadinessPlan.builtin(binaryFound: true, version: "2026.10.19", authenticated: true, tool: gemini)
        XCTAssertEqual(ready.state, .ready)
        XCTAssertEqual(ready.version, "2026.10.19")
        XCTAssertNil(ready.fixCommand)
        XCTAssertEqual(ready.title, "Ready")
    }

    func testCopyActionAndMenuSuffixOnlyForBuiltinFailures() throws {
        let gemini = try XCTUnwrap(CLITool.tool(for: .gemini))
        let missing = CLIReadinessPlan.builtin(binaryFound: false, version: nil, authenticated: false, tool: gemini)
        XCTAssertEqual(missing.setupActionTitle, "Install")
        XCTAssertEqual(missing.menuSuffix, "Not installed")

        let signedOut = CLIReadinessPlan.builtin(binaryFound: true, version: "1.0", authenticated: false, tool: gemini)
        XCTAssertEqual(signedOut.setupActionTitle, "Sign In")
        XCTAssertNil(signedOut.menuSuffix)

        let ready = CLIReadinessPlan.builtin(binaryFound: true, version: "1.0", authenticated: true, tool: gemini)
        XCTAssertNil(ready.setupActionTitle)
        XCTAssertNil(ready.menuSuffix)
        XCTAssertTrue(ready.showsStatus)
        XCTAssertFalse(CLIReadiness.unspecified().showsStatus)
    }

    func testCustomReadinessStaysQuietUntilACommandIsEntered() {
        let empty = CLIReadinessPlan.custom(command: "   ", binaryFound: false, authCommand: "", authPassed: false)
        XCTAssertEqual(empty.state, .unspecified)
        XCTAssertTrue(empty.hint.isEmpty)
        XCTAssertNil(empty.fixCommand)
        XCTAssertNil(empty.setupActionTitle)
        XCTAssertNil(empty.menuSuffix)

        let missing = CLIReadinessPlan.custom(command: "llm -m example", binaryFound: false, authCommand: "llm models", authPassed: false)
        XCTAssertEqual(missing.state, .notInstalled)
        XCTAssertEqual(missing.hint, "Command “llm” not found")
        XCTAssertNil(missing.setupActionTitle)
        XCTAssertNil(missing.menuSuffix)

        let ready = CLIReadinessPlan.custom(command: "llm", binaryFound: true, authCommand: "", authPassed: false)
        XCTAssertEqual(ready.state, .ready)
        XCTAssertNil(ready.setupActionTitle)

        let authFailed = CLIReadinessPlan.custom(command: "llm", binaryFound: true, authCommand: "llm models", authPassed: false)
        XCTAssertEqual(authFailed.state, .signInNeeded)
        XCTAssertEqual(authFailed.hint, "Auth check failed")
        XCTAssertNil(authFailed.fixCommand)
        XCTAssertNil(authFailed.setupActionTitle)
    }

    func testSupplementalDirectoriesCoverCommonInstallLocations() {
        let home = "/Users/g"
        let nvm = "\(home)/.nvm/versions/node/v22.11.0/bin"
        XCTAssertEqual(
            CLIExecutableSearch.supplementalDirectories(home: home + "/", nvmBin: nvm),
            [
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "\(home)/.local/bin",
                "\(home)/.opencode/bin",
                "\(home)/.npm-global/bin",
                "\(home)/.bun/bin",
                "\(home)/.volta/bin",
                nvm,
                "\(home)/.cargo/bin",
                "/usr/bin",
                "/bin"
            ]
        )
        XCTAssertFalse(CLIExecutableSearch.supplementalDirectories(home: home, nvmBin: nil).contains { $0.contains("nvm") })
    }

    func testLoginPathOutranksInstallLocations() {
        let home = "/Users/g"
        let supplemental = CLIExecutableSearch.supplementalDirectories(
            home: home,
            nvmBin: "\(home)/.nvm/versions/node/v22.11.0/bin"
        )
        let directories = CLIExecutableSearch.searchDirectories(
            loginPATH: ["\(home)/.local/bin", "", "/usr/bin", "\(home)/.local/bin"],
            supplemental: supplemental
        )
        XCTAssertEqual(directories.first, "\(home)/.local/bin")
        XCTAssertEqual(directories.filter { $0 == "/opt/homebrew/bin" }.count, 1)
        let files: Set<String> = [
            "/opt/homebrew/bin/gemini",
            "\(home)/.local/bin/gemini"
        ]
        XCTAssertEqual(
            CLIExecutableSearch.resolve(name: "gemini", home: home, directories: directories, isExecutable: { files.contains($0) }),
            "\(home)/.local/bin/gemini"
        )
        XCTAssertEqual(
            CLIExecutableSearch.resolve(name: "gemini", home: home, directories: ["/usr/bin", "\(home)/.nvm/versions/node/v22.11.0/bin"], isExecutable: { $0 == "\(home)/.nvm/versions/node/v22.11.0/bin/gemini" }),
            "\(home)/.nvm/versions/node/v22.11.0/bin/gemini"
        )
    }

    func testPathLookupRejectsBlankRelativeAndMissingPaths() {
        let home = "/Users/g"
        XCTAssertNil(CLIExecutableSearch.resolve(name: "  ", home: home, directories: ["/usr/bin"], isExecutable: { _ in true }))
        XCTAssertNil(CLIExecutableSearch.resolve(name: "gemini/../codex", home: home, directories: ["/usr/bin"], isExecutable: { _ in true }))
        XCTAssertNil(CLIExecutableSearch.resolve(name: "/opt/missing", home: home, directories: ["/opt"], isExecutable: { _ in false }))
        XCTAssertEqual(
            CLIExecutableSearch.resolve(name: "~/bin/gemini", home: home + "/", directories: [], isExecutable: { $0 == "\(home)/bin/gemini" }),
            "\(home)/bin/gemini"
        )
        XCTAssertEqual(
            CLIExecutableSearch.resolve(name: "/opt/homebrew/bin/gemini", home: home, directories: [], isExecutable: { $0 == "/opt/homebrew/bin/gemini" }),
            "/opt/homebrew/bin/gemini"
        )
    }

    func testLoginPathParserIgnoresProfileNoise() {
        let output = """
        Updated: homebrew
        OPENCLIP_PATH_BEGIN
        /opt/homebrew/bin:/Users/g/.nvm/versions/node/v22.11.0/bin:/usr/bin
        OPENCLIP_PATH_END
        done
        """
        XCTAssertEqual(
            CLIExecutableSearch.pathFromLoginOutput(output),
            ["/opt/homebrew/bin", "/Users/g/.nvm/versions/node/v22.11.0/bin", "/usr/bin"]
        )
        XCTAssertEqual(CLIExecutableSearch.pathFromLoginOutput("no markers\n"), [])
        XCTAssertEqual(CLIExecutableSearch.parsePATH("/usr/bin::/bin/"), ["/usr/bin", "/bin"])
        XCTAssertTrue(CLIExecutableSearch.loginPathScript(shellPath: "/bin/zsh").contains("\"$PATH\""))
        XCTAssertTrue(CLIExecutableSearch.loginPathScript(shellPath: "/opt/homebrew/bin/fish").contains("string join : $PATH"))
        XCTAssertFalse(CLIExecutableSearch.loginPathScript(shellPath: "/bin/bash").contains("string join"))
    }

    func testNvmAliasChainsAndNumericPrefixes() {
        let chained = CLINvmLayout(
            aliasFiles: [
                "default": "lts/*\n",
                "lts/*": "lts/jod",
                "lts/jod": "v22.11.0"
            ],
            versionNames: ["v20.18.0", "v22.11.0"]
        )
        XCTAssertEqual(
            CLIExecutableSearch.nvmBinDirectory(home: "/Users/g", nvmDir: nil, layout: chained),
            "/Users/g/.nvm/versions/node/v22.11.0/bin"
        )

        let prefixed = CLINvmLayout(
            aliasFiles: ["default": "20"],
            versionNames: ["v20.9.0", "v20.18.10", "v22.1.0"]
        )
        XCTAssertEqual(
            CLIExecutableSearch.nvmBinDirectory(home: "/Users/g", nvmDir: "/custom/nvm/", layout: prefixed),
            "/custom/nvm/versions/node/v20.18.10/bin"
        )

        let system = CLINvmLayout(aliasFiles: ["default": "system"], versionNames: ["v22.1.0"])
        XCTAssertNil(CLIExecutableSearch.nvmBinDirectory(home: "/Users/g", nvmDir: nil, layout: system))

        let newest = CLINvmLayout(aliasFiles: [:], versionNames: ["v18.20.0", "v22.2.0", "v20.10.0"])
        XCTAssertEqual(
            CLIExecutableSearch.nvmBinDirectory(home: "/Users/g", nvmDir: nil, layout: newest),
            "/Users/g/.nvm/versions/node/v22.2.0/bin"
        )
        XCTAssertNil(
            CLIExecutableSearch.nvmBinDirectory(home: "/Users/g", nvmDir: nil, layout: CLINvmLayout(aliasFiles: [:], versionNames: []))
        )
        XCTAssertEqual(CLIExecutableSearch.compareVersionNames("v20.9.0", "v20.10.0"), .orderedAscending)
        XCTAssertEqual(CLIExecutableSearch.compareVersionNames("v20.18.10", "v20.18.9"), .orderedDescending)
    }

    func testExecutableLookupSkipsDirectoriesAndNonExecutableFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("openclip-cli-lookup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        let other = root.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin.appendingPathComponent("gemini", isDirectory: true), withIntermediateDirectories: true)
        let plain = bin.appendingPathComponent("codex").path
        XCTAssertTrue(FileManager.default.createFile(atPath: plain, contents: Data()))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plain)
        let executable = other.appendingPathComponent("gemini").path
        XCTAssertTrue(FileManager.default.createFile(atPath: executable, contents: Data("#!/bin/sh\n".utf8)))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable)

        let directories = [bin.path, other.path]
        XCTAssertNil(
            CLIExecutableSearch.resolve(name: "codex", home: root.path, directories: directories, isExecutable: CLIExecutableSearch.isExecutableFile(at:))
        )
        XCTAssertEqual(
            CLIExecutableSearch.resolve(name: "gemini", home: root.path, directories: directories, isExecutable: CLIExecutableSearch.isExecutableFile(at:)),
            executable
        )
    }

    private func arguments(_ tool: CLITool, model: String) -> [String] {
        CLIArgumentPlan.arguments(
            template: tool.invocation,
            thinkingArguments: tool.thinkingArguments,
            systemPrompt: "SYS",
            userContent: "TEXT",
            model: model
        )
    }
}
