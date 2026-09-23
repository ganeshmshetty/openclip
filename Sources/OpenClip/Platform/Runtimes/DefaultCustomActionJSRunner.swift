// DefaultCustomActionJSRunner.swift
// OpenClip
//
// Implements CustomActionJSRunning for JavaScript CustomActions by delegating to OpenClipJSHost.
// Kept in the OpenClip target so Core stays free of JavaScriptCore and platform side effects.

import Foundation
import Core

@MainActor
public struct DefaultCustomActionJSRunner: CustomActionJSRunning {
    public init() {}

    public func run(
        script: String,
        isAsync: Bool,
        replaceSelection: Bool,
        context: ActionContext,
        actionID: String
    ) async throws -> ActionResult {
        let request = OpenClipJSHost.Request(
            actionID: actionID,
            scriptCode: script,
            context: context,
            options: [],
            optionStore: SettingsActionOptionStore(),
            rules: ExtensionActionRules(),
            isAsync: isAsync,
            timeout: Constants.scriptTimeout,
            packageDirectory: nil,
            entryDirectory: nil,
            pasteboardContent: OpenClipJSHost.PasteboardContent.read()
        )
        return try await OpenClipJSHost().run(request)
    }
}
