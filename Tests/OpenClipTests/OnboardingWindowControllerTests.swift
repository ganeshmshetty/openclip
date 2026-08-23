// OnboardingWindowControllerTests.swift
// OpenClip
//
// Regression: borderless windows cannot become key by default, which made every
// TextField/SecureField in the onboarding (AI API key step) unusable on first launch.
import XCTest
@testable import OpenClip

@MainActor
final class OnboardingWindowControllerTests: XCTestCase {

    func testOnboardingWindowCanBecomeKey() {
        let controller = OnboardingWindowController(onComplete: {})
        XCTAssertTrue(controller.window?.canBecomeKey ?? false,
                      "onboarding text fields need key status to receive typing")
        XCTAssertTrue(controller.window?.canBecomeMain ?? false)
    }
}
