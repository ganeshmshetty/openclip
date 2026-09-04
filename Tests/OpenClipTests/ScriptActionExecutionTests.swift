import XCTest
@testable import Core
@testable import OpenClip

private extension ActionContext {
    init(selectedText: String) {
        let selection = SelectionContext(
            text: selectedText,
            sourceApp: AppIdentity(bundleIdentifier: "com.test.app", localizedName: "TestApp"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        self.init(selection: selection)
    }
}

final class ScriptActionExecutionTests: XCTestCase {
    func testScriptActionPlainStdoutReturnsTextResult() async throws {
        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("echo_test_\(UUID().uuidString).sh")
        let scriptContent = """
        #!/bin/bash
        echo "Processed: $OPENCLIP_TEXT"
        """
        try scriptContent.write(to: tempScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)
        
        let action = ScriptAction(id: "test.echo", title: "Echo", icon: .symbol("terminal"), scriptURL: tempScript)
        let context = ActionContext(selectedText: "SampleInput")
        let result = try await action.perform(context)
        
        if case .text(let text) = result {
            XCTAssertEqual(text.trimmingCharacters(in: .whitespacesAndNewlines), "Processed: SampleInput")
        } else {
            XCTFail("Expected .text result for plain stdout, got \(result)")
        }
        
        try? FileManager.default.removeItem(at: tempScript)
    }
    
    func testScriptActionExposesActionIDEnvVar() async throws {
        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("action_id_test_\(UUID().uuidString).sh")
        let scriptContent = """
        #!/bin/bash
        echo "$OPENCLIP_ACTION_ID"
        """
        try scriptContent.write(to: tempScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)

        let action = ScriptAction(id: "test.actionid", title: "ActionID", icon: .symbol("terminal"), scriptURL: tempScript)
        let result = try await action.perform(ActionContext(selectedText: "SampleInput"))

        if case .text(let text) = result {
            XCTAssertEqual(text.trimmingCharacters(in: .whitespacesAndNewlines), "test.actionid")
        } else {
            XCTFail("Expected .text result echoing the action id, got \(result)")
        }

        try? FileManager.default.removeItem(at: tempScript)
    }

    func testScriptActionEnvironmentVariables() async throws {
        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("env_test_\(UUID().uuidString).sh")
        let scriptContent = """
        #!/bin/bash
        if [ "$OPENCLIP_TEXT" = "SampleInput" ]; then
            echo "PASS_ENV"
        fi
        """
        try scriptContent.write(to: tempScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)
        
        let action = ScriptAction(id: "test.env", title: "Env", icon: .symbol("terminal"), scriptURL: tempScript)
        let context = ActionContext(selectedText: "SampleInput")
        let result = try await action.perform(context)
        
        if case .text(let text) = result {
            XCTAssertEqual(text.trimmingCharacters(in: .whitespacesAndNewlines), "PASS_ENV")
        } else {
            XCTFail("Expected .text result with PASS_ENV, got \(result)")
        }
        
        try? FileManager.default.removeItem(at: tempScript)
    }
    
    func testScriptActionJSONStdoutReturnsParsedResult() async throws {
        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("json_test_\(UUID().uuidString).sh")
        let scriptContent = """
        #!/bin/bash
        echo '{"type":"copy","value":"CopiedResult"}'
        """
        try scriptContent.write(to: tempScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)
        
        let action = ScriptAction(id: "test.json", title: "JSON", icon: .symbol("terminal"), scriptURL: tempScript)
        let context = ActionContext(selectedText: "SampleInput")
        let result = try await action.perform(context)
        
        if case .copy(let text) = result {
            XCTAssertEqual(text, "CopiedResult")
        } else {
            XCTFail("Expected .copy result, got \(result)")
        }
        
        try? FileManager.default.removeItem(at: tempScript)
    }

    func testScriptActionLegacyShowContentJSONFallsThroughToSuccess() async throws {
        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("content_test_\(UUID().uuidString).sh")
        let scriptContent = """
        #!/bin/bash
        echo '{"type":"showContent","title":"T","body":"Body"}'
        """
        try scriptContent.write(to: tempScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)

        let action = ScriptAction(id: "test.content", title: "Content", icon: .symbol("terminal"), scriptURL: tempScript)
        let result = try await action.perform(ActionContext(selectedText: "SampleInput"))

        guard case .success = result else {
            return XCTFail("Expected .success for the legacy showContent JSON type (unmapped → success), got \(result)")
        }

        try? FileManager.default.removeItem(at: tempScript)
    }

    func testScriptActionReturnsRawCopyResult() async throws {
        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("raw_copy_test_\(UUID().uuidString).sh")
        let scriptContent = """
        #!/bin/bash
        echo '{"type":"copy","value":"X"}'
        """
        try scriptContent.write(to: tempScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)

        let action = ScriptAction(
            id: "test.rawcopy",
            title: "Raw Copy",
            icon: .symbol("terminal"),
            scriptURL: tempScript,
            rules: ExtensionActionRules()
        )
        let result = try await action.perform(ActionContext(selectedText: "SampleInput"))

        guard case .copy(let text) = result else {
            return XCTFail("Expected .copy (raw runtime result), got \(result)")
        }
        XCTAssertEqual(text, "X")

        try? FileManager.default.removeItem(at: tempScript)
    }

    /// A legacy manifest `type: "canvas"` whose `script` points at a `.sh` file degrades to a shell
    /// ScriptAction — with the canvas feature removed, the script file is routed by extension, so
    /// a `.sh` payload is a plain shell action (and validation rejects the canvas kind anyway).
    func testCanvasManifestWithShellFileIsPlainShellAction() async {
        let factory = DefaultActionFactory()
        let actionMeta = ExtensionActionMetadata(title: "Canvas File Action", icon: "symbol:terminal", script: "main.sh", type: "canvas")
        let manifest = ExtensionMetadata(identifier: "com.test.canvasfile", name: "Canvas File Test", actions: [actionMeta], options: nil)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let scriptFile = tempDir.appendingPathComponent("main.sh")
        try? "#!/bin/sh\necho hi".write(to: scriptFile, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptFile.path)

        let action = await factory.createAction(metadata: actionMeta, manifest: manifest, directoryURL: tempDir, index: 0)
        guard let action else {
            try? FileManager.default.removeItem(at: tempDir)
            return XCTFail("A canvas manifest pointing at a shell file must still produce an action")
        }
        XCTAssertTrue(action is ScriptAction || action is CustomAction,
                      "expected a shell ScriptAction (or CustomAction), got \(String(describing: action))")

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testScriptActionNonZeroExitThrowsError() async throws {
        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("fail_test_\(UUID().uuidString).sh")
        let scriptContent = """
        #!/bin/bash
        echo "Some error" >&2
        exit 1
        """
        try scriptContent.write(to: tempScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)

        let action = ScriptAction(id: "test.fail", title: "Fail", icon: .symbol("terminal"), scriptURL: tempScript)
        do {
            _ = try await action.perform(ActionContext(selectedText: "hello"))
            XCTFail("Expected script to throw an error due to non-zero exit code")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, Constants.actionErrorDomain)
            XCTAssertEqual(nsError.code, 1)
        }

        try? FileManager.default.removeItem(at: tempScript)
    }

    /// A subprocess that never exits must be killed by the GCD watchdog at the invocation budget
    /// instead of hanging the suite. Regression for the mid-suite hang where a blocked
    /// `readToEnd()` plus a starved `Task.sleep` watchdog wedged the cooperative pool.
    func testScriptActionWatchdogKillsNeverExitingScript() async throws {
        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("hang_test_\(UUID().uuidString).sh")
        let scriptContent = """
        #!/bin/bash
        exec sleep 60
        """
        try scriptContent.write(to: tempScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)

        do {
            _ = try await ShellProcessRunner.run(ShellProcessRunner.Invocation(
                executableURL: tempScript,
                arguments: [],
                environment: [:],
                stdinText: nil,
                timeout: 0.1
            ))
            XCTFail("Expected watchdog timeout")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, Constants.actionErrorDomain)
            XCTAssertTrue(nsError.localizedDescription.contains("timed out"),
                          "expected timeout error, got \(nsError.localizedDescription)")
        }

        try? FileManager.default.removeItem(at: tempScript)
    }

    /// Cancelling the Swift Task executing a subprocess must immediately signal and kill the
    /// subprocess group and throw CancellationError without waiting for the full timeout.
    func testScriptActionCancellationKillsSubprocessImmediately() async throws {
        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("cancel_test_\(UUID().uuidString).sh")
        let scriptContent = """
        #!/bin/bash
        exec sleep 60
        """
        try scriptContent.write(to: tempScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)

        let startTime = Date()
        let task = Task {
            try await ShellProcessRunner.run(ShellProcessRunner.Invocation(
                executableURL: tempScript,
                arguments: [],
                environment: [:],
                stdinText: nil,
                timeout: 60.0
            ))
        }

        // Wait slightly for process to spawn
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected task to be cancelled and throw CancellationError")
        } catch is CancellationError {
            // Expected
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        let elapsed = Date().timeIntervalSince(startTime)
        XCTAssertLessThan(elapsed, 5.0, "Subprocess cancellation should abort almost immediately, took \(elapsed)s")

        try? FileManager.default.removeItem(at: tempScript)
    }

    /// Large stdout output spanning multiple pipe buffer chunks must be completely and
    /// cleanly accumulated without truncation.
    func testScriptActionLargeOutputIsCapturedCompletely() async throws {
        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("large_output_\(UUID().uuidString).sh")
        let scriptContent = """
        #!/bin/bash
        for i in $(seq 1 5000); do
            echo "Line $i: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        done
        """
        try scriptContent.write(to: tempScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)

        let output = try await ShellProcessRunner.run(ShellProcessRunner.Invocation(
            executableURL: tempScript,
            arguments: [],
            environment: [:],
            stdinText: nil,
            timeout: 5.0
        ))

        let lines = output.stdout.split(separator: "\n")
        XCTAssertEqual(lines.count, 5000)
        XCTAssertEqual(lines.first, "Line 1: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        XCTAssertEqual(lines.last, "Line 5000: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")

        try? FileManager.default.removeItem(at: tempScript)
    }

    /// When a script spawns a background grandchild process that inherits the pipe fds,
    /// finish must not hang indefinitely waiting for EOF on the pipe.
    func testScriptActionGrandchildHoldingPipeDoesNotHang() async throws {
        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("grandchild_pipe_\(UUID().uuidString).sh")
        let scriptContent = """
        #!/bin/bash
        (sleep 5) &
        echo "ParentDone"
        exit 0
        """
        try scriptContent.write(to: tempScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)

        let output = try await ShellProcessRunner.run(ShellProcessRunner.Invocation(
            executableURL: tempScript,
            arguments: [],
            environment: [:],
            stdinText: nil,
            timeout: 2.0
        ))

        XCTAssertEqual(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "ParentDone")

        try? FileManager.default.removeItem(at: tempScript)
    }

    @MainActor
    func testAppleScriptActionEscapesPlaceholdersWithQuotesAndBackslashes() async throws {
        let scriptCode = """
        return "{text}"
        """
        let action = AppleScriptAction(id: "test.applescript.escape", title: "Test AppleScript", appleScriptCode: scriptCode)
        let inputWithQuotes = "Hello \"World\" \\ test"
        let context = ActionContext(selectedText: inputWithQuotes)

        let result = try await action.perform(context)
        if case .text(let output) = result {
            XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), inputWithQuotes)
        } else {
            XCTFail("Expected .text result containing returned text, got \(result)")
        }
    }

