import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class ActionPresentationTests: XCTestCase {
    var presentation: ActionPresentation!
    var settingsStore: DefaultSettingsStore!

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults(suiteName: #file)!
        defaults.removePersistentDomain(forName: #file)
        settingsStore = DefaultSettingsStore(userDefaults: defaults)
        let customizationManager = ActionCustomizationManager(settingsStore: settingsStore)
        presentation = ActionPresentation(customizationManager: customizationManager)
    }

    func testDefaultPresentationForCopyAction() {
        let copyAction = CopyAction()
        let popupModel = presentation.presented(copyAction, surface: .popup)
        let tableModel = presentation.presented(copyAction, surface: .table)

        XCTAssertEqual(popupModel.title, "Copy")
        XCTAssertEqual(popupModel.icon, .symbol("doc.on.doc"))
        XCTAssertEqual(tableModel.icon, .symbol("doc.on.doc"))
    }

    func testPresentationWithOverride() {
        let copyAction = CopyAction()
        presentation.setOverride(for: copyAction.id, title: "Duplicate", symbol: "plus.square", text: "CP")
        
        let popupModel = presentation.presented(copyAction, surface: .popup)
        XCTAssertEqual(popupModel.title, "Duplicate")
        XCTAssertEqual(popupModel.icon, .text("CP"))

        let tableModel = presentation.presented(copyAction, surface: .table)
        XCTAssertEqual(tableModel.title, "Duplicate")
        XCTAssertEqual(tableModel.icon, .symbol("plus.square"))
    }
}

