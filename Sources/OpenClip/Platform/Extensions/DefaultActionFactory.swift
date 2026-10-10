// DefaultActionFactory.swift
// OpenClip
//
// Birth Door: instantiates executable Actions from extension manifests and snippets. Applies the
// uniform action-ID rule, threads the option store into runtimes, and stamps `.extensionPkg` chrome
// on every action so GUI-authored actions share the trash path. `createAction` keeps groups
// schema-only; `createActions` materializes a `.group` with sub-actions named `\(groupID).\(subID)`.
import Foundation
import Core

public final class DefaultActionFactory: ActionFactory, Sendable {
    private let optionStore: any ActionOptionReading
    private let captureRichSelection: @MainActor @Sendable (SelectionContext) async throws -> SelectionContext

    public init(optionStore: any ActionOptionReading = SettingsActionOptionStore(),
                isSelectionCurrent: @escaping @MainActor @Sendable (SelectionContext) -> Bool = { _ in true },
                captureRichSelection: (@MainActor @Sendable (SelectionContext) async throws -> SelectionContext)? = nil) {
        self.optionStore = optionStore
        self.captureRichSelection = captureRichSelection ?? { selection in
            try await ActionSelectionCapture(isSelectionCurrent: isSelectionCurrent).capture(selection)
        }
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

    /// Maps option metadata to `ExtensionOption`; `values` become `.multiple` picker choices.
    private func makeExtensionOption(from metadata: ExtensionOptionMetadata) -> ExtensionOption {
        ExtensionOption(
            identifier: metadata.identifier,
            label: metadata.label,
            type: ExtensionOptionType(rawValue: metadata.type.lowercased()) ?? .string,
            defaultValue: metadata.defaultValue,
            options: metadata.values
        )
    }

    /// Merges action options onto manifest defaults by identifier, keeping manifest order; action-only options are appended.
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

    /// Materializes all registry entries for one manifest action: a group yields its row plus sub-actions. Nested groups are not flattened.
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
            legacyRegex: metadata.regex
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

    /// Wraps `action` per manifest metadata. `menuRelevance` stays outermost so RelevanceProviding surfaces on the registered action.
    private func decorate(_ action: any Action, metadata: ExtensionActionMetadata, manifest: ExtensionMetadata? = nil) -> any Action {
        var result = action
        if metadata.captureRtf == true || metadata.captureHtml == true {
            result = RichInputAction(base: result, captureRtf: metadata.captureRtf == true,
                                     captureHtml: metadata.captureHtml == true, capture: captureRichSelection)
        }
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

    /// Declared `ActionDelivery`, or nil when no secondary/toast/secondaryToast is declared.
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

    /// Maps a manifest `secondary` to an `ActionResult`, sharing `ShellResultMapper`'s vocabulary. Unknown types fail open to `.success`.
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

    /// Maps a `toast`/`secondaryToast` to `StatusFeedback`; style defaults to `.success`.
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

    /// One executable Action for a manifest entry, or nil for groups (see `createActions`). `forcedID` stamps group sub-actions.
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
        // Sub-actions without their own icon inherit the group's.
        let icon: ActionIcon
        if let iconString = metadata.icon, !iconString.isEmpty {
            icon = ExtensionManager.parseIcon(iconString, directoryURL: directoryURL)
        } else if let inheritedIcon {
            icon = inheritedIcon
        } else {
            icon = .symbol(Constants.defaultIconSymbol)
        }
        
        let options = mergedOptions(manifestOptions: manifest.options, actionOptions: metadata.options)
        
        // Declarative visibility rules shared by all extension actions.
        let rules = ExtensionActionRules(
            requirements: metadata.requirements,
            legacyRegex: metadata.regex
        )
        
        let declaredOutput = metadata.output
        let declaredResult = metadata.result
        let hasExplicitDeclaration = (declaredOutput != nil || declaredResult != nil || manifest.output != nil || manifest.result != nil || metadata.inline == true)

        let resolvedOutputKind: ActionOutputKind
        let resolvedResult: ActionResultDeliveryMode?

        if hasExplicitDeclaration {
            let resolved = ExtensionOutputContract.resolveEffective(
                declaredOutput: declaredOutput,
                declaredResult: declaredResult,
                manifestOutput: manifest.output,
                manifestResult: manifest.result,
                inline: metadata.inline
            )
            resolvedOutputKind = resolved.output
            resolvedResult = resolved.result
        } else {
            switch metadata.kind {
            case .textSnippet:
                resolvedOutputKind = .text
                resolvedResult = .pasteOrCopy
            case .url, .webSearch, .keyPress, .service, .shortcut, .group:
                resolvedOutputKind = .none
                resolvedResult = nil
            case .applescript, .shellInline, .scriptFile, .js:
                let code = scriptContent(for: metadata, directoryURL: directoryURL)
                let producesText: Bool
                if let code {
                    switch metadata.kind {
                    case .applescript:
                        producesText = ScriptOutputSniffers.appleScriptProducesText(code: code)
                    case .shellInline, .scriptFile:
                        producesText = ScriptOutputSniffers.shellProducesText(code: code)
                    case .js:
                        producesText = ScriptOutputSniffers.jsProducesText(code: code)
                    default:
                        producesText = true
                    }
                } else {
                    producesText = true
                }
                if producesText {
                    resolvedOutputKind = .text
                    resolvedResult = .pasteOrCopy
                } else {
                    resolvedOutputKind = .none
                    resolvedResult = nil
                }
            }
        }

        let extensionChrome = ActionChrome(
            badge: .extensionPkg(manifest.name),
            rowStyle: .standard,
            popupBehavior: .perform,
            source: .extensionPkg(packageID: manifest.identifier),
            requiresLiveSelection: metadata.requirements?.input == .liveSelection
                || metadata.requirements?.input == .editableSelection,
            showsLoading: metadata.loading ?? false,
            loadingMessage: metadata.loadingMessage,
            isInlineResult: metadata.inline == true,
            outputKind: resolvedOutputKind,
            recommendedResult: resolvedResult
        )

        // Checked before the url/script branches so a keyPress without a URL does not fall through to ScriptAction.
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

        // Text snippets keep their template in `scriptCode`.
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

        // Directories pass fileExists too; neither they nor unreadable scripts may register as empty actions.
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
                options: options,
                optionStore: optionStore,
                chrome: extensionChrome,
                rules: rules
            )
        }
    }

    private func scriptContent(for metadata: ExtensionActionMetadata, directoryURL: URL) -> String? {
        if let scriptCode = metadata.scriptCode, !scriptCode.isEmpty {
            return scriptCode
        }
        if let scriptFile = metadata.script, !scriptFile.isEmpty {
            let fileURL = directoryURL.appendingPathComponent(scriptFile)
            guard !scriptFile.hasPrefix("/"),
                  !scriptFile.hasPrefix("~"),
                  !scriptFile.contains(":"),
                  Constants.isPathSafe(destinationURL: fileURL, baseDirectory: directoryURL) else {
                return nil
            }
            return try? String(contentsOf: fileURL, encoding: .utf8)
        }
        return nil
    }
}
