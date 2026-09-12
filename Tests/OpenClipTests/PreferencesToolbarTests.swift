// PreferencesToolbarTests.swift
// OpenClipTests
//
// Pins where the settings window's page switch lives and how big it is. macOS 26 draws a glass
// background behind toolbar items and merges adjacent ones into one capsule, so a switch sitting
// next to the ellipsis shared a pill with it and had a border drawn tight around it. It is a title
// bar accessory now, which sits outside that treatment; and it is parked at its own size, because
// an accessory's view is stretched to the title bar's height and `NSSwitch` draws itself into
// whatever bounds it is given.

import XCTest
import AppKit
@testable import OpenClip

@MainActor
final class PreferencesToolbarTests: XCTestCase {
    private let pageToggleIdentifier = NSToolbarItem.Identifier("openclip.preferences.pageToggle")
    /// Held for the length of the test: the controller owns the subscription that keeps the switch
    /// in step with the model, and the window only retains the accessory's view.
    private var controller: PreferencesToolbarController?

    override func tearDown() {
        controller = nil
        super.tearDown()
    }

    /// The size AppKit gives its own switch at the control size the title bar uses.
    private var systemSwitchSize: NSSize {
        let reference = NSSwitch()
        reference.controlSize = .regular
        reference.sizeToFit()
        return reference.fittingSize
    }

    @discardableResult
    private func makeWindow(
        model: PreferencesToolbarModel = PreferencesToolbarModel()
    ) -> (PreferencesToolbarController, NSWindow, PreferencesToolbarModel) {
        let controller = PreferencesToolbarController(model: model, router: SettingsRouter())
        self.controller = controller
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 640),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.toolbar = controller.makeToolbar()
        controller.window = window
        return (controller, window, model)
    }

    func testThePageSwitchIsNotAToolbarItem() {
        let (controller, window, _) = makeWindow()
        let toolbar = try? XCTUnwrap(window.toolbar)

        XCTAssertNil(
            controller.toolbar(toolbar!, itemForItemIdentifier: pageToggleIdentifier, willBeInsertedIntoToolbar: true),
            "a toolbar item would be drawn on glass, sharing a capsule with the ellipsis next to it"
        )
        XCTAssertFalse(
            controller.toolbarDefaultItemIdentifiers(toolbar!).contains(pageToggleIdentifier),
            "and it must not be in the default set either"
        )
    }

    func testThePageSwitchSitsInATrailingTitlebarAccessory() throws {
        let (_, window, _) = makeWindow()

        let accessory = try XCTUnwrap(window.titlebarAccessoryViewControllers.first,
                                      "the switch rides the title bar, beside the toolbar's items")
        XCTAssertEqual(accessory.layoutAttribute, .right, "trailing edge, right of the ellipsis")
        XCTAssertNotNil(accessory.view.subviews.first as? NSSwitch)
    }

    func testThePageSwitchKeepsItsSizeWhateverHeightTheTitleBarGivesIt() throws {
        let (_, window, _) = makeWindow()
        let host = try XCTUnwrap(window.titlebarAccessoryViewControllers.first).view
        let control = try XCTUnwrap(host.subviews.first as? NSSwitch)
        let expected = systemSwitchSize

        // What the title bar does to an accessory's view.
        host.frame = NSRect(x: 0, y: 0, width: host.frame.width, height: 52)
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(control.frame.width, expected.width, accuracy: 1)
        XCTAssertEqual(control.frame.height, expected.height, accuracy: 1)
        XCTAssertLessThan(control.frame.height, 32, "a title-bar-height switch is the bug this pins")
        XCTAssertEqual(control.frame.midY, host.bounds.midY, accuracy: 1, "centred in the title bar")
    }

    func testThePageSwitchMirrorsTheModelAndGivesBackItsSpaceWhenThereIsNone() throws {
        let (_, window, model) = makeWindow()
        let host = try XCTUnwrap(window.titlebarAccessoryViewControllers.first).view
        let control = try XCTUnwrap(host.subviews.first as? NSSwitch)

        model.pageToggle = SettingsToolbarToggle(isOn: true, label: "Enable JWT")
        XCTAssertEqual(control.state, .on)
        XCTAssertFalse(control.isHidden)
        XCTAssertGreaterThan(host.intrinsicContentSize.width, systemSwitchSize.width,
                             "the switch plus the margins that keep it off the window edge")

        model.pageToggle = SettingsToolbarToggle(isOn: false, label: "Enable JWT")
        XCTAssertEqual(control.state, .off)

        model.pageToggle = nil
        XCTAssertTrue(control.isHidden)
        XCTAssertEqual(host.intrinsicContentSize.width, 0,
                       "a page with no switch must not reserve title bar space")
    }
}
