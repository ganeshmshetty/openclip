import XCTest
@testable import Core

private extension ActionContext {
    init(selectedText: String, bundleID: String? = "com.test.app", appName: String? = "TestApp", match: ActionMatchInfo? = nil) {
        let selection = SelectionContext(
            text: selectedText,
            sourceApp: AppIdentity(bundleIdentifier: bundleID, localizedName: appName),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        self.init(selection: selection, modifiers: [], match: match)
    }
}

private func eval(_ source: String, text: String = "hello@example.com", context: ActionContext? = nil) throws -> Bool {
    let parsed = try XCTUnwrap(try ValidateExpression.parse(source).get())
    let ctx = context ?? ActionContext(selectedText: text)
    return try XCTUnwrap(try parsed.evaluate(ctx, match: nil).get())
}

@MainActor
final class ValidateExpressionTests: XCTestCase {

    // MARK: - Parsing

    func testParseAcceptsValidExpression() {
        XCTAssertNotNil(try? ValidateExpression.parse("isEmail(text) && length(text) >= 5").get())
    }

    func testParseRejectsMalformedExpression() {
        XCTAssertThrowsError(try ValidateExpression.parse("isEmail(text) &&").get())
        XCTAssertThrowsError(try ValidateExpression.parse("(text").get())
        XCTAssertThrowsError(try ValidateExpression.parse("\"unterminated").get())
        XCTAssertThrowsError(try ValidateExpression.parse("length(text").get())
    }

    // MARK: - Semantic predicates

    func testIsEmailEnabledForValidEmail() throws {
        XCTAssertTrue(try eval("isEmail(text)", text: "a@b.com"))
    }

    func testIsEmailDisabledForInvalidEmail() throws {
        XCTAssertFalse(try eval("isEmail(text)", text: "not an email"))
    }

    func testIsURLMatchesHTTPAndWww() throws {
        XCTAssertTrue(try eval("isURL(text)", text: "https://example.com"))
        XCTAssertTrue(try eval("isURL(text)", text: "www.example.com"))
        XCTAssertFalse(try eval("isURL(text)", text: "example.com"))
    }

    // MARK: - Numeric comparisons

    func testLengthGreaterThanEnables() throws {
        XCTAssertTrue(try eval("length(text) > 10", text: "12345678901"))
        XCTAssertFalse(try eval("length(text) > 10", text: "short"))
    }

    func testNumberFunctionComparesNumericSelection() throws {
        XCTAssertTrue(try eval("number(text) >= 100", text: "250"))
        XCTAssertFalse(try eval("number(text) >= 100", text: "42"))
    }

    func testNumberFunctionReturnsNullForNonNumeric() throws {
        XCTAssertTrue(try eval("number(text) == null", text: "abc"))
        XCTAssertFalse(try eval("number(text) == null", text: "12"))
    }

    // MARK: - Composition

    func testAndRequiresBothSides() throws {
        let expr = "isEmail(text) && length(text) >= 8"
        XCTAssertTrue(try eval(expr, text: "hello@example.com"))
        XCTAssertFalse(try eval(expr, text: "a@b.co"))
    }

    func testOrShortCircuits() throws {
        let expr = "isURL(text) || isEmail(text)"
        XCTAssertTrue(try eval(expr, text: "https://example.com"))
        XCTAssertTrue(try eval(expr, text: "a@b.com"))
        XCTAssertFalse(try eval(expr, text: "plain text"))
    }

    func testNotFlipsBoolean() throws {
        XCTAssertTrue(try eval("!isEmail(text)", text: "nope"))
        XCTAssertFalse(try eval("!isEmail(text)", text: "a@b.com"))
    }

    func testParenthesesGroupComparison() throws {
        XCTAssertTrue(try eval("(length(text) >= 5) && isEmail(text)", text: "a@b.co"))
    }

    // MARK: - Context variables

    func testAppVariableEquality() throws {
        let ctx = ActionContext(selectedText: "hello", bundleID: "com.safari")
        XCTAssertTrue(try eval("app == \"com.safari\"", context: ctx))
        XCTAssertFalse(try eval("app == \"com.mail\"", context: ctx))
    }

    func testAppIsEmptyStringWhenBundleNil() throws {
        let ctx = ActionContext(selectedText: "hello", bundleID: nil)
        XCTAssertTrue(try eval("app == \"\"", context: ctx))
    }

