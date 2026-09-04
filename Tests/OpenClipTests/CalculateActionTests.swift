import XCTest
import AppKit
@testable import OpenClip
@testable import Core

final class CalculateActionTests: XCTestCase {
    @MainActor
    func testCalculateActionEnabledForMath() async throws {
        let action = CalculateAction()
        let app = AppIdentity(NSRunningApplication.current)
        
        let validMathContext = ActionContext(
            selection: SelectionContext(text: "12 + 4.5", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertTrue(action.isEnabled(for: validMathContext), "CalculateAction should be enabled for math expressions")
        
        let plainTextContext = ActionContext(
            selection: SelectionContext(text: "Hello World", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertFalse(action.isEnabled(for: plainTextContext), "CalculateAction should be disabled for non-math text")
    }
    
    @MainActor
    func testCalculateActionExecution() async throws {
        let action = CalculateAction()
        let app = AppIdentity(NSRunningApplication.current)
        let context = ActionContext(
            selection: SelectionContext(text: "100 * 2.5", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        
        let result = try await action.perform(context)
        if case .text(let newText) = result {
            XCTAssertEqual(newText, "250", "Math calculation 100 * 2.5 should equal 250")
        } else {
            XCTFail("Expected text result for CalculateAction")
        }
    }

    // MARK: - Malformed Input Regression (crash fix)

    /// Previously, "12 + 4.5" worked but a bare operator or malformed expression crashed the app:
    /// NSExpression(format:) throws an uncaught Objective-C exception. These must all be treated as
    /// "not calculable" (disabled, no crash) rather than trapping.
    @MainActor
    func testMalformedExpressionsAreDisabledAndDoNotCrash() {
        let action = CalculateAction()
        let app = AppIdentity(NSRunningApplication.current)
        for bad in ["+", "-", "*", "/", "%", "1+", "(1+", "1+2)", "2..5", "1 1", "(", "1+*2", "1 % 0", "5/0"] {
            let context = ActionContext(
                selection: SelectionContext(text: bad, sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
                modifiers: []
            )
            XCTAssertFalse(action.isEnabled(for: context),
                           "\(bad) must be treated as not calculable (and must not crash)")
        }
    }

    @MainActor
    func testModuloExpressionEvaluates() async throws {
        let action = CalculateAction()
        let app = AppIdentity(NSRunningApplication.current)
        let context = ActionContext(
            selection: SelectionContext(text: "5 % 2", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertTrue(action.isEnabled(for: context), "5 % 2 should be calculable")
        let result = try await action.perform(context)
        if case .text(let newText) = result {
            XCTAssertEqual(newText, "1", "5 % 2 should equal 1")
        } else {
            XCTFail("Expected text result for modulo expression")
        }
    }

    @MainActor
    func testUnaryMinusAndParenthesesEvaluate() async throws {
        let action = CalculateAction()
        let app = AppIdentity(NSRunningApplication.current)
        let cases: [(input: String, expected: String)] = [
            ("-5", "-5"),
            ("(-5)", "-5"),
            ("1-(-2)", "3"),
            ("(1+2)*3", "9")
        ]
        for testCase in cases {
            let context = ActionContext(
                selection: SelectionContext(text: testCase.input, sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
                modifiers: []
            )
            XCTAssertTrue(action.isEnabled(for: context), "\(testCase.input) should be calculable")
            let result = try await action.perform(context)
            if case .text(let newText) = result {
                XCTAssertEqual(newText, testCase.expected, "\(testCase.input) should equal \(testCase.expected)")
            } else {
                XCTFail("Expected text result for \(testCase.input)")
            }
        }
    }

    @MainActor
    func testExtendedMathExpressionsAndSanitization() async throws {
        let action = CalculateAction()
        let app = AppIdentity(NSRunningApplication.current)
        let cases: [(input: String, expected: String)] = [
            ("10 × 5", "50"),
            ("100 ÷ 4", "25"),
            ("100 – 20", "80"), // En-dash (smart dash)
            ("100 — 20", "80"), // Em-dash
            ("100 − 20", "80"), // Unicode minus
            ("5 + 5 =", "10"),
            ("12 * 4 = ", "48"),
            ("25 + 15 = ?", "40"),
            ("$50 + $20", "70"),
            ("€100 - €20", "80"),
            ("£15 * 3", "45"),
            ("¥500 + ¥200", "700"),
            ("2^8", "256"),
            ("10^3", "1000"),
            ("5 x 10", "50"),
            ("100 * 20%", "20"),
            ("1,000 * 2.5", "2500"),
            ("2.5 * 1,000", "2500"),
            ("1,000 + 2,5", "1002.5"),
            ("1.250,50 + 50", "1300.5"),
            ("12,5 + 3,5", "16")
        ]
        for testCase in cases {
            let context = ActionContext(
                selection: SelectionContext(text: testCase.input, sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
                modifiers: []
            )
            XCTAssertTrue(action.isEnabled(for: context), "\(testCase.input) should be calculable")
            let result = try await action.perform(context)
            if case .text(let newText) = result {
                XCTAssertEqual(newText, testCase.expected, "\(testCase.input) should equal \(testCase.expected)")
            } else {
                XCTFail("Expected text result for \(testCase.input)")
            }
        }
    }

    // MARK: - MathEvaluator (deterministic parser, replaces crash-prone NSExpression)

    func testMathEvaluatorBasicArithmetic() {
        let cases: [(input: String, expected: Double)] = [
            ("12 + 4.5", 16.5),
            ("100 * 2.5", 250),
            ("1 + 2 - 3 * 4 / 2", -3),
            ("5 % 2", 1),
            ("100 * 20%", 20),
            ("2^8", 256),
            ("2**3", 8),
            (".5 + 0.5", 1)
        ]
        for testCase in cases {
            guard let value = MathEvaluator.evaluate(testCase.input) else {
                return XCTFail("\(testCase.input) should evaluate")
            }
            XCTAssertEqual(value, testCase.expected, accuracy: 0.0001)
        }
    }

    func testMathEvaluatorUnaryAndParens() {
        let cases: [(input: String, expected: Double)] = [
            ("-5", -5),
            ("(-5)", -5),
            ("1-(-2)", 3),
            ("(1+2)*3", 9),
            ("(-2)^3", -8)
        ]
        for testCase in cases {
            guard let value = MathEvaluator.evaluate(testCase.input) else {
                return XCTFail("\(testCase.input) should evaluate")
            }
            XCTAssertEqual(value, testCase.expected, accuracy: 0.0001)
        }
    }

    /// '^' is right-associative and unary minus binds looser than '^':
    /// 2^3^2 = 2^(3^2) = 512, and -2^2 = -(2^2) = -4.
    func testMathEvaluatorPowerPrecedenceAndAssociativity() {
        let cases: [(input: String, expected: Double)] = [
            ("2^3^2", 512),
            ("2**3**2", 512),
            ("-2^2", -4),
            ("-2**2", -4),
            ("(-2)^2", 4),
            ("2^-2", 0.25),
            ("-2^-2", -0.25),
            ("4^0.5", 2),
            ("2*3^2", 18),
            ("-3^2 + 1", -8)
        ]
        for testCase in cases {
            guard let value = MathEvaluator.evaluate(testCase.input) else {
                return XCTFail("\(testCase.input) should evaluate")
            }
            XCTAssertEqual(value, testCase.expected, accuracy: 0.0001, "\(testCase.input)")
        }
    }

    func testMathEvaluatorRejectsMalformed() {
        XCTAssertNil(MathEvaluator.evaluate("+"))
        XCTAssertNil(MathEvaluator.evaluate("-"))
        XCTAssertNil(MathEvaluator.evaluate("1+"))
        XCTAssertNil(MathEvaluator.evaluate("1+*2"))
        XCTAssertNil(MathEvaluator.evaluate("()"))
        XCTAssertNil(MathEvaluator.evaluate("("))
        XCTAssertNil(MathEvaluator.evaluate("1+2)"))
        XCTAssertNil(MathEvaluator.evaluate("2..5"))
        XCTAssertNil(MathEvaluator.evaluate("1 1"))
        XCTAssertNil(MathEvaluator.evaluate("1/0"))
        XCTAssertNil(MathEvaluator.evaluate("5 % 0"))
        XCTAssertNil(MathEvaluator.evaluate(""))
        XCTAssertNil(MathEvaluator.evaluate("hello"))
    }
}
