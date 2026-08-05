// MathEvaluator.swift
// OpenClip
//
// Deterministic, exception-free evaluator for simple arithmetic expressions used by
// CalculateAction. Replaces NSExpression(format:), which throws an uncaught Objective-C
// exception on malformed input (bare operators, unbalanced parens, invalid numbers) and crashes
// the app. Returns nil for anything that isn't well-formed; never traps.
import Foundation

enum MathEvaluator {
    static func evaluate(_ input: String) -> Double? {
        var tokens = tokenize(input)
        guard !tokens.isEmpty else { return nil }
        var pos = 0
        guard let value = parseExpression(tokens: &tokens, pos: &pos) else { return nil }
        return pos == tokens.count ? value : nil
    }

    // MARK: - Tokens

    private enum Token {
        case number(Double)
        case plus, minus, times, divide, mod
        case leftParen, rightParen
    }

    /// Splits an already-validated arithmetic string into tokens. Returns an empty array for any
    /// character outside the number/operator/paren alphabet, so callers treat it as "not calculable".
    private static func tokenize(_ input: String) -> [Token] {
        let chars = Array(input)
        var result: [Token] = []
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == " " {
                i += 1
                continue
            }
            // A number starts with a digit, or a dot directly followed by a digit (e.g. ".5").
            if c.isNumber || (c == "." && i + 1 < chars.count && chars[i + 1].isNumber) {
                var j = i
                var sawDot = false
                while j < chars.count {
                    let ch = chars[j]
                    if ch.isNumber {
                        j += 1
                    } else if ch == ".", !sawDot {
                        sawDot = true
                        j += 1
                    } else {
                        break
                    }
                }
                guard let value = Double(String(chars[i..<j])) else { return [] }
                result.append(.number(value))
                i = j
                continue
            }
            switch c {
            case "+": result.append(.plus)
            case "-": result.append(.minus)
            case "*": result.append(.times)
            case "/": result.append(.divide)
            case "%": result.append(.mod)
            case "(": result.append(.leftParen)
            case ")": result.append(.rightParen)
            default: return []
            }
            i += 1
        }
        return result
    }

    // MARK: - Recursive descent:  expr := term (('+'|'-') term)*
    //                               term := factor (('*'|'/'|'%') factor)*
    //                             factor := ('-'|'+') factor | number | '(' expr ')'

    private static func parseExpression(tokens: inout [Token], pos: inout Int) -> Double? {
        guard let term = parseTerm(tokens: &tokens, pos: &pos) else { return nil }
        var value = term
        while pos < tokens.count {
            switch tokens[pos] {
            case .plus:
                pos += 1
                guard let rhs = parseTerm(tokens: &tokens, pos: &pos) else { return nil }
                value += rhs
            case .minus:
                pos += 1
                guard let rhs = parseTerm(tokens: &tokens, pos: &pos) else { return nil }
                value -= rhs
            default:
                return value
            }
        }
        return value
    }

    private static func parseTerm(tokens: inout [Token], pos: inout Int) -> Double? {
        guard let factor = parseFactor(tokens: &tokens, pos: &pos) else { return nil }
        var value = factor
        while pos < tokens.count {
            switch tokens[pos] {
            case .times:
                pos += 1
                guard let rhs = parseFactor(tokens: &tokens, pos: &pos) else { return nil }
                value *= rhs
            case .divide:
                pos += 1
                guard let rhs = parseFactor(tokens: &tokens, pos: &pos) else { return nil }
                guard rhs != 0 else { return nil }
                value /= rhs
            case .mod:
                pos += 1
                guard let rhs = parseFactor(tokens: &tokens, pos: &pos) else { return nil }
                guard rhs != 0 else { return nil }
                value = value.truncatingRemainder(dividingBy: rhs)
            default:
                return value
            }
        }
        return value
    }

    private static func parseFactor(tokens: inout [Token], pos: inout Int) -> Double? {
        guard pos < tokens.count else { return nil }
        switch tokens[pos] {
        case .minus:
            pos += 1
            guard let operand = parseFactor(tokens: &tokens, pos: &pos) else { return nil }
            return -operand
        case .plus:
            pos += 1
            return parseFactor(tokens: &tokens, pos: &pos)
        case .number(let number):
            pos += 1
            return number
        case .leftParen:
            pos += 1
            guard let inner = parseExpression(tokens: &tokens, pos: &pos) else { return nil }
            guard pos < tokens.count, case .rightParen = tokens[pos] else { return nil }
            pos += 1
            return inner
        case .rightParen, .times, .divide, .mod:
            return nil
        }
    }
}
