import XCTest
@testable import Core

final class ExtensionRiskProfileTests: XCTestCase {
    private func manifest(json: String) throws -> ExtensionMetadata {
        try JSONDecoder().decode(ExtensionMetadata.self, from: Data(json.utf8))
    }

    func testShellPackageRunsCode() throws {
        let m = try manifest(json: """
        {"identifier":"com.t.shell","name":"Shell","actions":[
            {"title":"Run","type":"shell","scriptCode":"echo hi"}]}
        """)
        let profile = ExtensionRiskProfile(manifest: m)
        XCTAssertTrue(profile.runsCode)
        XCTAssertFalse(profile.scriptNetwork)
        XCTAssertFalse(profile.urlOnly)
    }

    func testAsyncJSPackageGetsScriptNetwork() throws {
        let m = try manifest(json: """
        {"identifier":"com.t.js","name":"JS","actions":[
            {"title":"Fetch","type":"js","scriptCode":"return 1","async":true}]}
        """)
        let profile = ExtensionRiskProfile(manifest: m)
        XCTAssertTrue(profile.runsCode)
        XCTAssertTrue(profile.scriptNetwork)
        XCTAssertFalse(profile.urlOnly)
    }

    func testURLOnlyPackage() throws {
        let m = try manifest(json: """
        {"identifier":"com.t.url","name":"URL","actions":[
            {"title":"Go","type":"url","url":"https://x.com/{query}"},
            {"title":"Snippet","type":"textsnippet","scriptCode":"{text}"}]}
        """)
        let profile = ExtensionRiskProfile(manifest: m)
        XCTAssertTrue(profile.opensURLs)
        XCTAssertTrue(profile.urlOnly)
        XCTAssertFalse(profile.runsCode)
    }

    func testKeyPressAndShortcutAreKeyboard() throws {
        let m = try manifest(json: """
        {"identifier":"com.t.keys","name":"Keys","actions":[
            {"title":"Press","type":"keypress","keyPress":"command+c"},
            {"title":"Shortcut","type":"shortcut","shortcutName":"Trim"}]}
        """)
        let profile = ExtensionRiskProfile(manifest: m)
        XCTAssertTrue(profile.keyboard)
        XCTAssertFalse(profile.urlOnly)
    }

    func testAppleScriptIsAppAutomation() throws {
        let m = try manifest(json: """
        {"identifier":"com.t.as","name":"AS","actions":[
            {"title":"Drive","type":"applescript","scriptCode":"tell application \\"Music\\""}]}
        """)
        let profile = ExtensionRiskProfile(manifest: m)
        XCTAssertTrue(profile.runsCode)
        XCTAssertTrue(profile.appAutomation)
    }

    func testGroupFlattensIntoParentRisk() throws {
        let m = try manifest(json: """
        {"identifier":"com.t.grp","name":"Grp","actions":[{"title":"G","type":"group","subActions":[
            {"id":"a","title":"A","type":"shell","scriptCode":"echo hi"},
            {"id":"b","title":"B","type":"websearch","url":"https://x.com/{query}"}]}]}
        """)
        let profile = ExtensionRiskProfile(manifest: m)
        XCTAssertTrue(profile.runsCode)
        XCTAssertTrue(profile.opensURLs)
        XCTAssertFalse(profile.urlOnly)
    }
}