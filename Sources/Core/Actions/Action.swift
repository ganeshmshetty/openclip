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

