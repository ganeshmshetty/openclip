// CanvasSessionState.swift
// OpenClip
//
// The app-owned, JSON-serializable session state for a canvas session (spec §4.2): a dictionary of
// JSONValue keyed by the stable textField/toggle ids. Values are injected into each JS evaluation
// and written back after a dispatch — state is never JS-heap-resident between events, which keeps
// the engine fresh-context while the canvas feels stateful. Also carries the Core value type
// CanvasHeader (chrome title/icon supplied by the running action); CanvasSize lives in
// CanvasComponent.swift (defined there alongside CanvasImageProps, which references it). Pure Core —
// no AppKit/SwiftUI.
import Foundation

/// A JSON-serializable scalar/collection value used by CanvasSessionState and CanvasElementSpec.
public enum JSONValue: Sendable, Equatable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid JSONValue payload"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// App-owned session state: a JSON-serializable dictionary keyed by stable component ids (spec §4.2).
public struct CanvasSessionState: Sendable, Equatable, Codable {
    public var values: [String: JSONValue]

    public init(_ values: [String: JSONValue] = [:]) {
        self.values = values
    }

    public subscript(_ key: String) -> JSONValue? {
        get { values[key] }
        set { values[key] = newValue }
    }

    public func string(_ key: String) -> String? {
        values[key]?.stringValue
    }

    public func bool(_ key: String) -> Bool? {
        values[key]?.boolValue
    }
}

/// Chrome header (title + optional icon) for the canvas, supplied by the running action (spec §7).
/// The tree carries no root title; producers cannot override the header.
public struct CanvasHeader: Sendable, Equatable {
    public var title: String
    public var icon: String?

    public init(title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }
}
