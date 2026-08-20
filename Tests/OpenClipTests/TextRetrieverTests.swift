import XCTest
import AppKit
@testable import OpenClip
@testable import Core

final class TextRetrieverTests: XCTestCase {
    private static func makeTarget(selectedText: String? = nil, role: String = "AXTextField") -> AXElementInspector.Target {
        AXElementInspector.Target(
            focusedApp: nil,
            focusedElement: nil,
            role: role,
            subRole: nil,
            parentRoles: [],
            containedInRoles: [],
            webArea: nil,
            selectedText: selectedText,
            selectedTextMarkerRange: nil,
            value: nil,
            selectedTextRange: nil,
            bounds: nil
        )
    }

    @MainActor
    func testTextRetrieverRetrievesSelectedText() async throws {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.makeTarget(selectedText: nil) },
            browserRead: { _ in nil },
            copyCapture: { _ in nil }
        )
        let retriever = MacTextRetriever(coordinator: coordinator)
        let currentApp = AppIdentity(bundleIdentifier: "com.test.app", localizedName: "TestApp")

        let text = await retriever.retrieveText(for: currentApp, policy: AppPolicyContext.default)

        XCTAssertNil(text, "Retriever should return nil when there is no selection")
    }

    @MainActor
    func testTextRetrieverSurfacesFoundText() async throws {
        let coordinator = SelectionRetrievalCoordinator(
            inspect: { Self.makeTarget(selectedText: "Sample Selection") },
            browserRead: { _ in nil },
            copyCapture: { _ in nil }
        )
        let retriever = MacTextRetriever(coordinator: coordinator)
        let currentApp = AppIdentity(bundleIdentifier: "com.test.app", localizedName: "TestApp")

        let text = await retriever.retrieveText(for: currentApp, policy: AppPolicyContext.default)

        XCTAssertEqual(text, "Sample Selection")
    }

    func testTextResultInitialization() {
        let bounds = CGRect(x: 10, y: 20, width: 100, height: 50)
        let result = TextResult(text: "Hello World", bounds: bounds)
        XCTAssertEqual(result.text, "Hello World")
        XCTAssertEqual(result.bounds, bounds)
    }
}
