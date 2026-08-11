// CanvasScriptBox.swift
// OpenClip
//
// Pure JSContext glue for JavaScript extensions: registers the `h(type, props, children)` helper,
// bridges JS element objects to Core's neutral `CanvasElementSpec` structure, and installs the
// `openclip` canvas bridge (read-only input context: text/matchedText/captures/app + resolved
// options; effects, keepVisible, showContent(tree, {size}), showStatus) into a per-evaluation
// `CanvasBridgeCollector`.

import Foundation
import JavaScriptCore
import Core

/// Pure JSContext glue: element-object bridging + the h() helper the canvas contract requires.
public enum CanvasScriptBox {
    /// Registers `h(type, props, ...children)` on the context (returns `{type, props, children}` objects).
    /// Child arrays are flattened recursively and `null`/`undefined` children are omitted, so mixed
    /// static and mapped children produce one flat child list. A single surviving child is unwrapped
    /// (preserving the bare-string child that `elementSpec` maps to `content` for `text`).
    public static func installH(in context: JSContext) {
        context.evaluateScript("""
        function h(type, props) {
            var args = Array.prototype.slice.call(arguments, 2);
            var flat = [];
            function collect(list) {
                for (var i = 0; i < list.length; i++) {
                    var v = list[i];
                    if (Array.isArray(v)) {
                        collect(v);
                    } else if (v !== null && v !== undefined) {
                        flat.push(v);
                    }
                }
            }
            collect(args);
            var children;
            if (flat.length === 0) {
                children = [];
            } else if (flat.length === 1) {
                children = flat[0];
            } else {
                children = flat;
            }
            return {
                type: type,
                props: props || {},
                children: children
            };
        }
        """)
    }

