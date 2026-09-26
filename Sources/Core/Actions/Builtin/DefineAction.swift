// DefineAction.swift
// OpenClip
//
// Implements the dictionary lookup action for single selected words. A single display picker chooses
// the outcome: resolve the definition in-process and return it as text (rendered in the result card,
// default), show the system Look Up dictionary popover, or hand the word to the macOS Dictionary app
// via its `x-dictionary:` URL scheme.
import Foundation

public struct DefineAction: ConfigurableAction {
    public static let actionID = "builtin.define"
    public let id = Self.actionID
    public var title: String { String(localized: "Define") }
    public let preferenceIconName = "character.book.closed"
    public let icon = ActionIcon.symbol("character.book.closed")
    public var chrome: ActionChrome {
        ActionChrome(outputKind: .text, recommendedResult: .preview)
    }

    /// How a single selected word is presented when Define runs. A single user-visible picker keeps
    /// the three mutually-exclusive outcomes explicit instead of a set of independent toggles.
    public enum Display: String, CaseIterable, Sendable {
        /// Resolve the definition in-process and render it in the result card (default).
        case card
        /// Show the system Look Up dictionary popover anchored to the popup.
        case popover
        /// Hand the word to the macOS Dictionary app.
        case dictionary
    }

    /// Option id for the display picker.
    static let displayOptionID = "definitionDisplay"
    /// Legacy boolean option, superseded by `displayOptionID`; `true` meant "open in Dictionary.app".
    /// Kept so existing installs migrate to `display = dictionary` instead of silently resetting.
    static let legacyOpenInDictionaryOptionID = "openInDictionaryApp"

    public var actionOptions: [ExtensionOption] {
        [
            ExtensionOption(
                identifier: Self.displayOptionID,
                label: String(localized: "Definition display"),
                type: .multiple,
                defaultValue: Display.card.rawValue,
                options: Display.allCases.map(\.rawValue)
            )
        ]
    }

    private let lookup: @Sendable (String) -> String?
    private let settingsStore: any SettingsStore

    public init(
        lookup: @escaping @Sendable (String) -> String? = { _ in nil },
        settingsStore: any SettingsStore = DefaultSettingsStore.shared
    ) {
        self.lookup = lookup
        self.settingsStore = settingsStore
    }

    /// The configured presentation mode. Falls back to the legacy boolean for installs that set
    /// `openInDictionaryApp` before the picker existed.
    var display: Display {
        let stored = settingsStore.get(
            SettingKey.actionOption(actionID: id, optionID: Self.displayOptionID)
        )
        if let resolved = Display(rawValue: stored.lowercased()) { return resolved }
        let legacy = settingsStore.get(
            SettingKey.actionOption(actionID: id, optionID: Self.legacyOpenInDictionaryOptionID)
        )
        return legacy.caseInsensitiveCompare("true") == .orderedSame ? .dictionary : .card
    }

    /// One-time normalization run at launch: a legacy `openInDictionaryApp = true` becomes
    /// `display = dictionary` so the picker matches the behaviour the install already had.
    static func migrateLegacyDisplayOptionIfNeeded(settingsStore: any SettingsStore) {
        let displayKey = SettingKey.actionOption(actionID: actionID, optionID: displayOptionID)
        guard settingsStore.get(displayKey).isEmpty else { return }
        let legacy = settingsStore.get(
            SettingKey.actionOption(actionID: actionID, optionID: legacyOpenInDictionaryOptionID)
        )
        guard legacy.caseInsensitiveCompare("true") == .orderedSame else { return }
        settingsStore.set(displayKey, value: Display.dictionary.rawValue)
    }

    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        let text = context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Length check: 1 to 40 characters
        guard !text.isEmpty && text.count <= 40 else { return false }

        // Word count check: strictly 1 word
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard words.count == 1 else { return false }

        // Must contain letters
        guard text.rangeOfCharacter(from: .letters) != nil else { return false }

        // For non-space-delimited scripts (Chinese, Japanese, Korean), verify single-word boundary
        guard isSingleLinguisticWord(text) else { return false }

        // Exclude URLs, email addresses, and math symbols
        let isURL = text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://") || text.contains("www.")
        let hasMathSymbol = text.contains("+") || text.contains("*") || text.contains("/") || text.contains("=") || text.contains("%")

        guard !isURL && !hasMathSymbol else { return false }

        // Dictionary-app mode hands any single word to the app (which reports its own "no entry"),
        // and popover mode asks the system dictionaries to render the entry; neither needs an
        // in-process definition, so both skip the `DCSCopyTextDefinition` probe entirely.
        if display != .card { return true }

        guard let definition = lookup(text), !definition.isEmpty else { return false }
        return true
    }

    private func isSingleLinguisticWord(_ text: String) -> Bool {
        let hasCJK = text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) ||
            (0x3400...0x4DBF).contains(scalar.value) ||
            (0x3040...0x309F).contains(scalar.value) ||
            (0x30A0...0x30FF).contains(scalar.value) ||
            (0xAC00...0xD7AF).contains(scalar.value)
        }
        guard hasCJK else { return true }

        let cfText = text as CFString
        let range = CFRange(location: 0, length: CFStringGetLength(cfText))
        guard let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault,
            cfText,
            range,
            kCFStringTokenizerUnitWord,
            CFLocaleCopyCurrent()
        ) else {
            return true
        }

        var tokenCount = 0
        var tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        while tokenType != [] {
            if tokenType.contains(.normal) {
                tokenCount += 1
                if tokenCount > 1 { return false }
            }
            tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }
        return tokenCount <= 1
    }

    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        let text = context.selection.text.trimmingCharacters(in: .whitespacesAndNewlines)

        switch display {
        case .dictionary:
            guard let url = Self.dictionaryURL(for: text) else { return .none }
            return .openURL(url)
        case .popover:
            return .showDefinition(text)
        case .card:
            guard let definition = lookup(text), !definition.isEmpty else { return .none }
            return .text(definition)
        }
    }

    /// Builds a Dictionary.app lookup URL using the documented `x-dictionary:d:<key_text>`
    /// definition form (`x-dictionary:` is the scheme Dictionary.app registers).
    /// Exposed for tests.
    static func dictionaryURL(for word: String) -> URL? {
        guard !word.isEmpty,
              let encoded = word.addingPercentEncoding(withAllowedCharacters: Constants.queryValueAllowed)
        else { return nil }
        return URL(string: "x-dictionary:d:\(encoded)")
    }
}
