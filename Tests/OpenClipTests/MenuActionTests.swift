import XCTest
@testable import Core

@MainActor
final class MenuActionTests: XCTestCase {

    private func makeContext(text: String) -> ActionContext {
        let selection = SelectionContext(
            text: text,
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        return ActionContext(selection: selection, modifiers: [])
    }

    // MARK: - MenuDecoratedAction: identity forwarding

    func testDecoratorForwardsIdentity() {
        let chrome = ActionChrome(badge: .extensionPkg("Pkg"), rowStyle: .transformGroup, popupBehavior: .showTransformMenu, source: .extensionPkg(packageID: "com.test.pkg"))
        let base = MockAction(id: "pkg.sub", shouldBeEnabled: true, chrome: chrome)
        let decorated = MenuDecoratedAction(base: base, menuRelevanceRegex: "\\d+", menuPreviewTemplate: "{text}")

        XCTAssertEqual(decorated.id, base.id)
        XCTAssertEqual(decorated.title, base.title)
        XCTAssertEqual(decorated.icon, base.icon)
        XCTAssertEqual(decorated.chrome, base.chrome)
        XCTAssertEqual(decorated.isFormatting, base.isFormatting)
        XCTAssertEqual(decorated.actionOptions.count, base.actionOptions.count)
        XCTAssertEqual(decorated.isEnabled(for: makeContext(text: "x")), true)
    }

    func testDecoratorForwardsPerform() async throws {
        let base = MockAction(id: "pkg.run", shouldBeEnabled: true)
        let decorated = MenuDecoratedAction(base: base, menuPreviewTemplate: "{text}")
        let result = try await decorated.perform(makeContext(text: "hi"))
        guard case .success = result else {
            return XCTFail("perform should delegate to the base action")
        }
        _ = result
    }

    // MARK: - MenuDecoratedAction: relevance

    func testDecoratorAlwaysRelevantWithoutRegex() {
        let decorated = MenuDecoratedAction(base: MockAction(id: "pkg.a", shouldBeEnabled: true))
        XCTAssertTrue(decorated.isRelevant(for: "anything at all"))
        XCTAssertTrue(decorated.isRelevant(for: ""))
    }

    func testDecoratorRelevanceRegexFilters() {
        let decorated = MenuDecoratedAction(base: MockAction(id: "pkg.a", shouldBeEnabled: true), menuRelevanceRegex: "\\b\\d{5,}\\b")
        XCTAssertTrue(decorated.isRelevant(for: "zip 90210 now"))
        XCTAssertFalse(decorated.isRelevant(for: "no digits here"))
        // Empty selection is defensive-relevant (nothing to filter on).
        XCTAssertTrue(decorated.isRelevant(for: ""))
    }

    func testDecoratorMalformedRegexIsRelevant() {
        let decorated = MenuDecoratedAction(base: MockAction(id: "pkg.a", shouldBeEnabled: true), menuRelevanceRegex: "([unclosed")
        XCTAssertTrue(decorated.isRelevant(for: "anything"))
    }

    // MARK: - MenuDecoratedAction: preview

    func testDecoratorPreviewTemplateRendersContext() async {
        let decorated = MenuDecoratedAction(base: MockAction(id: "pkg.a", shouldBeEnabled: true), menuPreviewTemplate: "Copy: {text}")
        let preview = await decorated.previewLine(for: makeContext(text: "hello world"))
        XCTAssertEqual(preview, "Copy: hello world")
    }

    func testDecoratorPreviewNilWithoutTemplate() async {
        let decorated = MenuDecoratedAction(base: MockAction(id: "pkg.a", shouldBeEnabled: true))
        let preview = await decorated.previewLine(for: makeContext(text: "hello"))
        XCTAssertNil(preview)
    }
}
