// ExtensionRiskProfile.swift
// OpenClip
//
// Type-derived risk summary for the trust model: computed from the manifest's action kinds, so a
// bad/absent capability declaration can never make a dangerous package look safe. Independent of
// the manifest's declared `capabilities` (an author claim shown verbatim elsewhere).
// Pure Core — no AppKit/SwiftUI.
import Foundation

public struct ExtensionRiskProfile: Sendable, Equatable {
    /// Any shell / applescript / javascript action (inline `scriptCode` or script file).
    public let runsCode: Bool
    /// Any javascript action with `async: true` (the JS `fetch` polyfill is the network path).
    public let scriptNetwork: Bool
    /// Any url / websearch action.
    public let opensURLs: Bool
    /// Any keypress / shortcut action.
    public let keyboard: Bool
    /// Any applescript (drives other apps) or service action.
    public let appAutomation: Bool
    /// None of runsCode / scriptNetwork / keyboard / appAutomation (only url/websearch/textsnippet).
    public let urlOnly: Bool

    public init(manifest: ExtensionMetadata) {
        let traits = Self.collectTraits(actions: manifest.actions)
        runsCode = traits.runsCode
        scriptNetwork = traits.scriptNetwork
        opensURLs = traits.opensURLs
        keyboard = traits.keyboard
        appAutomation = traits.appAutomation
        urlOnly = !traits.runsCode && !traits.scriptNetwork && !traits.keyboard && !traits.appAutomation
    }

    private struct Traits {
        var runsCode = false
        var scriptNetwork = false
        var opensURLs = false
        var keyboard = false
        var appAutomation = false
    }

    private static func collectTraits(actions: [ExtensionActionMetadata]) -> Traits {
        var traits = Traits()
        for action in actions {
            switch action.kind {
            case .js:
                traits.runsCode = true
                if action.isAsync ?? false { traits.scriptNetwork = true }
            case .shellInline, .scriptFile:
                traits.runsCode = true
            case .applescript:
                traits.runsCode = true
                traits.appAutomation = true
            case .url, .webSearch:
                traits.opensURLs = true
            case .keyPress, .shortcut:
                traits.keyboard = true
            case .service:
                traits.appAutomation = true
            case .textSnippet:
                break
            case .group:
                let nested = collectTraits(actions: action.subActions ?? [])
                traits.runsCode = traits.runsCode || nested.runsCode
                traits.scriptNetwork = traits.scriptNetwork || nested.scriptNetwork
                traits.opensURLs = traits.opensURLs || nested.opensURLs
                traits.keyboard = traits.keyboard || nested.keyboard
                traits.appAutomation = traits.appAutomation || nested.appAutomation
            }
        }
        return traits
    }
}