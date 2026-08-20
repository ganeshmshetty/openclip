import XCTest
@testable import OpenClip
@testable import Core

@MainActor
final class RevealInFinderActionTests: XCTestCase {
    func testPathResolution() {
        let action = RevealInFinderAction()
        
        // Existing path (current working directory)
        let currentDir = FileManager.default.currentDirectoryPath
        let resolved = action.resolvePath(from: currentDir)
        XCTAssertEqual(resolved, currentDir)
        
        // Non-existent path
        let nonExistent = "/non/existent/path/for/unit/test/12345"
        XCTAssertNil(action.resolvePath(from: nonExistent))

        // Existing file (this test source file)
        let existingFile = #filePath
        XCTAssertEqual(action.resolvePath(from: existingFile), existingFile)

        // Compiler error format (:line:col)
        let withLineCol = "\(existingFile):42:15"
        XCTAssertEqual(action.resolvePath(from: withLineCol), existingFile)

        // Single colon line number
        let withLine = "\(existingFile):42"
        XCTAssertEqual(action.resolvePath(from: withLine), existingFile)

        // Quoted paths (ASCII and smart quotes)
        XCTAssertEqual(action.resolvePath(from: "\"\(existingFile)\""), existingFile)
        XCTAssertEqual(action.resolvePath(from: "'\(existingFile)'"), existingFile)
        XCTAssertEqual(action.resolvePath(from: "“\(existingFile)”"), existingFile)

        // Markdown / Bracket wrapped
        XCTAssertEqual(action.resolvePath(from: "<\(existingFile)>"), existingFile)
        XCTAssertEqual(action.resolvePath(from: "(\(existingFile))"), existingFile)

        // Embedded in log line
        let logLine = "Error in \(existingFile):80:15: syntax error"
        XCTAssertEqual(action.resolvePath(from: logLine), existingFile)

        // Trailing sentence punctuation
        XCTAssertEqual(action.resolvePath(from: "Check \(existingFile)."), existingFile)
        XCTAssertEqual(action.resolvePath(from: "See \(existingFile),"), existingFile)

        // file:// URI
        XCTAssertEqual(action.resolvePath(from: "file://\(existingFile)"), existingFile)
    }
    
    func testIsEnabledOnlyForExistingPaths() {
        let action = RevealInFinderAction()
        let currentDir = FileManager.default.currentDirectoryPath
        
        let app = AppIdentity(NSRunningApplication.current)
        let validContext = ActionContext(
            selection: SelectionContext(
                text: currentDir,
                sourceApp: app,
                cursorPosition: .zero,
                selectionBounds: nil,
                timestamp: Date(),
                appPolicy: .default
            ),
            modifiers: []
        )
        
        XCTAssertTrue(action.isEnabled(for: validContext))
        
        let invalidContext = ActionContext(
            selection: SelectionContext(
                text: "Just random text here",
                sourceApp: app,
                cursorPosition: .zero,
                selectionBounds: nil,
                timestamp: Date(),
                appPolicy: .default
            ),
            modifiers: []
        )
        
        XCTAssertFalse(action.isEnabled(for: invalidContext))

        let existingFile = #filePath
        let embeddedValidContext = ActionContext(
            selection: SelectionContext(
                text: "Found error in \(existingFile):10:5",
                sourceApp: app,
                cursorPosition: .zero,
                selectionBounds: nil,
                timestamp: Date(),
                appPolicy: .default
            ),
            modifiers: []
        )
        XCTAssertTrue(action.isEnabled(for: embeddedValidContext))
    }
}
