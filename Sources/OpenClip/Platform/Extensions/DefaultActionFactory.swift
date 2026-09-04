// DefaultActionFactory.swift
// OpenClip
//
// Serves as the Birth Door implementation, instantiating executable Action instances from extension manifests and snippets.
// Applies the uniform action-ID rule, threads the option store into every runtime that reads configured option values,
// and stamps `.extensionPkg` chrome on every action it creates — including shellInline/textSnippet CustomActions — so
// GUI-authored actions share the extension package trash path. Single-action creation (`createAction`) keeps `group`
// actions schema-only (returns nil); `createActions` (used by the registry loader) materializes a `.group` into a
// GroupAction row plus one entry per sub-action under the `\(groupID).\(subID)` ID-prefix convention, and routes the
// keyPress/shortcut/service kinds (Phase 8) to their runtime actions.
import Foundation
import Core

public final class DefaultActionFactory: ActionFactory, Sendable {
    private let optionStore: any ActionOptionReading

    public init(optionStore: any ActionOptionReading = SettingsActionOptionStore()) {
        self.optionStore = optionStore
    }

    /// Reduces any `ActionIcon` to the plain symbol name `CustomAction` stores in `iconName`.
    private func iconSymbolName(_ icon: ActionIcon) -> String {
        switch icon {
        case .symbol(let name): name
        case .local(let url): url.lastPathComponent
        case .url(let url): url.absoluteString
        case .text(let txt): txt
        }
    }

    /// Maps manifest/action option metadata to the runtime `ExtensionOption` model, wiring
    /// `values`/`options` into the `.multiple` picker choices (T1-minor-1 carryover).
    private func makeExtensionOption(from metadata: ExtensionOptionMetadata) -> ExtensionOption {
        ExtensionOption(
            identifier: metadata.identifier,
            label: metadata.label,
            type: ExtensionOptionType(rawValue: metadata.type.lowercased()) ?? .string,
            defaultValue: metadata.defaultValue,
            options: metadata.values
        )
    }

    /// Compiles the manifest expression DSL once (parse-once-eval-many). On a parse failure the
    /// expression is dropped and logged via Log.js: the action then behaves exactly as before the
    /// DSL existed (defensive fail-open, mirroring the malformed-regex stance).
    private func compiledExpression(for metadata: ExtensionActionMetadata, actionID: String) -> ValidateExpression? {
        guard let source = metadata.requirements?.expression,
              !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        switch ValidateExpression.parse(source) {
        case .success(let expression):
            return expression
        case .failure(let error):
            Log.js.error("Enablement expression parse failed for \(actionID, privacy: .public): \(error)")
            return nil
        }
    }

    /// Merges per-action option overrides (`metadata.options`) onto the manifest-level defaults
    /// (`manifest.options`) by identifier. Manifest-level options keep their order; overrides
    /// replace matching identifiers in place, and identifiers unique to the action are appended
    /// in declaration order.
    private func mergedOptions(
        manifestOptions: [ExtensionOptionMetadata]?,
        actionOptions: [ExtensionOptionMetadata]?
    ) -> [ExtensionOption] {
        var result: [ExtensionOption] = (manifestOptions ?? []).map(makeExtensionOption)
        guard let actionOverrides = actionOptions, !actionOverrides.isEmpty else { return result }

        var overrides: [String: ExtensionOption] = [:]
        var orderedNewKeys: [String] = []
        for metadata in actionOverrides {
            let option = makeExtensionOption(from: metadata)
            if overrides[option.identifier] == nil { orderedNewKeys.append(option.identifier) }
            overrides[option.identifier] = option
        }
        for index in result.indices {
            if let override = overrides[result[index].identifier] {
                result[index] = override
                overrides.removeValue(forKey: result[index].identifier)
                orderedNewKeys.removeAll { $0 == result[index].identifier }
            }
        }
        for key in orderedNewKeys {
            if let override = overrides[key] {
                result.append(override)
            }
        }
        return result
    }

    public func createAction(
        metadata: ExtensionActionMetadata,
        manifest: ExtensionMetadata,
        directoryURL: URL,
        index: Int
    ) async -> (any Action)? {
        guard let base = await makeAction(metadata: metadata, manifest: manifest, directoryURL: directoryURL, index: index, forcedID: nil) else { return nil }
        return decorate(base, metadata: metadata, manifest: manifest)
    }

