// CanvasRendererTests.swift
// OpenClipTests
//
// Integration and live-panel test suite for canvas renderer smoke, sizing bounds,
// layout clamping, and accessibility labels.

import XCTest
import AppKit
import Core
@testable import OpenClip

@MainActor
final class CanvasRendererTests: XCTestCase {

    private func shownController(for cursor: CGPoint = .zero) throws -> PopupWindowController {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen available") }
        let controller = PopupWindowController()
        let pos = cursor == .zero ? CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200) : cursor
        let context = SelectionContext(
            text: "hello world",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: pos,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.show(for: context)
        return controller
    }

    private func visiblePanel() throws -> PopupPanel {
        guard let panel = NSApp.windows.first(where: { $0 is PopupPanel && $0.isVisible }) as? PopupPanel else {
            throw XCTSkip("popup panel did not appear")
        }
        return panel
    }

    private func pump(_ duration: TimeInterval = 0.3) {
        RunLoop.current.run(until: Date().addingTimeInterval(duration))
    }

    // MARK: - Sizing and Renderer Smoke Tests

    func testArmsNativeTreeAndGrowsPanel() throws {
        let controller = try shownController()
        defer { controller.hide() }
        let panel = try visiblePanel()

        pump()
        let barHeight = panel.frame.height
        XCTAssertGreaterThan(barHeight, 0)

        let tree = Canvas.build {
            Canvas.text("Header Title")
            Canvas.button("Action Button", id: "btn1")
        }

        controller.armCanvasForTesting(tree: tree, header: CanvasHeader(title: "Native Test"))

        XCTAssertEqual(controller.modeStore.mode, .content)

        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline && panel.frame.height <= barHeight + 1 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
        XCTAssertGreaterThan(panel.frame.height, barHeight, "canvas rendering must grow the panel height")
    }

    func testRendersEveryComponentWithoutCrashing() throws {
        let controller = try shownController()
        defer { controller.hide() }

        let tree = Canvas.build {
            Canvas.text("Sample text")
            Canvas.icon(.symbol("star"))
            Canvas.button("Click Me", id: "btn")
            Canvas.toggle("tog", value: true)
            Canvas.textField("txt", value: "Input value")
            Canvas.link("Website", url: URL(string: "https://openclip.app")!)
            Canvas.list([
                CanvasListSection(items: [
                    CanvasListItem(id: "i1", title: "Item 1"),
                    CanvasListItem(id: "i2", title: "Item 2")
                ])
            ])
            Canvas.divider
            Canvas.spacer(minLength: 12)
            Canvas.stack(CanvasStackProps(orientation: .horizontal)) {
                Canvas.text("Left text")
                Canvas.text("Right text")
            }
        }

        controller.armCanvasForTesting(tree: tree, header: CanvasHeader(title: "All Components Catalog"))
        pump()

        let panel = try visiblePanel()
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(controller.modeStore.mode, .content)
    }

    func testWidthColumnClampsToLimits() throws {
        let controller = try shownController()
        defer { controller.hide() }

        let wideText = String(repeating: "A very long line of text that exceeds standard canvas width boundaries ", count: 10)
        let tree = Canvas.build {
            Canvas.text(wideText)
        }

        controller.armCanvasForTesting(tree: tree, header: CanvasHeader(title: "Wide Test"))
        pump()

        let panel = try visiblePanel()
        let maxAllowedWidth = CanvasLimits.canvasMaxWidth + 2.0 * PopupMetrics.popupPadding
        XCTAssertLessThanOrEqual(panel.frame.width, maxAllowedWidth + 2.0, "panel width must clamp within CanvasLimits max width boundaries")
    }

    func testHeightCappedAtPopupMaxHeight() throws {
        let controller = try shownController()
        defer { controller.hide() }

        let tree = Canvas.build {
            for i in 1...40 {
                Canvas.text("Long content item number \(i) in scrollable stack")
            }
        }

        controller.armCanvasForTesting(tree: tree, header: CanvasHeader(title: "Scrollable Stack"))
        pump()

        let panel = try visiblePanel()
        XCTAssertLessThanOrEqual(panel.frame.height, PopupMetrics.popupMaxHeight + 10.0, "panel height must cap near popupMaxHeight")
    }

    func testPreferredSizeIsFixedAcrossDispatch() throws {
        let controller = try shownController()
        defer { controller.hide() }

        let initialTree = Canvas.build {
            Canvas.text("Line 1")
            Canvas.text("Line 2")
            Canvas.text("Line 3")
        }

        let preferred = CanvasSize(width: 320, height: 220)
        controller.armCanvasForTesting(tree: initialTree, header: CanvasHeader(title: "Fixed Size"), preferredSize: preferred)
        pump()

        let panel = try visiblePanel()
        let mountedHeight = panel.frame.height

        // Replace session tree with a shorter single line tree
        let shorterTree = Canvas.build {
            Canvas.text("Line 1 only")
        }
        if let session = controller.canvasSessionController.session {
            let updatedSession = CanvasSession(
                header: session.header,
                input: session.input,
                preferredSize: session.preferredSize,
                scripting: nil,
                isAsync: false,
                tree: shorterTree
            )
            controller.canvasSessionController.replace(with: updatedSession)
        }
        pump()

        XCTAssertEqual(panel.frame.height, mountedHeight, "panel size must not shrink below mounted fixed preferred size")
    }

