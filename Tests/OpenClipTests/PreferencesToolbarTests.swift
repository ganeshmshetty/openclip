// PreferencesToolbarTests.swift
// OpenClipTests
//
// Pins the size of the settings toolbar's custom controls. A toolbar stretches a custom view that
// reports no intrinsic content size, and `NSSwitch` draws itself into whatever bounds it is given —
// which rendered the page switch at roughly twice its size, filling the height of the title bar.

import XCTest
import AppKit
@testable import OpenClip

@MainActor
final class PreferencesToolbarTests: XCTestCase {
    private let pageToggleIdentifier = NSToolbarItem.Identifier("openclip.preferences.pageToggle")

    /// The size AppKit gives its own switch at the control size the toolbar uses.
    private var systemSwitchSize: NSSize {
        let reference = NSSwitch()
        reference.controlSize = .regular
        reference.sizeToFit()
        return reference.fittingSize
    }

    private func makePageToggleItem() throws -> NSToolbarItem {
        let controller = PreferencesToolbarController(model: PreferencesToolbarModel(), router: SettingsRouter())
        let toolbar = controller.makeToolbar()
        return try XCTUnwrap(
            controller.toolbar(toolbar, itemForItemIdentifier: pageToggleIdentifier, willBeInsertedIntoToolbar: true),
            "the toolbar must vend an item for the page switch"
        )
    }

    func testThePageSwitchReportsTheSystemSwitchSize() throws {
        let view = try XCTUnwrap(makePageToggleItem().view)
        let expected = systemSwitchSize

        XCTAssertEqual(view.intrinsicContentSize.width, expected.width, accuracy: 1,
                       "a view with no intrinsic width is stretched across the toolbar")
        XCTAssertEqual(view.intrinsicContentSize.height, expected.height, accuracy: 1)
    }

    func testThePageSwitchKeepsItsSizeWhenTheToolbarStretchesTheItem() throws {
        let view = try XCTUnwrap(makePageToggleItem().view)
        let expected = systemSwitchSize

        // What the toolbar did on the title bar of a wide window.
        view.frame = NSRect(x: 0, y: 0, width: 240, height: 56)
        view.layoutSubtreeIfNeeded()

        let control = try XCTUnwrap(view.subviews.first as? NSSwitch, "the switch is hosted, not handed over bare")
        XCTAssertEqual(control.frame.width, expected.width, accuracy: 1,
                       "the switch must not grow with the space around it")
        XCTAssertEqual(control.frame.height, expected.height, accuracy: 1)
        XCTAssertLessThan(control.frame.height, 32, "a title-bar-height switch is the bug this pins")
    }

    func testThePageSwitchMirrorsTheModel() throws {
        let model = PreferencesToolbarModel()
        let controller = PreferencesToolbarController(model: model, router: SettingsRouter())
        let toolbar = controller.makeToolbar()
        let item = try XCTUnwrap(
            controller.toolbar(toolbar, itemForItemIdentifier: pageToggleIdentifier, willBeInsertedIntoToolbar: true)
        )
        let control = try XCTUnwrap((item.view?.subviews.first) as? NSSwitch)

        model.pageToggle = SettingsToolbarToggle(isOn: true, label: "Enable JWT")
        XCTAssertEqual(control.state, .on)

        model.pageToggle = SettingsToolbarToggle(isOn: false, label: "Enable JWT")
        XCTAssertEqual(control.state, .off)
    }
}