    func testHasSelection() throws {
        let empty = ActionContext(selectedText: "   ")
        let nonEmpty = ActionContext(selectedText: "hey")
        XCTAssertFalse(try eval("hasSelection", context: empty))
        XCTAssertTrue(try eval("hasSelection", context: nonEmpty))
    }

    // MARK: - String helpers

    func testStartsWithEndsWithContains() throws {
        XCTAssertTrue(try eval("startsWith(text, \"http\")", text: "https://x.com"))
        XCTAssertTrue(try eval("endsWith(text, \".com\")", text: "https://x.com"))
        XCTAssertTrue(try eval("contains(text, \"example\")", text: "https://example.com"))
        XCTAssertFalse(try eval("contains(text, \"nope\")", text: "https://example.com"))
    }

    func testTrimLowerUpper() throws {
        XCTAssertTrue(try eval("trim(text) == \"a@b.com\"", text: "  a@b.com  "))
        XCTAssertTrue(try eval("lower(text) == \"abc\"", text: "ABC"))
        XCTAssertTrue(try eval("upper(text) == \"ABC\"", text: "abc"))
    }

    func testMatchesFunctionUsesRegexSemantics() throws {
        XCTAssertTrue(try eval("matches(text, \"^[a-z]+@[a-z]+\\\\.com$\")", text: "a@b.com"))
        XCTAssertFalse(try eval("matches(text, \"^[a-z]+@[a-z]+\\\\.com$\")", text: "nope"))
    }

    // MARK: - Captures

    func testLengthOfCapturesArray() throws {
        let match = ActionMatchInfo(text: "a@b.com", matchedText: "a@b.com", captures: ["a", "b.com"], sourceBundleID: "com.test.app")
        let ctx = ActionContext(selectedText: "a@b.com", match: match)
        XCTAssertTrue(try eval("length(captures) == 2", context: ctx))
    }

    func testContainsOnCapturesArray() throws {
        let match = ActionMatchInfo(text: "a@b.com", matchedText: "a@b.com", captures: ["user", "domain.com"], sourceBundleID: "com.test.app")
        let ctx = ActionContext(selectedText: "a@b.com", match: match)
        XCTAssertTrue(try eval("contains(captures, \"user\")", context: ctx))
    }

    // MARK: - Error surfaces

    func testRuntimeTypeErrorReturnsFailure() {
        let expr = try! ValidateExpression.parse("length(text) == \"x\"").get()
        let ctx = ActionContext(selectedText: "hello")
        XCTAssertThrowsError(try expr.evaluate(ctx, match: nil).get()) { error in
            XCTAssertTrue(error is ValidateExpression.EvalError)
        }
    }

    func testUnknownFunctionAndVariableReturnFailures() {
        let ctx = ActionContext(selectedText: "hello")
        XCTAssertThrowsError(try ValidateExpression.parse("frobnicate(text)").get().evaluate(ctx, match: nil).get())
        XCTAssertThrowsError(try ValidateExpression.parse("mysteryvar == \"x\"").get().evaluate(ctx, match: nil).get())
    }

    func testNonBooleanTopLevelReturnsFailure() {
        let ctx = ActionContext(selectedText: "hello")
        XCTAssertThrowsError(try ValidateExpression.parse("length(text)").get().evaluate(ctx, match: nil).get())
    }

    // MARK: - Parse once, eval many

    func testParseOnceEvalManyReusesASTAcrossContexts() throws {
        let expr = try ValidateExpression.parse("isEmail(text) && length(text) >= 8").get()
        XCTAssertTrue(try expr.evaluate(ActionContext(selectedText: "user@example.com"), match: nil).get())
        XCTAssertFalse(try expr.evaluate(ActionContext(selectedText: "x@y.io"), match: nil).get())
        XCTAssertFalse(try expr.evaluate(ActionContext(selectedText: "plain text"), match: nil).get())
    }

    // MARK: - Sendable

    func testASTCrossesActorBoundary() async throws {
        let compiled = try await Task.detached {
            try ValidateExpression.parse("endsWith(text, \".com\")").get()
        }.value
        let ctx = ActionContext(selectedText: "https://example.com")
        XCTAssertTrue(try compiled.evaluate(ctx, match: nil).get())
    }
}
