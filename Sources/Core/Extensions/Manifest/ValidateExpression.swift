// ValidateExpression.swift
// OpenClip
//
// Pure-Core expression DSL for computed extension visibility. Tokenizes, parses, and evaluates a
// small bounded expression language (booleans, comparisons, string predicates, numeric helpers)
// without any JavaScript or AppKit. Parse-once-eval-many: DefaultActionFactory compiles the AST
// once at load; ActionVisibility evaluates it synchronously per gate. Bounded by construction
// (depth caps, no loops/assignments), so no timeout/watchdog is ever needed.
import Foundation

public struct ValidateExpression: Sendable, Equatable {
    public let source: String

    public enum ParseError: Error, Equatable, Sendable {
        case unterminatedString
        case unexpectedToken(String)
        case expectedExpression
        case expectedComma
        case expectedParen
        case tooDeep
    }

    public enum EvalError: Error, Equatable, Sendable {
        case arity(name: String, expected: Int, got: Int)
        case typeMismatch(String)
        case unknownFunction(String)
        case unknownVariable(String)
        case tooDeep
    }

    // MARK: - AST

    indirect enum Node: Equatable, Sendable {
        case literal(Value)
        case variable(String)
        case call(String, [Node])
        case not(Node)
        case and(Node, Node)
        case or(Node, Node)
        case equal(Node, Node)
        case notEqual(Node, Node)
        case less(Node, Node)
        case lessEqual(Node, Node)
        case greater(Node, Node)
        case greaterEqual(Node, Node)
    }

    enum Value: Equatable, Sendable {
        case bool(Bool)
        case number(Double)
        case string(String)
        case array([String])
        case null
    }

    private let root: Node
    private static let maxDepth = 200

    private init(source: String, root: Node) {
        self.source = source
        self.root = root
    }

    // MARK: - Public API

    public static func parse(_ source: String) -> Result<ValidateExpression, ParseError> {
        var lexer = Lexer(source: source)
        let tokens: [Token]
        do {
            tokens = try lexer.tokenize()
        } catch let error as ParseError {
            return .failure(error)
        } catch {
            return .failure(.unexpectedToken(String(describing: error)))
        }
        guard !tokens.isEmpty else { return .failure(.expectedExpression) }
        var parser = Parser(tokens: tokens)
        do {
            let node = try parser.parseExpression()
            return .success(ValidateExpression(source: source, root: node))
        } catch let error as ParseError {
            return .failure(error)
        } catch {
            return .failure(.unexpectedToken(String(describing: error)))
        }
    }

    public func evaluate(_ context: ActionContext, match: ActionMatchInfo?) -> Result<Bool, EvalError> {
        let evaluator = Evaluator(context: context, match: match)
        do {
            let value = try evaluator.evaluate(root)
            guard case .bool(let result) = value else {
                return .failure(.typeMismatch("expression must resolve to a boolean"))
            }
            return .success(result)
        } catch let error as EvalError {
            return .failure(error)
        } catch {
            return .failure(.typeMismatch("unexpected evaluation error"))
        }
    }

    // MARK: - Tokenizer

    private enum Token: Equatable {
        case identifier(String)
        case string(String)
        case number(Double)
        case bool(Bool)
        case null
        case not
        case and
        case or
        case equal
        case notEqual
        case less
        case lessEqual
        case greater
        case greaterEqual
        case lparen
        case rparen
        case comma
    }

    private struct Lexer {
        let characters: [Character]
        var index = 0

        init(source: String) {
            self.characters = Array(source)
        }

        mutating func tokenize() throws -> [Token] {
            var tokens: [Token] = []
            while index < characters.count {
                let c = characters[index]
                if c.isWhitespace { index += 1; continue }
                if index + 1 < characters.count, let pair = Lexer.twoCharToken([c, characters[index + 1]]) {
                    tokens.append(pair)
                    index += 2
                    continue
                }
                switch c {
                case "!": tokens.append(.not); index += 1
                case "<": tokens.append(.less); index += 1
                case ">": tokens.append(.greater); index += 1
                case "(": tokens.append(.lparen); index += 1
                case ")": tokens.append(.rparen); index += 1
                case ",": tokens.append(.comma); index += 1
                case "\"": tokens.append(try scanString())
                default:
                    if c.isNumber || c == "." {
                        tokens.append(try scanNumber())
                    } else if c.isLetter || c == "_" {
                        tokens.append(scanIdentifier())
                    } else {
                        throw ParseError.unexpectedToken(String(c))
                    }
                }
            }
            return tokens
        }

