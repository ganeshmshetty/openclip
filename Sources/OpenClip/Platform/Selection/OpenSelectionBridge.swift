// OpenSelectionBridge.swift
// OpenClip
//
// Bridges OpenSelection to OpenClip's internal Core domain types, logging pipeline,
// and backward-compatibility interfaces.
import AppKit
import Foundation
import Core
@_exported import OpenSelection

// Disambiguate types shared with Core in favor of Core domain types within OpenClip.
public typealias AppIdentity = Core.AppIdentity
public typealias SelectionGatePolicy = Core.SelectionGatePolicy
public typealias CursorClass = Core.CursorClass
public typealias TextResult = Core.TextResult

extension SelectionRetrievalCoordinator {
    /// Convenience initializer preserving compatibility with OpenClip's TextResult-based copy captures.
    public init(
        inspect: @escaping TargetProvider = { AXElementInspector.inspect() },
        copyCapture: (@Sendable (CopyTrigger) async -> Core.TextResult?)?,
        menuPress: @escaping MenuPress = SelectionRetrievalCoordinator.pressEditCopyMenu,
        scriptRunner: @escaping ScriptRunner = SelectionRetrievalCoordinator.defaultScriptRunner
    ) {
        let mappedCapture: CopyCapture? = copyCapture.map { cc in
            { @Sendable trigger in
                if let res = await cc(trigger) {
                    return OpenSelection.SelectionResult(
                        text: res.text,
                        bounds: res.bounds,
                        html: res.html,
                        rtf: res.rtf,
                        strategy: .keyboardCopy
                    )
                }
                return nil
            }
        }
        self.init(
            configuration: .default,
            inspect: inspect,
            copyCapture: mappedCapture,
            menuPress: menuPress,
            scriptRunner: scriptRunner
        )
    }

    /// Reads selection details using OpenClip's Core.AppIdentity and Core.AppPolicyContext.
    public func retrieveDetails(
        for app: Core.AppIdentity,
        policy: Core.AppPolicyContext,
        cursor: Core.CursorClass,
        isSelectAll: Bool = false,
        allowCopyFallback: Bool = true
    ) async -> (result: Core.TextResult?, isEditable: Bool) {
        let openSelectionApp = OpenSelection.AppIdentity(bundleIdentifier: app.bundleIdentifier, localizedName: app.localizedName)
        let openSelectionPolicy = OpenSelection.SelectionPolicy(
            disabled: policy.disabled,
            hotkeyOnly: policy.hotkeyOnly,
            denyPaste: policy.denyPaste,
            useMenuCopy: policy.useMenuCopy,
            retrievalMode: OpenSelection.SelectionStrategy(rawValue: policy.retrievalMode.rawValue) ?? .axTextControl,
            gate: OpenSelection.SelectionGatePolicy(
                skipRoles: policy.gate.skipRoles,
                allowedCursors: Set(policy.gate.allowedCursors.compactMap { OpenSelection.CursorClass(rawValue: $0.rawValue) })
            )
        )
        let openSelectionCursor = OpenSelection.CursorClass(rawValue: cursor.rawValue) ?? .unknown

        let (result, isEditable) = await self.retrieveDetails(
            for: openSelectionApp,
            policy: openSelectionPolicy,
            cursor: openSelectionCursor,
            isSelectAll: isSelectAll,
            allowCopyFallback: allowCopyFallback
        )

        let textResult = result.map {
            Core.TextResult(text: $0.text, bounds: $0.bounds, html: $0.html, rtf: $0.rtf)
        }
        return (textResult, isEditable)
    }


    /// Reads selection using OpenClip's Core.AppIdentity and Core.AppPolicyContext.
    public func retrieve(
        for app: Core.AppIdentity,
        policy: Core.AppPolicyContext,
        cursor: Core.CursorClass,
        isSelectAll: Bool = false,
        allowCopyFallback: Bool = true
    ) async -> Core.TextResult? {
        await retrieveDetails(
            for: app,
            policy: policy,
            cursor: cursor,
            isSelectAll: isSelectAll,
            allowCopyFallback: allowCopyFallback
        ).result
    }
}

extension Core.CursorClass {
    public var asOpenSelection: OpenSelection.CursorClass {
        OpenSelection.CursorClass(rawValue: self.rawValue) ?? .unknown
    }
}

extension OpenSelection.CursorClass {
    public var asCore: Core.CursorClass {
        Core.CursorClass(rawValue: self.rawValue) ?? .unknown
    }
}

extension Core.TextResult {
    public init(_ result: OpenSelection.SelectionResult) {
        self.init(text: result.text, bounds: result.bounds, html: result.html, rtf: result.rtf)
    }
}

extension OpenSelection.SelectionResult {
    public var asTextResult: Core.TextResult {
        Core.TextResult(text: text, bounds: bounds, html: html, rtf: rtf)
    }
}

extension OpenSelection {
    /// Non-destructive or clipboard-copy paste replacement for OpenClip effects.
    @MainActor
    public static func replace(
        with text: String,
        in app: NSRunningApplication? = nil,
        pasteboard: NSPasteboard = .general,
        restoreDelay: TimeInterval = 0.25,
        restorePasteboard: Bool = true,
        keyPoster: (@MainActor @Sendable (CGKeyCode, CGEventFlags) -> Void)? = nil
    ) async throws {
        let config = SelectionConfiguration(
            pasteboardDeliveryRestoreDelay: restoreDelay,
            pasteVirtualKey: Constants.vVirtualKey
        )
        let replacer = SelectionReplacer(
            configuration: config,
            pasteboard: pasteboard,
            directAXReplacer: { _, _ in false },
            keyPoster: keyPoster ?? { KeyboardEventPoster.postKey(keyCode: $0, flags: $1) }
        )
        try await replacer.replace(with: text, in: app, restorePasteboard: restorePasteboard)
    }
}

