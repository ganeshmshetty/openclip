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
    }
}
