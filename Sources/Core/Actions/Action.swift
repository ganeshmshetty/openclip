// Action.swift
// OpenClip
//
// Defines the core Action protocol and ActionIcon enum that all executable actions in OpenClip implement.
// Provides default protocol extensions for chrome metadata, action options, and customization resolution.
import Foundation

public enum ActionIcon: Sendable, Equatable {
    case symbol(String)
    case url(URL)
    case local(URL)
    case text(String)
}

public extension ActionIcon {
    /// The SF Symbol name for symbol icons; nil for local/url/text icons.
    var symbolName: String? {
        switch self {
        case .symbol(let name): return name
        case .local, .url, .text: return nil
        }
    }

    /// Resolves an icon identifier string into a typed ActionIcon.
    /// - Handles "custom:<filename>" -> .local(Constants.customIconsDirectory.appendingPathComponent(filename))
    /// - Handles absolute paths ("/...") and "file://..." -> .local(url)
    /// - Handles image extensions with directoryURL -> .local(...)
    /// - Handles "http://..." / "https://..." -> .url(url)
    /// - Handles "symbol(...)" or bare strings -> .symbol(...)
    static func resolve(from iconStr: String?, relativeTo directoryURL: URL? = nil) -> ActionIcon {
        guard let iconStr = iconStr?.trimmingCharacters(in: .whitespacesAndNewlines), !iconStr.isEmpty else {
            return .symbol(Constants.defaultIconSymbol)
        }
        if iconStr.hasPrefix(Constants.symbolPrefix) && iconStr.hasSuffix(Constants.symbolSuffix) {
            let symbolName = String(iconStr.dropFirst(Constants.symbolPrefix.count).dropLast(Constants.symbolSuffix.count))
            return .symbol(symbolName)
        }
        if iconStr.hasPrefix(Constants.customIconPrefix) {
            let rawFilename = String(iconStr.dropFirst(Constants.customIconPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            let safeName = (rawFilename as NSString).lastPathComponent
            if !safeName.isEmpty && safeName != "." && safeName != ".." && !rawFilename.contains("/") {
                let dest = Constants.customIconsDirectory.appendingPathComponent(safeName)
                if Constants.isPathSafe(destinationURL: dest, baseDirectory: Constants.customIconsDirectory) {
                    return .local(dest)
                }
            }
            return .symbol(Constants.defaultIconSymbol)
        }
        if iconStr.hasPrefix("/") {
            return .local(URL(fileURLWithPath: iconStr))
        }
        if iconStr.hasPrefix("file://"), let url = URL(string: iconStr) {
            return .local(url)
        }
        if (iconStr.hasPrefix("http://") || iconStr.hasPrefix("https://")), let url = URL(string: iconStr) {
            return .url(url)
        }
        let lower = iconStr.lowercased()
        if Constants.imageExtensions.contains(where: { lower.hasSuffix($0) }) {
            if let directoryURL {
                let candidate = directoryURL.appendingPathComponent(iconStr)
                if Constants.isPathSafe(destinationURL: candidate, baseDirectory: directoryURL) {
                    return .local(candidate)
                }
            } else {
                let safeName = (iconStr as NSString).lastPathComponent
                if !safeName.isEmpty && safeName != "." && safeName != ".." && !iconStr.contains("/") {
                    let dest = Constants.customIconsDirectory.appendingPathComponent(safeName)
                    if Constants.isPathSafe(destinationURL: dest, baseDirectory: Constants.customIconsDirectory) {
                        return .local(dest)
                    }
                }
            }
        }
        return .symbol(iconStr)
    }
}

public protocol Action: Sendable {
    var id: String { get }
    var title: String { get }
    var icon: ActionIcon { get }
    var chrome: ActionChrome { get }
    
    @MainActor
    func isEnabled(for context: ActionContext) -> Bool

    /// Re-runs the shared visibility evaluator for this action at perform time (match plumbing
    /// approach A). Returns the `ActionMatchInfo` the caller should thread into
    /// `ActionContext.match`; nil for actions with no match plumbing (builtins).
    @MainActor
    func matchInfo(for context: ActionContext) -> ActionMatchInfo?
    
    @MainActor
    func perform(_ context: ActionContext) async throws -> ActionResult
    
    var actionOptions: [ExtensionOption] { get }

    /// Declares a secondary (⇧-click / secondary-click) result and per-click toasts. Defaults to
    /// nil (derive secondary from the primary result); see `ActionDelivery`.
    var delivery: ActionDelivery? { get }

    /// Search keywords for the action palette.
    var keywords: [String] { get }
}

public extension Action {
    var actionOptions: [ExtensionOption] { [] }
    var delivery: ActionDelivery? { nil }
    var keywords: [String] { [] }
    var chrome: ActionChrome {
        ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin)
    }

    @MainActor
    func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }

    /// Resolves the user-customized display title through an explicit presenter. The presenter is a
    /// parameter (never a hidden process-wide singleton) so display resolution is decoupled from the
    /// customization singleton and injectable in tests and previews.
    @MainActor
    func displayTitle(using presenter: any ActionPresenting) -> String {
        presenter.displayTitle(for: self)
    }

    /// Resolves the user-customized display icon through an explicit presenter (see above).
    @MainActor
    func displayIcon(using presenter: any ActionPresenting) -> ActionIcon {
        presenter.popupIcon(for: self)
    }
}

/// Resolves the display title/icon of an action as surfaced in UI, honoring any user overrides.
/// `ActionCustomizationManager` is the production conformer; callers pass the presenter explicitly
/// rather than letting the `Action` protocol extension reach for a singleton.
@MainActor
public protocol ActionPresenting: Sendable {
    func displayTitle(for action: any Action) -> String
    func popupIcon(for action: any Action) -> ActionIcon
}

