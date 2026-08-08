// CanvasElementSpec.swift
// OpenClip
//
// The neutral, Codable element-object form of a canvas node (spec §5.1 / §5.4): the JS engine
// converts a JSValue from `h(type, props, children)` into this shape via JSONSerialization, and
// Core's CanvasElementParser decodes it into a CanvasComponent — keeping the parser
// JavaScriptCore-free. `props` uses JSONValue so numbers/strings/bools/arrays/objects round-trip.
import Foundation

public struct CanvasElementSpec: Codable, Sendable, Equatable {
    public var type: String
    public var props: [String: JSONValue]
    public var children: [CanvasElementSpec]

    public init(type: String, props: [String: JSONValue] = [:], children: [CanvasElementSpec] = []) {
        self.type = type
        self.props = props
        self.children = children
    }
}
