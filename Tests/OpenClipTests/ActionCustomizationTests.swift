import XCTest
@testable import OpenClip
@testable import Core

private struct CustomizationMockAction: Action {
    let id: String = "mock.test"
    let title: String = "Default Title"
    let icon: ActionIcon = .symbol("star")
    
    func isEnabled(for context: ActionContext) -> Bool { true }
    func perform(_ context: ActionContext) async throws -> ActionResult { .none }
}

private struct MockConfigurableAction: ConfigurableAction {
    let id: String
    let title: String
    let icon: ActionIcon
    let chrome: ActionChrome
    let preferenceIconName: String

    func isEnabled(for context: ActionContext) -> Bool { true }
    func perform(_ context: ActionContext) async throws -> ActionResult { .none }
}

@MainActor
final class ActionCustomizationTests: XCTestCase {
    func testDefaultTitleAndIconFallback() {
        let manager = ActionCustomizationManager(settingsStore: MemorySettingsStore())
        let action = CustomizationMockAction()
        XCTAssertEqual(action.displayTitle(using: manager), "Default Title")
        XCTAssertEqual(action.displayIcon(using: manager), .symbol("star"))
    }
    
    func testCustomTitleAndIconOverrides() {
        let manager = ActionCustomizationManager(settingsStore: MemorySettingsStore())
        let action = CustomizationMockAction()
        
        // Set custom title and custom symbol icon
        manager.setOverride(for: "mock.test", title: "Custom Title", symbol: "heart.fill", text: nil)
        XCTAssertEqual(action.displayTitle(using: manager), "Custom Title")
        XCTAssertEqual(action.displayIcon(using: manager), .symbol("heart.fill"))
        
        // Set custom text/emoji icon
        manager.setOverride(for: "mock.test", title: "Custom Title", symbol: nil, text: "❤️")
        XCTAssertEqual(action.displayTitle(using: manager), "Custom Title")
        XCTAssertEqual(action.displayIcon(using: manager), .text("❤️"))
        
        // Reset override
        manager.resetOverride(for: "mock.test")
        XCTAssertEqual(action.displayTitle(using: manager), "Default Title")
        XCTAssertEqual(action.displayIcon(using: manager), .symbol("star"))
    }

    func testTableIconForConfigurableActions() {
        let manager = ActionCustomizationManager(settingsStore: MemorySettingsStore())

        // Built-in text action uses preferenceIconName symbol
        let builtinTextAction = MockConfigurableAction(
            id: "builtin.copy",
            title: "Copy",
            icon: .text("⌘C"),
            chrome: ActionChrome(source: .builtin),
            preferenceIconName: "doc.on.doc"
        )
        XCTAssertEqual(manager.tableIcon(for: builtinTextAction), .symbol("doc.on.doc"))

        // Extension text action preserves text icon unchanged
        let extensionTextAction = MockConfigurableAction(
            id: "com.example.wordcount",
            title: "Word Count",
            icon: .text("W"),
            chrome: ActionChrome(source: .extensionPkg(packageID: "com.example.wordcount")),
            preferenceIconName: "W"
        )
        XCTAssertEqual(manager.tableIcon(for: extensionTextAction), .text("W"))

        // Symbol icon uses preferenceIconName
        let symbolAction = MockConfigurableAction(
            id: "builtin.calc",
            title: "Calculate",
            icon: .symbol("equal.circle"),
            chrome: ActionChrome(source: .builtin),
            preferenceIconName: "equal.circle"
        )
        XCTAssertEqual(manager.tableIcon(for: symbolAction), .symbol("equal.circle"))

        // Local and URL icons are preserved
        let localURL = URL(fileURLWithPath: "/tmp/icon.png")
        let localAction = MockConfigurableAction(
            id: "com.example.local",
            title: "Local Icon",
            icon: .local(localURL),
            chrome: ActionChrome(source: .extensionPkg(packageID: "com.example.local")),
            preferenceIconName: "icon.png"
        )
        XCTAssertEqual(manager.tableIcon(for: localAction), .local(localURL))

        let webURL = URL(string: "https://example.com/icon.png")!
        let urlAction = MockConfigurableAction(
            id: "com.example.url",
            title: "URL Icon",
            icon: .url(webURL),
            chrome: ActionChrome(source: .extensionPkg(packageID: "com.example.url")),
            preferenceIconName: "https://example.com/icon.png"
        )
        XCTAssertEqual(manager.tableIcon(for: urlAction), .url(webURL))

        // Custom override symbol takes precedence over all
        manager.setOverride(for: "builtin.copy", title: nil, symbol: "sparkles", text: nil)
        XCTAssertEqual(manager.tableIcon(for: builtinTextAction), .symbol("sparkles"))
    }
}
