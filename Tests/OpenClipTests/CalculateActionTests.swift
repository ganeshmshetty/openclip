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
        UserDefaults.standard.removeObject(forKey: "action.calculate.mode")
        let action = CalculateAction()
        let app = AppIdentity(NSRunningApplication.current)
        let context = ActionContext(
            selection: SelectionContext(text: "100 * 2.5", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        
        let result = try await action.perform(context)
        if case .paste(let newText) = result {
            XCTAssertEqual(newText, "250", "Math calculation 100 * 2.5 should equal 250")
        } else {
            XCTFail("Expected paste result for CalculateAction")
        }
    }

    // MARK: - Result Bubble

    @MainActor
    func testResultBubbleFooterOptions() async {
        let action = CalculateAction()
        let app = AppIdentity(NSRunningApplication.current)
        let context = ActionContext(
            selection: SelectionContext(text: "12 * 12", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )

        guard let bubble = await action.makeBubble(for: context) else {
            return XCTFail("Expected a result bubble")
        }
        XCTAssertEqual(bubble.title, "Calculate")
        XCTAssertEqual(bubble.subtitle, "12 * 12 = 144")
        XCTAssertEqual(
            bubble.footer.map(\.title),
            ["Paste 144", "Copy 144", "Copy 12 * 12 = 144"]
        )
    }

    @MainActor
    func testResultBubbleNilForNonMath() async {
        let action = CalculateAction()
        let app = AppIdentity(NSRunningApplication.current)
        let context = ActionContext(
            selection: SelectionContext(text: "Hello World", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )

        let bubble = await action.makeBubble(for: context)
        XCTAssertNil(bubble)
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
        UserDefaults.standard.removeObject(forKey: "action.calculate.mode")
        let action = CalculateAction()
        let app = AppIdentity(NSRunningApplication.current)
        let context = ActionContext(
            selection: SelectionContext(text: "5 % 2", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default),
            modifiers: []
        )
        XCTAssertTrue(action.isEnabled(for: context), "5 % 2 should be calculable")
        let result = try await action.perform(context)
        if case .paste(let newText) = result {
            XCTAssertEqual(newText, "1", "5 % 2 should equal 1")
        } else {
            XCTFail("Expected paste result for modulo expression")
        }
    }

    @MainActor
    func testUnaryMinusAndParenthesesEvaluate() async throws {
        UserDefaults.standard.removeObject(forKey: "action.calculate.mode")
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
            if case .paste(let newText) = result {
                XCTAssertEqual(newText, testCase.expected, "\(testCase.input) should equal \(testCase.expected)")
            } else {
                XCTFail("Expected paste result for \(testCase.input)")
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
            ("(1+2)*3", 9)
        ]
        for testCase in cases {
            guard let value = MathEvaluator.evaluate(testCase.input) else {
                return XCTFail("\(testCase.input) should evaluate")
            }
            XCTAssertEqual(value, testCase.expected, accuracy: 0.0001)
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
