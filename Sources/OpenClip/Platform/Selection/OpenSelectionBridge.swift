// OpenSelectionBridge.swift
// OpenClip
//
// Bridges OpenSelection to OpenClip's internal Core domain types, logging pipeline,
// and backward-compatibility interfaces.
import AppKit
import Foundation
import Core
@_exported import OpenSelection

// Prefer Core domain types over OpenSelection's same-named types.
public typealias AppIdentity = Core.AppIdentity
public typealias SelectionGatePolicy = Core.SelectionGatePolicy
public typealias CursorClass = Core.CursorClass
public typealias TextResult = Core.TextResult
public typealias SelectionReadStatus = Core.SelectionReadStatus
public typealias LogLevel = Core.LogLevel

extension SelectionRetrievalCoordinator {
    /// Compatibility init for TextResult-based copy captures.
    public init(
        inspect: @escaping TargetProvider = { trace in AXElementInspector.inspect(trace: trace) },
        copyCapture: (@Sendable (CopyTrigger) async -> Core.TextResult?)?,
        menuPress: @escaping MenuPress = SelectionRetrievalCoordinator.pressEditCopyMenu,
        scriptRunner: @escaping ScriptRunner = SelectionRetrievalCoordinator.defaultScriptRunner
    ) {
        let mappedCapture: CopyCapture? = copyCapture.map { cc in
            { @Sendable (request: CopyRequest) in
                if let res = await cc(request.trigger) {
                    return OpenSelection.SelectionResult(
                        text: res.text,
                        bounds: res.bounds,
                        html: res.html,
                        rtf: res.rtf,
                        flavors: res.flavors.map { PasteboardFlavor(type: $0.type, data: $0.data) },
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

    public init(
        inspect: @escaping SimpleTargetProvider,
        copyCapture: (@Sendable (CopyTrigger) async -> Core.TextResult?)?,
        menuPress: @escaping MenuPress = SelectionRetrievalCoordinator.pressEditCopyMenu,
        scriptRunner: @escaping ScriptRunner = SelectionRetrievalCoordinator.defaultScriptRunner
    ) {
        self.init(
            inspect: { _ in inspect() },
            copyCapture: copyCapture,
            menuPress: menuPress,
            scriptRunner: scriptRunner
        )
    }

    public func retrieveResponse(
        for app: Core.AppIdentity,
        policy: Core.AppPolicyContext,
        cursor: Core.CursorClass,
        isSelectAll: Bool = false,
        allowCopyFallback: Bool = true,
        requireCopyEvidence: Bool = true,
        trigger: TriggerSource = .programmatic
    ) async -> Core.TextReadResponse {
        // When policy explicitly opts into kbCpNoAXWebAreaRetry (e.g. Monaco / code editors under kbCpNoAXWebAreaApps),
        // Monaco never exposes selection via AXWebArea. Passing nil bundleIdentifier to OpenSelection bypasses its multi-process
        // electronGroup check, evaluating strategyCascade directly to [.keyboardCopy] without the 105ms AXWebArea settling wait.
        let openSelectionBundleID: String? = policy.kbCpNoAXWebAreaRetry ? nil : app.bundleIdentifier
        let openSelectionApp = OpenSelection.AppIdentity(
            bundleIdentifier: openSelectionBundleID,
            localizedName: app.localizedName,
            processIdentifier: app.processIdentifier
        )
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

        let response = await self.retrieveResponse(
            for: openSelectionApp,
            policy: openSelectionPolicy,
            cursor: openSelectionCursor,
            isSelectAll: isSelectAll,
            allowCopyFallback: allowCopyFallback,
            requireCopyEvidence: requireCopyEvidence,
            trigger: trigger
        )

        // `formattedText` performs WebKit-backed HTML import, which is main-actor isolated.
        let textResult: Core.TextResult?
        if let result = response.result {
            textResult = await MainActor.run {
                Core.TextResult(
                    text: result.formattedText,
                    bounds: result.bounds,
                    html: result.html,
                    rtf: result.rtf,
                    flavors: result.flavors.map { Core.RichPasteboardFlavor($0) }
                )
            }
        } else {
            textResult = nil
        }
        return Core.TextReadResponse(result: textResult, isEditable: response.isEditable,
                                     status: Core.SelectionReadStatus(rawValue: response.status.rawValue) ?? .failed, traceID: response.traceID)
    }


    public func retrieveDetails(
        for app: Core.AppIdentity, policy: Core.AppPolicyContext, cursor: Core.CursorClass,
        isSelectAll: Bool = false, allowCopyFallback: Bool = true, requireCopyEvidence: Bool = true
    ) async -> (result: Core.TextResult?, isEditable: Bool) {
        let response = await retrieveResponse(for: app, policy: policy, cursor: cursor,
            isSelectAll: isSelectAll, allowCopyFallback: allowCopyFallback,
            requireCopyEvidence: requireCopyEvidence)
        return (response.result, response.isEditable)
    }

    public func retrieve(
        for app: Core.AppIdentity,
        policy: Core.AppPolicyContext,
        cursor: Core.CursorClass,
        isSelectAll: Bool = false,
        allowCopyFallback: Bool = true,
        requireCopyEvidence: Bool = true
    ) async -> Core.TextResult? {
        await retrieveDetails(
            for: app,
            policy: policy,
            cursor: cursor,
            isSelectAll: isSelectAll,
            allowCopyFallback: allowCopyFallback,
            requireCopyEvidence: requireCopyEvidence
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

extension Core.RichPasteboardFlavor {
    public init(_ flavor: PasteboardFlavor) {
        self.init(type: flavor.type, data: flavor.data)
    }
}

extension Core.TextResult {
    @MainActor
    public init(_ result: OpenSelection.SelectionResult) {
        self.init(
            text: result.formattedText,
            bounds: result.bounds,
            html: result.html,
            rtf: result.rtf,
            flavors: result.flavors.map { Core.RichPasteboardFlavor($0) }
        )
    }
}

extension OpenSelection.SelectionResult {
    @MainActor
    public var asTextResult: Core.TextResult {
        Core.TextResult(
            text: formattedText,
            bounds: bounds,
            html: html,
            rtf: rtf,
            flavors: flavors.map { Core.RichPasteboardFlavor($0) }
        )
    }
}

extension OpenSelection {
    @MainActor
    public static func replace(
        with text: String,
        html: String? = nil,
        rtf: String? = nil,
        flavors: [PasteboardFlavor] = [],
        in app: NSRunningApplication? = nil,
        matchStyle: Bool = false,
        pasteboard: NSPasteboard = .general,
        restoreDelay: TimeInterval = 0.25,
        restorePasteboard: Bool = true,
        appActivator: (@MainActor @Sendable (NSRunningApplication) -> Void)? = nil,
        targetActiveChecker: (@MainActor @Sendable (NSRunningApplication) async -> Bool)? = nil,
        keyPoster: (@MainActor @Sendable (CGKeyCode, CGEventFlags) -> Void)? = nil
    ) async throws {
        let config = SelectionConfiguration(
            pasteboardDeliveryRestoreDelay: restoreDelay,
            pasteVirtualKey: Constants.vVirtualKey
        )
        let replacer = SelectionReplacer(
            configuration: config,
            pasteboard: pasteboard,
            focusedElementProvider: { _ in nil },
            directAXReplacer: { _, _ in false },
            keyPoster: keyPoster ?? { KeyboardEventPoster.postKey(keyCode: $0, flags: $1) },
            appActivator: appActivator ?? { $0.activate() },
            targetActiveChecker: targetActiveChecker ?? SelectionReplacer.defaultTargetActiveChecker
        )
        try await replacer.replace(
            with: text,
            html: html,
            rtf: rtf,
            flavors: flavors,
            in: app,
            matchStyle: matchStyle,
            restorePasteboard: restorePasteboard
        )
    }
}

/// Routes OpenSelection diagnostics into OpenClip's logging.
public struct OpenClipDiagnosticsSink: OpenSelectionDiagnosticsSink {
    public let minimumLevel: OpenSelection.LogLevel

    public init(minimumLevel: OpenSelection.LogLevel = .debug) {
        self.minimumLevel = minimumLevel
    }

    public func record(_ event: DiagnosticEvent) {
        let coreLevel: Core.LogLevel
        switch event.level {
        case .trace, .debug:
            coreLevel = .debug
        case .info:
            coreLevel = .info
        case .warning:
            coreLevel = .warning
        case .error:
            coreLevel = .error
        case .fault:
            coreLevel = .fault
        }

        let formattedFields = event.fields.map { "\($0.key)=\(Self.format($0.value))" }.sorted().joined(separator: " ")
        let line = formattedFields.isEmpty
            ? "[\(event.traceID)] [\(event.category.rawValue)] \(event.message)"
            : "[\(event.traceID)] [\(event.category.rawValue)] \(event.message) [\(formattedFields)]"

        Log.selection.log(level: coreLevel, Core.LogMessage(stringValue: line))
    }

    public func finish(_ report: CascadeReport) {
        // Only the correlated completion event logs at normal level.
    }

    private static func format(_ value: OpenSelection.FieldValue) -> String {
        switch value {
        case .int(let v):
            return "\(v)"
        case .bool(let v):
            return v ? "true" : "false"
        case .micros(let v):
            return "\(v)µs"
        case .presence(let v):
            return v.rawValue
        case .ax(let v):
            return v.rawValue
        case .token(let v):
            return v
        }
    }
}