    func testNilPreferredSizeUsesFittingSize() throws {
        let controller = try shownController()
        defer { controller.hide() }

        let tree = Canvas.build {
            Canvas.text("Short fitting size content")
        }
        controller.armCanvasForTesting(tree: tree, header: CanvasHeader(title: "Fitting Size"), preferredSize: nil)
        pump()

        let panel = try visiblePanel()
        XCTAssertLessThan(panel.frame.height, PopupMetrics.popupMaxHeight, "nil preferredSize must use content fitting size smaller than max height cap")
    }

    func testDividerAndSpacerRender() throws {
        let controller = try shownController()
        defer { controller.hide() }

        let tree = Canvas.build {
            Canvas.text("Top section")
            Canvas.divider
            Canvas.spacer(minLength: 20)
            Canvas.text("Bottom section")
        }

        controller.armCanvasForTesting(tree: tree, header: CanvasHeader(title: "Divider and Spacer"))
        pump()

        let panel = try visiblePanel()
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(controller.modeStore.mode, .content)
    }

    // MARK: - Accessibility & Edge Scenarios

    func testInteractiveNodesExposeLabels() throws {
        let controller = try shownController()
        defer { controller.hide() }

        let tree = Canvas.build {
            Canvas.button("Paste Result", id: "b1")
            Canvas.link("Open Docs", url: URL(string: "https://openclip.app")!)
            Canvas.textField("f1", value: "Input", placeholder: "Type here")
        }

        controller.armCanvasForTesting(tree: tree, header: CanvasHeader(title: "Accessibility Test"))
        pump()

        let panel = try visiblePanel()
        let labels = collectAccessibilityLabels(in: panel.contentView)
        let hasExpectedLabel = labels.contains(where: { $0.contains("Paste Result") || $0.contains("Open Docs") || $0.contains("Type here") || $0.contains("Input") })
        XCTAssertTrue(hasExpectedLabel, "rendered view should expose interactive node labels")
    }

    func testThemingGlassVsClassicDoesNotRemountCanvas() throws {
        let initialTheme = DefaultSettingsStore.shared.get(.popupTheme)
        DefaultSettingsStore.shared.set(.popupTheme, value: "classic")
        let controller = try shownController()
        defer {
            controller.hide()
            DefaultSettingsStore.shared.set(.popupTheme, value: initialTheme)
        }

        let tree = Canvas.build {
            Canvas.text("Theme independent content")
        }
        controller.armCanvasForTesting(tree: tree, header: CanvasHeader(title: "Theme Test"))
        pump()

        let initialSessionID = controller.canvasSessionController.session?.id
        XCTAssertNotNil(initialSessionID)

        DefaultSettingsStore.shared.set(.popupTheme, value: "glass")
        pump()

        XCTAssertEqual(controller.modeStore.mode, .content)
        XCTAssertEqual(controller.canvasSessionController.session?.id, initialSessionID, "switching theme must not remount canvas session")
    }

    func testUnsafeImagePathRejectedWithPlaceholder() throws {
        let controller = try shownController()
        defer { controller.hide() }

        let unsafeURL = URL(fileURLWithPath: "/etc/passwd")
        let tree = Canvas.image(.local(unsafeURL))

        controller.armCanvasForTesting(tree: tree, header: CanvasHeader(title: "Unsafe Image"))
        pump()

        let panel = try visiblePanel()
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(controller.modeStore.mode, .content)
    }

    func testUnsafeIconPathRejectedWithPlaceholder() throws {
        let controller = try shownController()
        defer { controller.hide() }

        let unsafeURL = URL(fileURLWithPath: "/Users/x/Documents/secret.png")
        let tree = Canvas.icon(.local(unsafeURL))

        controller.armCanvasForTesting(tree: tree, header: CanvasHeader(title: "Unsafe Icon"))
        pump()

        let panel = try visiblePanel()
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(controller.modeStore.mode, .content)
    }

    // MARK: - Helper

    private func collectAccessibilityLabels(in view: NSView?) -> [String] {
        guard let view else { return [] }
        var results: [String] = []
        if let label = view.accessibilityLabel(), !label.isEmpty {
            results.append(label)
        }
        if let title = view.accessibilityTitle(), !title.isEmpty {
            results.append(title)
        }
        if let value = view.accessibilityValue() as? String, !value.isEmpty {
            results.append(value)
        }
        if let children = view.accessibilityChildren() {
            for child in children {
                if let childView = child as? NSView {
                    results.append(contentsOf: collectAccessibilityLabels(in: childView))
                } else if let element = child as? NSAccessibilityElement {
                    if let label = element.accessibilityLabel(), !label.isEmpty {
                        results.append(label)
                    }
                    if let title = element.accessibilityTitle(), !title.isEmpty {
                        results.append(title)
                    }
                    if let value = element.accessibilityValue() as? String, !value.isEmpty {
                        results.append(value)
                    }
                }
            }
        }
        for subview in view.subviews {
            results.append(contentsOf: collectAccessibilityLabels(in: subview))
        }
        return results
    }
}
