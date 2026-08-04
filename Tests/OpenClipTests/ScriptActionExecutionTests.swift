import XCTest
@testable import Core
@testable import OpenClip

fileprivate struct MockApp: AppIdentifying {
    let bundleIdentifier: String? = "com.test.app"
    let localizedName: String? = "TestApp"
}

private extension ActionContext {
    init(selectedText: String) {
        let selection = SelectionContext(
            text: selectedText,
            sourceApp: MockApp(),
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

    func testScriptActionShowBubbleJSONReturnsShowBubble() async throws {
        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("bubble_test_\(UUID().uuidString).sh")
        let scriptContent = """
        #!/bin/bash
        echo '{"type":"showBubble","title":"T","body":"Body","footer":["paste","copy"]}'
        """
        try scriptContent.write(to: tempScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)

        let action = ScriptAction(id: "test.bubble", title: "Bubble", icon: .symbol("terminal"), scriptURL: tempScript)
        let result = try await action.perform(ActionContext(selectedText: "SampleInput"))

        guard case .showBubble(let content) = result else {
            return XCTFail("Expected .showBubble, got \(result)")
        }
        XCTAssertEqual(content.title, "T")
        XCTAssertEqual(content.rows.count, 1)
        guard case .text(let rowText) = content.rows[0] else {
            return XCTFail("Expected text row")
        }
        XCTAssertEqual(rowText, "Body")
        XCTAssertEqual(content.footer.count, 2)
        XCTAssertEqual(content.footer[0].title, "Paste")
        guard case .perform(.paste("Body")) = content.footer[0].outcome else {
            return XCTFail("Expected Paste footer performing .paste(Body)")
        }
        XCTAssertEqual(content.footer[1].title, "Copy")
        guard case .perform(.copy("Body")) = content.footer[1].outcome else {
            return XCTFail("Expected Copy footer performing .copy(Body)")
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
}
