// AXMenuNavigator.swift
// OpenClip
//
// Robust, localization-agnostic navigation of the frontmost application's menu bar through the raw
// Accessibility API. Menu items are matched by action identifier (`copy:`/`paste:`), by their
// Command-key equivalent (⌘C/⌘V), or by a curated set of localized titles, then deep-searched the
// same way SelectedTextKit does: try the Edit menu first, expand to adjacent menus, and fall back
// to a full menu-bar scan. This replaces the title-only walks that previously missed non-English
// menus and apps that do not expose localized titles.
import ApplicationServices
import Foundation

public struct AXMenuNavigator {
    /// The system menu commands OpenClip needs to locate and, for copy, press.
    public enum MenuCommand: CaseIterable {
        case copy
        case paste

        /// The AX action-selector identifier for this command (e.g. `copy:`).
        var identifier: String {
            switch self {
            case .copy: return "copy:"
            case .paste: return "paste:"
            }
        }

        /// The expected Command-key equivalent character for this command.
        var cmdChar: String {
            switch self {
            case .copy: return "C"
            case .paste: return "V"
            }
        }

        /// Localized menu titles for this command, lowercased for case-insensitive matching.
        var titles: Set<String> {
            switch self {
            case .copy: return AXMenuNavigator.copyTitles
            case .paste: return AXMenuNavigator.pasteTitles
            }
        }
    }

    /// Finds the requested menu item in `app`'s menu bar, optionally requiring it to be enabled.
    ///
    /// - Parameters:
    ///   - command: The menu command to locate.
    ///   - app: The application AXUIElement (never the system-wide element; menu items are children
    ///     of the application element).
    ///   - requireEnabled: When true, only an enabled item matches.
    /// - Returns: The matching menu item, or nil.
    public static func findMenuItem(
        _ command: MenuCommand,
        in app: AXUIElement?,
        requireEnabled: Bool = false
    ) -> AXUIElement? {
        guard let app,
              let menuBar = attribute(app, kAXMenuBarAttribute).flatMap(axElement),
              let topLevelMenus = children(menuBar) else { return nil }

        // The Edit menu is usually the 4th top-level item (index 3). Try it first, then expand to
        // adjacent menus alternately, then scan the whole menu bar as a last resort.
        let startIndex = 3
        if topLevelMenus.indices.contains(startIndex),
           let match = findMenuItem(command, in: topLevelMenus[startIndex], requireEnabled: requireEnabled) {
            return match
        }

        for offset in 1...max(startIndex, topLevelMenus.count - startIndex - 1) {
            let leftIndex = startIndex - offset
            if leftIndex >= 0 && leftIndex < topLevelMenus.count,
               let match = findMenuItem(command, in: topLevelMenus[leftIndex], requireEnabled: requireEnabled) {
                return match
            }

            let rightIndex = startIndex + offset
            if rightIndex < topLevelMenus.count,
               let match = findMenuItem(command, in: topLevelMenus[rightIndex], requireEnabled: requireEnabled) {
                return match
            }
        }

        return findMenuItem(command, in: menuBar, requireEnabled: requireEnabled)
    }

    /// Presses the requested menu item if it can be found and is enabled.
    @discardableResult
    public static func press(_ command: MenuCommand, in app: AXUIElement?) -> Bool {
        guard let item = findMenuItem(command, in: app, requireEnabled: true) else { return false }
        AXUIElementPerformAction(item, kAXPressAction as CFString)
        return true
    }

    /// Whether the supplied title/cmd-char/modifiers describe the requested menu command.
    public static func matches(
        _ command: MenuCommand,
        title: String?,
        identifier: String?,
        cmdChar: String?,
        cmdModifiers: UInt?
    ) -> Bool {
        if let identifier, identifier == command.identifier { return true }

        if let cmdChar, cmdChar.caseInsensitiveCompare(command.cmdChar) == .orderedSame,
           let modifiers = cmdModifiers {
            return modifiers == 0
        }

        guard let title else { return false }
        return command.titles.contains(title.localizedLowercase)
    }

    // MARK: - Tree walking

    /// Depth-first search bounded by `maxDepth` so a malformed or cyclic AX tree can never recurse
    /// forever.
    private static func findMenuItem(
        _ command: MenuCommand,
        in element: AXUIElement,
        requireEnabled: Bool,
        depth: Int = 0
    ) -> AXUIElement? {
        guard depth <= maxDepth else { return nil }

        if isMatch(command, element: element, requireEnabled: requireEnabled) {
            return element
        }

        for child in children(element) ?? [] {
            if let match = findMenuItem(
                command,
                in: child,
                requireEnabled: requireEnabled,
                depth: depth + 1
            ) {
                return match
            }
        }

        return nil
    }