    /// Materializes every registry entry for one manifest action. Non-group actions return the
    /// single `createAction` result; a `.group` returns a GroupAction row plus one entry per
    /// sub-action whose ID is `\(groupID).\(subID)` (ID-prefix convention — no parentGroupID
    /// marker). Nested groups are not flattened.
    public func createActions(
        metadata: ExtensionActionMetadata,
        manifest: ExtensionMetadata,
        directoryURL: URL,
        index: Int
    ) async -> [any Action] {
        guard metadata.kind == .group else {
            guard let action = await makeAction(metadata: metadata, manifest: manifest, directoryURL: directoryURL, index: index, forcedID: nil) else { return [] }
            return [decorate(action, metadata: metadata, manifest: manifest)]
        }

        let groupID = ExtensionManager.uniformActionID(metadata: metadata, manifest: manifest, index: index)
        let groupRules = ExtensionActionRules(
            requirements: metadata.requirements,
            legacyRegex: metadata.regex,
            compiledExpression: compiledExpression(for: metadata, actionID: groupID)
        )
        let groupChrome = ActionChrome(
            badge: .extensionPkg(manifest.name),
            rowStyle: .actionGroup,
            popupBehavior: .showSubActions,
            source: .extensionPkg(packageID: manifest.identifier)
        )
        let groupIcon = ExtensionManager.parseIcon(metadata.icon, directoryURL: directoryURL)
        let groupKeywords = (metadata.keywords ?? []) + (manifest.keywords ?? [])
        var result: [any Action] = [GroupAction(
            id: groupID,
            title: metadata.title ?? manifest.name,
            icon: groupIcon,
            chrome: groupChrome,
            rules: groupRules,
            keywords: groupKeywords
        )]
        for (subIndex, sub) in (metadata.subActions ?? []).enumerated() where sub.kind != .group {
            let subID = "\(groupID).\(sub.id ?? String(subIndex))"
            if let action = await makeAction(metadata: sub, manifest: manifest, directoryURL: directoryURL, index: subIndex, forcedID: subID, inheritedIcon: groupIcon) {
                result.append(decorate(action, metadata: sub, manifest: manifest))
            }
        }
        return result
    }

    /// Wraps a created action in `MenuDecoratedAction` when its manifest metadata declares
    /// `menuRelevance`, stamping the action with sub-menu relevance without changing its
    /// identity. Non-declaring actions pass through unchanged.
    ///
    /// Delivery-declaring actions (manifest `secondary`/`toast`/`secondaryToast`) are wrapped in
    /// `DeliveryDecoratedAction` carrying the mapped `ActionDelivery`. The wraps compose: the
    /// menuRelevance wrapper stays outermost so `RelevanceProviding` surfaces on the registered
    /// action, with `MenuDecoratedAction` forwarding `delivery` through to the inner wrapper.
    private func decorate(_ action: any Action, metadata: ExtensionActionMetadata, manifest: ExtensionMetadata? = nil) -> any Action {
        var result = action
        let declaredKeywords = (metadata.keywords ?? []) + (manifest?.keywords ?? [])
        if !declaredKeywords.isEmpty {
            result = KeywordDecoratedAction(base: result, keywords: declaredKeywords)
        }
        if let delivery = delivery(from: metadata) {
            result = DeliveryDecoratedAction(base: result, delivery: delivery)
        }
        if metadata.menuRelevance != nil {
            result = MenuDecoratedAction(
                base: result,
                menuRelevanceRegex: metadata.menuRelevance
            )
        }
        return result
    }

    /// Builds the declared `ActionDelivery` from manifest metadata, or nil when none of
    /// secondary/toast/secondaryToast is declared (preserving the current nil-delivery default).
    private func delivery(from metadata: ExtensionActionMetadata) -> ActionDelivery? {
        guard metadata.secondary != nil || metadata.toast != nil || metadata.secondaryToast != nil else {
            return nil
        }
        return ActionDelivery(
            secondary: metadata.secondary.map(actionResult(from:)),
            primaryToast: metadata.toast.map(statusFeedback(from:)),
            secondaryToast: metadata.secondaryToast.map(statusFeedback(from:))
        )
    }

