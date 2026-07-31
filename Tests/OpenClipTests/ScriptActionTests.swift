import XCTest
@testable import OpenClip
@testable import Core

fileprivate struct MockApp: AppIdentifying {
    let bundleIdentifier: String?
    let localizedName: String?
}

final class ScriptActionTests: XCTestCase {
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    @MainActor
    func testScriptExecution() async throws {
        let scriptPath = tempDir.appendingPathComponent("test_script.sh")
        let scriptContent = """
        #!/bin/bash
        # Read from stdin
        read input
        if [ "$input" == "hello" ]; then
            echo '{"type":"paste","value":"world"}'
        else
            echo '{"type":"paste","value":"fail"}'
        fi
        """
        try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
        
        // Make executable
        var attrs = try FileManager.default.attributesOfItem(atPath: scriptPath.path)
        attrs[.posixPermissions] = 0o755
        try FileManager.default.setAttributes(attrs, ofItemAtPath: scriptPath.path)
        
        let action = ScriptAction(id: "test", title: "Test", icon: .symbol("test"), scriptURL: scriptPath)
        
        let context = ActionContext(selection: SelectionContext(text: "hello", sourceApp: MockApp(bundleIdentifier: "test", localizedName: "test"), cursorPosition: .zero, timestamp: Date()))
        let result = try await action.perform(context)
        
        switch result {
        case .paste(let value):
            XCTAssertEqual(value, "world")
        default:
            XCTFail("Expected paste action")
        }
    }
    
    @MainActor
    func testScriptEnvVar() async throws {
        let scriptPath = tempDir.appendingPathComponent("env_script.sh")
        let scriptContent = """
        #!/bin/bash
        if [ "$POPCLIP_TEXT" == "environment" ]; then
            echo '{"type":"copy","value":"success"}'
        fi
        """
        try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
        
        // Make executable
        var attrs = try FileManager.default.attributesOfItem(atPath: scriptPath.path)
        attrs[.posixPermissions] = 0o755
        try FileManager.default.setAttributes(attrs, ofItemAtPath: scriptPath.path)
        
        let action = ScriptAction(id: "test2", title: "Test2", icon: .symbol("test"), scriptURL: scriptPath)
        
        let context = ActionContext(selection: SelectionContext(text: "environment", sourceApp: MockApp(bundleIdentifier: "test", localizedName: "test"), cursorPosition: .zero, timestamp: Date()))
        let result = try await action.perform(context)
        
        switch result {
        case .copy(let value):
            XCTAssertEqual(value, "success")
        default:
            XCTFail("Expected copy action")
        }
    }
    @MainActor
    func testScriptFailure() async throws {
        let scriptPath = tempDir.appendingPathComponent("fail_script.sh")
        let scriptContent = """
        #!/bin/bash
        echo "Some error" >&2
        exit 1
        """
        try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
        
        // Make executable
        var attrs = try FileManager.default.attributesOfItem(atPath: scriptPath.path)
        attrs[.posixPermissions] = 0o755
        try FileManager.default.setAttributes(attrs, ofItemAtPath: scriptPath.path)
        
        let action = ScriptAction(id: "testFail", title: "TestFail", icon: .symbol("test"), scriptURL: scriptPath)
        
        let context = ActionContext(selection: SelectionContext(text: "hello", sourceApp: MockApp(bundleIdentifier: "test", localizedName: "test"), cursorPosition: .zero, timestamp: Date()))
        
        do {
            _ = try await action.perform(context)
            XCTFail("Expected script to throw an error due to non-zero exit code")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, Constants.actionErrorDomain)
            XCTAssertEqual(nsError.code, 1) // exit code 1
        }
    }
}
