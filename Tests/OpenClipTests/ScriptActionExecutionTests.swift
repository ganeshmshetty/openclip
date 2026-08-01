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
    
    func testScriptActionEnvironmentVariables() async throws {
        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("env_test_\(UUID().uuidString).sh")
        let scriptContent = """
        #!/bin/bash
        if [ "$OPENCLIP_TEXT" = "SampleInput" ] && [ "$POPCLIP_TEXT" = "SampleInput" ]; then
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
}
