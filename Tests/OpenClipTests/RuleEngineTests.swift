import XCTest
@testable import Core

final class RuleEngineTests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        TestIsolation.reset()
    }
    
    func testJSONDecodingWithKebabCase() throws {
        let json = """
        {
            "rules": [
                {
                    "bundle-identifiers": ["com.test.app"],
                    "use-menu-copy": true,
                    "deny-paste": true
                }
            ]
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let config = try decoder.decode(RuleEngineConfig.self, from: json)
        
        XCTAssertEqual(config.rules.count, 1)
        let rule = config.rules[0]
        XCTAssertEqual(rule.bundleIdentifiers, ["com.test.app"])
        XCTAssertEqual(rule.useMenuCopy, true)
        XCTAssertEqual(rule.denyPaste, true)
    }
    
    @MainActor
    func testWildcardMatchingAndResolvePolicies() async throws {
        let json = """
        {
            "rules": [
                {
                    "bundle-identifiers": ["com.jetbrains.*"],
                    "deny-paste": true
                },
                {
                    "bundle-identifiers": ["*"],
                    "use-menu-copy": true
                },
                {
                    "bundle-identifiers": ["com.jetbrainsfoo"],
                    "deny-paste": false
                },
                {
                    "bundle-identifiers": [":menu-copy-apps:"],
                    "deny-paste": true
                }
            ]
        }
        """.data(using: .utf8)!
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("rules_test.json")
        try json.write(to: tempURL)
        
        await RuleEngine.shared.loadRules(from: tempURL)
        
        // Test wildcard `.*`
        let jetbrainsContext = RuleEngine.shared.resolvePolicies(for: "com.jetbrains.idea")
        XCTAssertEqual(jetbrainsContext.denyPaste, true)
        XCTAssertEqual(jetbrainsContext.useMenuCopy, true) // inherits from `*`
        
        let jetbrainsFooContext = RuleEngine.shared.resolvePolicies(for: "com.jetbrainsfoo")
        XCTAssertEqual(jetbrainsFooContext.denyPaste, false)
        XCTAssertEqual(jetbrainsFooContext.useMenuCopy, true)
        
        // Test `*`
        let randomContext = RuleEngine.shared.resolvePolicies(for: "com.random.app")
        XCTAssertEqual(randomContext.useMenuCopy, true)
        XCTAssertEqual(randomContext.denyPaste, false)
        
        // Test macro
        let menuCopyContext = RuleEngine.shared.resolvePolicies(for: "com.microsoft.VSCode")
        XCTAssertEqual(menuCopyContext.denyPaste, true)
        
        try FileManager.default.removeItem(at: tempURL)
    }

    @MainActor
    func testMenuCopyAppsMacroResolvesUseMenuCopy() async throws {
        let vsCodeContext = RuleEngine.shared.resolvePolicies(for: "com.microsoft.VSCode")
        XCTAssertTrue(vsCodeContext.useMenuCopy, "VS Code should resolve useMenuCopy policy to true")
        
        let zedContext = RuleEngine.shared.resolvePolicies(for: "dev.zed.Zed")
        XCTAssertTrue(zedContext.useMenuCopy, "Zed should resolve useMenuCopy policy to true")
        
        let randomContext = RuleEngine.shared.resolvePolicies(for: "com.random.app")
        XCTAssertFalse(randomContext.useMenuCopy, "Random app should resolve useMenuCopy policy to false")
    }
}
