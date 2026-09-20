// ActionChrome.swift
// OpenClip
//
// Defines UI policy metadata structures through the Chrome Door, including badge types, row styles, popup behaviors, and action sources.
// Enables data-driven UI views to inspect action presentation rules without runtime type checking or string matching.
import Foundation

public struct ActionChrome: Codable, Sendable, Equatable {
    public enum Badge: Codable, Sendable, Equatable {
        case none
        case script
        case url
        case custom
        case extensionPkg(String)

        private enum CodingKeys: String, CodingKey {
            case none
            case script
            case url
            case custom
            case extensionPkg
            case _0
        }

        public init(from decoder: Decoder) throws {
            if let container = try? decoder.singleValueContainer(),
               let str = try? container.decode(String.self) {
                switch str {
                case "none": self = .none
                case "script": self = .script
                case "url": self = .url
                case "custom": self = .custom
                default:
                    if str.hasPrefix("extensionPkg:") {
                        self = .extensionPkg(String(str.dropFirst("extensionPkg:".count)))
                    } else {
                        self = .extensionPkg(str)
                    }
                }
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.allKeys.contains(.none) {
                self = .none
            } else if container.allKeys.contains(.script) {
                self = .script
            } else if container.allKeys.contains(.url) {
                self = .url
            } else if container.allKeys.contains(.custom) {
                self = .custom
            } else if container.allKeys.contains(.extensionPkg) {
                if let nested = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: .extensionPkg) {
                    let val = try nested.decode(String.self, forKey: ._0)
                    self = .extensionPkg(val)
                } else if let str = try? container.decode(String.self, forKey: .extensionPkg) {
                    self = .extensionPkg(str)
                } else {
                    self = .none
                }
            } else {
                self = .none
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .none:
                var container = encoder.singleValueContainer()
                try container.encode("none")
            case .script:
                var container = encoder.singleValueContainer()
                try container.encode("script")
            case .url:
                var container = encoder.singleValueContainer()
                try container.encode("url")
            case .custom:
                var container = encoder.singleValueContainer()
                try container.encode("custom")
            case .extensionPkg(let name):
                var container = encoder.container(keyedBy: CodingKeys.self)
                var nested = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .extensionPkg)
                try nested.encode(name, forKey: ._0)
            }
        }
    }

    public enum RowStyle: String, Codable, Sendable, Equatable {
        case standard
        case actionGroup
    }

    public enum PopupBehavior: String, Codable, Sendable, Equatable {
        case perform
        case showSubActions
        case provideCompletions
    }

    public enum Source: Codable, Sendable, Equatable {
        case builtin
        case custom
        case extensionPkg(packageID: String)
        /// AI preset action (a row in AIServiceManager's preset list). Reachable through the
        /// action-search palette and Preferences → Actions, never through the popup bar
        /// (the reorderable `builtin.aiTools` action is the bar's entry point to AI).
        case ai

        private enum CodingKeys: String, CodingKey {
            case builtin
            case custom
            case extensionPkg
            case ai
            case packageID
            case _0
        }

        public init(from decoder: Decoder) throws {
            if let container = try? decoder.singleValueContainer(),
               let str = try? container.decode(String.self) {
                switch str {
                case "builtin": self = .builtin
                case "custom": self = .custom
                case "ai": self = .ai
                default:
                    if str.hasPrefix("extensionPkg:") {
                        self = .extensionPkg(packageID: String(str.dropFirst("extensionPkg:".count)))
                    } else {
                        self = .extensionPkg(packageID: str)
                    }
                }
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.allKeys.contains(.builtin) {
                self = .builtin
            } else if container.allKeys.contains(.custom) {
                self = .custom
            } else if container.allKeys.contains(.ai) {
                self = .ai
            } else if container.allKeys.contains(.extensionPkg) {
                if let nested = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: .extensionPkg) {
                    if let val = try? nested.decode(String.self, forKey: .packageID) {
                        self = .extensionPkg(packageID: val)
                    } else if let val = try? nested.decode(String.self, forKey: ._0) {
                        self = .extensionPkg(packageID: val)
                    } else {
                        self = .builtin
                    }
                } else if let str = try? container.decode(String.self, forKey: .extensionPkg) {
                    self = .extensionPkg(packageID: str)
                } else {
                    self = .builtin
                }
            } else {
                self = .builtin
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .builtin:
                var container = encoder.singleValueContainer()
                try container.encode("builtin")
            case .custom:
                var container = encoder.singleValueContainer()
                try container.encode("custom")
            case .ai:
                var container = encoder.singleValueContainer()
                try container.encode("ai")
            case .extensionPkg(let packageID):
                var container = encoder.container(keyedBy: CodingKeys.self)
                var nested = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .extensionPkg)
                try nested.encode(packageID, forKey: .packageID)
            }
        }
    }

    public let badge: Badge
    public let rowStyle: RowStyle
    public let popupBehavior: PopupBehavior
    public let source: Source
    /// True when the action reads or mutates the real text selection (e.g. Copy/Cut) and is
    /// therefore unsafe when the text came from the clipboard rather than a live selection.
    public let requiresLiveSelection: Bool
    /// True when the action is an AI-mode launcher (the "AI Tools" bar entry). The popup bar
    /// routes its click into AI mode instead of `perform`, and the search palette excludes it
    /// (AI presets are already searchable there).
    public let launchesAI: Bool
    /// True when the action is slow (e.g. an AppleScript that activates an app) and the popup
    /// should close immediately on click with a spinner toast until the result lands.
    public let showsLoading: Bool
    /// The loading toast's text when `showsLoading` (e.g. "Connecting to Music…"). When nil the
    /// presentation layer falls back to its default ("Opening <title>…").
    public let loadingMessage: String?
    /// True when the action produces an inline result preview directly in the popup bar (e.g. Calculate
    /// or synchronous JavaScript inline extensions) rather than performing on click.
    public let isInlineResult: Bool
    /// The kind of uncommitted result the action produces (.text, .file, .none, .dynamic).
    public let outputKind: ActionOutputKind
    /// The author-recommended delivery for uncommitted results (.preview, .paste, .copy, .pasteOrCopy, .open, .save).
    public let recommendedResult: ActionResultDeliveryMode?

    public init(
        badge: Badge = .none,
        rowStyle: RowStyle = .standard,
        popupBehavior: PopupBehavior = .perform,
        source: Source = .builtin,
        requiresLiveSelection: Bool = false,
        launchesAI: Bool = false,
        showsLoading: Bool = false,
        loadingMessage: String? = nil,
        isInlineResult: Bool = false,
        outputKind: ActionOutputKind = .none,
        recommendedResult: ActionResultDeliveryMode? = nil
    ) {
        self.badge = badge
        self.rowStyle = rowStyle
        self.popupBehavior = popupBehavior
        self.source = source
        self.requiresLiveSelection = requiresLiveSelection
        self.launchesAI = launchesAI
        self.showsLoading = showsLoading
        self.loadingMessage = loadingMessage
        self.isInlineResult = isInlineResult
        self.outputKind = (outputKind == .none && isInlineResult) ? .text : outputKind
        self.recommendedResult = recommendedResult
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.badge = try container.decode(Badge.self, forKey: .badge)
        self.rowStyle = try container.decode(RowStyle.self, forKey: .rowStyle)
        self.popupBehavior = try container.decode(PopupBehavior.self, forKey: .popupBehavior)
        self.source = try container.decode(Source.self, forKey: .source)
        self.requiresLiveSelection = try container.decode(Bool.self, forKey: .requiresLiveSelection)
        self.launchesAI = try container.decode(Bool.self, forKey: .launchesAI)
        self.showsLoading = try container.decode(Bool.self, forKey: .showsLoading)
        self.loadingMessage = try container.decodeIfPresent(String.self, forKey: .loadingMessage)
        let inline = try container.decodeIfPresent(Bool.self, forKey: .isInlineResult) ?? false
        self.isInlineResult = inline
        let rawOutput = try? container.decodeIfPresent(String.self, forKey: .outputKind)
        let decodedOutput = rawOutput.flatMap(ActionOutputKind.init(rawValue:)) ?? .none
        self.outputKind = (decodedOutput == .none && inline) ? .text : decodedOutput
        let rawResult = try? container.decodeIfPresent(String.self, forKey: .recommendedResult)
        self.recommendedResult = rawResult.flatMap(ActionResultDeliveryMode.init(rawValue:))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(badge, forKey: .badge)
        try container.encode(rowStyle, forKey: .rowStyle)
        try container.encode(popupBehavior, forKey: .popupBehavior)
        try container.encode(source, forKey: .source)
        try container.encode(requiresLiveSelection, forKey: .requiresLiveSelection)
        try container.encode(launchesAI, forKey: .launchesAI)
        try container.encode(showsLoading, forKey: .showsLoading)
        try container.encodeIfPresent(loadingMessage, forKey: .loadingMessage)
        try container.encode(isInlineResult, forKey: .isInlineResult)
        if outputKind != .none {
            try container.encode(outputKind.rawValue, forKey: .outputKind)
        }
        try container.encodeIfPresent(recommendedResult?.rawValue, forKey: .recommendedResult)
    }

    enum CodingKeys: String, CodingKey {
        case badge
        case rowStyle
        case popupBehavior
        case source
        case requiresLiveSelection
        case launchesAI
        case showsLoading
        case loadingMessage
        case isInlineResult
        case outputKind
        case recommendedResult
    }
}