        private static func twoCharToken(_ pair: [Character]) -> Token? {
            switch String(pair) {
            case "&&": return .and
            case "||": return .or
            case "==": return .equal
            case "!=": return .notEqual
            case "<=": return .lessEqual
            case ">=": return .greaterEqual
            default: return nil
            }
        }

        private mutating func scanString() throws -> Token {
            index += 1 // opening quote
            var value = ""
            var closed = false
            while index < characters.count {
                let c = characters[index]
                if c == "\\" {
                    index += 1
                    guard index < characters.count else { throw ParseError.unterminatedString }
                    let escaped = characters[index]
                    switch escaped {
                    case "n": value.append("\n")
                    case "t": value.append("\t")
                    case "\"": value.append("\"")
                    case "\\": value.append("\\")
                    default: value.append(escaped)
                    }
                    index += 1
                } else if c == "\"" {
                    closed = true
                    index += 1
                    break
                } else {
                    value.append(c)
                    index += 1
                }
            }
            guard closed else { throw ParseError.unterminatedString }
            return .string(value)
        }

        private mutating func scanNumber() throws -> Token {
            var digits = ""
            while index < characters.count, characters[index].isNumber || characters[index] == "." {
                digits.append(characters[index])
                index += 1
            }
            guard let number = Double(digits) else { throw ParseError.unexpectedToken(digits) }
            return .number(number)
        }

        private mutating func scanIdentifier() -> Token {
            var value = ""
            while index < characters.count {
                let c = characters[index]
                if c.isLetter || c.isNumber || c == "_" {
                    value.append(c)
                    index += 1
                } else {
                    break
                }
            }
            switch value {
            case "true": return .bool(true)
            case "false": return .bool(false)
            case "null": return .null
            default: return .identifier(value)
            }
        }
    }

    // MARK: - Parser

    private struct Parser {
        let tokens: [Token]
        var index = 0

        init(tokens: [Token]) {
            self.tokens = tokens
        }

        private var current: Token { tokens[min(index, tokens.count - 1)] }

        private mutating func advance() -> Token {
            defer { if index < tokens.count { index += 1 } }
            return current
        }

        mutating func parseExpression() throws -> Node {
            let node = try orExpr(depth: 0)
            guard index == tokens.count else { throw ParseError.unexpectedToken("trailing tokens") }
            return node
        }

        private mutating func orExpr(depth: Int) throws -> Node {
            if depth > ValidateExpression.maxDepth { throw ParseError.tooDeep }
            var left = try andExpr(depth: depth + 1)
            while case .or = current {
                _ = advance()
                left = .or(left, try andExpr(depth: depth + 1))
            }
            return left
        }

        private mutating func andExpr(depth: Int) throws -> Node {
            if depth > ValidateExpression.maxDepth { throw ParseError.tooDeep }
            var left = try comparison(depth: depth + 1)
            while case .and = current {
                _ = advance()
                left = .and(left, try comparison(depth: depth + 1))
            }
            return left
        }

        private mutating func comparison(depth: Int) throws -> Node {
            let left = try primary(depth: depth + 1)
            switch current {
            case .equal: _ = advance(); return .equal(left, try primary(depth: depth + 1))
            case .notEqual: _ = advance(); return .notEqual(left, try primary(depth: depth + 1))
            case .less: _ = advance(); return .less(left, try primary(depth: depth + 1))
            case .lessEqual: _ = advance(); return .lessEqual(left, try primary(depth: depth + 1))
            case .greater: _ = advance(); return .greater(left, try primary(depth: depth + 1))
            case .greaterEqual: _ = advance(); return .greaterEqual(left, try primary(depth: depth + 1))
            default: return left
            }
        }

        private mutating func primary(depth: Int) throws -> Node {
            if depth > ValidateExpression.maxDepth { throw ParseError.tooDeep }
            switch current {
            case .not:
                _ = advance()
                return .not(try primary(depth: depth + 1))
            case .number(let n):
                _ = advance()
                return .literal(.number(n))
            case .string(let s):
                _ = advance()
                return .literal(.string(s))
            case .bool(let b):
                _ = advance()
                return .literal(.bool(b))
            case .null:
                _ = advance()
                return .literal(.null)
            case .identifier(let name):
                _ = advance()
                if case .lparen = current {
                    _ = advance()
                    var args: [Node] = []
                    if case .rparen = current {
                        _ = advance()
                    } else {
                        argsLoop: while true {
                            args.append(try primary(depth: depth + 1))
                            switch current {
                            case .comma:
                                _ = advance()
                                continue
                            case .rparen:
                                _ = advance()
                                break argsLoop
                            default:
                                throw ParseError.expectedComma
                            }
                        }
                    }
                    return .call(name, args)
                }
                return .variable(name)
            case .lparen:
                _ = advance()
                let inner = try orExpr(depth: depth + 1)
                guard case .rparen = current else { throw ParseError.expectedParen }
                _ = advance()
                return inner
            default:
                throw ParseError.expectedExpression
            }
        }
    }

