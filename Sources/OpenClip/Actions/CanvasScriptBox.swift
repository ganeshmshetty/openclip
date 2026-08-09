// CanvasScriptBox.swift
// OpenClip
//
// Pure JSContext glue for JavaScript extensions: registers the `h(type, props, children)` helper
// and bridges JS element objects to Core's neutral `CanvasElementSpec` structure.

import Foundation
import JavaScriptCore
import Core

/// Pure JSContext glue: element-object bridging + the h() helper the canvas contract requires.
public enum CanvasScriptBox {
    /// Registers `h(type, props, children)` on the context (returns `{type, props, children}` objects).
    public static func installH(in context: JSContext) {
        let hBlock: @convention(block) (String, Any?, Any?) -> Any = { type, props, children in
            var element: [String: Any] = ["type": type]
            if let props { element["props"] = props }
            if let children { element["children"] = children }
            return element
        }
        context.setObject(hBlock, forKeyedSubscript: "h" as NSString)
    }

    /// Converts a bridged JS element object to the neutral Core spec; nil for a non-object root or invalid type.
    public static func elementSpec(from object: [String: Any]) -> CanvasElementSpec? {
        guard let type = object["type"] as? String else { return nil }
        let props = (object["props"] as? [String: Any] ?? [:]).compactMapValues(Self.jsonValue(from:))
        let rawChildren: [Any]
        if let array = object["children"] as? [Any] {
            rawChildren = array
        } else if let dict = object["children"] as? [String: Any] {
            rawChildren = [dict]
        } else {
            rawChildren = []
        }
        let children = rawChildren.compactMap { child -> CanvasElementSpec? in
            guard let dict = child as? [String: Any] else { return nil }
            return elementSpec(from: dict)
        }
        return CanvasElementSpec(type: type, props: props, children: children)
    }

    /// `[String: Any]`/`[Any]`/`NSNumber`/`String`/`Bool` → `JSONValue` (CFBoolean handled).
    public static func jsonValue(from value: Any) -> JSONValue? {
        switch value {
        case let s as String:
            return .string(s)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return .bool(n.boolValue)
            } else {
                return .number(n.doubleValue)
            }
        case let b as Bool:
            return .bool(b)
        case let arr as [Any]:
            return .array(arr.compactMap(jsonValue(from:)))
        case let dict as [String: Any]:
            return .object(dict.compactMapValues(jsonValue(from:)))
        default:
            return nil
        }
    }
}