    /// Converts a bridged JS element object to the neutral Core spec; nil for a non-object root or invalid type.
    public static func elementSpec(from object: [String: Any], depth: Int = 0) -> CanvasElementSpec? {
        guard depth <= CanvasLimits.maxDepth else { return nil }
        guard let type = object["type"] as? String else { return nil }
        var props = (object["props"] as? [String: Any] ?? [:]).compactMapValues(Self.jsonValue(from:))

        let rawChildren: [Any]
        if let array = object["children"] as? [Any] {
            rawChildren = array
        } else if let dict = object["children"] as? [String: Any] {
            rawChildren = [dict]
        } else if let str = object["children"] as? String, type == "text" {
            if props["content"] == nil {
                props["content"] = .string(str)
            }
            rawChildren = []
        } else {
            rawChildren = []
        }
        var children: [CanvasElementSpec] = []
        for child in rawChildren {
            guard let dict = child as? [String: Any],
                  let childSpec = elementSpec(from: dict, depth: depth + 1) else {
                return nil
            }
            children.append(childSpec)
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

    /// Registers the `openclip` bridge object and side-effect functions on the context. Every call
    /// collects into the passed `CanvasBridgeCollector` (fresh per evaluation — never shared state).
    /// `captures`/`sourceApp` surface the action's match to the script as
    /// `openclip.input.captures` / `openclip.input.app.{bundleID,name}` (same shape as the JS host);
    /// `input.text` is the full text, `input.matchedText` is the matched substring.
    public static func installCanvasBridge(
        in context: JSContext,
        input: String,
        matchedText: String? = nil,
        captures: [String],
        sourceApp: AppIdentity?,
        optionValues: [String: JSONValue],
        collector: CanvasBridgeCollector
    ) {
        let openclip: JSValue
        if let existing = context.objectForKeyedSubscript("openclip"), !existing.isUndefined, !existing.isNull, existing.isObject {
            openclip = existing
        } else {
            guard let created = JSValue(newObjectIn: context) else {
                collector.parseError = CanvasJSRuntimeError.scriptException("Could not create openclip JSValue")
                return
            }
            openclip = created
        }

        // Input object
        guard let inputObj = JSValue(newObjectIn: context) else {
            collector.parseError = CanvasJSRuntimeError.scriptException("Could not create input JSValue")
            return
        }
        let effectiveMatchedText = matchedText ?? input
        inputObj.setObject(input, forKeyedSubscript: "text" as NSString)
        inputObj.setObject(effectiveMatchedText, forKeyedSubscript: "matchedText" as NSString)
        inputObj.setObject(captures, forKeyedSubscript: "captures" as NSString)
        guard let appObj = JSValue(newObjectIn: context) else {
            collector.parseError = CanvasJSRuntimeError.scriptException("Could not create app JSValue")
            return
        }
        appObj.setObject(sourceApp?.bundleIdentifier ?? "", forKeyedSubscript: "bundleID" as NSString)
        appObj.setObject(sourceApp?.localizedName ?? "", forKeyedSubscript: "name" as NSString)
        inputObj.setObject(appObj, forKeyedSubscript: "app" as NSString)
        openclip.setObject(inputObj, forKeyedSubscript: "input" as NSString)

        // Options
        var optionsDict: [String: Any] = [:]
        for (key, val) in optionValues {
            optionsDict[key] = jsonValueToRawObject(val)
        }
        openclip.setObject(optionsDict, forKeyedSubscript: "options" as NSString)

        // Effects
        let copyBlock: @convention(block) (String) -> Void = { text in
            collector.effects.append(.copy(text))
        }
        let pasteBlock: @convention(block) (String) -> Void = { text in
            collector.effects.append(.paste(text))
        }
        let cutBlock: @convention(block) (String) -> Void = { text in
            collector.effects.append(.cut(text))
        }
        let simulatePasteBlock: @convention(block) () -> Void = {
            collector.effects.append(.simulatePaste)
        }
        let openURLBlock: @convention(block) (String) -> Void = { urlString in
            if let url = URL(string: urlString) {
                collector.effects.append(.openURL(url))
            }
        }
        let keyPressBlock: @convention(block) (String, NSArray?) -> Void = { key, modifiers in
            let mods = mapModifiers(modifiers)
            collector.effects.append(.keyPress(KeyPressSpec(key: key, modifiers: mods)))
        }
        let runShortcutBlock: @convention(block) (String, String?) -> Void = { name, inputOverride in
            let cleanedInput = (inputOverride == nil || inputOverride == "undefined" || inputOverride == "null") ? nil : inputOverride
            collector.effects.append(.runShortcut(name: name, input: cleanedInput ?? input))
        }
        let showServicesBlock: @convention(block) (String) -> Void = { text in
            collector.effects.append(.showServices(text))
        }
        let notifyBlock: @convention(block) (String, String) -> Void = { title, body in
            collector.effects.append(.notify(title: title, body: body))
        }
        let keepVisibleBlock: @convention(block) () -> Void = {
            collector.keepVisible = true
        }

        // showContent(tree, options?) — captures mountedTree + preferredSize
        let showContentBlock: @convention(block) (JSValue, JSValue?) -> Void = { treeValue, options in
            if let object = treeValue.toObject() as? [String: Any],
               let spec = CanvasScriptBox.elementSpec(from: object) {
                do {
                    collector.mountedTree = try CanvasElementParser.parseTree(spec)
                } catch {
                    collector.parseError = CanvasJSRuntimeError.scriptException(error.localizedDescription)
                }
            } else {
                collector.parseError = CanvasJSRuntimeError.scriptException("showContent payload rejected")
            }
            if let options, options.isObject, let size = options.objectForKeyedSubscript("size"), size.isObject {
                let w = size.objectForKeyedSubscript("width")
                let h = size.objectForKeyedSubscript("height")
                if let w, !w.isUndefined, w.isNumber, let h, !h.isUndefined, h.isNumber {
                    collector.preferredSize = CanvasSize(width: w.toDouble(), height: h.toDouble())
                }
            }
        }
        // showStatus(message, style?) — style defaults "info"
        let showStatusBlock: @convention(block) (String, String?) -> Void = { message, style in
            collector.status = StatusFeedback(message: message, style: CanvasScriptBox.mapStatusStyle(style ?? "info"))
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
        openclip.setObject(showContentBlock, forKeyedSubscript: "showContent" as NSString)
        openclip.setObject(showStatusBlock, forKeyedSubscript: "showStatus" as NSString)

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

    /// Maps a JS status style string to the Core style (defaults to `.info`).
    public static func mapStatusStyle(_ raw: String) -> StatusFeedback.Style {
        switch raw.lowercased() {
        case "success": return .success
        case "error": return .error
        case "info": return .info
        default: return .info
        }
    }
}

/// Per-evaluation capture bag for everything the `openclip` canvas bridge collects: side-effect
/// requests, the keepVisible flag, the showContent tree/size override, and a showStatus feedback.
/// A fresh collector is created for every mount/dispatch evaluation (never shared/static state).
public final class CanvasBridgeCollector: @unchecked Sendable {
    public var effects: [CanvasEffect] = []
    public var keepVisible: Bool = false
    public var preferredSize: CanvasSize?
    public var status: StatusFeedback?
    public var mountedTree: CanvasComponent?
    public var parseError: CanvasJSRuntimeError?
    public init() {}
}
