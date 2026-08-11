// NamedServiceAction.swift
// OpenClip
//
// Implements the `service` extension runtime (Phase 8). v1 maps the kind to the generic macOS
// share picker (`.showServices(text)`); when `serviceName` is set, it invokes the named service via
// `NSPerformService` against an isolated pasteboard so the user's global clipboard is untouched.
// Enablement and match resolution
// delegate to the shared ActionVisibility evaluator when rules are attached; otherwise the
// default requires a non-blank selection.
import Foundation
import AppKit
import Core

public struct NamedServiceAction: Action {
    public let id: String
    public let title: String
    public let icon: ActionIcon
    public let serviceName: String?
    public let chrome: ActionChrome
    public let rules: ExtensionActionRules?
    public var performService: @Sendable (String, NSPasteboard) -> Bool

    public init(
        id: String,
        title: String,
        icon: ActionIcon = .symbol("share"),
        serviceName: String? = nil,
        chrome: ActionChrome? = nil,
        rules: ExtensionActionRules? = nil,
        performService: @escaping @Sendable (String, NSPasteboard) -> Bool = { NSPerformService($0, $1) }
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.serviceName = serviceName
        self.chrome = chrome ?? ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .extensionPkg(packageID: id))
        self.rules = rules
        self.performService = performService
    }

    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        guard let rules else {
            return !context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return rules.resolveVisibility(for: context).enabled
    }

    @MainActor
    public func matchInfo(for context: ActionContext) -> ActionMatchInfo? {
        guard let rules else { return nil }
        return rules.resolveVisibility(for: context).match
    }

    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        if let serviceName = serviceName, !serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Use an isolated named pasteboard so invoking the service never overwrites the
            // user's global clipboard contents with the selected text.
            let pboard = NSPasteboard(name: NSPasteboard.Name("com.openclip.namedService.\(UUID().uuidString)"))
            pboard.clearContents()
            pboard.setString(context.selection.text, forType: .string)
            if performService(serviceName, pboard) {
                return .none
            } else {
                throw NSError(
                    domain: Constants.actionErrorDomain,
                    code: Int(Constants.actionErrorCode),
                    userInfo: [NSLocalizedDescriptionKey: "Failed to perform system service '\(serviceName)'. Check that the service is enabled in System Settings."]
                )
            }
        }
        return .showServices(context.selection.text)
    }
}