    /// Maps a manifest `secondary` declaration onto the `ActionResult` it stands for, reusing
    /// `ShellResultMapper`'s stdout vocabulary where the two overlap: copy/paste/openURL/toast
    /// map to the same result shapes, `success` is the mapper's fallback, and an unknown type
    /// fails open to `.success` (mirroring the mapper's default case). `none` is the small pure
    /// addition — the empty result for an explicitly no-op secondary.
    private func actionResult(from secondary: ExtensionSecondaryDeclaration) -> ActionResult {
        switch secondary.type {
        case Constants.actionTypeCopy:
            guard let value = secondary.value else { return .success }
            return .copy(value)
        case Constants.actionTypePaste:
            guard let value = secondary.value else { return .success }
            return .paste(value)
        case Constants.actionTypeOpenURL:
            guard let value = secondary.value, let url = URL(string: value) else { return .success }
            return .openURL(url)
        case "toast":
            return .toast(StatusFeedback(message: secondary.message ?? "", style: .info))
        case "success":
            return .success
        case "none":
            return .none
        default:
            return .success
        }
    }

    /// Maps a manifest `toast`/`secondaryToast` declaration onto the `StatusFeedback` it renders.
    /// `style` mirrors `ShellResultMapper`'s status mapping, defaulting to `.success` (the
    /// validator's whitelist default) when absent or unknown.
    private func statusFeedback(from toast: ExtensionToastDeclaration) -> StatusFeedback {
        let style: StatusFeedback.Style
        switch toast.style?.lowercased() {
        case "success": style = .success
        case "error": style = .error
        case "info": style = .info
        default: style = .success
        }
        return StatusFeedback(message: toast.message, style: style)
    }

