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
    func testScriptActionPlainStdoutReturnsPasteResult() async throws {
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
        
        if case .paste(let text) = result {
            XCTAssertEqual(text.trimmingCharacters(in: .whitespacesAndNewlines), "Processed: SampleInput")
        } else {
            XCTFail("Expected .paste result for plain stdout, got \(result)")
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

        if case .paste(let text) = result {
            XCTAssertEqual(text.trimmingCharacters(in: .whitespacesAndNewlines), "test.actionid")
        } else {
            XCTFail("Expected .paste result echoing the action id, got \(result)")
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
        
        if case .paste(let text) = result {
            XCTAssertEqual(text.trimmingCharacters(in: .whitespacesAndNewlines), "PASS_ENV")
        } else {
            XCTFail("Expected .paste result with PASS_ENV, got \(result)")
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

    func testScriptActionShowContentJSONFallsThroughToSuccess() async throws {
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
            return XCTFail("Expected .success for shell showContent, got \(result)")
        }

        try? FileManager.default.removeItem(at: tempScript)
    }

    func testScriptActionKeepVisibleJSONWrapsEffect() async throws {
        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("keep_test_\(UUID().uuidString).sh")
        let scriptContent = """
        #!/bin/bash
        echo '{"type":"keepVisible","effect":{"type":"copy","value":"X"}}'
        """
        try scriptContent.write(to: tempScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)

        let action = ScriptAction(id: "test.keep", title: "Keep", icon: .symbol("terminal"), scriptURL: tempScript)
        let result = try await action.perform(ActionContext(selectedText: "SampleInput"))

        guard case .keepVisible(.copy(let text)) = result else {
            return XCTFail("Expected .keepVisible(.copy), got \(result)")
        }
        XCTAssertEqual(text, "X")

        try? FileManager.default.removeItem(at: tempScript)
    }

    func testScriptActionAfterPasteResultOverridesRawCopy() async throws {
        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("after_test_\(UUID().uuidString).sh")
        let scriptContent = """
        #!/bin/bash
        echo '{"type":"copy","value":"X"}'
        """
        try scriptContent.write(to: tempScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)

        let action = ScriptAction(
            id: "test.after",
            title: "After",
            icon: .symbol("terminal"),
            scriptURL: tempScript,
            rules: ExtensionActionRules(after: .pasteResult)
        )
        let result = try await action.perform(ActionContext(selectedText: "SampleInput"))

        guard case .paste(let text) = result else {
            return XCTFail("Expected .paste (raw .copy overridden by paste-result), got \(result)")
        }
        XCTAssertEqual(text, "X")

        try? FileManager.default.removeItem(at: tempScript)
    }

    /// A manifest `type: "canvas"` whose `script` points at a `.sh` file falls through to a shell
    /// ScriptAction — the inline `scriptCode` is what makes a canvas action a canvas; a script file
    /// is routed by extension, so a `.sh` payload is never a JavaScriptCanvasAction.
    func testCanvasManifestWithShellFileIsNotCanvasAction() async {
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
        XCTAssertFalse(action is JavaScriptCanvasAction, "a shell script file must never become a JavaScriptCanvasAction")
        XCTAssertTrue(action is ScriptAction || action is CustomAction,
                      "expected a shell ScriptAction (or CustomAction), got \(String(describing: action))")

        try? FileManager.default.removeItem(at: tempDir)
    }
}
