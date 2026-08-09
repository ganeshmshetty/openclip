// CanvasEffectDeliveryTests.swift
// OpenClipTests
//
// Unit test suite for deliverKeyboardEffect ordering, effect routing doors,
// and KeyboardEventPosting injection seams.

import XCTest
import AppKit
import Core
@testable import OpenClip

@MainActor
private final class RecordingActionResultHandler: ActionResultHandler, @unchecked Sendable {
    private(set) var handledResults: [ActionResult] = []
    private(set) var handledWithoutDismissalResults: [ActionResult] = []

    func handle(_ result: ActionResult, in view: NSView?) async throws {
        handledResults.append(result)
    }

    func handleWithoutDismissal(_ result: ActionResult, in view: NSView?) async {
        handledWithoutDismissalResults.append(result)
    }
}

@MainActor
private final class RecordingKeyboardPoster: KeyboardEventPosting, @unchecked Sendable {
    struct KeyRecord: Equatable {
        let keyCode: CGKeyCode
        let flags: CGEventFlags
    }

    private(set) var postedKeys: [KeyRecord] = []

    func postKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        postedKeys.append(KeyRecord(keyCode: keyCode, flags: flags))
    }
}

@MainActor
final class CanvasEffectDeliveryTests: XCTestCase {

    private func shownController(with resultHandler: ActionResultHandler) throws -> PopupWindowController {
        guard let screen = NSScreen.main else { throw XCTSkip("no screen available") }
        let controller = PopupWindowController(resultHandler: resultHandler)
        let context = SelectionContext(
            text: "hello world",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 200),
            timestamp: Date(),
            appPolicy: .default
        )
        controller.show(for: context)
        return controller
    }

    private func pump(_ duration: TimeInterval = 0.3) {
        RunLoop.current.run(until: Date().addingTimeInterval(duration))
    }

    func testKeyboardEffectResignsActivatesPostsRestores() throws {
        let recordingHandler = RecordingActionResultHandler()
        let controller = try shownController(with: recordingHandler)
        defer { controller.hide() }

        let tree = Canvas.build {
            Canvas.button("Paste", id: "b1", handler: .effect(.paste("hello")))
        }
        controller.armCanvasForTesting(tree: tree, header: CanvasHeader(title: "Delivery Test"))
        pump()

        let originalOnEffects = controller.canvasSessionController.onEffects
        let expectation = expectation(description: "keyboard effect handling")
        controller.canvasSessionController.onEffects = { effects in
            originalOnEffects?(effects)
            expectation.fulfill()
        }

        controller.canvasSessionController.onEffects?([.paste("hello")])
        wait(for: [expectation], timeout: 2.0)
        pump(0.5)

        let handledPaste = recordingHandler.handledResults.contains(where: { actionResult in
            if case .paste(let val) = actionResult.effectForHandler {
                return val == "hello"
            }
            return false
        })

        XCTAssertTrue(handledPaste, "keyboard paste effect must route through resultHandler.handle")
        XCTAssertEqual(controller.modeStore.mode, .content, "keyboard effect delivery must restore panel to content mode")
    }

    func testNonKeyboardEffectDoesNotResign() throws {
        let recordingHandler = RecordingActionResultHandler()
        let controller = try shownController(with: recordingHandler)
        defer { controller.hide() }

        let tree = Canvas.build {
            Canvas.text("Copy Test")
        }
        controller.armCanvasForTesting(tree: tree, header: CanvasHeader(title: "Copy Test"))
        pump()

        let originalOnEffects = controller.canvasSessionController.onEffects
        controller.canvasSessionController.onEffects = { effects in
            originalOnEffects?(effects)
        }

        controller.canvasSessionController.onEffects?([.copy("copy text")])
        pump(0.5)

        let handledCopy = recordingHandler.handledWithoutDismissalResults.contains(where: { actionResult in
            if case .copy(let val) = actionResult.effectForHandler {
                return val == "copy text"
            }
            return false
        })

        XCTAssertTrue(handledCopy, "non-keyboard copy effect must route through resultHandler.handleWithoutDismissal")
        XCTAssertEqual(controller.modeStore.mode, .content, "non-keyboard effect delivery must keep panel in content mode without resigning")
    }

    func testKeyboardEffectWithNoKeyPanelSkipsResign() throws {
        let recordingHandler = RecordingActionResultHandler()
        let controller = try shownController(with: recordingHandler)
        defer { controller.hide() }

        XCTAssertFalse(controller.modeStore.mode == .content)

        let originalOnEffects = controller.canvasSessionController.onEffects
        controller.canvasSessionController.onEffects = { effects in
            originalOnEffects?(effects)
        }

        controller.canvasSessionController.onEffects?([.keyPress(KeyPressSpec(key: "c", modifiers: [.command]))])
        pump(0.5)

        let handledKeyPress = recordingHandler.handledResults.contains(where: { actionResult in
            if case .keyPress = actionResult.effectForHandler {
                return true
            }
            return false
        })

        XCTAssertTrue(handledKeyPress, "keyPress effect with non-key panel must still execute effect")
    }

    func testDefaultActionResultHandlerUsesKeyboardPoster() throws {
        let poster = RecordingKeyboardPoster()
        let defaultHandler = DefaultActionResultHandler(keyboardPoster: poster)
        let controller = try shownController(with: defaultHandler)
        defer { controller.hide() }

        let tree = Canvas.build {
            Canvas.text("Poster Test")
        }
        controller.armCanvasForTesting(tree: tree, header: CanvasHeader(title: "Poster Test"))
        pump()

        let originalOnEffects = controller.canvasSessionController.onEffects
        controller.canvasSessionController.onEffects = { effects in
            originalOnEffects?(effects)
        }

        controller.canvasSessionController.onEffects?([.paste("pasted text")])
        pump(0.5)

        XCTAssertFalse(poster.postedKeys.isEmpty, "DefaultActionResultHandler paste must post key via injected KeyboardEventPosting seam")
        XCTAssertEqual(poster.postedKeys.first?.keyCode, Constants.vVirtualKey, "paste must post Cmd+V (vVirtualKey)")
    }
}