    // MARK: - Evaluator

    private struct Evaluator {
        let context: ActionContext
        let match: ActionMatchInfo?

        init(context: ActionContext, match: ActionMatchInfo?) {
            self.context = context
            // The explicit match parameter takes precedence; fall back to the match the
            // context carries (populated by ActionVisibility) when it is nil.
            self.match = match ?? context.match
        }

        func evaluate(_ node: Node, depth: Int = 0) throws -> Value {
            if depth > ValidateExpression.maxDepth { throw EvalError.tooDeep }
            switch node {
            case .literal(let value):
                return value
            case .variable(let name):
                return try variable(name)
            case .call(let name, let args):
                return try call(name, args, depth: depth)
            case .not(let inner):
                let value = try evaluate(inner, depth: depth + 1)
                guard case .bool(let b) = value else { throw EvalError.typeMismatch("'!' requires a boolean") }
                return .bool(!b)
            case .and(let l, let r):
                let lv = try evaluate(l, depth: depth + 1)
                guard case .bool(let lb) = lv else { throw EvalError.typeMismatch("'&&' requires booleans") }
                if !lb { return .bool(false) }
                let rv = try evaluate(r, depth: depth + 1)
                guard case .bool(let rb) = rv else { throw EvalError.typeMismatch("'&&' requires booleans") }
                return .bool(rb)
            case .or(let l, let r):
                let lv = try evaluate(l, depth: depth + 1)
                guard case .bool(let lb) = lv else { throw EvalError.typeMismatch("'||' requires booleans") }
                if lb { return .bool(true) }
                let rv = try evaluate(r, depth: depth + 1)
                guard case .bool(let rb) = rv else { throw EvalError.typeMismatch("'||' requires booleans") }
                return .bool(rb)
            case .equal(let l, let r):
                return .bool(try equality(l, r, depth: depth))
            case .notEqual(let l, let r):
                return .bool(!(try equality(l, r, depth: depth)))
            case .less(let l, let r):
                return .bool(try compare(l, r, depth: depth) == .orderedAscending)
            case .lessEqual(let l, let r):
                return .bool(try compare(l, r, depth: depth) != .orderedDescending)
            case .greater(let l, let r):
                return .bool(try compare(l, r, depth: depth) == .orderedDescending)
            case .greaterEqual(let l, let r):
                return .bool(try compare(l, r, depth: depth) != .orderedAscending)
            }
        }

