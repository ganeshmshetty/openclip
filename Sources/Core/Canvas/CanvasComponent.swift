// CanvasComponent.swift
// OpenClip
//
// The typed component tree that powers the interactive content canvas (spec §4). Every node is
// pure data — Sendable + Equatable, no closures, no AppKit/SwiftUI — so native actions (Task 8
// DSL) and extensions (JS h() element objects parsed via CanvasElementSpec, Task 6) build the
// same tree. Node-level `id: String?` enables identity-matched re-renders for implicit
// animations (spec §7.2); `textField`/`toggle` carry a required `id` that doubles as the state
// key and the SwiftUI focus id.
import Foundation

public enum CanvasOrientation: String, Sendable, Equatable {
    case vertical
    case horizontal
}

public enum CanvasTextStyle: String, Sendable, Equatable {
    case title
    case body
    case caption
    case monospaced
}

public enum CanvasColorToken: String, Sendable, Equatable {
    case primary
    case secondary
    case accent
}

public enum CanvasButtonStyle: String, Sendable, Equatable {
    case accent
    case plain
}

/// An icon the renderer resolves through the app's existing icon pipeline (SF Symbol, Iconify
/// "prefix:name", local file inside the extension directory, or remote URL).
public enum CanvasIconSource: Sendable, Equatable {
    case symbol(String)
    case iconify(String)
    case local(URL)
    case url(URL)
}

/// An image resolved through the existing loader pipeline (AsyncImage / LocalIconCache / SVG).
public enum CanvasImageSource: Sendable, Equatable {
    case url(URL)
    case local(URL)
}

/// A leaf effect a canvas node may carry (spec §4.1). Deliberately no `.success`/`.failure`/
/// `.none`, no presentation results, no `.sequence`/`.keepVisible` — a canvas re-renders via
/// `.dispatch`, and in-session dismissal is suppressed. Staying `Equatable + Sendable` keeps the
/// tree's conformances (an `Error` payload would break both).
public enum CanvasEffect: Sendable, Equatable {
    case paste(String)
    case copy(String)
    case cut(String)
    case simulatePaste
    case keyPress(KeyPressSpec)
    case runShortcut(name: String, input: String?)
    case openURL(URL)
    case showServices(String)
    case notify(title: String, body: String)

    /// Whether this canvas effect dismisses the popup window.
    public var dismissesPopup: Bool {
        switch self {
        case .paste, .cut, .simulatePaste, .keyPress, .runShortcut:
            return true
        case .copy, .openURL, .showServices, .notify:
            return false
        }
    }

    /// The leaf effect as an `ActionResult` for the existing effect door.
    public var asActionResult: ActionResult {
        switch self {
        case .paste(let text): return .paste(text)
        case .copy(let text): return .copy(text)
        case .cut(let text): return .cut(text)
        case .simulatePaste: return .simulatePaste
        case .keyPress(let spec): return .keyPress(spec)
        case .runShortcut(let name, let input): return .runShortcut(name: name, input: input)
        case .openURL(let url): return .openURL(url)
        case .showServices(let text): return .showServices(text)
        case .notify(let title, let body): return .notify(title: title, body: body)
        }
    }
}

/// What a node does when activated (spec §4.1): a leaf effect, or a named handler the session
/// resolves (JS `handlers[name]`; native registration deferred in v1).
public enum CanvasHandler: Sendable, Equatable {
    case effect(CanvasEffect)
    case dispatch(String)
}

/// The event payload crossing the `CanvasScripting` dispatch seam (spec §4.1a), matching the JS
/// event payload shape one-to-one.
public struct CanvasEvent: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case tap       // button / listItem / link / toggle activation
        case change    // committed value: textField blur/submit, toggle flip
        case submit    // textField Enter (distinct from change for handler branching)
    }

    public let kind: Kind
    public let handler: String
    public let value: String?
    public let targetID: String?

    public init(kind: Kind, handler: String, value: String? = nil, targetID: String? = nil) {
        self.kind = kind
        self.handler = handler
        self.value = value
        self.targetID = targetID
    }
}

// MARK: - Props

public struct CanvasSize: Sendable, Equatable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct CanvasStackProps: Sendable, Equatable {
    public var id: String?
    public var orientation: CanvasOrientation
    public var spacing: Double?

    public init(id: String? = nil, orientation: CanvasOrientation = .vertical, spacing: Double? = nil) {
        self.id = id
        self.orientation = orientation
        self.spacing = spacing
    }
}

public struct CanvasSpacerProps: Sendable, Equatable {
    public var id: String?
    public var minLength: Double?

    public init(id: String? = nil, minLength: Double? = nil) {
        self.id = id
        self.minLength = minLength
    }
}

public struct CanvasDividerProps: Sendable, Equatable {
    public var id: String?

    public init(id: String? = nil) {
        self.id = id
    }
}