    /// Renders a single executable Action for a manifest entry, or nil when the entry is a `.group`
    /// (schema-only here; `createActions` handles group materialization) or otherwise not runnable.
    /// `forcedID` overrides the uniform-ID computation so group sub-actions can be stamped with the
    /// `\(groupID).\(subID)` prefix convention.
    private func makeAction(
        metadata: ExtensionActionMetadata,
        manifest: ExtensionMetadata,
        directoryURL: URL,
        index: Int,
        forcedID: String?,
        inheritedIcon: ActionIcon? = nil
    ) async -> (any Action)? {
        // Groups are schema-only at the single-action seam: never register a bare group as runnable.
        guard metadata.kind != .group else { return nil }
        let actionId = forcedID ?? ExtensionManager.uniformActionID(metadata: metadata, manifest: manifest, index: index)
        let title = metadata.title ?? manifest.name
        // Sub-actions inherit their group's icon when they declare none (`inheritedIcon`); otherwise
        // a missing icon falls back to the default symbol.
        let icon: ActionIcon
        if let iconString = metadata.icon, !iconString.isEmpty {
            icon = ExtensionManager.parseIcon(iconString, directoryURL: directoryURL)
        } else if let inheritedIcon {
            icon = inheritedIcon
        } else {
            icon = .symbol(Constants.defaultIconSymbol)
        }
        
        let options = mergedOptions(manifestOptions: manifest.options, actionOptions: metadata.options)
        
        // Declarative visibility rules applied to every extension action this factory creates:
        // requirements (regex, app allow/deny, requiresSelection) + legacy manifest `regex`.
        let rules = ExtensionActionRules(
            requirements: metadata.requirements,
            legacyRegex: metadata.regex,
            compiledExpression: compiledExpression(for: metadata, actionID: actionId)
        )
        
        let extensionChrome = ActionChrome(
            badge: .extensionPkg(manifest.name),
            rowStyle: .standard,
            popupBehavior: .perform,
            source: .extensionPkg(packageID: manifest.identifier),
            showsLoading: metadata.loading ?? false,
            loadingMessage: metadata.loadingMessage
        )

        // Phase 8 runtime kinds: keyPress / shortcut / service. Checked before the generic url and
        // script branches so a keyPress-without-URL doesn't fall through to a bogus ScriptAction.
        if metadata.kind == .keyPress, let keyPress = metadata.keyPress, let spec = KeyPressSpec(manifestString: keyPress) {
            return KeyPressAction(
                id: actionId,
                title: title,
                icon: icon,
                spec: spec,
                chrome: extensionChrome,
                rules: rules
            )
        }
        if metadata.kind == .shortcut, let shortcutName = metadata.shortcutName {
            return ShortcutAction(
                id: actionId,
                title: title,
                icon: icon,
                shortcutName: shortcutName,
                chrome: extensionChrome,
                rules: rules
            )
        }
        if metadata.kind == .service {
            return NamedServiceAction(
                id: actionId,
                title: title,
                icon: icon,
                serviceName: metadata.serviceName,
                chrome: extensionChrome,
                rules: rules
            )
        }

        if let urlTemplate = metadata.url {
            return URLTemplateAction(
                id: actionId,
                title: title,
                icon: icon,
                urlTemplate: urlTemplate,
                regexPattern: metadata.regex,
                chrome: extensionChrome,
                rules: rules
            )
        }

        // Text snippet actions (GUI "Text Snippet", manifest type "textsnippet"/"snippet"/"text")
        // hold their template in `scriptCode` and run as CustomAction text snippets.
        if metadata.kind == .textSnippet, let scriptCode = metadata.scriptCode, !scriptCode.isEmpty {
            return CustomAction(
                id: actionId,
                title: title,
                iconName: iconSymbolName(icon),
                type: .textSnippet(template: scriptCode),
                chrome: extensionChrome,
                rules: rules
            )
        }
        
        if let scriptCode = metadata.scriptCode, !scriptCode.isEmpty {
            let typeStr = (metadata.type ?? "").lowercased()
            switch typeStr {
            case "js", "javascript":
                return JavaScriptAction(
                    id: actionId,
                    title: title,
                    icon: icon,
                    scriptCode: scriptCode,
                    options: options,
                    chrome: extensionChrome,
                    optionStore: optionStore,
                    rules: rules,
                    isAsync: metadata.isAsync ?? false
                )
            case "applescript", "scpt":
                return AppleScriptAction(
                    id: actionId,
                    title: title,
                    icon: icon,
                    appleScriptCode: scriptCode,
                    options: options,
                    chrome: extensionChrome,
                    rules: rules
                )
            case "sh", "shell", "shell script":
                return CustomAction(
                    id: actionId,
                    title: title,
                    iconName: iconSymbolName(icon),
                    type: .shellScript(script: scriptCode, replaceSelection: true),
                    chrome: extensionChrome,
                    rules: rules
                )
            default:
                break
            }
        }
        
        let scriptName = metadata.script ?? Constants.defaultScriptName
        let scriptURL = directoryURL.appendingPathComponent(scriptName)
        let ext = scriptURL.pathExtension.lowercased()

        guard !scriptName.hasPrefix("/"),
              !scriptName.hasPrefix("~"),
              !scriptName.contains(":"),
              Constants.isPathSafe(destinationURL: scriptURL, baseDirectory: directoryURL),
              scriptURL.standardized.path != directoryURL.standardized.path else {
            Log.factory.error("Script path escapes extension directory: \(scriptName, privacy: .public)")
            return nil
        }

        // Guard against garbage metadata: with neither url, scriptCode, nor an existing script file,
        // there is nothing executable to run. A directory (fileExists is true for directories) or a
        // script that can't be read must not register as an empty action.
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: scriptURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            Log.factory.error("No runnable content for \(actionId, privacy: .public): script file missing at \(scriptURL.path, privacy: .public)")
            return nil
        }

        switch ext {
        case "js":
            guard let code = try? String(contentsOf: scriptURL, encoding: .utf8), !code.isEmpty else {
                Log.factory.error("Failed to read JS script file at \(scriptURL.path, privacy: .public)")
                return nil
            }
            return JavaScriptAction(
                id: actionId,
                title: title,
                icon: icon,
                scriptCode: code,
                options: options,
                chrome: extensionChrome,
                optionStore: optionStore,
                rules: rules,
                isAsync: metadata.isAsync ?? false,
                packageDirectory: directoryURL,
                entryDirectory: scriptURL.deletingLastPathComponent()
            )
        case "applescript", "scpt":
            guard let code = try? String(contentsOf: scriptURL, encoding: .utf8), !code.isEmpty else {
                Log.factory.error("Failed to read AppleScript file at \(scriptURL.path, privacy: .public)")
                return nil
            }
            return AppleScriptAction(
                id: actionId,
                title: title,
                icon: icon,
                appleScriptCode: code,
                options: options,
                chrome: extensionChrome,
                rules: rules
            )
        default:
            return ScriptAction(
                id: actionId,
                title: title,
                icon: icon,
                scriptURL: scriptURL,
                chrome: extensionChrome,
                rules: rules
            )
        }
    }
}