        private func variable(_ name: String) throws -> Value {
            switch name {
            case "text": return .string(context.selection.text)
            case "matched": return .string(match?.matchedText ?? context.selection.text)
            case "app": return .string(context.selection.sourceApp.bundleIdentifier ?? "")
            case "appName": return .string(context.selection.sourceApp.localizedName ?? "")
            case "hasSelection":
                return .bool(!context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            case "captures": return .array(match?.captures ?? [])
            default: throw EvalError.unknownVariable(name)
            }
        }

        private func call(_ name: String, _ args: [Node], depth: Int) throws -> Value {
            switch name {
            case "length":
                try arity(name, 1, args.count)
                let value = try evaluate(args[0], depth: depth + 1)
                switch value {
                case .string(let s): return .number(Double(s.count))
                case .array(let a): return .number(Double(a.count))
                default: throw EvalError.typeMismatch("length() requires a string or array")
                }
            case "isEmail":
                try arity(name, 1, args.count)
                return .bool(Self.isEmail(try stringArg(name, args[0], depth: depth)))
            case "isURL":
                try arity(name, 1, args.count)
                return .bool(Self.isURL(try stringArg(name, args[0], depth: depth)))
            case "contains":
                try arity(name, 2, args.count)
                let needle = try stringArg(name, args[1], depth: depth)
                let haystack = try evaluate(args[0], depth: depth + 1)
                switch haystack {
                case .string(let s): return .bool(s.range(of: needle) != nil)
                case .array(let a): return .bool(a.contains(needle))
                default: throw EvalError.typeMismatch("contains() requires a string or array")
                }
            case "startsWith":
                try arity(name, 2, args.count)
                let s = try stringArg(name, args[0], depth: depth)
                return .bool(s.hasPrefix(try stringArg(name, args[1], depth: depth)))
            case "endsWith":
                try arity(name, 2, args.count)
                let s = try stringArg(name, args[0], depth: depth)
                return .bool(s.hasSuffix(try stringArg(name, args[1], depth: depth)))
            case "trim":
                try arity(name, 1, args.count)
                return .string(try stringArg(name, args[0], depth: depth).trimmingCharacters(in: .whitespacesAndNewlines))
            case "lower":
                try arity(name, 1, args.count)
                return .string(try stringArg(name, args[0], depth: depth).lowercased())
            case "upper":
                try arity(name, 1, args.count)
                return .string(try stringArg(name, args[0], depth: depth).uppercased())
            case "matches":
                try arity(name, 2, args.count)
                let text = try stringArg(name, args[0], depth: depth)
                let pattern = try stringArg(name, args[1], depth: depth)
                return .bool(Self.regexMatches(pattern: pattern, in: text))
            case "number":
                try arity(name, 1, args.count)
                let raw = try stringArg(name, args[0], depth: depth).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let number = Double(raw) else { return .null }
                return .number(number)
            default:
                throw EvalError.unknownFunction(name)
            }
        }

        private func stringArg(_ fn: String, _ node: Node, depth: Int) throws -> String {
            let value = try evaluate(node, depth: depth + 1)
            guard case .string(let s) = value else { throw EvalError.typeMismatch("\(fn)() requires a string argument") }
            return s
        }

        private func arity(_ fn: String, _ expected: Int, _ got: Int) throws {
            guard got == expected else { throw EvalError.arity(name: fn, expected: expected, got: got) }
        }

        private func equality(_ l: Node, _ r: Node, depth: Int) throws -> Bool {
            let lv = try evaluate(l, depth: depth + 1)
            let rv = try evaluate(r, depth: depth + 1)
            switch (lv, rv) {
            case (.null, .null):
                return true
            case (.null, _), (_, .null):
                // Fail closed: null never equals a non-null value.
                return false
            default:
                switch (lv, rv) {
                case (.bool(let a), .bool(let b)): return a == b
                case (.number(let a), .number(let b)): return a == b
                case (.string(let a), .string(let b)): return a == b
                case (.array(let a), .array(let b)): return a == b
                default:
                    // Cross-type equality is a manifest authoring error, not a runtime value.
                    // Surface it as an EvalError so the gate fails closed and the author sees why.
                    throw EvalError.typeMismatch("== requires operands of the same type")
                }
            }
        }

        /// Returns .orderedSame / .orderedAscending / .orderedDescending. Cross-type or null
        /// operands for ordering comparisons are a type mismatch (EvalError).
        private func compare(_ l: Node, _ r: Node, depth: Int) throws -> ComparisonResult {
            let lv = try evaluate(l, depth: depth + 1)
            let rv = try evaluate(r, depth: depth + 1)
            switch (lv, rv) {
            case (.number(let a), .number(let b)):
                if a == b { return .orderedSame }
                return a < b ? .orderedAscending : .orderedDescending
            case (.string(let a), .string(let b)):
                return (a as NSString).compare(b)
            default:
                throw EvalError.typeMismatch("ordering comparison requires two numbers or two strings")
            }
        }

        // MARK: Predicates

        private static func isEmail(_ string: String) -> Bool {
            isEmailRegex.firstMatch(in: string, options: [], range: NSRange(string.startIndex..., in: string)) != nil
        }

        private static func isURL(_ string: String) -> Bool {
            isURLRegex.firstMatch(in: string, options: [], range: NSRange(string.startIndex..., in: string)) != nil
        }

        private static func regexMatches(pattern: String, in string: String) -> Bool {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
                return false // malformed matches() pattern behaves like "no match"
            }
            let range = NSRange(string.startIndex..., in: string)
            return regex.firstMatch(in: string, options: [], range: range) != nil
        }

        private static let isEmailRegex = try! NSRegularExpression(
            pattern: "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$",
            options: []
        )

        private static let isURLRegex = try! NSRegularExpression(
            pattern: "^(https?|ftp|file)://|^www\\.",
            options: [.caseInsensitive]
        )
    }
}

// MARK: - Descriptions (for Log surfaces)

extension ValidateExpression.ParseError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unterminatedString: return "unterminated string literal"
        case .unexpectedToken(let t): return "unexpected token \"\(t)\""
        case .expectedExpression: return "expected an expression"
        case .expectedComma: return "expected ',' between arguments"
        case .expectedParen: return "expected ')'"
        case .tooDeep: return "expression nesting too deep"
        }
    }
}

extension ValidateExpression.EvalError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .arity(let name, let expected, let got): return "\(name)() expects \(expected) argument(s), got \(got)"
        case .typeMismatch(let message): return "type mismatch: \(message)"
        case .unknownFunction(let name): return "unknown function \"\(name)\""
        case .unknownVariable(let name): return "unknown variable \"\(name)\""
        case .tooDeep: return "evaluation nesting too deep"
        }
    }
}
