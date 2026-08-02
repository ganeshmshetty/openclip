import Foundation

public struct ActionChrome: Sendable, Equatable {
    public enum Badge: Sendable, Equatable {
        case none
        case script
        case url
        case custom
        case extensionPkg(String)
    }

    public enum RowStyle: Sendable, Equatable {
        case standard
        case transformGroup
    }

    public enum PopupBehavior: Sendable, Equatable {
        case perform
        case showTransformMenu
        case provideCompletions
    }

    public enum Source: Sendable, Equatable {
        case builtin
        case custom
        case extensionPkg(packageID: String)
    }

    public let badge: Badge
    public let rowStyle: RowStyle
    public let popupBehavior: PopupBehavior
    public let source: Source

    public init(
        badge: Badge = .none,
        rowStyle: RowStyle = .standard,
        popupBehavior: PopupBehavior = .perform,
        source: Source = .builtin
    ) {
        self.badge = badge
        self.rowStyle = rowStyle
        self.popupBehavior = popupBehavior
        self.source = source
    }
}