    private static func isMatch(
        _ command: MenuCommand,
        element: AXUIElement,
        requireEnabled: Bool
    ) -> Bool {
        guard matches(
            command,
            title: title(element),
            identifier: identifier(element),
            cmdChar: cmdChar(element),
            cmdModifiers: cmdModifiers(element)
        ) else { return false }

        if requireEnabled {
            guard enabled(element) == true else { return false }
        }
        return true
    }

    private static let maxDepth = 8

    // MARK: - AX attribute helpers

    private static func children(_ element: AXUIElement) -> [AXUIElement]? {
        guard let value = attribute(element, kAXChildrenAttribute) else { return nil }
        return value as? [AXUIElement]
    }

    private static func title(_ element: AXUIElement) -> String? {
        attribute(element, kAXTitleAttribute) as? String
    }

    private static func identifier(_ element: AXUIElement) -> String? {
        attribute(element, kAXIdentifierAttribute) as? String
    }

    private static func cmdChar(_ element: AXUIElement) -> String? {
        attribute(element, kAXMenuItemCmdCharAttribute) as? String
    }

    private static func cmdModifiers(_ element: AXUIElement) -> UInt? {
        guard let value = attribute(element, kAXMenuItemCmdModifiersAttribute) else { return nil }
        return (value as? NSNumber)?.uintValue
    }

    private static func enabled(_ element: AXUIElement) -> Bool? {
        attribute(element, kAXEnabledAttribute) as? Bool
    }

    private static func attribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func axElement(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return value as! AXUIElement
    }

    // MARK: - Localized titles

    private static let copyTitles: Set<String> = [
        "copy",  // English
        "拷贝", "复制",  // Simplified Chinese
        "拷貝", "複製",  // Traditional Chinese
        "コピー",  // Japanese
        "복사",  // Korean
        "copier",  // French
        "copiar",  // Spanish, Portuguese
        "copia",  // Italian
        "kopieren",  // German
        "копировать",  // Russian
        "kopiëren",  // Dutch
        "kopiér",  // Danish
        "kopiera",  // Swedish
        "kopioi",  // Finnish
        "αντιγραφή",  // Greek
        "kopyala",  // Turkish
        "salin",  // Indonesian
        "sao chép",  // Vietnamese
        "คัดลอก",  // Thai
        "копіювати",  // Ukrainian
        "kopiuj",  // Polish
        "másolás",  // Hungarian
        "kopírovat",  // Czech
        "kopírovať",  // Slovak
        "kopiraj",  // Croatian, Serbian (Latin)
        "копирај",  // Serbian (Cyrillic)
        "копиране",  // Bulgarian
        "kopēt",  // Latvian
        "kopijuoti",  // Lithuanian
        "copiază",  // Romanian
        "העתק",  // Hebrew
        "نسخ",  // Arabic
        "کپی",  // Persian
    ]

    private static let pasteTitles: Set<String> = [
        "paste", "paste and match style",  // English
        "粘贴", "贴上",  // Simplified Chinese
        "貼上", "粘貼",  // Traditional Chinese
        "ペースト",  // Japanese
        "붙여넣기",  // Korean
        "coller", "coller et assortir le style",  // French
        "pegar", "pegar y combinar estilo",  // Spanish, Portuguese
        "incolla",  // Italian
        "einfügen", "einfügen und stil anpassen",  // German
        "вставить",  // Russian
        "plakken", "plakken en stijl aanpassen",  // Dutch
        "indsæt",  // Danish
        "klistra", "klistra in",  // Swedish
        "liitä",  // Finnish
        "επικόλληση",  // Greek
        "yapıştır",  // Turkish
        "tempel",  // Indonesian
        "dán",  // Vietnamese
        "วาง",  // Thai
        "вставити",  // Ukrainian
        "wklej",  // Polish
        "beillesztés",  // Hungarian
        "vložit",  // Czech
        "vložiť",  // Slovak
        "umetni",  // Croatian, Serbian (Latin)
        "уметни",  // Serbian (Cyrillic)
        "поставяне",  // Bulgarian
        "ielīmēt",  // Latvian
        "įklijuoti",  // Lithuanian
        "lipește",  // Romanian
        "colar", "colar e combinar estilo",  // Portuguese (BR)
        "lim inn",  // Norwegian
        "הדבק",  // Hebrew
        "لصق",  // Arabic
        "چسباندن",  // Persian
        "貼り付け",  // Japanese (alt)
    ]
}
