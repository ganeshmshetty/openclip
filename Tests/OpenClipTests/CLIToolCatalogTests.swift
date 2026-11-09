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
        for preset in [CLIPreset.copilot, .gemini, .cursor, .custom] {
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
        XCTAssertEqual(gemini.installCommand, "brew install gemini-cli")
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
    }

    func testReadinessPlan() throws {
        let gemini = try XCTUnwrap(CLITool.tool(for: .gemini))
        let missing = CLIReadinessPlan.builtin(binaryFound: false, version: nil, authenticated: false, tool: gemini)
        XCTAssertEqual(missing.state, .notInstalled)
        XCTAssertEqual(missing.fixCommand, "brew install gemini-cli")

        let signedOut = CLIReadinessPlan.builtin(binaryFound: true, version: "1.0", authenticated: false, tool: gemini)
        XCTAssertEqual(signedOut.state, .signInNeeded)
        XCTAssertEqual(signedOut.fixCommand, "gemini")

        let ready = CLIReadinessPlan.builtin(binaryFound: true, version: "2026.10.19", authenticated: true, tool: gemini)
        XCTAssertEqual(ready.state, .ready)
        XCTAssertEqual(ready.version, "2026.10.19")
        XCTAssertNil(ready.fixCommand)
        XCTAssertEqual(ready.title, "Ready")
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
