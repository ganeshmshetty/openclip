// OnboardingWindowControllerTests.swift
// OpenClip
//
// Regression: borderless windows cannot become key by default, which made every
// TextField/SecureField in the onboarding (AI API key step) unusable on first launch.
import XCTest
import SwiftUI
@testable import OpenClip

@MainActor
final class OnboardingWindowControllerTests: XCTestCase {

    func testOnboardingWindowCanBecomeKey() {
        let controller = OnboardingWindowController(onComplete: {})
        XCTAssertTrue(controller.window?.canBecomeKey ?? false,
                      "onboarding text fields need key status to receive typing")
        XCTAssertTrue(controller.window?.canBecomeMain ?? false)
    }

    func testSandboxTextViewHostsSuccessfully() {
        let host = NSHostingController(rootView: SandboxTextView(text: "Test text"))
        _ = host.view
        XCTAssertNotNil(host.view)
    }

    func testOnboardingViewHostsSuccessfully() {
        let host = NSHostingController(rootView: OnboardingView(onComplete: {}))
        _ = host.view
        XCTAssertNotNil(host.view)
    }

    func testOnboardingHasFourSteps() {
        XCTAssertEqual(OnboardingStep.allCases.count, 4)
        XCTAssertEqual(OnboardingStep.allCases.map(\.title),
                       ["Welcome", "Access", "Extensions", "Try It"])
    }

    func testSandboxTextViewCoordinatorInvokesOnSelection() {
        var selectionFired = false
        let textView = NSTextView()
        textView.string = "Hello World"
        textView.setSelectedRange(NSRange(location: 0, length: 5))

        let coordinator = SandboxTextView.Coordinator(onSelection: {
            selectionFired = true
        })

        let notification = Notification(name: NSTextView.didChangeSelectionNotification, object: textView, userInfo: nil)
        coordinator.textViewDidChangeSelection(notification)

        XCTAssertTrue(selectionFired)
    }

    func testSandboxTextViewCoordinatorIgnoresZeroLengthSelection() {
        var selectionFired = false
        let textView = NSTextView()
        textView.string = "Hello World"
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        let coordinator = SandboxTextView.Coordinator(onSelection: {
            selectionFired = true
        })

        let notification = Notification(name: NSTextView.didChangeSelectionNotification, object: textView, userInfo: nil)
        coordinator.textViewDidChangeSelection(notification)

        XCTAssertFalse(selectionFired)
    }
}
