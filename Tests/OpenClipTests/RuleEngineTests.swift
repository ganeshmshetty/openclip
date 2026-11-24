import XCTest
@testable import Core

final class RuleEngineTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
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
    func testWebsitesDecodeAndResolveGlobally() async throws {
        let json = """
        {
            "rules": [],
            "websites": ["google.com/maps*", "*.youtube.com"]
        }
        """.data(using: .utf8)!
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("rules_website_test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try json.write(to: tempURL)

        await RuleEngine.shared.loadRules(from: tempURL)

        XCTAssertEqual(RuleEngine.shared.websitePatterns, ["google.com/maps*", "*.youtube.com"])
        let context = RuleEngine.shared.resolvePolicies(for: "com.google.Chrome")
        XCTAssertEqual(context.blockedWebsitePatterns, ["google.com/maps*", "*.youtube.com"])
        let otherContext = RuleEngine.shared.resolvePolicies(for: "com.apple.TextEdit")
        XCTAssertEqual(otherContext.blockedWebsitePatterns, ["google.com/maps*", "*.youtube.com"])
    }

    @MainActor
    func testWebsitesAreEmptyByDefaultAndPersist() throws {
        XCTAssertTrue(RuleEngine.shared.websitePatterns.isEmpty)

        let url = tempRulesURL()
        defer { try? FileManager.default.removeItem(at: url) }
        RuleEngine.shared.addWebsite("google.com/maps", saveURL: url)
        RuleEngine.shared.addWebsite("google.com/maps", saveURL: url)   // duplicate ignored
        XCTAssertEqual(RuleEngine.shared.websitePatterns, ["google.com/maps"])

        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["websites"] as? [String], ["google.com/maps"])

        RuleEngine.shared.removeWebsite("google.com/maps", saveURL: url)
        XCTAssertTrue(RuleEngine.shared.websitePatterns.isEmpty)
    }

    @MainActor
    func testEnablingAPageRemovesEveryMatchingPattern() throws {
        let url = tempRulesURL()
        defer { try? FileManager.default.removeItem(at: url) }
        RuleEngine.shared.addWebsite("google.com", saveURL: url)
        RuleEngine.shared.addWebsite("google.com/maps", saveURL: url)
        RuleEngine.shared.addWebsite("youtube.com", saveURL: url)

        RuleEngine.shared.removeWebsites(matching: URL(string: "https://www.google.com/maps/@1")!, saveURL: url)

        XCTAssertEqual(RuleEngine.shared.websitePatterns, ["youtube.com"])
    }

    private func tempRulesURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("rules_website_\(UUID().uuidString).json")
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
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("rules_test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }
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
        let menuCopyContext = RuleEngine.shared.resolvePolicies(for: "com.apple.Terminal")
        XCTAssertEqual(menuCopyContext.denyPaste, true)
    }

    @MainActor
    func testMenuCopyAppsMacroResolvesUseMenuCopy() async throws {
        let vsCodeContext = RuleEngine.shared.resolvePolicies(for: "com.microsoft.VSCode")
        XCTAssertEqual(vsCodeContext.retrievalMode, .keyboardCopy, "VS Code should resolve keyboard-copy retrieval mode")
        XCTAssertFalse(vsCodeContext.useMenuCopy, "VS Code should not use menu copy")
        
        let zedContext = RuleEngine.shared.resolvePolicies(for: "dev.zed.Zed")
        XCTAssertEqual(zedContext.retrievalMode, .keyboardCopy, "Zed should resolve keyboard-copy retrieval mode")
        
        let alacrittyContext = RuleEngine.shared.resolvePolicies(for: "org.alacritty")
        XCTAssertEqual(alacrittyContext.retrievalMode, .menuCopy, "Alacritty should resolve menu-copy retrieval mode")
        
        let randomContext = RuleEngine.shared.resolvePolicies(for: "com.random.app")
        XCTAssertEqual(randomContext.retrievalMode, .axTextControl, "Random app should stay on the default retrieval mode")
        XCTAssertFalse(randomContext.useMenuCopy, "Random app should resolve useMenuCopy policy to false")
    }

    @MainActor
    func testLegacyUseMenuCopyResolvesToMenuCopyMode() async throws {
        let json = """
        {
            "rules": [
                {
                    "bundle-identifiers": ["com.legacy.app"],
                    "use-menu-copy": true
                }
            ]
        }
        """.data(using: .utf8)!
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("rules_legacy_test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try json.write(to: tempURL)
        
        await RuleEngine.shared.loadRules(from: tempURL)
        
        let context = RuleEngine.shared.resolvePolicies(for: "com.legacy.app")
        XCTAssertTrue(context.useMenuCopy)
        XCTAssertEqual(context.retrievalMode, .menuCopy, "Legacy use-menu-copy: true should alias to .menuCopy")
    }

    @MainActor
    func testExplicitRetrievalModeSuppressesLegacyMenuCopyAlias() async throws {
        let json = """
        {
            "rules": [
                {
                    "bundle-identifiers": ["com.legacy.explicit"],
                    "use-menu-copy": true,
                    "retrieval-mode": "ax-text-control"
                }
            ]
        }
        """.data(using: .utf8)!

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("rules_legacy_explicit_test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try json.write(to: tempURL)

        await RuleEngine.shared.loadRules(from: tempURL)

        let context = RuleEngine.shared.resolvePolicies(for: "com.legacy.explicit")
        XCTAssertTrue(context.useMenuCopy)
        XCTAssertEqual(context.retrievalMode, .axTextControl, "explicit ax-text-control must opt out of the legacy menu-copy alias")
    }

    @MainActor
    func testRetrievalModeJSONDecodesAndResolves() async throws {
        let json = """
        {
            "rules": [
                {
                    "bundle-identifiers": ["com.test.browser"],
                    "retrieval-mode": "browser-script"
                }
            ]
        }
        """.data(using: .utf8)!
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("rules_retrieval_mode_test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try json.write(to: tempURL)
        
        await RuleEngine.shared.loadRules(from: tempURL)
        
        let context = RuleEngine.shared.resolvePolicies(for: "com.test.browser")
        XCTAssertEqual(context.retrievalMode, .browserScript, "retrieval-mode: browser-script should resolve for a matching bundle")
    }

    @MainActor
    func testBrowserScriptModeResolvesForBrowserGroups() async throws {
        let safariContext = RuleEngine.shared.resolvePolicies(for: "com.apple.Safari")
        XCTAssertEqual(safariContext.retrievalMode, .axWebArea)
        
        let firefoxContext = RuleEngine.shared.resolvePolicies(for: "org.mozilla.firefox")
        XCTAssertEqual(firefoxContext.retrievalMode, .axWebArea)
        
        let arcContext = RuleEngine.shared.resolvePolicies(for: "company.thebrowser.Browser")
        XCTAssertEqual(arcContext.retrievalMode, .axWebArea)
    }

    @MainActor
    func testKeyboardCopyModeResolvesForCodeEditorApps() async throws {
        let vsCodeContext = RuleEngine.shared.resolvePolicies(for: "com.microsoft.VSCode")
        XCTAssertEqual(vsCodeContext.retrievalMode, .keyboardCopy)
        XCTAssertFalse(vsCodeContext.denyPaste)
    }

    @MainActor
    func testDenyPasteModeResolvesForTerminalAndGhostty() async throws {
        let terminalContext = RuleEngine.shared.resolvePolicies(for: "com.apple.Terminal")
        XCTAssertTrue(terminalContext.denyPaste)
        XCTAssertEqual(terminalContext.retrievalMode, .keyboardCopy)

        let itermContext = RuleEngine.shared.resolvePolicies(for: "com.googlecode.iterm2")
        XCTAssertTrue(itermContext.denyPaste)
        XCTAssertEqual(itermContext.retrievalMode, .keyboardCopy)

        let ghosttyContext = RuleEngine.shared.resolvePolicies(for: "com.mitchellh.ghostty")
        XCTAssertTrue(ghosttyContext.denyPaste)
        XCTAssertEqual(ghosttyContext.retrievalMode, .menuCopy)
    }

    @MainActor
    func testGateResolvesDefaultAndLenient() async throws {
        let json = """
        {
            "rules": [
                {
                    "bundle-identifiers": ["com.lenient.app"],
                    "gate": {
                        "skipRoles": [],
                        "allowedCursors": ["beam", "arrow", "pointingHand", "unknown"]
                    }
                }
            ]
        }
        """.data(using: .utf8)!
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("rules_gate_test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try json.write(to: tempURL)
        
        await RuleEngine.shared.loadRules(from: tempURL)
        
        let lenientContext = RuleEngine.shared.resolvePolicies(for: "com.lenient.app")
        XCTAssertEqual(lenientContext.gate, .lenient, "Explicit lenient gate should resolve for a matching bundle")
        
        let defaultContext = RuleEngine.shared.resolvePolicies(for: "com.random.app")
        XCTAssertEqual(defaultContext.gate, .default, "Apps with no gate rule keep the default gate")
    }

    @MainActor
    func testDisabledAndHotkeyOnlyJSONDecodingAndResolution() async throws {
        let json = """
        {
            "rules": [
                {
                    "bundle-identifiers": ["com.disabled.app"],
                    "disabled": true
                },
                {
                    "bundle-identifiers": ["com.hotkeyonly.app"],
                    "hotkey-only": true
                }
            ]
        }
        """.data(using: .utf8)!
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("rules_disabled_hotkey_test_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try json.write(to: tempURL)
        
        await RuleEngine.shared.loadRules(from: tempURL)
        
        let disabledContext = RuleEngine.shared.resolvePolicies(for: "com.disabled.app")
        XCTAssertTrue(disabledContext.disabled)
        XCTAssertFalse(disabledContext.hotkeyOnly)
        
        let hotkeyContext = RuleEngine.shared.resolvePolicies(for: "com.hotkeyonly.app")
        XCTAssertFalse(hotkeyContext.disabled)
        XCTAssertTrue(hotkeyContext.hotkeyOnly)
        
        let randomContext = RuleEngine.shared.resolvePolicies(for: "com.random.app")
        XCTAssertFalse(randomContext.disabled)
        XCTAssertFalse(randomContext.hotkeyOnly)
    }

    @MainActor
    func testVMsRemotesAndCanvasAppsAreDisabledByDefault() {
        let blocked = [
            "com.utmapp.UTM",
            "com.parallels.desktop.console",
            "com.vmware.fusion",
            "org.virtualbox.app.VirtualBox",
            "com.microsoft.rdc.macos",
            "com.citrix.Workspace",
            "com.teamviewer.TeamViewer",
            "com.anydesk.AnyDesk",
            "com.jumpdesktop.JumpDesktop",
            "com.apple.iphonesimulator",
            "com.adobe.Photoshop"
        ]
        for bundleID in blocked {
            XCTAssertTrue(RuleEngine.shared.resolvePolicies(for: bundleID).disabled, bundleID)
        }
        XCTAssertFalse(RuleEngine.shared.resolvePolicies(for: "com.apple.TextEdit").disabled)
    }

    @MainActor
    func testUserRuleReEnablesADefaultBlockedApp() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rules_re_enable_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        RuleEngine.shared.addOrUpdateRule(
            AppRule(bundleIdentifiers: ["com.utmapp.UTM"], disabled: false),
            saveURL: tempURL
        )

        XCTAssertFalse(RuleEngine.shared.resolvePolicies(for: "com.utmapp.UTM").disabled)
    }

    @MainActor
    func testPagesUsesKeyboardCopyForItsAXOpaqueTextEngine() {
        XCTAssertEqual(
            RuleEngine.shared.resolvePolicies(for: "com.apple.iWork.Pages").retrievalMode,
            .keyboardCopy
        )
    }

    func testAppFilterKeepsOnlyNeverTargetIdentities() {
        XCTAssertTrue(AppFilter.isExcluded(bundleID: "com.openclip.app"))
        XCTAssertFalse(AppFilter.isExcluded(bundleID: "com.utmapp.UTM"))
        XCTAssertFalse(AppFilter.isExcluded(bundleID: "com.parallels.desktop.console"))
        XCTAssertFalse(AppFilter.isExcluded(bundleID: "com.adobe.Photoshop"))
    }
}