    /// A multiline selection must be escaped to AppleScript's `\r`/`\n` string escapes so the
    /// generated script is a valid string literal and the value round-trips.
    @MainActor
    func testAppleScriptActionEscapesMultilineSelection() async throws {
        let scriptCode = """
        return "{text}"
        """
        let action = AppleScriptAction(id: "test.applescript.multiline", title: "Test AppleScript", appleScriptCode: scriptCode)
        let input = "line1\nline2\rline3"
        let context = ActionContext(selectedText: input)

        let result = try await action.perform(context)
        if case .text(let output) = result {
            XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), input)
        } else {
            XCTFail("Expected .text result containing multiline text, got \(result)")
        }
    }

    /// A script authored with an explicit `on run` handler must work: the runtime injects the
    /// selection as a top-level `property` (which coexists with `on run`), not top-level `set`
    /// statements (which AppleScript rejects with -2752). Regression for the Apple Music extension.
    @MainActor
    func testAppleScriptActionSupportsOnRunHandlerStyle() async throws {
        let scriptCode = """
        on run
            return "AS:" & OPENCLIP_TEXT
        end run
        """
        let action = AppleScriptAction(id: "test.applescript.onrun", title: "On Run", appleScriptCode: scriptCode)
        let context = ActionContext(selectedText: "hello")
        let result = try await action.perform(context)
        if case .text(let output) = result {
            XCTAssertEqual(output, "AS:hello")
        } else {
            XCTFail("Expected .text result for on-run script, got \(result)")
        }
    }

    @MainActor
    func testShellResultMapperParsesExpandedJSONProtocol() throws {
        let cutRes = ShellResultMapper.actionResult(from: "{\"type\":\"cut\",\"value\":\"clip\"}", actionID: "a")
        guard case .cut(let text) = cutRes else { return XCTFail("Expected .cut") }
        XCTAssertEqual(text, "clip")

        let keyRes = ShellResultMapper.actionResult(from: "{\"type\":\"keyPress\",\"key\":\"c\",\"modifiers\":[\"command\"]}", actionID: "a")
        guard case .keyPress(let spec) = keyRes else { return XCTFail("Expected .keyPress") }
        XCTAssertEqual(spec.key, "c")
        XCTAssertEqual(spec.modifiers, [.command])

        let scRes = ShellResultMapper.actionResult(from: "{\"type\":\"runShortcut\",\"name\":\"MySc\",\"input\":\"txt\"}", actionID: "a")
        guard case .runShortcut(let name, let input) = scRes else { return XCTFail("Expected .runShortcut") }
        XCTAssertEqual(name, "MySc")
        XCTAssertEqual(input, "txt")

        let notRes = ShellResultMapper.actionResult(from: "{\"type\":\"notify\",\"title\":\"T\",\"body\":\"B\"}", actionID: "a")
        guard case .notify(let title, let body) = notRes else { return XCTFail("Expected .notify") }
        XCTAssertEqual(title, "T")
        XCTAssertEqual(body, "B")

        let shareRes = ShellResultMapper.actionResult(from: "{\"type\":\"shareService\",\"identifier\":\"com.apple.Notes.SharingExtension\",\"value\":\"hi\"}", actionID: "a")
        guard case .shareService(let identifier, let text) = shareRes else { return XCTFail("Expected .shareService") }
        XCTAssertEqual(identifier, "com.apple.Notes.SharingExtension")
        XCTAssertEqual(text, "hi")

        let seqRes = ShellResultMapper.actionResult(from: "{\"type\":\"sequence\",\"actions\":[{\"type\":\"copy\",\"value\":\"1\"},{\"type\":\"paste\",\"value\":\"2\"}]}", actionID: "a")
        guard case .sequence(let sub) = seqRes else { return XCTFail("Expected .sequence") }
        XCTAssertEqual(sub.count, 2)

        let failRes = ShellResultMapper.actionResult(from: "{\"type\":\"fail\",\"message\":\"Broken\"}", actionID: "a")
        guard case .failure(let err) = failRes else { return XCTFail("Expected .failure") }
        XCTAssertEqual((err as NSError).localizedDescription, "Broken")

        let toastRes = ShellResultMapper.actionResult(from: "{\"type\":\"toast\",\"message\":\"Saved\",\"style\":\"success\",\"keepVisible\":true}", actionID: "a")
        guard case .toast(let fb) = toastRes else { return XCTFail("Expected .toast") }
        XCTAssertEqual(fb.message, "Saved")
        XCTAssertEqual(fb.style, .success)
        XCTAssertTrue(fb.keepVisible)

        let toastPlainRes = ShellResultMapper.actionResult(from: "{\"type\":\"toast\",\"message\":\"Note\",\"style\":\"info\"}", actionID: "a")
        guard case .toast(let plainFb) = toastPlainRes else { return XCTFail("Expected .toast") }
        XCTAssertEqual(plainFb.message, "Note")
        XCTAssertEqual(plainFb.style, .info)
        XCTAssertFalse(plainFb.keepVisible)

        let legacyStatusRes = ShellResultMapper.actionResult(from: "{\"type\":\"status\",\"message\":\"Old\"}", actionID: "a")
        guard case .success = legacyStatusRes else { return XCTFail("Expected .success for removed \"status\" type") }
    }
}

