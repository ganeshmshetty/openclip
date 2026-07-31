import XCTest
@testable import Core

final class RuleEngineTests: XCTestCase {
    
    func testJSONDecodingWithKebabCase() throws {
        let json = """
        {
            "rules": [
                {
                    "bundleIdentifiers": ["com.test.app"],
                    "deny-formatting": true,
                    "grab-pb": true,
                    "grab-kb": false,
                    "browser-address-bar": true,
                    "assume-paste": true,
                    "lenient-select": false,
                    "deny-probe": true,
                    "deny-preprobe": false
                }
            ]
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        let config = try decoder.decode(RuleEngineConfig.self, from: json)
        
        XCTAssertEqual(config.rules.count, 1)
        let rule = config.rules[0]
        XCTAssertEqual(rule.bundleIdentifiers, ["com.test.app"])
        XCTAssertEqual(rule.denyFormatting, true)
        XCTAssertEqual(rule.grabPasteboard, true)
        XCTAssertEqual(rule.grabKeyboard, false)
        XCTAssertEqual(rule.browserAddressBar, true)
        XCTAssertEqual(rule.assumePaste, true)
        XCTAssertEqual(rule.lenientSelect, false)
        XCTAssertEqual(rule.denyProbe, true)
        XCTAssertEqual(rule.denyPreprobe, false)
    }
    
    @MainActor
    func testWildcardMatchingAndResolvePolicies() async throws {
        let json = """
        {
            "rules": [
                {
                    "bundleIdentifiers": ["com.jetbrains.*"],
                    "deny-formatting": true
                },
                {
                    "bundleIdentifiers": ["*"],
                    "assume-paste": true
                },
                {
                    "bundleIdentifiers": ["com.jetbrainsfoo"],
                    "deny-formatting": false
                },
                {
                    "bundleIdentifiers": [":safari-group:"],
                    "grab-pb": true
                }
            ]
        }
        """.data(using: .utf8)!
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("rules_test.json")
        try json.write(to: tempURL)
        
        await RuleEngine.shared.loadRules(from: tempURL)
        
        // Test wildcard `.*`
        let jetbrainsContext = RuleEngine.shared.resolvePolicies(for: "com.jetbrains.idea")
        XCTAssertEqual(jetbrainsContext.denyFormatting, true)
        XCTAssertEqual(jetbrainsContext.assumePaste, true) // inherits from `*`
        
        let jetbrainsFooContext = RuleEngine.shared.resolvePolicies(for: "com.jetbrainsfoo")
        XCTAssertEqual(jetbrainsFooContext.denyFormatting, false)
        XCTAssertEqual(jetbrainsFooContext.assumePaste, true)
        
        // Test `*`
        let randomContext = RuleEngine.shared.resolvePolicies(for: "com.random.app")
        XCTAssertEqual(randomContext.assumePaste, true)
        XCTAssertEqual(randomContext.denyFormatting, false)
        
        // Test Macro
        let safariContext = RuleEngine.shared.resolvePolicies(for: "com.apple.Safari")
        XCTAssertEqual(safariContext.grabPasteboard, true)
        
        let safariTpContext = RuleEngine.shared.resolvePolicies(for: "com.apple.SafariTechnologyPreview")
        XCTAssertEqual(safariTpContext.grabPasteboard, true)
        
        try FileManager.default.removeItem(at: tempURL)
    }
}
