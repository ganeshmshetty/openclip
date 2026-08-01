import XCTest
@testable import Core

final class CustomActionManagerTests: XCTestCase {
    private struct MockApp: AppIdentifying {
        let bundleIdentifier: String?
        let localizedName: String?
    }
    
    var tempDirectory: URL!
    var originalActions: [any Action]!
    
    @MainActor
    override func setUp() async throws {
        // Setup code if needed
    }
    
    @MainActor
    override func tearDown() async throws {
        CustomActionManager.shared.delete(customActionID: "test_web")
        CustomActionManager.shared.delete(customActionID: "test_snippet")
        CustomActionManager.shared.delete(customActionID: "test_shell")
    }

    @MainActor
    func testEncodingAndPersistence() throws {
        let action = CustomAction(
            id: "test_web",
            title: "Test Web Search",
            iconName: "magnifyingglass",
            type: .webSearch(urlTemplate: "https://example.com/?q={text}")
        )
        
        CustomActionManager.shared.register(customAction: action)
        XCTAssertTrue(CustomActionManager.shared.customActions.contains(where: { $0.id == "test_web" }))
        
        CustomActionManager.shared.load()
        XCTAssertTrue(CustomActionManager.shared.customActions.contains(where: { $0.id == "test_web" }))
        
        CustomActionManager.shared.delete(customActionID: "test_web")
        XCTAssertFalse(CustomActionManager.shared.customActions.contains(where: { $0.id == "test_web" }))
    }

    @MainActor
    func testTextSnippetExecution() async throws {
        let action = CustomAction(
            id: "test_snippet",
            title: "Snippet",
            iconName: "doc.text",
            type: .textSnippet(template: "Hello {text}!")
        )
        
        let context = ActionContext(selection: SelectionContext(text: "World", sourceApp: MockApp(bundleIdentifier: "com.test", localizedName: "test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default))
        XCTAssertTrue(action.isEnabled(for: context))
        
        let result = try await action.perform(context)
        if case .paste(let string) = result {
            XCTAssertEqual(string, "Hello World!")
        } else {
            XCTFail("Expected .paste result")
        }
    }
    
    @MainActor
    func testShellScriptExecution() async throws {
        let action = CustomAction(
            id: "test_shell",
            title: "Shell",
            iconName: "terminal",
            type: .shellScript(script: "echo -n \"$OPENCLIP_TEXT received\"", replaceSelection: false)
        )
        
        let context = ActionContext(selection: SelectionContext(text: "Data", sourceApp: MockApp(bundleIdentifier: "com.test", localizedName: "test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default))
        let result = try await action.perform(context)
        
        if case .copy(let string) = result {
            XCTAssertEqual(string, "Data received")
        } else {
            XCTFail("Expected .copy result")
        }
    }
}
