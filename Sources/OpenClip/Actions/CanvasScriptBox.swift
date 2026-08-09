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

    /// Registers the `openclip` bridge object and side-effect functions on the context.
    public static func installCanvasBridge(
        in context: JSContext,
        input: String,
        optionValues: [String: JSONValue],
        effectsBox: CanvasEffectsBox,
        keepVisibleBox: CanvasKeepVisibleBox
    ) {
        let openclip: JSValue
        if let existing = context.objectForKeyedSubscript("openclip"), !existing.isUndefined, !existing.isNull, existing.isObject {
            openclip = existing
        } else {
            openclip = JSValue(newObjectIn: context)!
        }

        // Input object
        let inputObj = JSValue(newObjectIn: context)!
        inputObj.setObject(input, forKeyedSubscript: "text" as NSString)
        inputObj.setObject(input, forKeyedSubscript: "matchedText" as NSString)
        openclip.setObject(inputObj, forKeyedSubscript: "input" as NSString)

        // Options
        var optionsDict: [String: Any] = [:]
        for (key, val) in optionValues {
            optionsDict[key] = jsonValueToRawObject(val)
        }
        openclip.setObject(optionsDict, forKeyedSubscript: "options" as NSString)

        // Effects
        let copyBlock: @convention(block) (String) -> Void = { text in
            effectsBox.value.append(.copy(text))
        }
        let pasteBlock: @convention(block) (String) -> Void = { text in
            effectsBox.value.append(.paste(text))
        }
        let cutBlock: @convention(block) (String) -> Void = { text in
            effectsBox.value.append(.cut(text))
        }
        let simulatePasteBlock: @convention(block) () -> Void = {
            effectsBox.value.append(.simulatePaste)
        }
        let openURLBlock: @convention(block) (String) -> Void = { urlString in
            if let url = URL(string: urlString) {
                effectsBox.value.append(.openURL(url))
            }
        }
        let keyPressBlock: @convention(block) (String, NSArray?) -> Void = { key, modifiers in
            let mods = mapModifiers(modifiers)
            effectsBox.value.append(.keyPress(KeyPressSpec(key: key, modifiers: mods)))
        }
        let runShortcutBlock: @convention(block) (String, String?) -> Void = { name, inputOverride in
            effectsBox.value.append(.runShortcut(name: name, input: inputOverride ?? input))
        }
        let showServicesBlock: @convention(block) (String) -> Void = { text in
            effectsBox.value.append(.showServices(text))
        }
        let notifyBlock: @convention(block) (String, String) -> Void = { title, body in
            effectsBox.value.append(.notify(title: title, body: body))
        }
        let keepVisibleBlock: @convention(block) () -> Void = {
            keepVisibleBox.value = true
        }

        openclip.setObject(copyBlock, forKeyedSubscript: "copy" as NSString)
        openclip.setObject(pasteBlock, forKeyedSubscript: "paste" as NSString)
        openclip.setObject(cutBlock, forKeyedSubscript: "cut" as NSString)
        openclip.setObject(simulatePasteBlock, forKeyedSubscript: "simulatePaste" as NSString)
        openclip.setObject(openURLBlock, forKeyedSubscript: "openURL" as NSString)
        openclip.setObject(keyPressBlock, forKeyedSubscript: "keyPress" as NSString)
        openclip.setObject(runShortcutBlock, forKeyedSubscript: "runShortcut" as NSString)
        openclip.setObject(showServicesBlock, forKeyedSubscript: "showServices" as NSString)
        openclip.setObject(notifyBlock, forKeyedSubscript: "notify" as NSString)
        openclip.setObject(keepVisibleBlock, forKeyedSubscript: "keepVisible" as NSString)

        context.setObject(openclip, forKeyedSubscript: "openclip" as NSString)
        context.evaluateScript("openclip.option = function(id) { return openclip.options[id]; };")
    }

    public static func jsonValueToRawObject(_ json: JSONValue) -> Any {
        switch json {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let arr): return arr.map(jsonValueToRawObject)
        case .object(let dict): return dict.mapValues(jsonValueToRawObject)
        }
    }

    private static func mapModifiers(_ modifiers: NSArray?) -> [KeyPressSpec.KeyModifier] {
        guard let modifiers else { return [] }
        return modifiers.compactMap { element in
            guard let raw = element as? String else { return nil }
            switch raw.lowercased() {
            case "command": return .command
            case "shift": return .shift
            case "option": return .option
            case "control": return .control
            default: return nil
            }
        }
    }
}

public final class CanvasEffectsBox: @unchecked Sendable {
    public var value: [CanvasEffect] = []
    public init() {}
}

public final class CanvasKeepVisibleBox: @unchecked Sendable {
    public var value: Bool = false
    public init() {}
}