public struct CanvasTextProps: Sendable, Equatable {
    public var id: String?
    public var content: String
    public var style: CanvasTextStyle
    public var color: CanvasColorToken
    public var selectable: Bool

    public init(id: String? = nil, content: String, style: CanvasTextStyle = .body,
                color: CanvasColorToken = .primary, selectable: Bool = false) {
        self.id = id
        self.content = content
        self.style = style
        self.color = color
        self.selectable = selectable
    }
}

public struct CanvasIconProps: Sendable, Equatable {
    public var id: String?
    public var source: CanvasIconSource
    public var size: Double

    public init(id: String? = nil, source: CanvasIconSource, size: Double = 14) {
        self.id = id
        self.source = source
        self.size = size
    }
}

public struct CanvasImageProps: Sendable, Equatable {
    public var id: String?
    public var source: CanvasImageSource
    public var cornerRadius: Double?

    public init(id: String? = nil, source: CanvasImageSource, cornerRadius: Double? = nil) {
        self.id = id
        self.source = source
        self.cornerRadius = cornerRadius
    }
}

public struct CanvasButtonProps: Sendable, Equatable {
    public var id: String?
    public var title: String
    public var icon: CanvasIconSource?
    public var style: CanvasButtonStyle
    public var disabled: Bool
    public var handler: CanvasHandler?

    public init(id: String? = nil, title: String, icon: CanvasIconSource? = nil,
                style: CanvasButtonStyle = .plain, disabled: Bool = false, handler: CanvasHandler? = nil) {
        self.id = id
        self.title = title
        self.icon = icon
        self.style = style
        self.disabled = disabled
        self.handler = handler
    }
}

public struct CanvasListProps: Sendable, Equatable {
    public var id: String?

    public init(id: String? = nil) {
        self.id = id
    }
}

public struct CanvasListItem: Sendable, Equatable {
    public var id: String?
    public var icon: CanvasIconSource?
    public var title: String
    public var subtitle: String?
    public var badge: String?
    public var disabled: Bool
    public var handler: CanvasHandler?

    public init(id: String? = nil, icon: CanvasIconSource? = nil, title: String,
                subtitle: String? = nil, badge: String? = nil, disabled: Bool = false,
                handler: CanvasHandler? = nil) {
        self.id = id
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.disabled = disabled
        self.handler = handler
    }
}

/// A `list` section: an optional header plus its items (spec §7 list sections). v1 ships on
/// `Canvas`-built/simple lists as a single implicit section; the header renders when non-nil.
public struct CanvasListSection: Sendable, Equatable {
    public var id: String?
    public var header: String?
    public var items: [CanvasListItem]

    public init(id: String? = nil, header: String? = nil, items: [CanvasListItem]) {
        self.id = id
        self.header = header
        self.items = items
    }
}

public struct CanvasTextFieldProps: Sendable, Equatable {
    public var id: String
    public var value: String
    public var placeholder: String?
    public var onSubmit: CanvasHandler?
    public var onChange: CanvasHandler?

    public init(id: String, value: String, placeholder: String? = nil,
                onSubmit: CanvasHandler? = nil, onChange: CanvasHandler? = nil) {
        self.id = id
        self.value = value
        self.placeholder = placeholder
        self.onSubmit = onSubmit
        self.onChange = onChange
    }
}

public struct CanvasToggleProps: Sendable, Equatable {
    public var id: String
    public var value: Bool
    public var disabled: Bool
    public var onToggle: CanvasHandler?

    public init(id: String, value: Bool, disabled: Bool = false, onToggle: CanvasHandler? = nil) {
        self.id = id
        self.value = value
        self.disabled = disabled
        self.onToggle = onToggle
    }
}

public struct CanvasLinkProps: Sendable, Equatable {
    public var id: String?
    public var title: String
    public var url: URL

    public init(id: String? = nil, title: String, url: URL) {
        self.id = id
        self.title = title
        self.url = url
    }
}

// MARK: - Component

public enum CanvasComponent: Sendable, Equatable {
    case stack(CanvasStackProps, [CanvasComponent])
    case divider(CanvasDividerProps)
    case spacer(CanvasSpacerProps)
    case text(CanvasTextProps)
    case icon(CanvasIconProps)
    case image(CanvasImageProps)
    case button(CanvasButtonProps)
    case list(CanvasListProps, [CanvasListSection])
    case textField(CanvasTextFieldProps)
    case toggle(CanvasToggleProps)
    case link(CanvasLinkProps)
}

extension CanvasComponent {
    public var id: String? {
        switch self {
        case .stack(let p, _): return p.id
        case .divider(let p): return p.id
        case .spacer(let p): return p.id
        case .text(let p): return p.id
        case .icon(let p): return p.id
        case .image(let p): return p.id
        case .button(let p): return p.id
        case .list(let p, _): return p.id
        case .textField(let p): return p.id
        case .toggle(let p): return p.id
        case .link(let p): return p.id
        }
    }
}

